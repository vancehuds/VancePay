VancePay.Transactions = VancePay.Transactions or {}

local Transactions = VancePay.Transactions

Transactions._ready = Transactions._ready or false
Transactions._initializing = Transactions._initializing or false

local function getDatabaseConfig()
    return Config.Database or {}
end

local function shouldRunSchemaMigrations()
    return getDatabaseConfig().autoMigrate == true
end

local function shouldBackfillRefundSummaries()
    return getDatabaseConfig().backfillTransactionRefunds == true
end

local TRANSACTION_SELECT = [[
    SELECT
        t.*,
        original.tx_code AS original_tx_code
    FROM vancepay_transactions t
    LEFT JOIN vancepay_transactions original ON original.id = t.original_tx_id
]]

local function normalizeTransaction(row)
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

    row.tax_rate = Utils.roundCurrency(row.tax_rate or 0)
    row.tax_exempt = Utils.parseBool(row.tax_exempt)
    row.tax_amount = Utils.roundCurrency(row.tax_amount or 0)
    row.commission_rate = Utils.roundCurrency(row.commission_rate or 0)
    row.commission_amount = Utils.roundCurrency(row.commission_amount or 0)
    row.refunded_commission_amount = Utils.roundCurrency(row.refunded_commission_amount or 0)
    row.refunded_tax_amount = Utils.roundCurrency(row.refunded_tax_amount or 0)
    row.tax_settlement_mode = row.tax_settlement_mode == VancePay.StoreSettlementModes.publicAccount
        and VancePay.StoreSettlementModes.publicAccount
        or VancePay.StoreSettlementModes.storeBalance
    row.tax_settlement_account_identifier = Utils.trim(row.tax_settlement_account_identifier)

    return row
end

local function roundAmount(value)
    return Utils.roundCurrency(value or 0)
end

local function getStoreNetAfterCommission(netAmount, commissionAmount)
    netAmount = roundAmount(netAmount)
    commissionAmount = roundAmount(commissionAmount)
    return roundAmount(math.max(0, netAmount - commissionAmount))
end

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
            AND TABLE_NAME = 'vancepay_transactions'
            AND COLUMN_NAME = ?
        LIMIT 1
    ]], { columnName })
end

local function fetchTransactionColumnMap()
    local rows = MySQL.query.await([[
        SELECT
            COLUMN_NAME,
            COLUMN_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'vancepay_transactions'
    ]]) or {}

    local columnMap = {}

    for index = 1, #rows do
        local row = rows[index]
        local columnName = getSchemaValue(row, 'COLUMN_NAME', 'column_name')
        if columnName then
            columnMap[columnName] = tostring(getSchemaValue(row, 'COLUMN_TYPE', 'column_type') or '')
        end
    end

    return columnMap
end

local function fetchIntentColumnMap()
    local rows = MySQL.query.await([[
        SELECT
            COLUMN_NAME,
            COLUMN_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'vancepay_payment_intents'
    ]]) or {}

    local columnMap = {}

    for index = 1, #rows do
        local row = rows[index]
        local columnName = getSchemaValue(row, 'COLUMN_NAME', 'column_name')
        if columnName then
            columnMap[columnName] = tostring(getSchemaValue(row, 'COLUMN_TYPE', 'column_type') or '')
        end
    end

    return columnMap
end

local function appendTransactionSchemaIssues(issues)
    local columnMap = fetchTransactionColumnMap()
    if next(columnMap) == nil then
        issues[#issues + 1] = '缺少表 vancepay_transactions'
        return issues
    end

    local requiredColumns = {
        'item_description',
        'item_lines',
        'tax_rate',
        'tax_exempt',
        'tax_amount',
        'commission_rate',
        'commission_amount',
        'tax_settlement_mode',
        'tax_settlement_account_identifier',
        'refunded_final_amount',
        'refunded_net_amount',
        'refunded_tax_amount',
        'refunded_commission_amount',
    }

    for index = 1, #requiredColumns do
        local columnName = requiredColumns[index]
        if not columnMap[columnName] then
            issues[#issues + 1] = ('缺少列 %s'):format(columnName)
        end
    end

    local statusColumnType = columnMap.status or ''
    if statusColumnType ~= '' and not statusColumnType:find('partially_refunded', 1, true) then
        issues[#issues + 1] = 'status 枚举缺少 partially_refunded'
    end

    local taxSettlementModeColumnType = columnMap.tax_settlement_mode or ''
    if taxSettlementModeColumnType ~= '' and not taxSettlementModeColumnType:find('public_account', 1, true) then
        issues[#issues + 1] = 'tax_settlement_mode 枚举缺少 public_account'
    end

    return issues
end

local function appendIntentSchemaIssues(issues)
    local columnMap = fetchIntentColumnMap()
    if next(columnMap) == nil then
        issues[#issues + 1] = '缺少表 vancepay_payment_intents'
        return issues
    end

    if not columnMap.completed_at then
        issues[#issues + 1] = 'vancepay_payment_intents 缺少列 completed_at'
    end

    if not columnMap.commission_rate then
        issues[#issues + 1] = 'vancepay_payment_intents 缺少列 commission_rate'
    end

    if not columnMap.commission_amount then
        issues[#issues + 1] = 'vancepay_payment_intents 缺少列 commission_amount'
    end

    local statusColumnType = columnMap.status or ''
    if statusColumnType ~= ''
        and (not statusColumnType:find('awaiting_customer', 1, true)
            or not statusColumnType:find('awaiting_swipe', 1, true)
            or not statusColumnType:find('completed', 1, true)
            or not statusColumnType:find('failed', 1, true)) then
        issues[#issues + 1] = 'vancepay_payment_intents.status 枚举不完整'
    end

    return issues
end

local function getRuntimeSchemaIssues(action)
    local issues = {}
    appendTransactionSchemaIssues(issues)

    if action == 'payment' then
        appendIntentSchemaIssues(issues)
    end

    return issues
end

local function ensureRuntimeSchemaCompatible(action)
    local issues = getRuntimeSchemaIssues(action)
    if #issues == 0 then
        return true
    end

    Utils.debug('Transaction schema compatibility check failed', action or 'unknown', table.concat(issues, '; '))

    return false, '数据库结构未升级到最新版本，请先执行 sql/migrate_to_latest.sql'
end

local function ensureSchema()
    local tableExists = MySQL.single.await([[
        SELECT 1 AS present
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'vancepay_transactions'
        LIMIT 1
    ]])

    if not tableExists then
        return
    end

    local migrationApplied = false
    local statusColumn = fetchColumnMetadata('status')
    local statusColumnType = tostring(getSchemaValue(statusColumn, 'COLUMN_TYPE', 'column_type') or '')

    if not statusColumnType:find('partially_refunded', 1, true) then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            MODIFY COLUMN status ENUM('completed', 'partially_refunded', 'refunded') NOT NULL DEFAULT 'completed'
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('refunded_final_amount') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN refunded_final_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER net_amount
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('refunded_net_amount') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN refunded_net_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER refunded_final_amount
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('item_description') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN item_description VARCHAR(255) DEFAULT NULL AFTER terminal_serial_snapshot
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('item_lines') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN item_lines JSON DEFAULT NULL AFTER item_description
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('tax_rate') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER fee_amount
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('tax_exempt') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN tax_exempt TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_rate
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('tax_amount') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER tax_exempt
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('commission_rate') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER tax_amount
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('commission_amount') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER commission_rate
        ]])
        migrationApplied = true
    end

    local taxSettlementModeColumn = fetchColumnMetadata('tax_settlement_mode')
    local taxSettlementModeColumnType = tostring(getSchemaValue(taxSettlementModeColumn, 'COLUMN_TYPE', 'column_type') or '')
    if not taxSettlementModeColumn then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance' AFTER commission_amount
        ]])
        migrationApplied = true
    elseif not taxSettlementModeColumnType:find('public_account', 1, true) then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            MODIFY COLUMN tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance'
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('tax_settlement_account_identifier') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER tax_settlement_mode
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('refunded_tax_amount') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN refunded_tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER refunded_net_amount
        ]])
        migrationApplied = true
    end

    if not fetchColumnMetadata('refunded_commission_amount') then
        MySQL.query.await([[
            ALTER TABLE vancepay_transactions
            ADD COLUMN refunded_commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER refunded_tax_amount
        ]])
        migrationApplied = true
    end

    if migrationApplied or shouldBackfillRefundSummaries() then
        MySQL.query.await([[
            UPDATE vancepay_transactions payment
            LEFT JOIN (
                SELECT
                    original_tx_id,
                    COALESCE(SUM(final_amount), 0) AS refunded_final_amount,
                    COALESCE(SUM(net_amount), 0) AS refunded_net_amount,
                    COALESCE(SUM(tax_amount), 0) AS refunded_tax_amount,
                    COALESCE(SUM(commission_amount), 0) AS refunded_commission_amount
                FROM vancepay_transactions
                WHERE type = 'refund'
                    AND original_tx_id IS NOT NULL
                GROUP BY original_tx_id
            ) refunds ON refunds.original_tx_id = payment.id
            SET payment.refunded_final_amount = COALESCE(refunds.refunded_final_amount, 0),
                payment.refunded_net_amount = COALESCE(refunds.refunded_net_amount, 0),
                payment.refunded_tax_amount = COALESCE(refunds.refunded_tax_amount, 0),
                payment.refunded_commission_amount = COALESCE(refunds.refunded_commission_amount, 0),
                payment.status = CASE
                    WHEN COALESCE(refunds.refunded_final_amount, 0) >= payment.final_amount THEN 'refunded'
                    WHEN COALESCE(refunds.refunded_final_amount, 0) > 0 THEN 'partially_refunded'
                    ELSE 'completed'
                END
            WHERE payment.type = 'payment'
        ]])
    end
