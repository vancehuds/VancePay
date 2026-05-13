VancePay.Balance = VancePay.Balance or {}

local Balance = VancePay.Balance

Balance._ready = Balance._ready or false
Balance._initializing = Balance._initializing or false

local EntryTypes = {
    commission = 'commission',
    commissionRefund = 'commission_refund',
    withdrawal = 'withdrawal',
}

local BALANCE_ENTRY_SELECT = [[
    SELECT
        b.*
    FROM vancepay_balance_entries b
]]

local CREATE_BALANCE_ENTRIES_TABLE = [[
    CREATE TABLE IF NOT EXISTS vancepay_balance_entries (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(50) NOT NULL,
        store_id INT DEFAULT NULL,
        entry_type ENUM('commission', 'commission_refund', 'withdrawal') NOT NULL,
        amount DECIMAL(15,2) NOT NULL,
        reference_code VARCHAR(32) DEFAULT NULL,
        related_reference_code VARCHAR(32) DEFAULT NULL,
        store_name_snapshot VARCHAR(100) DEFAULT NULL,
        description VARCHAR(255) DEFAULT NULL,
        available_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_citizen_available (citizenid, available_at, created_at),
        INDEX idx_reference (reference_code, related_reference_code),
        INDEX idx_store_time (store_id, created_at),
        FOREIGN KEY (store_id) REFERENCES vancepay_stores(id) ON DELETE SET NULL
    ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local function getDatabaseConfig()
    return Config.Database or {}
end

local function shouldRunSchemaMigrations()
    return getDatabaseConfig().autoMigrate == true
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

local function fetchTableExists(tableName)
    return MySQL.single.await([[
        SELECT 1 AS present
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = ?
        LIMIT 1
    ]], { tableName })
end

local function fetchColumnMetadata(columnName)
    return MySQL.single.await([[
        SELECT
            COLUMN_NAME,
            COLUMN_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'vancepay_balance_entries'
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
            AND TABLE_NAME = 'vancepay_balance_entries'
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
    local storeTableExists = fetchTableExists('vancepay_stores')
    if not storeTableExists then
        return
    end

    MySQL.query.await(CREATE_BALANCE_ENTRIES_TABLE)

    if not getSchemaValue(fetchColumnMetadata('reference_code'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD COLUMN reference_code VARCHAR(32) DEFAULT NULL AFTER amount
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('related_reference_code'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD COLUMN related_reference_code VARCHAR(32) DEFAULT NULL AFTER reference_code
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('store_name_snapshot'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD COLUMN store_name_snapshot VARCHAR(100) DEFAULT NULL AFTER related_reference_code
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('description'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD COLUMN description VARCHAR(255) DEFAULT NULL AFTER store_name_snapshot
        ]])
    end

    if not getSchemaValue(fetchColumnMetadata('available_at'), 'COLUMN_NAME', 'column_name') then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD COLUMN available_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER description
        ]])
    end

    local entryTypeColumn = fetchColumnMetadata('entry_type')
    local entryTypeColumnType = tostring(getSchemaValue(entryTypeColumn, 'COLUMN_TYPE', 'column_type') or '')
    if entryTypeColumnType ~= ''
        and (not entryTypeColumnType:find(EntryTypes.commissionRefund, 1, true)
            or not entryTypeColumnType:find(EntryTypes.withdrawal, 1, true)) then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            MODIFY COLUMN entry_type ENUM('commission', 'commission_refund', 'withdrawal') NOT NULL
        ]])
    end

    local indexMap = fetchIndexMap()

    if not indexMap.idx_citizen_available then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD INDEX idx_citizen_available (citizenid, available_at, created_at)
        ]])
    end

    if not indexMap.idx_reference then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD INDEX idx_reference (reference_code, related_reference_code)
        ]])
    end

    if not indexMap.idx_store_time then
        MySQL.query.await([[
            ALTER TABLE vancepay_balance_entries
            ADD INDEX idx_store_time (store_id, created_at)
        ]])
    end
end

local function getUnlockDelaySeconds()
    return math.max(tonumber(Config.CommissionBalanceUnlockSeconds) or 86400, 0)
end

