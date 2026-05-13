VancePay.Intents = VancePay.Intents or {}

local Intents = VancePay.Intents

Intents._ready = Intents._ready or false
Intents._initializing = Intents._initializing or false
Intents._scheduledExpirations = Intents._scheduledExpirations or {}
Intents._schedulerBootstrapped = Intents._schedulerBootstrapped or false

local function getDatabaseConfig()
    return Config.Database or {}
end

local function shouldRunSchemaMigrations()
    return getDatabaseConfig().autoMigrate == true
end

local INTENT_SELECT = [[
    SELECT
        i.*,
        s.name AS store_name,
        s.status AS store_status,
        s.balance AS store_balance,
        t.serial_number AS terminal_serial_number,
        t.status AS terminal_status,
        t.type AS terminal_type,
        t.coords AS terminal_coords,
        t.heading AS terminal_heading,
        t.model_key AS terminal_model_key
    FROM vancepay_payment_intents i
    JOIN vancepay_stores s ON s.id = i.store_id
    LEFT JOIN vancepay_terminals t ON t.id = i.terminal_id
]]

local function getSchemaValue(row, ...)
    if type(row) ~= 'table' then
        return nil
    end

    for index = 1, select('#', ...) do
        local key = select(index, ...)
        if row[key] ~= nil then
            return row[key]
        end
    end

    return nil
end

local function fetchColumnMetadata(columnName)
    return MySQL.single.await([[
        SELECT
            COLUMN_NAME,
            COLUMN_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'vancepay_payment_intents'
            AND COLUMN_NAME = ?
        LIMIT 1
    ]], { columnName })
end

local function fetchIndexMap()
    local rows = MySQL.query.await([[
        SELECT
            INDEX_NAME
        FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'vancepay_payment_intents'
    ]]) or {}

    local indexMap = {}
    for index = 1, #rows do
        local indexName = getSchemaValue(rows[index], 'INDEX_NAME', 'index_name')
        if indexName then
            indexMap[indexName] = true
        end
    end

    return indexMap
end