end

function Transactions.ensureReady()
    if Transactions._ready then
        return true
    end

    while Transactions._initializing do
        Wait(50)
        if Transactions._ready then
            return true
        end
    end

    Transactions._initializing = true
    local ok, err = pcall(function()
        if shouldRunSchemaMigrations() or shouldBackfillRefundSummaries() then
            ensureSchema()
        end
    end)
    Transactions._initializing = false
    if not ok then
        error(err)
    end

    Transactions._ready = true
    return true
end

function Transactions.fetchById(transactionId)
    Transactions.ensureReady()

    if not tonumber(transactionId) then
        return nil
    end

    local row = MySQL.single.await(TRANSACTION_SELECT .. ' WHERE t.id = ? LIMIT 1', { tonumber(transactionId) })
    return normalizeTransaction(row)
end

function Transactions.listRefundsByOriginalId(transactionId)
    Transactions.ensureReady()

    if not tonumber(transactionId) then
        return {}
    end

    local rows = MySQL.query.await(TRANSACTION_SELECT .. ' WHERE t.original_tx_id = ? ORDER BY t.id DESC', { tonumber(transactionId) }) or {}

    for index = 1, #rows do
        rows[index] = normalizeTransaction(rows[index])
    end

    return rows
end

function Transactions.fetchRefundByOriginalId(transactionId)
    local refunds = Transactions.listRefundsByOriginalId(transactionId)
    return refunds[1]
end

local function buildRefundSummary(paymentTransaction, refunds)
    if not paymentTransaction then
        return nil
    end

    refunds = refunds or {}

    local refundedSubtotalAmount = 0
    local refundedDiscountAmount = 0
    local refundedTipAmount = 0
    local refundedFeeAmount = 0
    local refundedTaxAmount = 0
    local refundedFinalAmount = 0
    local refundedNetAmount = 0
    local refundedCommissionAmount = 0

    for index = 1, #refunds do
        local refund = refunds[index]
        refundedSubtotalAmount = roundAmount(refundedSubtotalAmount + refund.subtotal_amount)
        refundedDiscountAmount = roundAmount(refundedDiscountAmount + refund.discount_amount)
        refundedTipAmount = roundAmount(refundedTipAmount + refund.tip_amount)
        refundedFeeAmount = roundAmount(refundedFeeAmount + refund.fee_amount)
        refundedTaxAmount = roundAmount(refundedTaxAmount + (refund.tax_amount or 0))
        refundedFinalAmount = roundAmount(refundedFinalAmount + refund.final_amount)
        refundedNetAmount = roundAmount(refundedNetAmount + refund.net_amount)
        refundedCommissionAmount = roundAmount(refundedCommissionAmount + (refund.commission_amount or 0))
    end

    local totalFinalAmount = roundAmount(paymentTransaction.final_amount)
    local totalNetAmount = roundAmount(paymentTransaction.net_amount)
    local totalTaxAmount = roundAmount(paymentTransaction.tax_amount or 0)
    local totalCommissionAmount = roundAmount(paymentTransaction.commission_amount or 0)

    return {
        refund_count = #refunds,
        refunded_subtotal_amount = refundedSubtotalAmount,
        refunded_discount_amount = refundedDiscountAmount,
        refunded_tip_amount = refundedTipAmount,
        refunded_fee_amount = refundedFeeAmount,
        refunded_tax_amount = refundedTaxAmount,
        refunded_final_amount = refundedFinalAmount,
        refunded_net_amount = refundedNetAmount,
        refunded_commission_amount = refundedCommissionAmount,
        remaining_tax_amount = roundAmount(math.max(0, totalTaxAmount - refundedTaxAmount)),
        remaining_final_amount = roundAmount(math.max(0, totalFinalAmount - refundedFinalAmount)),
        remaining_net_amount = roundAmount(math.max(0, totalNetAmount - refundedNetAmount)),
        remaining_commission_amount = roundAmount(math.max(0, totalCommissionAmount - refundedCommissionAmount)),
        is_fully_refunded = refundedFinalAmount >= totalFinalAmount,
    }
end