local function buildAvailableAt(baseTimestamp)
    local resolvedTimestamp = baseTimestamp

    if type(resolvedTimestamp) == 'string' then
        resolvedTimestamp = Utils.parseSqlDateTime(resolvedTimestamp)
    end

    resolvedTimestamp = tonumber(resolvedTimestamp) or os.time()

    return os.date('%Y-%m-%d %H:%M:%S', resolvedTimestamp + getUnlockDelaySeconds())
end

local function getEntryAvailabilityStatus(entry)
    local availableAt = Utils.parseSqlDateTime(entry.available_at)
    local pending = availableAt and availableAt > os.time()

    if pending then
        return entry.amount < 0 and 'pending_reversal' or 'pending'
    end

    if entry.entry_type == EntryTypes.withdrawal then
        return 'withdrawn'
    end

    if entry.entry_type == EntryTypes.commissionRefund then
        return 'reversed'
    end

    return 'available'
end

local function normalizeEntry(row)
    if not row then
        return nil
    end

    row = Utils.normalizeDbRow(row)
    row.entry_type = Utils.trim(row.entry_type)
    row.amount = Utils.roundCurrency(row.amount or 0)
    row.reference_code = Utils.trim(row.reference_code)
    row.related_reference_code = Utils.trim(row.related_reference_code)
    row.store_name_snapshot = Utils.trim(row.store_name_snapshot)
    row.description = Utils.trim(row.description)

    local availableAtTimestamp = Utils.parseSqlDateTime(row.available_at)
    row.available_in = math.max(0, (availableAtTimestamp or os.time()) - os.time())
    row.availability_status = getEntryAvailabilityStatus(row)

    return row
end

local function buildEmptySummary()
    return {
        available_balance = 0,
        pending_balance = 0,
        total_balance = 0,
        withdrawable_balance = 0,
        lifetime_commission_amount = 0,
        lifetime_reversed_amount = 0,
        lifetime_withdrawn_amount = 0,
        next_unlock_at = nil,
        next_unlock_in = 0,
        unlock_delay_seconds = getUnlockDelaySeconds(),
    }
end

function Balance.ensureReady()
    if Balance._ready then
        return true
    end

    while Balance._initializing do
        Wait(50)
        if Balance._ready then
            return true
        end
    end

    Balance._initializing = true
    local ok, err = pcall(function()
        if shouldRunSchemaMigrations() then
            ensureSchema()
        end
    end)
    Balance._initializing = false
    if not ok then
        error(err)
    end

    Balance._ready = true
    return true
end

function Balance.ensureSchemaAvailable()
    Balance.ensureReady()

    if fetchTableExists('vancepay_balance_entries') then
        return true
    end

    return false, '数据库结构未升级到最新版本，请先执行 sql/migrate_to_latest.sql'
end

function Balance.getUnlockDelaySeconds()
    return getUnlockDelaySeconds()
end

function Balance.getCommissionAvailableAt(baseTimestamp)
    return buildAvailableAt(baseTimestamp)
end

function Balance.getSummaryByCitizenId(citizenid)
    Balance.ensureReady()

    citizenid = Utils.trim(citizenid)
    if Utils.isBlank(citizenid) or not fetchTableExists('vancepay_balance_entries') then
        return buildEmptySummary()
    end

    local row = MySQL.single.await([[
        SELECT
            COALESCE(SUM(CASE
                WHEN available_at <= CURRENT_TIMESTAMP THEN amount
                ELSE 0
            END), 0) AS available_balance,
            COALESCE(SUM(CASE
                WHEN available_at > CURRENT_TIMESTAMP THEN amount
                ELSE 0
            END), 0) AS pending_balance,
            COALESCE(SUM(CASE
                WHEN entry_type = 'commission' AND amount > 0 THEN amount
                ELSE 0
            END), 0) AS lifetime_commission_amount,
            COALESCE(SUM(CASE
                WHEN entry_type = 'commission_refund' AND amount < 0 THEN ABS(amount)
                ELSE 0
            END), 0) AS lifetime_reversed_amount,
            COALESCE(SUM(CASE
                WHEN entry_type = 'withdrawal' AND amount < 0 THEN ABS(amount)
                ELSE 0
            END), 0) AS lifetime_withdrawn_amount,
            MIN(CASE
                WHEN available_at > CURRENT_TIMESTAMP AND amount > 0 THEN available_at
                ELSE NULL
            END) AS next_unlock_at
        FROM vancepay_balance_entries
        WHERE citizenid = ?
    ]], { citizenid }) or {}

    local summary = buildEmptySummary()
    summary.available_balance = Utils.roundCurrency(row.available_balance or 0)
    summary.pending_balance = Utils.roundCurrency(row.pending_balance or 0)
    summary.total_balance = Utils.roundCurrency(summary.available_balance + summary.pending_balance)
    summary.withdrawable_balance = Utils.roundCurrency(math.max(summary.available_balance, 0))
    summary.lifetime_commission_amount = Utils.roundCurrency(row.lifetime_commission_amount or 0)
    summary.lifetime_reversed_amount = Utils.roundCurrency(row.lifetime_reversed_amount or 0)
    summary.lifetime_withdrawn_amount = Utils.roundCurrency(row.lifetime_withdrawn_amount or 0)
    summary.next_unlock_at = row.next_unlock_at

    local nextUnlockTimestamp = Utils.parseSqlDateTime(summary.next_unlock_at)
    summary.next_unlock_in = math.max(0, (nextUnlockTimestamp or 0) - os.time())

    return summary