local function ensureSchema()
    local tableExists = MySQL.single.await([[
        SELECT 1 AS present
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'vancepay_payment_intents'
        LIMIT 1
    ]])

    if not tableExists then
        return
    end

    local statusColumn = fetchColumnMetadata('status')
    local statusColumnType = tostring(getSchemaValue(statusColumn, 'COLUMN_TYPE', 'column_type') or '')
    if statusColumnType ~= ''
        and (not statusColumnType:find('awaiting_customer', 1, true)
            or not statusColumnType:find('awaiting_swipe', 1, true)
            or not statusColumnType:find('completed', 1, true)
            or not statusColumnType:find('failed', 1, true)) then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            MODIFY COLUMN status ENUM('pending', 'awaiting_customer', 'awaiting_swipe', 'completed', 'cancelled', 'expired', 'failed') NOT NULL DEFAULT 'pending'
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('item_description'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN item_description VARCHAR(255) DEFAULT NULL AFTER target_citizenid
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('item_lines'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN item_lines JSON DEFAULT NULL AFTER item_description
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('tax_rate'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER fee_amount
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('tax_exempt'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN tax_exempt TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_rate
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('tax_amount'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER tax_exempt
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('commission_rate'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER tax_amount
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('commission_amount'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER commission_rate
        ]])
    end

    local taxSettlementModeColumn = fetchColumnMetadata('tax_settlement_mode')
    if not getSchemaValue(taxSettlementModeColumn, 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance' AFTER commission_amount
        ]])
    else
        local taxSettlementModeType = tostring(getSchemaValue(taxSettlementModeColumn, 'COLUMN_TYPE', 'column_type') or '')
        if not taxSettlementModeType:find('public_account', 1, true) then
            MySQL.query.await([[
                ALTER TABLE vancepay_payment_intents
                MODIFY COLUMN tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance'
            ]])
        end
    end

    if not getSchemaValue(fetchColumnMetadata('tax_settlement_account_identifier'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER tax_settlement_mode
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('completed_at'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_payment_intents
            ADD COLUMN completed_at TIMESTAMP NULL DEFAULT NULL AFTER expires_at
        ]])
    end

    local indexMap = fetchIndexMap()
    local missingIndexes = {}

    if not indexMap.idx_target_status then
        missingIndexes[#missingIndexes + 1] = 'ADD INDEX idx_target_status (target_citizenid, status, expires_at)'
    end

    if not indexMap.idx_status_expires then
        missingIndexes[#missingIndexes + 1] = 'ADD INDEX idx_status_expires (status, expires_at, id)'
    end

    if not indexMap.idx_terminal_status then
        missingIndexes[#missingIndexes + 1] = 'ADD INDEX idx_terminal_status (terminal_id, status, id)'
    end

    if not indexMap.idx_store_status then
        missingIndexes[#missingIndexes + 1] = 'ADD INDEX idx_store_status (store_id, status)'
    end

    if not indexMap.idx_store_created then
        missingIndexes[#missingIndexes + 1] = 'ADD INDEX idx_store_created (store_id, created_at)'
    end

    if #missingIndexes > 0 then
        MySQL.query.await(([[ 
            ALTER TABLE vancepay_payment_intents
            %s
        ]]):format(table.concat(missingIndexes, ',\n            ')))
    end
end

local function isTrackedIntentStatus(status)
    return status == VancePay.IntentStatuses.awaitingCustomer
        or status == VancePay.IntentStatuses.awaitingSwipe
end

local function setScheduledExpiration(intentId, expiresAt)
    local numericIntentId = tonumber(intentId)
    if not numericIntentId then
        return false
    end

    local parsedExpiresAt = expiresAt
    if type(parsedExpiresAt) == 'string' then
        parsedExpiresAt = Utils.parseSqlDateTime(parsedExpiresAt)
    end

    if not parsedExpiresAt then
        Intents._scheduledExpirations[numericIntentId] = nil
        return false
    end

    Intents._scheduledExpirations[numericIntentId] = parsedExpiresAt
    return true
end

local function clearScheduledExpiration(intentId)
    local numericIntentId = tonumber(intentId)
    if numericIntentId then
        Intents._scheduledExpirations[numericIntentId] = nil
    end
end

local function syncScheduledExpiration(intent)
    if type(intent) ~= 'table' or not intent.id then
        return false
    end

    if not isTrackedIntentStatus(intent.status) then
        clearScheduledExpiration(intent.id)
        return false
    end

    return setScheduledExpiration(intent.id, intent.expires_at)
end

local function bootstrapScheduledExpirations()
    if Intents._schedulerBootstrapped then
        return
    end

    local rows = MySQL.query.await([[
        SELECT id, status, expires_at
        FROM vancepay_payment_intents
        WHERE status IN ('awaiting_customer', 'awaiting_swipe')
    ]]) or {}

    Intents._scheduledExpirations = {}

    for index = 1, #rows do
        syncScheduledExpiration(rows[index])
    end

    Intents._schedulerBootstrapped = true
end

local function expireDueIntents(limit)
    limit = math.min(math.max(tonumber(limit) or 50, 1), 200)

    local rows = MySQL.query.await([[
        SELECT id
        FROM vancepay_payment_intents
        WHERE status IN ('awaiting_customer', 'awaiting_swipe')
            AND expires_at <= NOW()
        ORDER BY expires_at ASC, id ASC
        LIMIT ?
    ]], { limit }) or {}

    for index = 1, #rows do
        local intentId = tonumber(rows[index].id or rows[index].ID or rows[index].intent_id)
        if intentId then
            Intents.expireOne(intentId)
        end
    end
end

function Intents.ensureReady()
    if Intents._ready then
        return true
    end

    while Intents._initializing do
        Wait(50)
        if Intents._ready then
            return true
        end
    end

    Intents._initializing = true
    local ok, err = pcall(function()
        if shouldRunSchemaMigrations() then
            ensureSchema()
        end

        bootstrapScheduledExpirations()
    end)
    Intents._initializing = false
    if not ok then
        error(err)
    end

    Intents._ready = true
    return true
end

function Intents.syncScheduledExpiration(intent)
    return syncScheduledExpiration(intent)
end

function Intents.clearScheduledExpiration(intentId)
    clearScheduledExpiration(intentId)
end

local function normalizeIntent(row)
    if not row then
        return nil
    end

    row = Utils.normalizeDbRow(row)
    if type(row.item_lines) == 'string' then
        local ok, decoded = pcall(json.decode, row.item_lines)
        row.item_lines = ok and type(decoded) == 'table' and decoded or {}
    elseif type(row.item_lines) ~= 'table' then
        row.item_lines = {}
    end
    row.terminal_coords = Utils.decodeCoords(row.terminal_coords)
    local amounts = Utils.computeAmounts(row.subtotal_amount, row.discount_rate, row.tip_amount, row.tax_rate)
    row.net_amount = amounts.net_amount
    row.discount_amount = amounts.discount_amount
    row.tax_rate = row.tax_rate ~= nil and Utils.roundCurrency(row.tax_rate) or amounts.tax_rate
    row.tax_exempt = Utils.parseBool(row.tax_exempt)
    row.tax_amount = row.tax_amount ~= nil and Utils.roundCurrency(row.tax_amount) or amounts.tax_amount
    row.commission_rate = Utils.roundCurrency(row.commission_rate or 0)
    row.commission_amount = Utils.roundCurrency(row.commission_amount or 0)
    row.fee_amount = row.fee_amount ~= nil and Utils.roundCurrency(row.fee_amount) or amounts.fee_amount
    row.final_amount = row.final_amount ~= nil and Utils.roundCurrency(row.final_amount) or amounts.final_amount
    row.tax_settlement_mode = row.tax_settlement_mode == VancePay.StoreSettlementModes.publicAccount
        and VancePay.StoreSettlementModes.publicAccount
        or VancePay.StoreSettlementModes.storeBalance
    row.tax_settlement_account_identifier = Utils.trim(row.tax_settlement_account_identifier)

    return row
end

function Intents.fetchById(intentId)
    Intents.ensureReady()
    local row = MySQL.single.await(INTENT_SELECT .. ' WHERE i.id = ? LIMIT 1', { tonumber(intentId) })
    return normalizeIntent(row)
end

function Intents.fetchByCode(intentCode)
    Intents.ensureReady()
    if Utils.isBlank(intentCode) then
        return nil
    end

    local row = MySQL.single.await(INTENT_SELECT .. ' WHERE i.intent_code = ? LIMIT 1', { intentCode })
    return normalizeIntent(row)
end

function Intents.fetchReference(reference)
    if type(reference) == 'table' then
        if reference.intent_id or reference.id then
            return Intents.fetchById(reference.intent_id or reference.id)
        end

        return Intents.fetchByCode(reference.intent_code or reference.code)
    end

    return Intents.fetchById(reference)
end

function Intents.fetchActiveByTerminalId(terminalId)
    Intents.ensureReady()
    expireDueIntents(25)

    terminalId = tonumber(terminalId)
    if not terminalId then
        return nil
    end

    local row = MySQL.single.await(INTENT_SELECT .. [[
        WHERE i.terminal_id = ?
            AND i.status IN ('awaiting_customer', 'awaiting_swipe')
            AND i.expires_at > NOW()
        ORDER BY i.id DESC
        LIMIT 1
    ]], { terminalId })

    return normalizeIntent(row)
end

function Intents.buildClientPayload(intent, overrides)
    overrides = overrides or {}
    local currentBalance = VancePay.Banking and VancePay.Banking.getBalance(intent.target_citizenid) or 0
    local cashierSource = VancePay.Server.getSourceByCitizenId(intent.cashier_citizenid)

    return {
        intent_id = intent.id,
        intent_code = intent.intent_code,
        status = overrides.status or intent.status,
        method = intent.method,
        store_id = intent.store_id,
        store_name = intent.store_name,
        terminal_id = intent.terminal_id,
        terminal_serial_number = intent.terminal_serial_number,
        terminal_type = intent.terminal_type,
        terminal_coords = intent.terminal_coords,
        subtotal_amount = Utils.roundCurrency(intent.subtotal_amount),
        discount_rate = Utils.roundCurrency(intent.discount_rate),
        discount_amount = Utils.roundCurrency(intent.discount_amount),
        tip_amount = Utils.roundCurrency(intent.tip_amount),
        tax_rate = Utils.roundCurrency(intent.tax_rate or 0),
        tax_exempt = Utils.parseBool(intent.tax_exempt),
        tax_amount = Utils.roundCurrency(intent.tax_amount or 0),
        commission_rate = Utils.roundCurrency(intent.commission_rate or 0),
        commission_amount = Utils.roundCurrency(intent.commission_amount or 0),
        fee_amount = Utils.roundCurrency(intent.fee_amount),
        final_amount = Utils.roundCurrency(intent.final_amount),
        net_amount = Utils.roundCurrency(intent.net_amount),
        item_description = intent.item_description,
        item_lines = type(intent.item_lines) == 'table' and intent.item_lines or {},
        target_citizenid = intent.target_citizenid,
        cashier_citizenid = intent.cashier_citizenid,
        cashier_source = cashierSource,
        expires_at = intent.expires_at,
        expires_in = math.max(0, (Utils.parseSqlDateTime(intent.expires_at) or os.time()) - os.time()),
        current_balance = currentBalance,
        balance_after_preview = Utils.roundCurrency(currentBalance - intent.final_amount),
        message = overrides.message,
        reason = overrides.reason,
        transaction = overrides.transaction,
    }
end

function Intents.listCustomerPendingByCitizenId(citizenid, limit)
    Intents.ensureReady()
    expireDueIntents(50)
    if Utils.isBlank(citizenid) then
        return {}
    end

    limit = math.min(math.max(tonumber(limit) or 20, 1), 50)

    local rows = MySQL.query.await(INTENT_SELECT .. [[
        WHERE i.target_citizenid = ?
            AND i.method = 'phone'
            AND i.status = 'awaiting_customer'
            AND i.expires_at > NOW()
        ORDER BY i.expires_at ASC, i.id DESC
        LIMIT ?
    ]], { citizenid, limit }) or {}

    local items = {}

    for index = 1, #rows do
        local intent = normalizeIntent(rows[index])
        if intent then
            items[#items + 1] = Intents.buildClientPayload(intent, {
                status = intent.status,
            })
        end
    end

    return items
end

function Intents.listAssignedPendingByCitizenId(citizenid, limit)
    Intents.ensureReady()
    expireDueIntents(50)
    if Utils.isBlank(citizenid) then
        return {}
    end

    limit = math.min(math.max(tonumber(limit) or 20, 1), 50)

    local rows = MySQL.query.await(INTENT_SELECT .. [[
        WHERE i.target_citizenid = ?
            AND (
                (i.method = 'phone' AND i.status = 'awaiting_customer')
                OR (i.method = 'card' AND i.status = 'awaiting_swipe')
            )
            AND i.expires_at > NOW()
        ORDER BY i.expires_at ASC, i.id DESC
        LIMIT ?
    ]], { citizenid, limit }) or {}

    local items = {}

    for index = 1, #rows do
        local intent = normalizeIntent(rows[index])
        if intent then
            items[#items + 1] = Intents.buildClientPayload(intent, {
                status = intent.status,
            })
        end
    end

    return items
end

local function isCardIntentReachableBySource(source, intent)
    if not source or not intent then
        return false
    end

    local viewerCitizenId = VancePay.Permissions.getCitizenId(source)
    if not Utils.isBlank(viewerCitizenId) and viewerCitizenId == intent.cashier_citizenid then
        return false
    end

    local cashierSource = VancePay.Server.getSourceByCitizenId(intent.cashier_citizenid)
    return VancePay.Server.safeClientCallback('vancepay:client:isIntentReachable', source, {
        cashier_source = cashierSource,
        terminal_type = intent.terminal_type,
        coords = intent.terminal_coords,
        distance = Config.TargetingDistance,
    }) == true
end

function Intents.listReachableCardPendingBySource(source, limit)
    Intents.ensureReady()
    expireDueIntents(50)

    limit = math.min(math.max(tonumber(limit) or 20, 1), 50)

    local rows = MySQL.query.await(INTENT_SELECT .. [[
        WHERE i.method = 'card'
            AND i.status = 'awaiting_swipe'
            AND i.expires_at > NOW()
        ORDER BY i.expires_at ASC, i.id DESC
    ]]) or {}

    local items = {}

    for index = 1, #rows do
        local intent = normalizeIntent(rows[index])
        if intent and isCardIntentReachableBySource(source, intent) then
            items[#items + 1] = Intents.buildClientPayload(intent, {
                status = intent.status,
            })

            if #items >= limit then
                break
            end
        end
    end

    return items
end

local function getNearbySources(source)
    local nearbySources = VancePay.Server.safeClientCallback('vancepay:client:getNearbyPlayers', source, Config.TargetingDistance) or {}
    local mapped = {}

    for _, nearbySource in ipairs(nearbySources) do
        mapped[tonumber(nearbySource)] = true
    end

    return mapped
end

local function notifyNearbyCardCustomers(source, eventName, payload)
    if not source or source < 1 then
        return
    end

    local nearbySources = getNearbySources(source)
    for nearbySource in pairs(nearbySources) do
        if nearbySource and nearbySource > 0 then
            TriggerClientEvent(eventName, nearbySource, payload)
        end
    end
end

function Intents.pushUpdate(intent, overrides)
    local payload = Intents.buildClientPayload(intent, overrides)
    local cashierSource = VancePay.Server.getSourceByCitizenId(intent.cashier_citizenid)
    local targetSource = VancePay.Server.getSourceByCitizenId(intent.target_citizenid)

    if cashierSource and cashierSource > 0 then
        TriggerClientEvent(VancePay.Events.client.intentUpdated, cashierSource, payload)
    end

    if targetSource and targetSource > 0 then
        TriggerClientEvent(VancePay.Events.client.intentUpdated, targetSource, payload)
    elseif intent.method == VancePay.PaymentMethods.card then
        notifyNearbyCardCustomers(cashierSource, VancePay.Events.client.intentUpdated, payload)
    end
end

local function assertIntentActive(intent)
    if not intent then
        return false, '订单不存在'
    end

    if intent.status ~= VancePay.IntentStatuses.awaitingCustomer
        and intent.status ~= VancePay.IntentStatuses.awaitingSwipe then
        return false, '订单状态不允许继续操作'
    end

    local expiresAt = Utils.parseSqlDateTime(intent.expires_at)
    if expiresAt and expiresAt <= os.time() then
        return false, '订单已超时'
    end

    return true
end

function Intents.create(source, payload)
    Intents.ensureReady()
    expireDueIntents(25)
    payload = payload or {}
    local terminal = VancePay.Terminals.fetchByReference(payload)
    if not terminal then
        return VancePay.Server.fail('未找到对应终端', 'terminal_not_found')
    end

    if terminal.status ~= VancePay.TerminalStatuses.active then
        return VancePay.Server.fail('此终端已被停用', 'terminal_inactive')
    end

    if not terminal.store_id then
        return VancePay.Server.fail('此 POS 未绑定任何店铺', 'store_unbound')
    end

    local store = VancePay.Stores.fetchById(terminal.store_id)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'store_not_found')
    end

    if store.status ~= VancePay.StoreStatuses.active then
        return VancePay.Server.fail('该店铺已归档，不能再发起新交易', 'store_archived')
    end

    local allowed, accessOrReason = VancePay.Permissions.checkAccess(source, store.id, 'collect')
    if not allowed then
        return VancePay.Server.fail(accessOrReason, 'forbidden')
    end

    local method = Utils.trim(payload.method)
    if method ~= VancePay.PaymentMethods.phone and method ~= VancePay.PaymentMethods.card then
        return VancePay.Server.fail('支付方式无效', 'invalid_method')
    end

    local itemLines, itemLinesSubtotal, itemLinesError, itemLinesErrorCode = Utils.sanitizeItemLines(payload.item_lines or payload.itemLines)
    if itemLinesError then
        return VancePay.Server.fail(itemLinesError, itemLinesErrorCode or 'invalid_item_lines')
    end

    local amountPayload = payload
    if #itemLines > 0 then
        amountPayload = {
            subtotal_amount = itemLinesSubtotal,
            discount_rate = payload.discount_rate or payload.discountRate,
            tip_amount = payload.tip_amount or payload.tipAmount,
        }
    end

    local subtotalAmount, discountRate, tipAmount, amountError, amountErrorCode = Utils.sanitizeAmountInput(amountPayload)
    if amountError then
        return VancePay.Server.fail(amountError, amountErrorCode or 'invalid_amount')
    end

    local itemDescription = Utils.buildItemSummary(payload.item_description or payload.description or payload.note, itemLines)
    local encodedItemLines = #itemLines > 0 and json.encode(itemLines) or nil
    if discountRate > 0 and not accessOrReason.can_discount then
        return VancePay.Server.fail('你没有使用折扣的权限', 'discount_forbidden')
    end

    local targetSource = nil
    local targetRecord = nil

    if method == VancePay.PaymentMethods.phone then
        targetSource = tonumber(payload.target_source or payload.target_id or payload.target_server_id)
        if not targetSource or targetSource == source then
            return VancePay.Server.fail('必须先选择附近顾客', 'invalid_target')
        end

        local nearbySources = getNearbySources(source)
        if not nearbySources[targetSource] then
            return VancePay.Server.fail('目标顾客不在交互范围内', 'target_too_far')
        end

        targetRecord = VancePay.Server.getPlayerRecord(targetSource)
        if not targetRecord then
            return VancePay.Server.fail('目标顾客不在线', 'target_offline')
        end
    end

    local activeIntent = MySQL.single.await([[
        SELECT id, intent_code, status
        FROM vancepay_payment_intents
        WHERE terminal_id = ?
            AND status IN ('awaiting_customer', 'awaiting_swipe')
            AND expires_at > NOW()
        ORDER BY id DESC
        LIMIT 1
    ]], { terminal.id })

    if activeIntent then
        return VancePay.Server.fail('该终端已有待支付订单', 'intent_exists', activeIntent)
    end

    local taxRate = VancePay.Stores and VancePay.Stores.getEffectiveTaxRate and VancePay.Stores.getEffectiveTaxRate(store) or 0
    local taxExempt = VancePay.Stores and VancePay.Stores.isTaxExempt and VancePay.Stores.isTaxExempt(store) or false
    local taxSettlement = VancePay.Stores and VancePay.Stores.getTaxSettlementTarget and VancePay.Stores.getTaxSettlementTarget(store) or {
        mode = VancePay.StoreSettlementModes.storeBalance,
        identifier = nil,
    }

    if taxRate > 0
        and taxSettlement.mode == VancePay.StoreSettlementModes.publicAccount
        and Utils.isBlank(taxSettlement.identifier) then
        return VancePay.Server.fail('当前店铺税收未绑定有效公账', 'invalid_tax_settlement')
    end

    local amounts = Utils.computeAmounts(subtotalAmount, discountRate, tipAmount, taxRate)
    local idempotencyKey = Utils.trim(payload.idempotency_key or payload.idempotencyKey) or Utils.generateCode('ID', 12)
    local intentCode = Utils.generateCode('PI', 10)
    local waitingStatus = method == VancePay.PaymentMethods.phone
        and VancePay.IntentStatuses.awaitingCustomer
        or VancePay.IntentStatuses.awaitingSwipe
    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + Config.IntentTimeout)
    local cashierCitizenId = VancePay.Permissions.getCitizenId(source)
    local commissionRate = VancePay.Stores and VancePay.Stores.getCommissionRate and VancePay.Stores.getCommissionRate(store) or 0
    local commissionAmount = not Utils.isBlank(cashierCitizenId)
        and Utils.computeCommissionAmount(amounts.net_amount, commissionRate)
        or 0

    local insertedId = MySQL.insert.await([[
        INSERT INTO vancepay_payment_intents (
            intent_code,
            terminal_id,
            store_id,
            cashier_citizenid,
            target_citizenid,
            item_description,
            item_lines,
            subtotal_amount,
            discount_rate,
            discount_amount,
            tip_amount,
            fee_amount,
            tax_rate,
            tax_exempt,
            tax_amount,
            commission_rate,
            commission_amount,
            tax_settlement_mode,
            tax_settlement_account_identifier,
            final_amount,
            method,
            status,
            idempotency_key,
            expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        intentCode,
        terminal.id,
        store.id,
        cashierCitizenId,
        targetRecord and targetRecord.citizenid or nil,
        itemDescription,
        encodedItemLines,
        amounts.subtotal_amount,
        amounts.discount_rate,
        amounts.discount_amount,
        amounts.tip_amount,
        amounts.fee_amount,
        amounts.tax_rate,
        taxExempt and 1 or 0,
        amounts.tax_amount,
        commissionRate,
        commissionAmount,
        taxSettlement.mode,
        taxSettlement.identifier,
        amounts.final_amount,
        method,
        waitingStatus,
        idempotencyKey,
        expiresAt,
    })

    if not insertedId then
        local existing = MySQL.single.await([[
            SELECT id
            FROM vancepay_payment_intents
            WHERE terminal_id = ? AND idempotency_key = ?
            LIMIT 1
        ]], { terminal.id, idempotencyKey })

        if existing and existing.id then
            return VancePay.Server.ok(Intents.fetchById(existing.id), '已返回已有待支付订单')
        end

        return VancePay.Server.fail('创建订单失败', 'db_error')
    end

    local intent = Intents.fetchById(insertedId)
    if not intent then
        return VancePay.Server.fail('订单创建成功但回查失败', 'post_fetch_failed')
    end

    Intents.syncScheduledExpiration(intent)

    Intents.pushUpdate(intent, {
        status = waitingStatus,
        message = method == VancePay.PaymentMethods.phone and '支付请求已发送给顾客' or '等待附近顾客刷卡',
    })

    if method == VancePay.PaymentMethods.phone and VancePay.Server.notifyLBPhonePaymentRequest then
        VancePay.Server.notifyLBPhonePaymentRequest(targetSource, intent)
    end

    if method == VancePay.PaymentMethods.phone then
        TriggerClientEvent(VancePay.Events.client.openCustomerIntent, targetSource, Intents.buildClientPayload(intent, {
            status = waitingStatus,
            message = '新的手机支付请求',
        }))

        VancePay.Server.notify(source, '支付请求已发送', 'inform')
        VancePay.Server.notify(
            targetSource,
            ('%s 向你发起一笔手机支付请求，金额 %s'):format(
                store.name,
                Utils.formatCurrency(intent.final_amount)
            ),
            'inform'
        )
    else
        notifyNearbyCardCustomers(source, VancePay.Events.client.openCustomerIntent, Intents.buildClientPayload(intent, {
            status = waitingStatus,
            message = '附近有一笔待刷卡订单',
        }))
        VancePay.Server.notify(source, '等待附近顾客刷卡', 'inform')
    end

    if VancePay.Kook and VancePay.Kook.logIntent then
        VancePay.Kook.logIntent('created', intent, {
            actor_citizenid = cashierCitizenId,
        })
    end

    if VancePay.FiveMLog and VancePay.FiveMLog.logIntent then
        VancePay.FiveMLog.logIntent('created', intent, {
            actor_citizenid = cashierCitizenId,
            source = source,
        })
    end

    return VancePay.Server.ok(intent, '待支付订单已创建')
end

function Intents.cancel(source, payload)
    Intents.ensureReady()
    payload = payload or {}
    local intent = Intents.fetchReference(payload)
    local valid, reason = assertIntentActive(intent)
    if not valid then
        return VancePay.Server.fail(reason, 'invalid_intent')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    local isAdmin = VancePay.Permissions.isAdmin(source)
    local isCashier = actorCitizenId == intent.cashier_citizenid
    local isTarget = actorCitizenId == intent.target_citizenid

    if not isAdmin and not isCashier and not isTarget then
        return VancePay.Server.fail('你不能取消这笔订单', 'forbidden')
    end

    local cancelReason = Utils.trim(payload.reason)
    if Utils.isBlank(cancelReason) then
        if isTarget then
            cancelReason = 'customer_declined'
        elseif isCashier then
            cancelReason = 'cashier_cancelled'
        else
            cancelReason = 'admin_cancelled'
        end
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_payment_intents
        SET status = 'cancelled',
            cancelled_reason = ?
        WHERE id = ?
            AND status IN ('awaiting_customer', 'awaiting_swipe')
    ]], { cancelReason, intent.id })

    if not updated or updated < 1 then
        return VancePay.Server.fail('订单取消失败', 'db_error')
    end

    Intents.clearScheduledExpiration(intent.id)

    local updatedIntent = Intents.fetchById(intent.id)
    Intents.syncScheduledExpiration(updatedIntent)
    Intents.pushUpdate(updatedIntent, {
        status = VancePay.IntentStatuses.cancelled,
        reason = cancelReason,
        message = '支付请求已取消',
    })

    local cashierSource = VancePay.Server.getSourceByCitizenId(updatedIntent.cashier_citizenid)
    local targetSource = VancePay.Server.getSourceByCitizenId(updatedIntent.target_citizenid)

    if cashierSource then
        local cashierMessage = '支付请求已取消'
        if isTarget then
            cashierMessage = '顾客已取消支付请求'
        elseif isAdmin and not isCashier then
            cashierMessage = '管理员已取消支付请求'
        end

        VancePay.Server.notify(cashierSource, cashierMessage, 'warning')
    end

    if targetSource then
        local targetMessage = isTarget and '你已取消支付请求' or '商家已取消支付请求'
        if isAdmin and not isTarget and not isCashier then
            targetMessage = '管理员已取消支付请求'
        end

        VancePay.Server.notify(targetSource, targetMessage, 'warning')
    end

    if VancePay.Kook and VancePay.Kook.logIntent then
        VancePay.Kook.logIntent('cancelled', updatedIntent, {
            actor_citizenid = actorCitizenId,
            reason = cancelReason,
        })
    end

    if VancePay.FiveMLog and VancePay.FiveMLog.logIntent then
        VancePay.FiveMLog.logIntent('cancelled', updatedIntent, {
            actor_citizenid = actorCitizenId,
            source = source,
            reason = cancelReason,
        })
    end

    return VancePay.Server.ok(updatedIntent, '订单已取消')
end

function Intents.markFailed(intent, reason)
    Intents.ensureReady()
    local updated = MySQL.update.await([[
        UPDATE vancepay_payment_intents
        SET status = 'failed',
            cancelled_reason = ?
        WHERE id = ?
            AND status IN ('awaiting_customer', 'awaiting_swipe')
    ]], { reason, intent.id })

    if updated and updated > 0 then
        Intents.clearScheduledExpiration(intent.id)
    end

    if updated and updated > 0 and VancePay.Kook and VancePay.Kook.logIntent then
        local failedIntent = Intents.fetchById(intent.id) or intent
        VancePay.Kook.logIntent('failed', failedIntent, {
            actor_citizenid = failedIntent.cashier_citizenid,
            reason = reason,
            status = VancePay.IntentStatuses.failed,
        })
    end

    if updated and updated > 0 and VancePay.FiveMLog and VancePay.FiveMLog.logIntent then
        local failedIntent = Intents.fetchById(intent.id) or intent
        VancePay.FiveMLog.logIntent('failed', failedIntent, {
            actor_citizenid = failedIntent.cashier_citizenid,
            reason = reason,
            status = VancePay.IntentStatuses.failed,
        })
    end
end

function Intents.expireOne(intentId)
    Intents.ensureReady()
    local intent = Intents.fetchById(intentId)
    local valid, reason = assertIntentActive(intent)
    if not valid and reason ~= '订单已超时' then
        Intents.clearScheduledExpiration(intentId)
        return false
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_payment_intents
        SET status = 'expired',
            cancelled_reason = 'timeout'
        WHERE id = ?
            AND status IN ('awaiting_customer', 'awaiting_swipe')
    ]], { intentId })

    if updated and updated > 0 then
        Intents.clearScheduledExpiration(intentId)
        local updatedIntent = Intents.fetchById(intentId)
        Intents.syncScheduledExpiration(updatedIntent)
        Intents.pushUpdate(updatedIntent, {
            status = VancePay.IntentStatuses.expired,
            reason = 'timeout',
            message = '此次支付请求已超时',
        })

        local cashierSource = VancePay.Server.getSourceByCitizenId(updatedIntent.cashier_citizenid)
        local targetSource = VancePay.Server.getSourceByCitizenId(updatedIntent.target_citizenid)

        if cashierSource then
            VancePay.Server.notify(cashierSource, '此次支付请求已超时', 'warning')
        end

        if targetSource then
            VancePay.Server.notify(targetSource, '此次支付请求已超时', 'warning')
        end

        if VancePay.Kook and VancePay.Kook.logIntent then
            VancePay.Kook.logIntent('expired', updatedIntent, {
                reason = 'timeout',
            })
        end

        if VancePay.FiveMLog and VancePay.FiveMLog.logIntent then
            VancePay.FiveMLog.logIntent('expired', updatedIntent, {
                reason = 'timeout',
            })
        end
    end

    if not updated or updated < 1 then
        Intents.clearScheduledExpiration(intentId)
    end

    return updated and updated > 0