function Transactions.listInternal(filters)
    Transactions.ensureReady()

    filters = filters or {}
    local page, perPage, offset = Utils.getPageOffset(filters.page, filters.per_page or Config.TransPerPage)
    local conditions = { '1=1' }
    local params = {}

    if filters.store_id then
        conditions[#conditions + 1] = 't.store_id = ?'
        params[#params + 1] = tonumber(filters.store_id)
    end

    if filters.method and filters.method ~= 'all' then
        conditions[#conditions + 1] = 't.method = ?'
        params[#params + 1] = filters.method
    end

    if filters.type and filters.type ~= 'all' then
        conditions[#conditions + 1] = 't.type = ?'
        params[#params + 1] = filters.type
    end

    if filters.status and filters.status ~= 'all' then
        conditions[#conditions + 1] = 't.status = ?'
        params[#params + 1] = filters.status
    end

    if filters.date_from then
        conditions[#conditions + 1] = 'DATE(t.created_at) >= DATE(?)'
        params[#params + 1] = filters.date_from
    end

    if filters.date_to then
        conditions[#conditions + 1] = 'DATE(t.created_at) <= DATE(?)'
        params[#params + 1] = filters.date_to
    end

    local query = (TRANSACTION_SELECT .. [[
        WHERE %s
        ORDER BY t.id DESC
        LIMIT ? OFFSET ?
    ]]):format(table.concat(conditions, ' AND '))

    params[#params + 1] = perPage
    params[#params + 1] = offset

    local rows = MySQL.query.await(query, params) or {}

    for index = 1, #rows do
        rows[index] = normalizeTransaction(rows[index])
    end

    return {
        items = rows,
        page = page,
        per_page = perPage,
    }
end

function Transactions.fetchDetail(transactionId)
    Transactions.ensureReady()

    local transaction = Transactions.fetchById(transactionId)
    if not transaction then
        return nil
    end

    local original = transaction.original_tx_id and Transactions.fetchById(transaction.original_tx_id) or nil
    local paymentTransaction = transaction.type == VancePay.TransactionTypes.payment and transaction or original
    local refunds = paymentTransaction and Transactions.listRefundsByOriginalId(paymentTransaction.id) or {}
    local refundSummary = paymentTransaction and buildRefundSummary(paymentTransaction, refunds) or nil
    local intent = transaction.intent_id and VancePay.Intents.fetchById(transaction.intent_id) or nil

    return {
        transaction = transaction,
        original = original,
        refund = refunds[1],
        refunds = refunds,
        refund_summary = refundSummary,
        intent = intent,
    }
end

local function ensureRefundAllowed(source, transaction)
    if not transaction then
        return false, '原交易不存在'
    end

    if transaction.type ~= VancePay.TransactionTypes.payment then
        return false, '只能对支付交易执行退款'
    end

    if transaction.status ~= VancePay.TransactionStatuses.completed
        and transaction.status ~= VancePay.TransactionStatuses.partiallyRefunded then
        return false, '该交易已退款或状态无效'
    end

    local isAdmin = VancePay.Permissions.isAdmin(source)
    if not isAdmin then
        local allowed, reason = VancePay.Permissions.checkAccess(source, transaction.store_id, 'refund')
        if not allowed then
            return false, reason
        end
    end

    if Config.RefundTimeLimit > 0 and not (isAdmin and Config.AdminBypassRefundLimit) then
        local createdAt = Utils.parseSqlDateTime(transaction.created_at)
        if createdAt and (os.time() - createdAt) > Config.RefundTimeLimit then
            return false, '已超过退款时限'
        end
    end

    local refunds = Transactions.listRefundsByOriginalId(transaction.id)
    local refundSummary = buildRefundSummary(transaction, refunds)
    if refundSummary and refundSummary.remaining_final_amount <= 0 then
        return false, '该交易已全部退款'
    end

    return true, nil, refundSummary, refunds
end

local function buildRefundAmounts(transaction, refundSummary, refundAmount)
    local remainingFinalAmount = roundAmount(refundSummary.remaining_final_amount)
    local remainingNetAmount = roundAmount(refundSummary.remaining_net_amount)
    local remainingSubtotalAmount = roundAmount(roundAmount(transaction.subtotal_amount) - roundAmount(refundSummary.refunded_subtotal_amount))
    local remainingDiscountAmount = roundAmount(roundAmount(transaction.discount_amount) - roundAmount(refundSummary.refunded_discount_amount))
    local remainingTipAmount = roundAmount(roundAmount(transaction.tip_amount) - roundAmount(refundSummary.refunded_tip_amount))
    local remainingFeeAmount = roundAmount(roundAmount(transaction.fee_amount) - roundAmount(refundSummary.refunded_fee_amount))
    local remainingTaxAmount = roundAmount(roundAmount(transaction.tax_amount or 0) - roundAmount(refundSummary.refunded_tax_amount or 0))
    local remainingCommissionAmount = roundAmount(roundAmount(transaction.commission_amount or 0) - roundAmount(refundSummary.refunded_commission_amount or 0))

    if refundAmount >= remainingFinalAmount then
        return {
            subtotal_amount = remainingSubtotalAmount,
            discount_rate = roundAmount(transaction.discount_rate),
            discount_amount = remainingDiscountAmount,
            tip_amount = remainingTipAmount,
            fee_amount = remainingFeeAmount,
            tax_rate = roundAmount(transaction.tax_rate or 0),
            tax_exempt = Utils.parseBool(transaction.tax_exempt),
            tax_amount = remainingTaxAmount,
            commission_rate = roundAmount(transaction.commission_rate or 0),
            commission_amount = remainingCommissionAmount,
            final_amount = remainingFinalAmount,
            net_amount = remainingNetAmount,
        }
    end

    local ratio = refundAmount / remainingFinalAmount
    local scaleAmount = function(amount)
        amount = roundAmount(amount)
        return roundAmount(math.min(amount, amount * ratio))
    end

    return {
        subtotal_amount = scaleAmount(remainingSubtotalAmount),
        discount_rate = roundAmount(transaction.discount_rate),
        discount_amount = scaleAmount(remainingDiscountAmount),
        tip_amount = scaleAmount(remainingTipAmount),
        fee_amount = scaleAmount(remainingFeeAmount),
        tax_rate = roundAmount(transaction.tax_rate or 0),
        tax_exempt = Utils.parseBool(transaction.tax_exempt),
        tax_amount = scaleAmount(remainingTaxAmount),
        commission_rate = roundAmount(transaction.commission_rate or 0),
        commission_amount = scaleAmount(remainingCommissionAmount),
        final_amount = refundAmount,
        net_amount = scaleAmount(remainingNetAmount),
    }
end

local function normalizeSettlementMode(mode)
    if mode == VancePay.StoreSettlementModes.publicAccount then
        return VancePay.StoreSettlementModes.publicAccount
    end

    return VancePay.StoreSettlementModes.storeBalance
end

local function getStoreSettlement(store)
    if not store then
        return nil, '店铺不存在'
    end

    local settlement = VancePay.Stores and VancePay.Stores.getSettlementTarget and VancePay.Stores.getSettlementTarget(store) or {
        mode = VancePay.StoreSettlementModes.storeBalance,
        identifier = nil,
        label = 'VancePay 店铺余额',
        is_direct = false,
    }

    if settlement.mode == VancePay.StoreSettlementModes.publicAccount and Utils.isBlank(settlement.identifier) then
        return nil, '当前店铺未绑定有效公账'
    end

    return settlement
end

local function getIntentTaxSettlement(intent)
    local mode = normalizeSettlementMode(intent and intent.tax_settlement_mode)
    local identifier = Utils.trim(intent and intent.tax_settlement_account_identifier or nil)

    if mode == VancePay.StoreSettlementModes.publicAccount and Utils.isBlank(identifier) then
        return nil, '当前订单税收未绑定有效公账'
    end

    return {
        mode = mode,
        identifier = identifier,
        is_direct = mode == VancePay.StoreSettlementModes.publicAccount,
    }
end

local function getTransactionTaxSettlement(transaction, store)
    local mode = normalizeSettlementMode(transaction and transaction.tax_settlement_mode)
    local identifier = Utils.trim(transaction and transaction.tax_settlement_account_identifier or nil)

    if mode == VancePay.StoreSettlementModes.publicAccount and Utils.isBlank(identifier) and store then
        local fallback = VancePay.Stores and VancePay.Stores.getTaxSettlementTarget and VancePay.Stores.getTaxSettlementTarget(store) or nil
        if fallback then
            mode = normalizeSettlementMode(fallback.mode)
            identifier = Utils.trim(fallback.identifier)
        end
    end

    if mode == VancePay.StoreSettlementModes.publicAccount and Utils.isBlank(identifier) then
        return nil, '当前交易税收未绑定有效公账'
    end

    return {
        mode = mode,
        identifier = identifier,
        is_direct = mode == VancePay.StoreSettlementModes.publicAccount,
    }
end

local function processIntentPayment(source, intent, proximityValidator)
    Transactions.ensureReady()

    local schemaCompatible, schemaError = ensureRuntimeSchemaCompatible('payment')
    if not schemaCompatible then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local valid, reason = (function()
        if not intent then
            return false, '订单不存在'
        end

        if intent.status ~= VancePay.IntentStatuses.awaitingCustomer
            and intent.status ~= VancePay.IntentStatuses.awaitingSwipe then
            return false, '订单状态不允许继续支付'
        end

        local expiresAt = Utils.parseSqlDateTime(intent.expires_at)
        if expiresAt and expiresAt <= os.time() then
            return false, '订单已超时'
        end

        return true
    end)()

    if not valid then
        if reason == '订单已超时' then
            VancePay.Intents.expireOne(intent.id)
        end

        return VancePay.Server.fail(reason, 'invalid_intent')
    end

    local customerCitizenId = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(customerCitizenId) then
        return VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    if intent.method == VancePay.PaymentMethods.phone and customerCitizenId ~= intent.target_citizenid then
        return VancePay.Server.fail('这笔订单不是发给你的', 'wrong_target')
    end

    if intent.method == VancePay.PaymentMethods.card and customerCitizenId == intent.cashier_citizenid then
        return VancePay.Server.fail('收银员不能自己刷这笔订单', 'cashier_cannot_swipe')
    end

    if proximityValidator and not proximityValidator(intent) then
        return VancePay.Server.fail('你当前不在可刷卡范围内', 'out_of_range')
    end

    if not VancePay.Banking.hasFunds(customerCitizenId, intent.final_amount) then
        return VancePay.Server.fail(('余额不足，还需 %s'):format(Utils.formatCurrency(intent.final_amount - VancePay.Banking.getBalance(customerCitizenId))), 'insufficient_funds')
    end

    local store = VancePay.Stores.fetchById(intent.store_id)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'store_not_found')
    end

    local settlement, settlementError = getStoreSettlement(store)
    if not settlement then
        return VancePay.Server.fail(settlementError, 'invalid_store_settlement')
    end

    local taxAmount = roundAmount(intent.tax_amount or 0)
    local taxSettlement, taxSettlementError = nil, nil
    if taxAmount > 0 then
        taxSettlement, taxSettlementError = getIntentTaxSettlement(intent)
        if not taxSettlement then
            return VancePay.Server.fail(taxSettlementError, 'invalid_tax_settlement')
        end
    end

    local commissionRate = roundAmount(intent.commission_rate or 0)
    local commissionAmount = roundAmount(intent.commission_amount or 0)
    local storeNetAmount = getStoreNetAfterCommission(intent.net_amount, commissionAmount)

    if commissionAmount > 0 then
        local balanceSchemaAvailable, balanceSchemaError = VancePay.Balance.ensureSchemaAvailable()
        if not balanceSchemaAvailable then
            return VancePay.Server.fail(balanceSchemaError, 'db_schema_outdated')
        end
    end

    local withdrawn = VancePay.Banking.withdraw(customerCitizenId, intent.final_amount, ('vancepay:%s:%s'):format(intent.method, intent.intent_code))
    if not withdrawn then
        return VancePay.Server.fail('扣款失败', 'withdraw_failed')
    end

    local function rollbackCustomerWithdrawal()
        local customerRolledBack = VancePay.Banking.deposit(
            customerCitizenId,
            intent.final_amount,
            ('vancepay:rollback:%s'):format(intent.intent_code)
        )

        if not customerRolledBack then
            Utils.debug('Customer rollback after payment failure failed', intent.intent_code, customerCitizenId)
        end
    end

    local directSettlementsApplied = {}
    local function rollbackDirectSettlements()
        for index = #directSettlementsApplied, 1, -1 do
            local entry = directSettlementsApplied[index]
            local rolledBack = VancePay.Banking.withdraw(entry.identifier, entry.amount, entry.rollback_reason)
            if not rolledBack then
                Utils.debug('Direct settlement rollback failed', entry.identifier, entry.amount, entry.rollback_reason)
            end
        end
    end

    if settlement.mode == VancePay.StoreSettlementModes.publicAccount and storeNetAmount > 0 then
        local deposited = VancePay.Banking.deposit(
            settlement.identifier,
            storeNetAmount,
            ('vancepay:store:%s:%s'):format(intent.store_id, intent.intent_code)
        )

        if not deposited then
            rollbackCustomerWithdrawal()
            return VancePay.Server.fail('店铺公账入账失败，已尝试回滚顾客扣款', 'settlement_failed')
        end

        directSettlementsApplied[#directSettlementsApplied + 1] = {
            identifier = settlement.identifier,
            amount = storeNetAmount,
            rollback_reason = ('vancepay:store_rollback:%s'):format(intent.intent_code),
        }
    end

    if taxSettlement and taxSettlement.mode == VancePay.StoreSettlementModes.publicAccount and taxAmount > 0 then
        local deposited = VancePay.Banking.deposit(
            taxSettlement.identifier,
            taxAmount,
            ('vancepay:tax:%s:%s'):format(intent.store_id, intent.intent_code)
        )

        if not deposited then
            rollbackDirectSettlements()
            rollbackCustomerWithdrawal()
            return VancePay.Server.fail('税收公账入账失败，已尝试回滚顾客扣款', 'tax_settlement_failed')
        end

        directSettlementsApplied[#directSettlementsApplied + 1] = {
            identifier = taxSettlement.identifier,
            amount = taxAmount,
            rollback_reason = ('vancepay:tax_rollback:%s'):format(intent.intent_code),
        }
    end

    local transactionCode = Utils.generateCode('TX', 10)
    local encodedItemLines = type(intent.item_lines) == 'table' and #intent.item_lines > 0 and json.encode(intent.item_lines) or nil
    local transactionCustomerCitizenId = intent.method == VancePay.PaymentMethods.card
        and customerCitizenId
        or intent.target_citizenid

    local queries = {}
    local internalStoreCredit = 0
    if settlement.mode ~= VancePay.StoreSettlementModes.publicAccount then
        internalStoreCredit = roundAmount(internalStoreCredit + storeNetAmount)
    end

    if taxSettlement and taxSettlement.mode ~= VancePay.StoreSettlementModes.publicAccount then
        internalStoreCredit = roundAmount(internalStoreCredit + taxAmount)
    end

    if internalStoreCredit > 0 then
        queries[#queries + 1] = {
            query = 'UPDATE vancepay_stores SET balance = balance + ? WHERE id = ?',
            values = { internalStoreCredit, intent.store_id }
        }
    end

    queries[#queries + 1] = {
        query = [[
            INSERT INTO vancepay_transactions (
                tx_code,
                type,
                intent_id,
                original_tx_id,
                terminal_id,
                store_id,
                cashier_citizenid,
                customer_citizenid,
                processed_by_citizenid,
                store_name_snapshot,
                terminal_serial_snapshot,
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
                net_amount,
                method,
                status,
                refund_reason
            ) VALUES (?, 'payment', ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'completed', NULL)
        ]],
        values = {
            transactionCode,
            intent.id,
            intent.terminal_id,
            intent.store_id,
            intent.cashier_citizenid,
            transactionCustomerCitizenId,
            customerCitizenId,
            intent.store_name,
            intent.terminal_serial_number,
            intent.item_description,
            encodedItemLines,
            intent.subtotal_amount,
            intent.discount_rate,
            intent.discount_amount,
            intent.tip_amount,
            intent.fee_amount,
            intent.tax_rate or 0,
            Utils.parseBool(intent.tax_exempt) and 1 or 0,
            taxAmount,
            commissionRate,
            commissionAmount,
            taxSettlement and taxSettlement.mode or VancePay.StoreSettlementModes.storeBalance,
            taxSettlement and taxSettlement.identifier or nil,
            intent.final_amount,
            intent.net_amount,
            intent.method,
        }
    }

    if commissionAmount > 0 then
        VancePay.Balance.appendEntryQuery(queries, {
            citizenid = intent.cashier_citizenid,
            store_id = intent.store_id,
            entry_type = 'commission',
            amount = commissionAmount,
            reference_code = transactionCode,
            store_name_snapshot = intent.store_name,
            description = intent.item_description or ('交易 %s 提成'):format(transactionCode),
            available_at = VancePay.Balance.getCommissionAvailableAt(os.time()),
        })
    end

    queries[#queries + 1] = {
        query = [[
            UPDATE vancepay_payment_intents
            SET status = 'completed',
                completed_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ]],
        values = { intent.id }
    }

    local success = MySQL.transaction.await(queries)

    if not success then
        Utils.debug('Payment database transaction failed', intent.intent_code, intent.id, intent.store_id, intent.method)
        rollbackDirectSettlements()
        rollbackCustomerWithdrawal()
        VancePay.Intents.markFailed(intent, 'db_transaction_failed')
        return VancePay.Server.fail('支付处理失败，已尝试回滚', 'db_error')
    end

    VancePay.Intents.clearScheduledExpiration(intent.id)

    local transaction = MySQL.single.await(TRANSACTION_SELECT .. ' WHERE t.tx_code = ? LIMIT 1', { transactionCode })
    transaction = normalizeTransaction(transaction)

    local completedIntent = VancePay.Intents.fetchById(intent.id)
    VancePay.Intents.syncScheduledExpiration(completedIntent)
    VancePay.Intents.pushUpdate(completedIntent, {
        status = VancePay.IntentStatuses.completed,
        message = '支付成功',
        transaction = transaction,
    })

    local cashierSource = VancePay.Server.getSourceByCitizenId(intent.cashier_citizenid)
    if cashierSource then
        local cashierMessage = ('收款成功 %s（%s）'):format(
            Utils.formatCurrency(intent.final_amount),
            intent.method == VancePay.PaymentMethods.card and '刷卡' or '手机'
        )

        if commissionAmount > 0 then
            cashierMessage = ('%s，提成 %s 已记入 VancePay 余额，24 小时后可提现'):format(
                cashierMessage,
                Utils.formatCurrency(commissionAmount)
            )
        end

        VancePay.Server.notify(cashierSource, cashierMessage, 'success')
    end

    VancePay.Server.notify(source, ('支付成功 %s -> %s'):format(
        Utils.formatCurrency(intent.final_amount),
        intent.store_name
    ), 'success')

    if VancePay.Kook and VancePay.Kook.logTransaction then
        VancePay.Kook.logTransaction('payment_completed', transaction, {
            intent = completedIntent or intent,
            detail = {
                subtotal_amount = transaction.subtotal_amount,
                discount_rate = transaction.discount_rate,
                discount_amount = transaction.discount_amount,
                tip_amount = transaction.tip_amount,
                fee_amount = transaction.fee_amount,
                tax_rate = transaction.tax_rate,
                tax_amount = transaction.tax_amount,
                commission_rate = transaction.commission_rate,
                commission_amount = transaction.commission_amount,
                tax_exempt = transaction.tax_exempt,
                tax_settlement_mode = transaction.tax_settlement_mode,
                tax_settlement_account_identifier = transaction.tax_settlement_account_identifier,
                final_amount = transaction.final_amount,
                net_amount = transaction.net_amount,
            }
        })
    end

    if VancePay.FiveMLog and VancePay.FiveMLog.logTransaction then
        VancePay.FiveMLog.logTransaction('payment_completed', transaction, {
            intent = completedIntent or intent,
            source = source,
        })
    end

    if commissionAmount > 0 and VancePay.Balance and VancePay.Balance.refreshClientState then
        VancePay.Balance.refreshClientState(intent.cashier_citizenid, 'commission_credit')
    end

    return VancePay.Server.ok({
        intent = completedIntent,
        transaction = transaction,
    }, '支付成功')
end

function Transactions.confirmIntent(source, payload)
    payload = payload or {}
    local intent = VancePay.Intents.fetchReference(payload)
    if not intent then
        return VancePay.Server.fail('订单不存在', 'not_found')
    end

    if intent.method ~= VancePay.PaymentMethods.phone or intent.status ~= VancePay.IntentStatuses.awaitingCustomer then
        return VancePay.Server.fail('该订单不处于手机支付确认状态', 'invalid_state')
    end

    return processIntentPayment(source, intent)
end

function Transactions.swipeIntent(source, payload)
    payload = payload or {}
    local intent = VancePay.Intents.fetchReference(payload)
    if not intent then
        return VancePay.Server.fail('订单不存在', 'not_found')
    end

    if intent.method ~= VancePay.PaymentMethods.card or intent.status ~= VancePay.IntentStatuses.awaitingSwipe then
        return VancePay.Server.fail('该订单不处于刷卡状态', 'invalid_state')
    end

    if not VancePay.Banking.hasCard(source) then
        return VancePay.Server.fail('未检测到银行卡', 'missing_card')
    end

    local cashierSource = VancePay.Server.getSourceByCitizenId(intent.cashier_citizenid)
    local proximityValidator = function(currentIntent)
        return VancePay.Server.safeClientCallback('vancepay:client:isIntentReachable', source, {
            cashier_source = cashierSource,
            terminal_type = currentIntent.terminal_type,
            coords = currentIntent.terminal_coords,
            distance = Config.TargetingDistance,
        }) == true
    end

    return processIntentPayment(source, intent, proximityValidator)
end

function Transactions.listForPanel(source, filters)
    filters = filters or {}
    local isAdmin = VancePay.Permissions.isAdmin(source)
    local storeId = tonumber(filters.store_id)

    if storeId and not isAdmin then
        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'collect')
        end

        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    elseif not storeId and not isAdmin then
        return VancePay.Server.fail('缺少店铺范围', 'missing_store_id')
    end

    return VancePay.Server.ok(Transactions.listInternal(filters))
end

function Transactions.detailForPanel(source, transactionId)
    transactionId = tonumber(transactionId)
    if not transactionId then
        return VancePay.Server.fail('缺少交易 ID', 'missing_transaction_id')
    end

    local transaction = Transactions.fetchById(transactionId)
    if not transaction then
        return VancePay.Server.fail('交易不存在', 'not_found')
    end

    if not VancePay.Permissions.isAdmin(source) then
        local allowed, reason = VancePay.Permissions.checkAccess(source, transaction.store_id, 'manage')
        if not allowed then
            allowed, reason = VancePay.Permissions.checkAccess(source, transaction.store_id, 'collect')
        end

        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    return VancePay.Server.ok(Transactions.fetchDetail(transactionId))
end

function Transactions.listCustomerActivityPageByCitizenId(citizenid, filters)
    Transactions.ensureReady()

    if Utils.isBlank(citizenid) then
        return {
            items = {},
            page = 1,
            per_page = math.min(math.max(tonumber(filters and (filters.per_page or filters.limit)) or 12, 1), 50),
            total = 0,
            total_pages = 1,
            has_prev = false,
            has_more = false,
        }
    end

    filters = filters or {}

    local requestedPage = math.max(tonumber(filters.page) or 1, 1)
    local perPage = math.min(math.max(tonumber(filters.per_page or filters.limit) or 12, 1), 50)
    local totalRow = MySQL.single.await([[
        SELECT COUNT(*) AS total
        FROM vancepay_transactions
        WHERE customer_citizenid = ?
    ]], { citizenid }) or {}
    local total = tonumber(totalRow.total) or 0
    local totalPages = math.max(math.ceil(total / perPage), 1)
    local page = math.min(requestedPage, totalPages)
    local offset = (page - 1) * perPage

    local rows = MySQL.query.await(TRANSACTION_SELECT .. [[
        WHERE t.customer_citizenid = ?
        ORDER BY t.id DESC
        LIMIT ? OFFSET ?
    ]], { citizenid, perPage, offset }) or {}

    local items = {}

    for index = 1, #rows do
        local transaction = normalizeTransaction(rows[index])

        if transaction then
            local finalAmount = roundAmount(transaction.final_amount)
            items[#items + 1] = {
                id = transaction.id,
                tx_code = transaction.tx_code,
                type = transaction.type,
                status = transaction.status,
                method = transaction.method,
                store_id = transaction.store_id,
                store_name = transaction.store_name_snapshot,
                item_description = transaction.item_description,
                item_lines = type(transaction.item_lines) == 'table' and transaction.item_lines or {},
                final_amount = finalAmount,
                net_amount = roundAmount(transaction.net_amount),
                amount_delta = transaction.type == VancePay.TransactionTypes.refund and finalAmount or -finalAmount,
                created_at = transaction.created_at,
                refund_reason = transaction.refund_reason,
                original_tx_code = transaction.original_tx_code,
            }
        end
    end

    return {
        items = items,
        page = page,
        per_page = perPage,
        total = total,
        total_pages = totalPages,
        has_prev = page > 1,
        has_more = page < totalPages,
    }
end

function Transactions.listCustomerActivityByCitizenId(citizenid, limit)
    local pageResult = Transactions.listCustomerActivityPageByCitizenId(citizenid, {
        page = 1,
        per_page = limit,
    })

    return pageResult.items or {}
end

function Transactions.refund(source, payload)
    payload = payload or {}
    Transactions.ensureReady()

    local schemaCompatible, schemaError = ensureRuntimeSchemaCompatible('refund')
    if not schemaCompatible then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local transactionId = tonumber(payload.transaction_id or payload.id)
    if not transactionId then
        return VancePay.Server.fail('缺少交易 ID', 'missing_transaction_id')
    end

    local transaction = Transactions.fetchById(transactionId)
    local allowed, reason, refundSummary = ensureRefundAllowed(source, transaction)
    if not allowed then
        return VancePay.Server.fail(reason, 'refund_not_allowed')
    end

    local refundReason = Utils.trim(payload.reason)
    if Config.RefundRequireReason and Utils.isBlank(refundReason) then
        return VancePay.Server.fail('退款必须填写原因', 'missing_reason')
    end

    local store = VancePay.Stores.fetchById(transaction.store_id)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'store_not_found')
    end

    local refundAmountInput = payload.refund_amount or payload.amount
    local remainingFinalAmount = roundAmount(refundSummary.remaining_final_amount)
    local refundAmount = refundAmountInput == nil and remainingFinalAmount or roundAmount(Utils.ensureNumber(refundAmountInput, 0))

    if refundAmount <= 0 then
        return VancePay.Server.fail('退款金额必须大于 0', 'invalid_refund_amount')
    end

    if refundAmount > remainingFinalAmount then
        if (refundAmount - remainingFinalAmount) <= 0.01 then
            refundAmount = remainingFinalAmount
        else
            return VancePay.Server.fail(('退款金额不能超过剩余可退金额 %s'):format(Utils.formatCurrency(remainingFinalAmount)), 'refund_amount_exceeded')
        end
    end

    local refundAmounts = buildRefundAmounts(transaction, refundSummary, refundAmount)
    local refundCommissionAmount = roundAmount(refundAmounts.commission_amount or 0)
    local refundStoreNetAmount = getStoreNetAfterCommission(refundAmounts.net_amount, refundCommissionAmount)

    if refundCommissionAmount > 0 then
        local balanceSchemaAvailable, balanceSchemaError = VancePay.Balance.ensureSchemaAvailable()
        if not balanceSchemaAvailable then
            return VancePay.Server.fail(balanceSchemaError, 'db_schema_outdated')
        end
    end

    local settlement, settlementError = getStoreSettlement(store)
    if not settlement then
        return VancePay.Server.fail(settlementError, 'invalid_store_settlement')
    end

    local taxSettlement, taxSettlementError = nil, nil
    if roundAmount(refundAmounts.tax_amount or 0) > 0 then
        taxSettlement, taxSettlementError = getTransactionTaxSettlement(transaction, store)
        if not taxSettlement then
            return VancePay.Server.fail(taxSettlementError, 'invalid_tax_settlement')
        end
    end

    local isAdmin = VancePay.Permissions.isAdmin(source)
    local storeBalance = Utils.roundCurrency(store.balance)
    local requiredStoreBalance = 0

    if settlement.mode ~= VancePay.StoreSettlementModes.publicAccount then
        requiredStoreBalance = roundAmount(requiredStoreBalance + refundStoreNetAmount)
    end

    if taxSettlement and taxSettlement.mode ~= VancePay.StoreSettlementModes.publicAccount then
        requiredStoreBalance = roundAmount(requiredStoreBalance + refundAmounts.tax_amount)
    end

    if requiredStoreBalance > 0 and (not Config.AdminForceRefundAllowsNegativeBalance or not isAdmin) then
        if storeBalance < requiredStoreBalance then
            return VancePay.Server.fail('店铺余额不足，无法退款', 'insufficient_store_balance')
        end
    end

    if settlement.mode == VancePay.StoreSettlementModes.publicAccount and refundStoreNetAmount > 0 then
        local availableRefundBalance = Utils.roundCurrency(VancePay.Banking.getBalance(settlement.identifier))
        if availableRefundBalance < refundStoreNetAmount then
            return VancePay.Server.fail(
                ('公账余额不足，当前仅剩 %s'):format(Utils.formatCurrency(availableRefundBalance)),
                'insufficient_store_balance'
            )
        end
    end

    if taxSettlement and taxSettlement.mode == VancePay.StoreSettlementModes.publicAccount and refundAmounts.tax_amount > 0 then
        local availableTaxRefundBalance = Utils.roundCurrency(VancePay.Banking.getBalance(taxSettlement.identifier))
        if availableTaxRefundBalance < refundAmounts.tax_amount then
            return VancePay.Server.fail(
                ('税收公账余额不足，当前仅剩 %s'):format(Utils.formatCurrency(availableTaxRefundBalance)),
                'insufficient_tax_balance'
            )
        end
    end

    local directWithdrawals = {}
    local function rollbackDirectWithdrawals()
        for index = #directWithdrawals, 1, -1 do
            local entry = directWithdrawals[index]
            local rolledBack = VancePay.Banking.deposit(entry.identifier, entry.amount, entry.rollback_reason)
            if not rolledBack then
                Utils.debug('Direct refund rollback failed', entry.identifier, entry.amount, entry.rollback_reason)
            end
        end
    end

    if settlement.mode == VancePay.StoreSettlementModes.publicAccount and refundStoreNetAmount > 0 then
        local settlementWithdrawn = VancePay.Banking.withdraw(
            settlement.identifier,
            refundStoreNetAmount,
            ('vancepay:refund_store:%s'):format(transaction.tx_code)
        )

        if not settlementWithdrawn then
            return VancePay.Server.fail('从绑定公账扣除退款金额失败', 'withdraw_failed')
        end

        directWithdrawals[#directWithdrawals + 1] = {
            identifier = settlement.identifier,
            amount = refundStoreNetAmount,
            rollback_reason = ('vancepay:refund_store_rollback:%s'):format(transaction.tx_code),
        }
    end

    if taxSettlement and taxSettlement.mode == VancePay.StoreSettlementModes.publicAccount and refundAmounts.tax_amount > 0 then
        local taxWithdrawn = VancePay.Banking.withdraw(
            taxSettlement.identifier,
            refundAmounts.tax_amount,
            ('vancepay:refund_tax:%s'):format(transaction.tx_code)
        )

        if not taxWithdrawn then
            rollbackDirectWithdrawals()
            return VancePay.Server.fail('从税收公账扣除退款金额失败', 'tax_withdraw_failed')
        end

        directWithdrawals[#directWithdrawals + 1] = {
            identifier = taxSettlement.identifier,
            amount = refundAmounts.tax_amount,
            rollback_reason = ('vancepay:refund_tax_rollback:%s'):format(transaction.tx_code),
        }
    end

    local deposited = VancePay.Banking.deposit(transaction.customer_citizenid, refundAmounts.final_amount, ('vancepay:refund:%s'):format(transaction.tx_code))
    if not deposited then
        rollbackDirectWithdrawals()
        return VancePay.Server.fail('退回顾客账户失败', 'deposit_failed')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    local refundCode = Utils.generateCode('TX', 10)
    local newRefundedFinalAmount = roundAmount(refundSummary.refunded_final_amount + refundAmounts.final_amount)
    local newRefundedNetAmount = roundAmount(refundSummary.refunded_net_amount + refundAmounts.net_amount)
    local newRefundedTaxAmount = roundAmount((refundSummary.refunded_tax_amount or 0) + (refundAmounts.tax_amount or 0))
    local newRefundedCommissionAmount = roundAmount((refundSummary.refunded_commission_amount or 0) + refundCommissionAmount)
    local newStatus = newRefundedFinalAmount >= roundAmount(transaction.final_amount)
        and VancePay.TransactionStatuses.refunded
        or VancePay.TransactionStatuses.partiallyRefunded

    local queries = {}
    if requiredStoreBalance > 0 then
        queries[#queries + 1] = {
            query = 'UPDATE vancepay_stores SET balance = balance - ? WHERE id = ?',
            values = { requiredStoreBalance, transaction.store_id }
        }
    end

    local refundTaxSettlementMode = taxSettlement and taxSettlement.mode or normalizeSettlementMode(transaction.tax_settlement_mode)
    local refundTaxSettlementAccountIdentifier = taxSettlement and taxSettlement.identifier or Utils.trim(transaction.tax_settlement_account_identifier)
    local refundCommissionAvailableAt = refundCommissionAmount > 0
        and VancePay.Balance.getCommissionAvailableAtByReference(transaction.cashier_citizenid, transaction.tx_code, transaction.created_at)
        or nil

    queries[#queries + 1] = {
        query = [[
            INSERT INTO vancepay_transactions (
                tx_code,
                type,
                intent_id,
                original_tx_id,
                terminal_id,
                store_id,
                cashier_citizenid,
                customer_citizenid,
                processed_by_citizenid,
                store_name_snapshot,
                terminal_serial_snapshot,
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
                net_amount,
                method,
                status,
                refund_reason
            ) VALUES (?, 'refund', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'completed', ?)
        ]],
        values = {
            refundCode,
            transaction.intent_id,
            transaction.id,
            transaction.terminal_id,
            transaction.store_id,
            transaction.cashier_citizenid,
            transaction.customer_citizenid,
            actorCitizenId,
            transaction.store_name_snapshot,
            transaction.terminal_serial_snapshot,
            transaction.item_description,
            type(transaction.item_lines) == 'table' and #transaction.item_lines > 0 and json.encode(transaction.item_lines) or nil,
            refundAmounts.subtotal_amount,
            refundAmounts.discount_rate,
            refundAmounts.discount_amount,
            refundAmounts.tip_amount,
            refundAmounts.fee_amount,
            refundAmounts.tax_rate or 0,
            Utils.parseBool(refundAmounts.tax_exempt) and 1 or 0,
            refundAmounts.tax_amount or 0,
            refundAmounts.commission_rate or 0,
            refundCommissionAmount,
            refundTaxSettlementMode,
            refundTaxSettlementAccountIdentifier,
            refundAmounts.final_amount,
            refundAmounts.net_amount,
            transaction.method,
            refundReason,
        }
    }

    if refundCommissionAmount > 0 then
        VancePay.Balance.appendEntryQuery(queries, {
            citizenid = transaction.cashier_citizenid,
            store_id = transaction.store_id,
            entry_type = 'commission_refund',
            amount = -refundCommissionAmount,
            reference_code = refundCode,
            related_reference_code = transaction.tx_code,
            store_name_snapshot = transaction.store_name_snapshot,
            description = refundReason or ('退款 %s 提成冲回'):format(refundCode),
            available_at = refundCommissionAvailableAt,
        })
    end

    queries[#queries + 1] = {
        query = [[
            UPDATE vancepay_transactions
            SET status = ?,
                refunded_final_amount = ?,
                refunded_net_amount = ?,
                refunded_tax_amount = ?,
                refunded_commission_amount = ?,
                refund_reason = ?
            WHERE id = ?
        ]],
        values = {
            newStatus,
            newRefundedFinalAmount,
            newRefundedNetAmount,
            newRefundedTaxAmount,
            newRefundedCommissionAmount,
            refundReason,
            transaction.id,
        }
    }

    local success = MySQL.transaction.await(queries)

    if not success then
        Utils.debug('Refund database transaction failed', transaction.tx_code, transaction.id, transaction.store_id, transaction.method)
        VancePay.Banking.withdraw(transaction.customer_citizenid, refundAmounts.final_amount, ('vancepay:refund_rollback:%s'):format(transaction.tx_code))
        rollbackDirectWithdrawals()
        return VancePay.Server.fail('退款处理失败，已尝试回滚', 'db_error')
    end

    local refundTransaction = MySQL.single.await(TRANSACTION_SELECT .. ' WHERE t.tx_code = ? LIMIT 1', { refundCode })
    refundTransaction = normalizeTransaction(refundTransaction)

    VancePay.Audit.log(actorCitizenId, isAdmin and 'force_refund' or 'refund_transaction', 'transaction', transaction.id, {
        store_id = transaction.store_id,
        terminal_id = transaction.terminal_id,
        detail = {
            original_tx_code = transaction.tx_code,
            refund_tx_code = refundCode,
            reason = refundReason,
            amount = refundAmounts.final_amount,
            net_amount = refundAmounts.net_amount,
            tax_amount = refundAmounts.tax_amount,
            commission_amount = refundCommissionAmount,
            remaining_final_amount = roundAmount(transaction.final_amount - newRefundedFinalAmount),
            remaining_net_amount = roundAmount(transaction.net_amount - newRefundedNetAmount),
            remaining_tax_amount = roundAmount((transaction.tax_amount or 0) - newRefundedTaxAmount),
            remaining_commission_amount = roundAmount((transaction.commission_amount or 0) - newRefundedCommissionAmount),
            status = newStatus,
        }
    })

    if VancePay.FiveMLog and VancePay.FiveMLog.logTransaction then
        VancePay.FiveMLog.logTransaction('refund_completed', refundTransaction, {
            original = transaction,
            actor_citizenid = actorCitizenId,
            source = source,
            metadata = {
                reason = refundReason,
                original_status = transaction.status,
                updated_original_status = newStatus,
                remaining_final_amount = roundAmount(transaction.final_amount - newRefundedFinalAmount),
                remaining_net_amount = roundAmount(transaction.net_amount - newRefundedNetAmount),
                remaining_tax_amount = roundAmount((transaction.tax_amount or 0) - newRefundedTaxAmount),
                remaining_commission_amount = roundAmount((transaction.commission_amount or 0) - newRefundedCommissionAmount),
            },
        })
    end

    local cashierSource = transaction.cashier_citizenid and VancePay.Server.getSourceByCitizenId(transaction.cashier_citizenid) or nil
    local customerSource = VancePay.Server.getSourceByCitizenId(transaction.customer_citizenid)

    if cashierSource then
        VancePay.Server.notify(cashierSource, ('退款 %s 已完成'):format(Utils.formatCurrency(refundAmounts.final_amount)), 'success')
    end

    if customerSource then
        VancePay.Server.notify(customerSource, ('退款 %s 已退回'):format(Utils.formatCurrency(refundAmounts.final_amount)), 'success')
    end

    if refundCommissionAmount > 0 and VancePay.Balance and VancePay.Balance.refreshClientState then
        VancePay.Balance.refreshClientState(transaction.cashier_citizenid, 'commission_refund')
    end

    return VancePay.Server.ok({
        original = Transactions.fetchById(transaction.id),
        refund = refundTransaction,
        detail = Transactions.fetchDetail(transaction.id),
    }, newStatus == VancePay.TransactionStatuses.refunded and '退款成功' or '部分退款成功')
end

lib.callback.register('vancepay:server:confirmIntent', function(source, payload)
    return Transactions.confirmIntent(source, payload or {})
end)

lib.callback.register('vancepay:server:swipeIntent', function(source, payload)
    return Transactions.swipeIntent(source, payload or {})
end)

lib.callback.register('vancepay:server:getTransactions', function(source, filters)
    return Transactions.listForPanel(source, filters or {})
end)

lib.callback.register('vancepay:server:getTransactionDetail', function(source, transactionId)
    return Transactions.detailForPanel(source, transactionId)
end)

lib.callback.register('vancepay:server:getCustomerAppState', function(source, payload)
    payload = payload or {}

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) then
        return VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    local balanceSummary = VancePay.Balance and VancePay.Balance.getSummaryByCitizenId
        and VancePay.Balance.getSummaryByCitizenId(citizenid)
        or {
            available_balance = 0,
            pending_balance = 0,
            total_balance = 0,
            withdrawable_balance = 0,
        }

    return VancePay.Server.ok({
        balance = Utils.roundCurrency(balanceSummary.withdrawable_balance or 0),
        bank_balance = Utils.roundCurrency(VancePay.Banking.getBalance(citizenid)),
        balance_summary = balanceSummary,
        balance_history = VancePay.Balance and VancePay.Balance.listHistoryPageByCitizenId
            and VancePay.Balance.listHistoryPageByCitizenId(citizenid, {
                page = payload.balance_history_page,
                per_page = payload.balance_history_per_page or payload.balance_history_limit
                    or (Config.LBPhone and Config.LBPhone.balanceActivityLimit) or 20,
            })
            or {},
        loans = VancePay.Loans and VancePay.Loans.getCustomerState
            and VancePay.Loans.getCustomerState(citizenid)
            or {},
        pending_intents = VancePay.Intents.listCustomerPendingByCitizenId(
            citizenid,
            payload.intent_limit or (Config.LBPhone and Config.LBPhone.intentLimit) or 20
        ),
        activity = Transactions.listCustomerActivityPageByCitizenId(citizenid, {
            page = payload.activity_page,
            per_page = payload.activity_per_page or payload.activity_limit
                or (Config.LBPhone and Config.LBPhone.activityLimit) or 12,
        }),
    })
end)

lib.callback.register('vancepay:server:refundTransaction', function(source, payload)
    return Transactions.refund(source, payload or {})
end)