end

function Balance.listHistoryPageByCitizenId(citizenid, filters)
    Balance.ensureReady()

    citizenid = Utils.trim(citizenid)
    if Utils.isBlank(citizenid) or not fetchTableExists('vancepay_balance_entries') then
        return {
            items = {},
            page = 1,
            per_page = math.min(math.max(tonumber(filters and (filters.per_page or filters.limit)) or 20, 1), 100),
            total = 0,
            total_pages = 1,
            has_prev = false,
            has_more = false,
        }
    end

    filters = filters or {}

    local requestedPage = math.max(tonumber(filters.page) or 1, 1)
    local perPage = math.min(math.max(tonumber(filters.per_page or filters.limit) or 20, 1), 100)
    local totalRow = MySQL.single.await([[
        SELECT COUNT(*) AS total
        FROM vancepay_balance_entries
        WHERE citizenid = ?
    ]], { citizenid }) or {}
    local total = tonumber(totalRow.total) or 0
    local totalPages = math.max(math.ceil(total / perPage), 1)
    local page = math.min(requestedPage, totalPages)
    local offset = (page - 1) * perPage

    local rows = MySQL.query.await(BALANCE_ENTRY_SELECT .. [[
        WHERE b.citizenid = ?
        ORDER BY b.id DESC
        LIMIT ? OFFSET ?
    ]], { citizenid, perPage, offset }) or {}

    for index = 1, #rows do
        rows[index] = normalizeEntry(rows[index])
    end

    return {
        items = rows,
        page = page,
        per_page = perPage,
        total = total,
        total_pages = totalPages,
        has_prev = page > 1,
        has_more = page < totalPages,
    }
end

function Balance.listHistoryByCitizenId(citizenid, limit)
    local pageResult = Balance.listHistoryPageByCitizenId(citizenid, {
        page = 1,
        per_page = limit,
    })

    return pageResult.items or {}
end

function Balance.getCommissionAvailableAtByReference(citizenid, referenceCode, fallbackTimestamp)
    Balance.ensureReady()

    citizenid = Utils.trim(citizenid)
    referenceCode = Utils.trim(referenceCode)

    if Utils.isBlank(citizenid) or Utils.isBlank(referenceCode) or not fetchTableExists('vancepay_balance_entries') then
        return buildAvailableAt(fallbackTimestamp)
    end

    local row = MySQL.single.await([[
        SELECT available_at
        FROM vancepay_balance_entries
        WHERE citizenid = ?
            AND reference_code = ?
            AND entry_type = 'commission'
        ORDER BY id ASC
        LIMIT 1
    ]], { citizenid, referenceCode })

    return row and row.available_at or buildAvailableAt(fallbackTimestamp)
end