end

local function getNextScheduledExpiration()
    local nextIntentId
    local nextExpiresAt

    for intentId, expiresAt in pairs(Intents._scheduledExpirations) do
        if type(expiresAt) ~= 'number' then
            Intents._scheduledExpirations[intentId] = nil
        elseif not nextExpiresAt
            or expiresAt < nextExpiresAt
            or (expiresAt == nextExpiresAt and intentId < nextIntentId) then
            nextIntentId = intentId
            nextExpiresAt = expiresAt
        end
    end

    return nextIntentId, nextExpiresAt
end

local function collectDueIntentIds(now)
    local dueIntentIds = {}

    for intentId, expiresAt in pairs(Intents._scheduledExpirations) do
        if type(expiresAt) ~= 'number' then
            Intents._scheduledExpirations[intentId] = nil
        elseif expiresAt <= now then
            dueIntentIds[#dueIntentIds + 1] = {
                id = intentId,
                expires_at = expiresAt,
            }
        end
    end

    table.sort(dueIntentIds, function(left, right)
        if left.expires_at == right.expires_at then
            return left.id < right.id
        end

        return left.expires_at < right.expires_at
    end)

    return dueIntentIds
end

CreateThread(function()
    Intents.ensureReady()

    while true do
        local _, nextExpiresAt = getNextScheduledExpiration()
        if not nextExpiresAt then
            Wait(1000)
        else
            local waitMs = math.max(0, (nextExpiresAt - os.time()) * 1000)
            if waitMs > 0 then
                Wait(math.min(waitMs, 1000))
            else
                local dueIntentIds = collectDueIntentIds(os.time())
                for index = 1, #dueIntentIds do
                    Intents.expireOne(dueIntentIds[index].id)
                end
            end
        end
    end
end)

lib.callback.register('vancepay:server:createIntent', function(source, payload)
    return Intents.create(source, payload or {})
end)

lib.callback.register('vancepay:server:cancelIntent', function(source, payload)
    return Intents.cancel(source, payload or {})
end)

lib.callback.register('vancepay:server:getCustomerPendingIntents', function(source, payload)
    payload = payload or {}

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) then
        return VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    return VancePay.Server.ok({
        items = Intents.listAssignedPendingByCitizenId(citizenid, payload.limit or 20),
    })
end)

lib.callback.register('vancepay:server:getReachableCardIntents', function(source, payload)
    payload = payload or {}

    return VancePay.Server.ok({
        items = Intents.listReachableCardPendingBySource(source, payload.limit or 20),
    })
end)