function Balance.buildEntryInsertQuery(payload)
    payload = payload or {}

    local citizenid = Utils.trim(payload.citizenid)
    local entryType = Utils.trim(payload.entry_type)
    local amount = Utils.roundCurrency(payload.amount or 0)
    local availableAt = Utils.trim(payload.available_at)
    local description = Utils.trim(payload.description)

    if Utils.isBlank(citizenid) or amount == 0 then
        return nil
    end

    if entryType ~= EntryTypes.commission
        and entryType ~= EntryTypes.commissionRefund
        and entryType ~= EntryTypes.withdrawal
    then
        return nil
    end

    if Utils.isBlank(availableAt) then
        availableAt = os.date('%Y-%m-%d %H:%M:%S')
    end

    if Utils.isBlank(description) then
        description = nil
    end

    return {
        query = [[
            INSERT INTO vancepay_balance_entries (
                citizenid,
                store_id,
                entry_type,
                amount,
                reference_code,
                related_reference_code,
                store_name_snapshot,
                description,
                available_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]],
        values = {
            citizenid,
            tonumber(payload.store_id) or nil,
            entryType,
            amount,
            Utils.trim(payload.reference_code),
            Utils.trim(payload.related_reference_code),
            Utils.trim(payload.store_name_snapshot),
            description,
            availableAt,
        }
    }
end

function Balance.appendEntryQuery(queries, payload)
    local entryQuery = Balance.buildEntryInsertQuery(payload)

    if not entryQuery or type(queries) ~= 'table' then
        return false
    end

    queries[#queries + 1] = entryQuery
    return true
end

function Balance.refreshClientState(citizenid, reason)
    local eventName = VancePay.Events and VancePay.Events.client and VancePay.Events.client.refreshLBPhoneState
        or 'vancepay:client:refreshLbPhoneState'
    local target = VancePay.Server and VancePay.Server.getSourceByCitizenId and VancePay.Server.getSourceByCitizenId(citizenid) or nil

    if target and target > 0 then
        TriggerClientEvent(eventName, target, {
            reason = reason or 'balance_update',
        })
    end
end

function Balance.withdraw(source, payload)
    payload = payload or {}
    Balance.ensureReady()

    local schemaAvailable, schemaError = Balance.ensureSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) then
        return VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    local amount = Utils.roundCurrency(Utils.ensureNumber(payload.amount or payload.withdraw_amount, 0))
    if amount <= 0 then
        return VancePay.Server.fail('提现金额必须大于 0', 'invalid_amount')
    end

    local summary = Balance.getSummaryByCitizenId(citizenid)
    local withdrawableBalance = Utils.roundCurrency(summary.withdrawable_balance or 0)

    if withdrawableBalance < amount then
        return VancePay.Server.fail(
            ('可提现余额不足，当前仅剩 %s'):format(Utils.formatCurrency(math.max(withdrawableBalance, 0))),
            'insufficient_balance'
        )
    end

    local referenceCode = Utils.generateCode('BW', 10)
    local deposited = VancePay.Banking.deposit(citizenid, amount, ('vancepay:balance_withdraw:%s'):format(referenceCode))

    if not deposited then
        return VancePay.Server.fail('提现到银行失败', 'banking_failed')
    end

    local inserted = MySQL.insert.await([[
        INSERT INTO vancepay_balance_entries (
            citizenid,
            store_id,
            entry_type,
            amount,
            reference_code,
            related_reference_code,
            store_name_snapshot,
            description,
            available_at
        ) VALUES (?, NULL, 'withdrawal', ?, ?, NULL, NULL, ?, CURRENT_TIMESTAMP)
    ]], {
        citizenid,
        -amount,
        referenceCode,
        Utils.isBlank(Utils.trim(payload.description)) and 'VancePay 余额提现' or Utils.trim(payload.description),
    })

    if not inserted then
        local rolledBack = VancePay.Banking.withdraw(
            citizenid,
            amount,
            ('vancepay:balance_withdraw_rollback:%s'):format(referenceCode)
        )

        if not rolledBack then
            Utils.debug('VancePay balance withdrawal rollback failed', citizenid, amount, referenceCode)
        end

        return VancePay.Server.fail('提现记录写入失败，已尝试回滚银行入账', 'db_error')
    end

    VancePay.Audit.log(citizenid, 'withdraw_balance', 'balance', referenceCode, {
        detail = {
            citizenid = citizenid,
            amount = amount,
            reference_code = referenceCode,
        }
    })

    Balance.refreshClientState(citizenid, 'withdraw_success')

    return VancePay.Server.ok({
        reference_code = referenceCode,
        summary = Balance.getSummaryByCitizenId(citizenid),
    }, '提现成功')
end

lib.callback.register('vancepay:server:withdrawBalance', function(source, payload)
    return Balance.withdraw(source, payload or {})
end)
