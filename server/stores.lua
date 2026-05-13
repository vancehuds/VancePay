VancePay.Stores = VancePay.Stores or {}

local Stores = VancePay.Stores

Stores._ready = Stores._ready or false
Stores._initializing = Stores._initializing or false
Stores._settingsCache = Stores._settingsCache or {}

local EmployeeSources = {
    manual = 'manual',
    publicAccountSync = 'public_account_sync',
}

local SettingKeys = {
    defaultTaxRate = 'default_tax_rate',
    taxSettlementMode = 'tax_settlement_mode',
    taxSettlementAccountIdentifier = 'tax_settlement_account_identifier',
}

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

local function fetchTableColumnMetadata(tableName, columnName)
    return MySQL.single.await([[
        SELECT
            COLUMN_NAME,
            COLUMN_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = ?
            AND COLUMN_NAME = ?
        LIMIT 1
    ]], { tableName, columnName })
end

local function fetchTableIndexes(tableName)
    return MySQL.query.await([[
        SELECT INDEX_NAME
        FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = ?
    ]], { tableName }) or {}
end

local function fetchStoreColumnMetadata(columnName)
    return fetchTableColumnMetadata('vancepay_stores', columnName)
end

local function fetchEmployeeColumnMetadata(columnName)
    return fetchTableColumnMetadata('vancepay_employees', columnName)
end

local function getDefaultTaxRateFallback()
    return Utils.roundCurrency(Utils.clamp(Utils.ensureNumber(Config.DefaultTaxRate or 0, 0), 0, 100))
end

local function getDefaultTaxSettlementModeFallback()
    return VancePay.StoreSettlementModes.storeBalance
end

local function inferLegacyTaxSettlementSettings()
    local rows = MySQL.query.await([[
        SELECT tax_settlement_mode, tax_settlement_account_identifier
        FROM vancepay_stores
    ]]) or {}

    local resolvedMode = getDefaultTaxSettlementModeFallback()
    local resolvedIdentifier = nil
    local distinct = {}
    local distinctCount = 0

    if #rows == 0 then
        return resolvedMode, resolvedIdentifier
    end

    for index = 1, #rows do
        local row = rows[index] or {}
        local rawMode = Utils.trim(row.tax_settlement_mode)
        local mode = rawMode == VancePay.StoreSettlementModes.publicAccount
            and rawMode
            or getDefaultTaxSettlementModeFallback()
        local rawIdentifier = Utils.trim(row.tax_settlement_account_identifier)
        local identifier = mode == VancePay.StoreSettlementModes.publicAccount and rawIdentifier or nil

        if mode == VancePay.StoreSettlementModes.publicAccount and Utils.isBlank(identifier) then
            return getDefaultTaxSettlementModeFallback(), nil
        end

        local key = ('%s:%s'):format(mode, identifier or '')
        if not distinct[key] then
            distinct[key] = true
            distinctCount = distinctCount + 1
            if distinctCount > 1 then
                return getDefaultTaxSettlementModeFallback(), nil
            end

            resolvedMode = mode
            resolvedIdentifier = identifier
        end
    end

    return resolvedMode, resolvedIdentifier
end

local function ensureSettingsTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS vancepay_settings (
            setting_key VARCHAR(100) PRIMARY KEY,
            setting_value TEXT DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

local function fetchSettingValue(settingKey)
    local row = MySQL.single.await([[
        SELECT setting_value
        FROM vancepay_settings
        WHERE setting_key = ?
        LIMIT 1
    ]], { settingKey })

    return row and getSchemaValue(row, 'setting_value') or nil
end

local function setSettingValue(settingKey, settingValue)
    MySQL.insert.await([[
        INSERT INTO vancepay_settings (setting_key, setting_value)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
            setting_value = VALUES(setting_value)
    ]], { settingKey, tostring(settingValue) })

    Stores._settingsCache[settingKey] = tostring(settingValue)
end

local function getCachedSettingValue(settingKey)
    local cached = Stores._settingsCache[settingKey]
    if cached ~= nil then
        return cached == false and nil or cached
    end

    local value = fetchSettingValue(settingKey)
    Stores._settingsCache[settingKey] = value ~= nil and tostring(value) or false
    return value
end

local function ensureSchema()
    local tableExists = fetchTableExists('vancepay_stores')

    if not tableExists then
        return
    end

    ensureSettingsTable()

    if fetchSettingValue(SettingKeys.defaultTaxRate) == nil then
        setSettingValue(SettingKeys.defaultTaxRate, getDefaultTaxRateFallback())
    end

    local settlementModeColumn = fetchStoreColumnMetadata('settlement_mode')
    if not settlementModeColumn then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance' AFTER balance
        ]])
    else
        local settlementModeColumnType = tostring(getSchemaValue(settlementModeColumn, 'COLUMN_TYPE', 'column_type') or '')
        if not settlementModeColumnType:find('public_account', 1, true) then
            MySQL.query.await([[
                ALTER TABLE vancepay_stores
                MODIFY COLUMN settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance'
            ]])
        end
    end

    if not fetchStoreColumnMetadata('settlement_account_identifier') then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER settlement_mode
        ]])
    end

    if not fetchStoreColumnMetadata('commission_rate') then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER settlement_account_identifier
        ]])
    end

    if not fetchStoreColumnMetadata('tax_rate') then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER commission_rate
        ]])
    end

    if not fetchStoreColumnMetadata('tax_exempt') then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN tax_exempt TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_rate
        ]])
    end

    local taxCustomRateEnabledAdded = false
    if not fetchStoreColumnMetadata('tax_custom_rate_enabled') then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN tax_custom_rate_enabled TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_exempt
        ]])
        taxCustomRateEnabledAdded = true
    end

    local taxSettlementModeColumn = fetchStoreColumnMetadata('tax_settlement_mode')
    if not taxSettlementModeColumn then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance' AFTER tax_custom_rate_enabled
        ]])
    else
        local taxSettlementModeColumnType = tostring(getSchemaValue(taxSettlementModeColumn, 'COLUMN_TYPE', 'column_type') or '')
        if not taxSettlementModeColumnType:find('public_account', 1, true) then
            MySQL.query.await([[
                ALTER TABLE vancepay_stores
                MODIFY COLUMN tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance'
            ]])
        end
    end

    if not fetchStoreColumnMetadata('tax_settlement_account_identifier') then
        MySQL.query.await([[
            ALTER TABLE vancepay_stores
            ADD COLUMN tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER tax_settlement_mode
        ]])
    end

    local storedTaxSettlementMode = fetchSettingValue(SettingKeys.taxSettlementMode)
    local storedTaxSettlementAccountIdentifier = fetchSettingValue(SettingKeys.taxSettlementAccountIdentifier)
    if storedTaxSettlementMode == nil or storedTaxSettlementAccountIdentifier == nil then
        local inferredMode, inferredIdentifier = inferLegacyTaxSettlementSettings()

        if storedTaxSettlementMode == nil then
            setSettingValue(SettingKeys.taxSettlementMode, inferredMode)
        end

        if storedTaxSettlementAccountIdentifier == nil then
            setSettingValue(SettingKeys.taxSettlementAccountIdentifier, inferredIdentifier or '')
        end
    end

    if taxCustomRateEnabledAdded then
        MySQL.update.await([[
            UPDATE vancepay_stores
            SET tax_custom_rate_enabled = 1
            WHERE tax_rate > 0
        ]])
    end

    local employeeTableExists = fetchTableExists('vancepay_employees')
    if not employeeTableExists then
        return
    end

    local employeeSourceColumn = fetchEmployeeColumnMetadata('employee_source')
    if not employeeSourceColumn then
        MySQL.query.await([[
            ALTER TABLE vancepay_employees
            ADD COLUMN employee_source ENUM('manual', 'public_account_sync') NOT NULL DEFAULT 'manual' AFTER can_discount
        ]])
    else
        local employeeSourceColumnType = tostring(getSchemaValue(employeeSourceColumn, 'COLUMN_TYPE', 'column_type') or '')
        if not employeeSourceColumnType:find('public_account_sync', 1, true) then
            MySQL.query.await([[
                ALTER TABLE vancepay_employees
                MODIFY COLUMN employee_source ENUM('manual', 'public_account_sync') NOT NULL DEFAULT 'manual'
            ]])
        end
    end

    if not fetchEmployeeColumnMetadata('employee_source_key') then
        MySQL.query.await([[
            ALTER TABLE vancepay_employees
            ADD COLUMN employee_source_key VARCHAR(100) DEFAULT NULL AFTER employee_source
        ]])
    end

    local indexMap = {}
    local indexes = fetchTableIndexes('vancepay_employees')
    for index = 1, #indexes do
        local row = indexes[index]
        local name = row and getSchemaValue(row, 'INDEX_NAME', 'index_name')
        if name then
            indexMap[name] = true
        end
    end

    if not indexMap.idx_store_employee_source then
        MySQL.query.await([[
            ALTER TABLE vancepay_employees
            ADD INDEX idx_store_employee_source (store_id, employee_source, employee_source_key)
        ]])
    end
end

local function buildPlaceholders(count)
    return ('?,'):rep(count):sub(1, count * 2 - 1)
end

local function fetchStoreCounters()
    return [[
        SELECT
            s.*,
            (
                SELECT COUNT(*)
                FROM vancepay_terminals t
                WHERE t.store_id = s.id AND t.status <> 'archived'
            ) AS terminal_count,
            (
                SELECT COUNT(*)
                FROM vancepay_employees e
                WHERE e.store_id = s.id
            ) AS employee_count
        FROM vancepay_stores s
    ]]
end

local function toExcludedCitizenIdSet(excludedCitizenIds)
    local excluded = {}

    if type(excludedCitizenIds) == 'table' then
        for _, citizenid in pairs(excludedCitizenIds) do
            citizenid = Utils.trim(citizenid)
            if not Utils.isBlank(citizenid) then
                excluded[citizenid] = true
            end
        end
    else
        excludedCitizenIds = Utils.trim(excludedCitizenIds)
        if not Utils.isBlank(excludedCitizenIds) then
            excluded[excludedCitizenIds] = true
        end
    end

    return excluded
end

local function collectLeadershipCitizenIds(store)
    if not store or not store.id then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT citizenid
        FROM vancepay_employees
        WHERE store_id = ?
            AND role IN ('owner', 'manager')
    ]], { store.id }) or {}

    local ids = {}
    local seen = {}

    local function add(citizenid)
        citizenid = Utils.trim(citizenid)
        if Utils.isBlank(citizenid) or seen[citizenid] then
            return
        end

        seen[citizenid] = true
        ids[#ids + 1] = citizenid
    end

    add(store.owner_citizenid)

    for index = 1, #rows do
        add(rows[index].citizenid)
    end

    return ids
end

local function describeEmployeeAccess(role, canRefund, canDiscount)
    return ('角色 %s，退款%s，折扣%s'):format(
        role or VancePay.EmployeeRoles.cashier,
        canRefund and '开启' or '关闭',
        canDiscount and '开启' or '关闭'
    )
end

local function normalizeSettlementMode(mode)
    mode = Utils.trim(mode)
    if mode == VancePay.StoreSettlementModes.publicAccount then
        return mode
    end

    return VancePay.StoreSettlementModes.storeBalance
end

local function normalizeTaxRate(value)
    return Utils.roundCurrency(Utils.clamp(Utils.ensureNumber(value, 0), 0, 100))
end

local function normalizeCommissionRate(value)
    return Utils.roundCurrency(Utils.clamp(Utils.ensureNumber(value, 0), 0, 100))
end

local function normalizeTaxCustomRateEnabled(value)
    return Utils.parseBool(value)
end

local function normalizeTaxExempt(value)
    return Utils.parseBool(value)
end

local function sanitizeSettlementAccountIdentifier(value, settlementMode)
    value = Utils.trim(value)

    if Utils.isBlank(value) then
        if settlementMode == VancePay.StoreSettlementModes.publicAccount then
            return nil, '绑定公账时必须填写公账标识'
        end

        return nil
    end

    value = Utils.truncateUtf8(value, 100)
    value = Utils.trim(value)

    if Utils.isBlank(value) and settlementMode == VancePay.StoreSettlementModes.publicAccount then
        return nil, '绑定公账时必须填写公账标识'
    end

    return value
end

local function normalizeEmployeeSource(value)
    value = Utils.trim(value)
    if value == EmployeeSources.publicAccountSync then
        return value
    end

    return EmployeeSources.manual
end

local function decorateEmployeeRow(row)
    row = Utils.normalizeDbRow(row)
    row.employee_source = normalizeEmployeeSource(row.employee_source)
    row.employee_source_key = Utils.trim(row.employee_source_key)
    row.employee_source_label = row.employee_source == EmployeeSources.publicAccountSync and '产业同步' or '手动维护'
    return row
end

local function decodeJsonValue(rawValue)
    if type(rawValue) == 'table' then
        return rawValue
    end

    if Utils.isBlank(rawValue) then
        return nil
    end

    local ok, decoded = pcall(json.decode, rawValue)
    if ok and type(decoded) == 'table' then
        return decoded
    end

    return nil
end

local function extractPlayerName(record, fallback)
    if type(record) ~= 'table' then
        fallback = Utils.trim(fallback)
        return Utils.isBlank(fallback) and nil or fallback
    end

    local data = type(record.data) == 'table' and record.data or record
    local charinfo = decodeJsonValue(data.charinfo) or {}
    local firstname = Utils.trim(charinfo.firstname or charinfo.firstName or data.firstname or data.firstName or '')
    local lastname = Utils.trim(charinfo.lastname or charinfo.lastName or data.lastname or data.lastName or '')
    local name = Utils.trim(('%s %s'):format(firstname or '', lastname or ''))

    if Utils.isBlank(name) then
        name = Utils.trim(charinfo.name or data.name or record.name or fallback)
    end

    return Utils.isBlank(name) and nil or name
end

local function parseJobData(rawJob)
    rawJob = decodeJsonValue(rawJob) or rawJob
    if type(rawJob) ~= 'table' then
        return nil
    end

    local grade = type(rawJob.grade) == 'table' and rawJob.grade or {}

    return {
        name = Utils.trim(rawJob.name),
        is_boss = Utils.parseBool(rawJob.isboss)
            or Utils.parseBool(rawJob.isBoss)
            or Utils.parseBool(grade.isboss)
            or Utils.parseBool(grade.isBoss)
            or Utils.parseBool(grade.boss),
    }
end

local function buildSyncedEmployeeAccess()
    return {
        role = VancePay.EmployeeRoles.cashier,
        can_refund = false,
        can_discount = false,
    }
end

local function mergeSyncedEmployeeCandidate(candidates, citizenid, roleHint, isBoss)
    citizenid = Utils.trim(citizenid)
    if Utils.isBlank(citizenid) then
        return
    end

    local access = buildSyncedEmployeeAccess()
    local existing = candidates[citizenid]

    if existing then
        return
    end

    candidates[citizenid] = {
        citizenid = citizenid,
        role = access.role,
        can_refund = access.can_refund,
        can_discount = access.can_discount,
    }
end

local function fetchPlayersTableInfo()
    if not fetchTableExists('players') then
        return nil
    end

    local citizenidColumn = fetchTableColumnMetadata('players', 'citizenid')
    local jobColumn = fetchTableColumnMetadata('players', 'job')
    if not citizenidColumn or not jobColumn then
        return nil
    end

    return {
        has_license = fetchTableColumnMetadata('players', 'license') ~= nil,
        has_cid = fetchTableColumnMetadata('players', 'cid') ~= nil,
    }
end

local function populateEmployeeNames(rows)
    if type(rows) ~= 'table' or #rows == 0 then
        return rows
    end

    local trackedCitizenIds = {}
    local pendingCitizenIds = {}
    local namesByCitizenId = {}

    for index = 1, #rows do
        local employee = rows[index]
        local citizenid = Utils.trim(employee and employee.citizenid)
        if not Utils.isBlank(citizenid) and not trackedCitizenIds[citizenid] then
            trackedCitizenIds[citizenid] = true
            pendingCitizenIds[#pendingCitizenIds + 1] = citizenid
        end
    end

    if #pendingCitizenIds == 0 then
        return rows
    end

    local onlineSources = GetPlayers()
    for index = 1, #onlineSources do
        local sourceId = tonumber(onlineSources[index])
        if sourceId then
            local record = VancePay.Server.getPlayerRecord(sourceId)
            local citizenid = Utils.trim(record and record.citizenid)
            if not Utils.isBlank(citizenid) and trackedCitizenIds[citizenid] then
                namesByCitizenId[citizenid] = extractPlayerName(record, citizenid)
            end
        end
    end

    local unresolvedCitizenIds = {}
    for index = 1, #pendingCitizenIds do
        local citizenid = pendingCitizenIds[index]
        if Utils.isBlank(namesByCitizenId[citizenid]) then
            unresolvedCitizenIds[#unresolvedCitizenIds + 1] = citizenid
        end
    end

    if #unresolvedCitizenIds > 0
        and fetchTableExists('players')
        and fetchTableColumnMetadata('players', 'citizenid')
    then
        local playerRows = MySQL.query.await(
            ('SELECT * FROM players WHERE citizenid IN (%s)'):format(buildPlaceholders(#unresolvedCitizenIds)),
            unresolvedCitizenIds
        ) or {}

        for index = 1, #playerRows do
            local playerRow = playerRows[index]
            local citizenid = Utils.trim(playerRow and playerRow.citizenid)
            if not Utils.isBlank(citizenid) and trackedCitizenIds[citizenid] then
                namesByCitizenId[citizenid] = extractPlayerName(playerRow, citizenid)
            end
        end
    end

    for index = 1, #rows do
        local employee = rows[index]
        local citizenid = Utils.trim(employee and employee.citizenid)
        local name = citizenid and namesByCitizenId[citizenid] or nil
        employee.name = not Utils.isBlank(name) and name or citizenid
    end

    return rows
end

local function getOnlinePlayerIdentifierCandidates(record)
    local data = record and record.data or {}
    local deduped = {}
    local seen = {}

    local function add(value)
        value = Utils.trim(value)
        if not Utils.isBlank(value) and not seen[value] then
            seen[value] = true
            deduped[#deduped + 1] = value
        end
    end

    add(record and record.citizenid or nil)
    add(data.citizenid)
    add(data.citizenId)
    add(data.license)
    add(data.identifier)

    return deduped
end

local function findCitizenIdByPlayerIdentifier(identifier)
    identifier = Utils.trim(identifier)
    if Utils.isBlank(identifier) then
        return nil, nil
    end

    local onlineSources = GetPlayers()
    for index = 1, #onlineSources do
        local sourceId = tonumber(onlineSources[index])
        if sourceId then
            local record = VancePay.Server.getPlayerRecord(sourceId)
            if record then
                local candidates = getOnlinePlayerIdentifierCandidates(record)
                for candidateIndex = 1, #candidates do
                    if candidates[candidateIndex] == identifier then
                        local job = parseJobData(record.data and record.data.job)
                        return Utils.trim(record.citizenid), job
                    end
                end
            end
        end
    end

    local playersTable = fetchPlayersTableInfo()
    if not playersTable then
        return nil, nil
    end

    local conditions = { 'citizenid = ?' }
    local params = { identifier }

    if playersTable.has_license then
        conditions[#conditions + 1] = 'license = ?'
        params[#params + 1] = identifier
    end

    if playersTable.has_cid and tonumber(identifier) then
        conditions[#conditions + 1] = 'cid = ?'
        params[#params + 1] = tonumber(identifier)
    end

    local row = MySQL.single.await(
        ('SELECT citizenid, job FROM players WHERE %s LIMIT 1'):format(table.concat(conditions, ' OR ')),
        params
    )
    if not row then
        return nil, nil
    end

    return Utils.trim(row.citizenid), parseJobData(row.job)
end

local function collectOnlinePlayersByJob(jobName, candidates)
    jobName = Utils.trim(jobName)
    if Utils.isBlank(jobName) then
        return
    end

    local onlineSources = GetPlayers()
    for index = 1, #onlineSources do
        local sourceId = tonumber(onlineSources[index])
        if sourceId then
            local record = VancePay.Server.getPlayerRecord(sourceId)
            local citizenid = record and Utils.trim(record.citizenid)
            local job = parseJobData(record and record.data and record.data.job)
            if not Utils.isBlank(citizenid) and job and job.name == jobName then
                mergeSyncedEmployeeCandidate(candidates, citizenid, nil, job.is_boss)
            end
        end
    end
end

local function collectOfflinePlayersByJob(jobName, candidates)
    jobName = Utils.trim(jobName)
    if Utils.isBlank(jobName) then
        return
    end

    local playersTable = fetchPlayersTableInfo()
    if not playersTable then
        return
    end

    local rows = {}
    local ok, result = pcall(MySQL.query.await, [[
        SELECT citizenid, job
        FROM players
        WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?
    ]], { jobName })

    if ok and type(result) == 'table' then
        rows = result
    else
        rows = MySQL.query.await([[
            SELECT citizenid, job
            FROM players
        ]]) or {}
    end

    for index = 1, #rows do
        local row = rows[index]
        local citizenid = Utils.trim(row.citizenid)
        local job = parseJobData(row.job)
        if not Utils.isBlank(citizenid) and job and job.name == jobName then
            mergeSyncedEmployeeCandidate(candidates, citizenid, nil, job.is_boss)
        end
    end
end

local function fetchPublicAccountRecord(identifier)
    identifier = Utils.trim(identifier)
    if Utils.isBlank(identifier) or not fetchTableExists('p_bank_accounts') then
        return nil
    end

    local row = MySQL.single.await([[
        SELECT *
        FROM p_bank_accounts
        WHERE iban = ?
            OR owner = ?
            OR name = ?
        ORDER BY
            CASE
                WHEN iban = ? THEN 0
                WHEN owner = ? THEN 1
                WHEN name = ? THEN 2
                ELSE 3
            END
        LIMIT 1
    ]], { identifier, identifier, identifier, identifier, identifier, identifier })

    return row and Utils.normalizeDbRow(row) or nil
end

local function collectPublicAccountEmployees(store)
    local accountIdentifier = Stores.getPublicAccountIdentifier(store)
    if Utils.isBlank(accountIdentifier) then
        return nil, '当前店铺未绑定可同步的产业账户', 'missing_public_account'
    end

    local account = fetchPublicAccountRecord(accountIdentifier)
    if not account then
        return nil, '未找到对应的产业账户记录，无法同步人员', 'account_not_found'
    end

    local accountType = Utils.trim(account.type)
    if not Utils.isBlank(accountType) and accountType ~= 'society' then
        return nil, '当前绑定账户不是产业账户，不能同步人员', 'unsupported_account_type'
    end

    local candidates = {}
    local users = decodeJsonValue(account.users) or {}

    for userKey, entry in pairs(users) do
        local roleHint = nil
        local citizenid = nil
        local job = nil
        local identifier = nil

        if type(entry) == 'table' then
            roleHint = entry.role or entry.permission or entry.type
            citizenid = Utils.trim(entry.citizenid)
            identifier = entry.identifier
                or entry.player_identifier
                or entry.owner
                or entry.id
                or entry.value
                or (type(userKey) == 'string' and userKey or nil)
        else
            roleHint = type(entry) == 'string' and entry or nil
            identifier = type(userKey) == 'string' and userKey or entry
        end

        if Utils.isBlank(citizenid) then
            citizenid, job = findCitizenIdByPlayerIdentifier(identifier)
        else
            _, job = findCitizenIdByPlayerIdentifier(citizenid)
        end

        mergeSyncedEmployeeCandidate(candidates, citizenid, roleHint, job and job.is_boss)
    end

    local jobName = Utils.trim(account.owner)
    if next(candidates) == nil and not Utils.isBlank(jobName) then
        collectOnlinePlayersByJob(jobName, candidates)
        collectOfflinePlayersByJob(jobName, candidates)
    end

    return {
        account = account,
        account_identifier = accountIdentifier,
        job_name = jobName,
        members = candidates,
    }
end

local function isPublicAccountMode(modeOrStore)
    local mode = type(modeOrStore) == 'table' and modeOrStore.settlement_mode or modeOrStore
    return normalizeSettlementMode(mode) == VancePay.StoreSettlementModes.publicAccount
end

local function buildSettlementTargetLabel(store)
    if isPublicAccountMode(store) then
        local identifier = Utils.trim(store and store.settlement_account_identifier or nil)
        if Utils.isBlank(identifier) then
            return '绑定公账'
        end

        return ('公账 %s'):format(identifier)
    end

    return 'VancePay 店铺余额'
end

local function buildTaxTargetLabel(store, settlementMode, settlementAccountIdentifier)
    settlementMode = normalizeSettlementMode(settlementMode)
    settlementAccountIdentifier = Utils.trim(settlementAccountIdentifier)
    if settlementMode ~= VancePay.StoreSettlementModes.publicAccount then
        settlementAccountIdentifier = nil
    elseif Utils.isBlank(settlementAccountIdentifier) then
        settlementAccountIdentifier = nil
    end

    if normalizeTaxExempt(store.tax_exempt) then
        return '免税'
    end

    if Stores.getEffectiveTaxRate and Stores.getEffectiveTaxRate(store) <= 0 then
        return '未启用税收'
    end

    if settlementMode == VancePay.StoreSettlementModes.publicAccount then
        if Utils.isBlank(settlementAccountIdentifier) then
            return '税收公账'
        end

        return ('税收公账 %s'):format(settlementAccountIdentifier)
    end

    return '当前店铺 VancePay 余额'
end

function Stores.supportsPublicAccountSettlement()
    return VancePay.Banking
        and type(VancePay.Banking.supportsDirectAccountSettlement) == 'function'
        and VancePay.Banking.supportsDirectAccountSettlement() == true
end

function Stores.getDefaultTaxRate()
    local rawValue = getCachedSettingValue(SettingKeys.defaultTaxRate)
    if rawValue == nil then
        return getDefaultTaxRateFallback()
    end

    return normalizeTaxRate(rawValue)
end

function Stores.getTaxDefaults()
    Stores.ensureReady()

    local taxSettlement = Stores.getTaxSettlementTarget(nil)

    return {
        default_tax_rate = Stores.getDefaultTaxRate(),
        tax_settlement_mode = taxSettlement.mode,
        tax_settlement_account_identifier = taxSettlement.identifier,
        tax_target_label = taxSettlement.label,
    }
end

function Stores.hasCustomTaxRate(store)
    return normalizeTaxCustomRateEnabled(store and store.tax_custom_rate_enabled)
end

function Stores.getSettlementMode(store)
    return normalizeSettlementMode(store and store.settlement_mode)
end

function Stores.getCommissionRate(store)
    return normalizeCommissionRate(store and store.commission_rate)
end

function Stores.isPublicAccountStore(store)
    return isPublicAccountMode(store)
end

function Stores.getPublicAccountIdentifier(store)
    if not isPublicAccountMode(store) then
        return nil
    end

    local identifier = Utils.trim(store and store.settlement_account_identifier or nil)
    if Utils.isBlank(identifier) then
        return nil
    end

    return identifier
end

function Stores.getSettlementTarget(store)
    if isPublicAccountMode(store) then
        return {
            mode = VancePay.StoreSettlementModes.publicAccount,
            identifier = Stores.getPublicAccountIdentifier(store),
            label = buildSettlementTargetLabel(store),
            is_direct = true,
        }
    end

    return {
        mode = VancePay.StoreSettlementModes.storeBalance,
        identifier = nil,
        label = buildSettlementTargetLabel(store),
        is_direct = false,
    }
end

function Stores.getTaxRate(store)
    return normalizeTaxRate(store and store.tax_rate)
end

function Stores.isTaxExempt(store)
    return normalizeTaxExempt(store and store.tax_exempt)
end

function Stores.getEffectiveTaxRate(store)
    if Stores.isTaxExempt(store) then
        return 0
    end

    if Stores.hasCustomTaxRate(store) then
        return Stores.getTaxRate(store)
    end

    return Stores.getDefaultTaxRate()
end

function Stores.isTaxEnabled(store)
    return Stores.getEffectiveTaxRate(store) > 0
end

function Stores.getTaxSettlementTarget(store)
    local mode = normalizeSettlementMode(getCachedSettingValue(SettingKeys.taxSettlementMode))
    local identifier = Utils.trim(getCachedSettingValue(SettingKeys.taxSettlementAccountIdentifier))

    if mode ~= VancePay.StoreSettlementModes.publicAccount or Utils.isBlank(identifier) then
        identifier = nil
    end

    return {
        mode = mode,
        identifier = identifier,
        label = store and buildTaxTargetLabel(store, mode, identifier)
            or buildTaxTargetLabel({
                tax_exempt = false,
                tax_custom_rate_enabled = true,
                tax_rate = Stores.getDefaultTaxRate(),
            }, mode, identifier),
        is_direct = mode == VancePay.StoreSettlementModes.publicAccount,
    }
end

function Stores.getAvailableBalance(store)
    if not store then
        return 0
    end

    if isPublicAccountMode(store) then
        local identifier = Stores.getPublicAccountIdentifier(store)
        if Utils.isBlank(identifier) then
            return 0
        end

        return Utils.roundCurrency(VancePay.Banking.getBalance(identifier))
    end

    return Utils.roundCurrency(store.balance)
end

function Stores.getPayoutAvailableBalance(store)
    if not store or isPublicAccountMode(store) then
        return 0
    end

    return Utils.roundCurrency(store.balance)
end

local function decorateStoreRow(store)
    if not store then
        return nil
    end

    store = Utils.normalizeDbRow(store)
    store.settlement_mode = normalizeSettlementMode(store.settlement_mode)
    store.settlement_account_identifier = Utils.trim(store.settlement_account_identifier)
    store.commission_rate = normalizeCommissionRate(store.commission_rate)
    store.tax_rate = normalizeTaxRate(store.tax_rate)
    store.tax_custom_rate_enabled = normalizeTaxCustomRateEnabled(store.tax_custom_rate_enabled)
    store.tax_exempt = normalizeTaxExempt(store.tax_exempt)
    store.tax_settlement_mode = normalizeSettlementMode(store.tax_settlement_mode)
    store.tax_settlement_account_identifier = Utils.trim(store.tax_settlement_account_identifier)

    if store.settlement_mode ~= VancePay.StoreSettlementModes.publicAccount then
        store.settlement_account_identifier = nil
    end

    if store.tax_settlement_mode ~= VancePay.StoreSettlementModes.publicAccount then
        store.tax_settlement_account_identifier = nil
    end

    local taxSettlement = Stores.getTaxSettlementTarget(store)
    store.tax_settlement_mode = taxSettlement.mode
    store.tax_settlement_account_identifier = taxSettlement.identifier

    store.available_balance = Stores.getAvailableBalance(store)
    store.balance_label = store.settlement_mode == VancePay.StoreSettlementModes.publicAccount and '公账余额' or '店铺余额'
    store.settlement_mode_label = store.settlement_mode == VancePay.StoreSettlementModes.publicAccount and '绑定公账' or 'VancePay 店铺余额'
    store.settlement_target_label = buildSettlementTargetLabel(store)
    store.commission_enabled = store.commission_rate > 0
    store.default_tax_rate = Stores.getDefaultTaxRate()
    store.custom_tax_rate = store.tax_rate
    store.tax_enabled = Stores.isTaxEnabled(store)
    store.effective_tax_rate = Stores.getEffectiveTaxRate(store)
    store.tax_target_label = taxSettlement.label
    store.tax_status_label = store.tax_exempt
        and '免税'
        or (store.tax_enabled and (
            store.tax_custom_rate_enabled
                and ('自定义 %.2f%%'):format(store.effective_tax_rate)
                or ('默认 %.2f%%'):format(store.effective_tax_rate)
        ) or '未启用')
    store.payout_available_balance = Stores.getPayoutAvailableBalance(store)

    return store
end

function Stores.ensureReady()
    if Stores._ready then
        return true
    end

    while Stores._initializing do
        Wait(50)
        if Stores._ready then
            return true
        end
    end

    Stores._initializing = true
    local ok, err = pcall(function()
        if shouldRunSchemaMigrations() then
            ensureSchema()
        end
    end)
    Stores._initializing = false
    if not ok then
        error(err)
    end

    Stores._ready = true
    return true
end

function Stores.fetchById(storeId)
    Stores.ensureReady()

    if not tonumber(storeId) then
        return nil
    end

    local row = MySQL.single.await(fetchStoreCounters() .. ' WHERE s.id = ? LIMIT 1', { tonumber(storeId) })
    return row and decorateStoreRow(row) or nil
end

function Stores.getManagedStoreIds(citizenid)
    Stores.ensureReady()

    if Utils.isBlank(citizenid) then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT store_id
        FROM vancepay_employees
        WHERE citizenid = ? AND role IN ('owner', 'manager')
    ]], { citizenid }) or {}

    local ids = {}
    for index = 1, #rows do
        ids[#ids + 1] = tonumber(rows[index].store_id)
    end

    return ids
end

function Stores.getEmployeeStoreIds(citizenid)
    Stores.ensureReady()

    if Utils.isBlank(citizenid) then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT store_id
        FROM vancepay_employees
        WHERE citizenid = ?
    ]], { citizenid }) or {}

    local ids = {}
    for index = 1, #rows do
        ids[#ids + 1] = tonumber(rows[index].store_id)
    end

    return ids
end

function Stores.listForSource(source, filters)
    Stores.ensureReady()

    filters = filters or {}

    local query = fetchStoreCounters()
    local params = {}
    local conditions = {}

    if filters.store_id then
        conditions[#conditions + 1] = 's.id = ?'
        params[#params + 1] = tonumber(filters.store_id)
    end

    if filters.status and filters.status ~= 'all' then
        conditions[#conditions + 1] = 's.status = ?'
        params[#params + 1] = filters.status
    end

    if not VancePay.Permissions.isAdmin(source) then
        local citizenid = VancePay.Permissions.getCitizenId(source)
        local storeIds = Stores.getManagedStoreIds(citizenid)
        if #storeIds == 0 then
            return {}
        end

        conditions[#conditions + 1] = ('s.id IN (%s)'):format(buildPlaceholders(#storeIds))
        for index = 1, #storeIds do
            params[#params + 1] = storeIds[index]
        end
    end

    if #conditions > 0 then
        query = query .. ' WHERE ' .. table.concat(conditions, ' AND ')
    end

    query = query .. ' ORDER BY s.id DESC'

    local rows = MySQL.query.await(query, params) or {}

    for index = 1, #rows do
        rows[index] = decorateStoreRow(rows[index])
    end

    return rows
end

function Stores.getLeadershipSources(storeId, excludedCitizenIds)
    local store = Stores.fetchById(storeId)
    if not store then
        return {}, nil
    end

    local excluded = toExcludedCitizenIdSet(excludedCitizenIds)
    local citizenids = collectLeadershipCitizenIds(store)
    local sources = {}

    for index = 1, #citizenids do
        local citizenid = citizenids[index]
        if not excluded[citizenid] then
            local playerSource = VancePay.Server.getSourceByCitizenId(citizenid)
            if playerSource and playerSource > 0 then
                sources[#sources + 1] = playerSource
            end
        end
    end

    return sources, store
end

function Stores.notifyLeadership(storeId, message, notifyType, excludedCitizenIds)
    local sources = Stores.getLeadershipSources(storeId, excludedCitizenIds)

    for index = 1, #sources do
        VancePay.Server.notify(sources[index], message, notifyType)
    end
end

local function validateStoreName(name)
    name = Utils.trim(name)
    if Utils.isBlank(name) then
        return nil, '店铺名称不能为空'
    end

    if #name > 100 then
        return nil, '店铺名称不能超过 100 个字符'
    end

    return name
end

function Stores.create(source, payload)
    Stores.ensureReady()

    if not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail('只有管理员可以创建店铺', 'forbidden')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    local name, errorMessage = validateStoreName(payload.name)
    if not name then
        return VancePay.Server.fail(errorMessage, 'invalid_name')
    end

    local ownerCitizenId = Utils.trim(payload.owner_citizenid)
    if Utils.isBlank(ownerCitizenId) then
        return VancePay.Server.fail('店主 citizenid 不能为空', 'invalid_owner')
    end

    local settlementMode = normalizeSettlementMode(payload.settlement_mode)
    if settlementMode == VancePay.StoreSettlementModes.publicAccount and not Stores.supportsPublicAccountSettlement() then
        return VancePay.Server.fail('当前银行适配器不支持绑定公账', 'unsupported_settlement_mode')
    end

    local settlementAccountIdentifier, settlementError = sanitizeSettlementAccountIdentifier(
        payload.settlement_account_identifier or payload.public_account_identifier,
        settlementMode
    )
    if settlementError then
        return VancePay.Server.fail(settlementError, 'invalid_settlement_account')
    end

    local success = MySQL.transaction.await({
        {
            query = [[
                INSERT INTO vancepay_stores (
                    name,
                    owner_citizenid,
                    status,
                    settlement_mode,
                    settlement_account_identifier
                )
                VALUES (?, ?, ?, ?, ?)
            ]],
            values = {
                name,
                ownerCitizenId,
                VancePay.StoreStatuses.active,
                settlementMode,
                settlementAccountIdentifier,
            }
        },
        {
            query = [[
                INSERT INTO vancepay_employees (
                    store_id,
                    citizenid,
                    role,
                    can_refund,
                    can_discount,
                    employee_source,
                    employee_source_key
                ) VALUES (LAST_INSERT_ID(), ?, 'owner', 1, 1, 'manual', NULL)
            ]],
            values = { ownerCitizenId }
        }
    })

    if not success then
        return VancePay.Server.fail('创建店铺失败', 'db_error')
    end

    local createdStore = MySQL.single.await([[
        SELECT *
        FROM vancepay_stores
        WHERE owner_citizenid = ? AND name = ?
        ORDER BY id DESC
        LIMIT 1
    ]], { ownerCitizenId, name })

    createdStore = createdStore and Stores.fetchById(createdStore.id) or nil

    VancePay.Audit.log(actorCitizenId, 'create_store', 'store', createdStore and createdStore.id or nil, {
        store_id = createdStore and createdStore.id or nil,
        detail = {
            name = name,
            owner_citizenid = ownerCitizenId,
            settlement_mode = settlementMode,
            settlement_account_identifier = settlementAccountIdentifier,
            commission_rate = 0,
        }
    })

    return VancePay.Server.ok(createdStore, '店铺已创建')
end

function Stores.update(source, payload)
    Stores.ensureReady()

    local storeId = tonumber(payload.id or payload.store_id)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    local isAdmin = VancePay.Permissions.isAdmin(source)
    local allowed, accessOrMessage = VancePay.Permissions.checkAccess(source, storeId, 'manage')
    if not allowed and not isAdmin then
        return VancePay.Server.fail(accessOrMessage, 'forbidden')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    local name, errorMessage = validateStoreName(payload.name or store.name)
    if not name then
        return VancePay.Server.fail(errorMessage, 'invalid_name')
    end

    local settlementMode = Stores.getSettlementMode(store)
    local settlementAccountIdentifier = Stores.getPublicAccountIdentifier(store)

    if isAdmin then
        settlementMode = normalizeSettlementMode(payload.settlement_mode or store.settlement_mode)
        if settlementMode == VancePay.StoreSettlementModes.publicAccount and not Stores.supportsPublicAccountSettlement() then
            return VancePay.Server.fail('当前银行适配器不支持绑定公账', 'unsupported_settlement_mode')
        end

        local newSettlementAccountIdentifier, settlementError = sanitizeSettlementAccountIdentifier(
            payload.settlement_account_identifier or payload.public_account_identifier or store.settlement_account_identifier,
            settlementMode
        )
        if settlementError then
            return VancePay.Server.fail(settlementError, 'invalid_settlement_account')
        end

        settlementAccountIdentifier = newSettlementAccountIdentifier
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_stores
        SET name = ?,
            settlement_mode = ?,
            settlement_account_identifier = ?
        WHERE id = ?
    ]], {
        name,
        settlementMode,
        settlementAccountIdentifier,
        storeId,
    })

    if not updated or updated < 1 then
        return VancePay.Server.fail('未更新任何店铺信息', 'no_change')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'update_store', 'store', storeId, {
        store_id = storeId,
        detail = {
            old_name = store.name,
            new_name = name,
            old_settlement_mode = store.settlement_mode,
            new_settlement_mode = settlementMode,
            old_settlement_account_identifier = store.settlement_account_identifier,
            new_settlement_account_identifier = settlementAccountIdentifier,
        }
    })

    return VancePay.Server.ok(Stores.fetchById(storeId), '店铺信息已更新')
end

function Stores.updateTaxSettings(source, payload)
    Stores.ensureReady()

    payload = payload or {}

    if not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail('只有管理员可以修改税务设置', 'forbidden')
    end

    local storeId = tonumber(payload.store_id or payload.id)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    local taxRate = normalizeTaxRate(payload.tax_rate ~= nil and payload.tax_rate or payload.custom_tax_rate or store.tax_rate)
    local taxCustomRateEnabled = normalizeTaxCustomRateEnabled(
        payload.tax_custom_rate_enabled ~= nil and payload.tax_custom_rate_enabled or store.tax_custom_rate_enabled
    )
    local taxExempt = normalizeTaxExempt(payload.tax_exempt ~= nil and payload.tax_exempt or store.tax_exempt)

    local updated = MySQL.update.await([[
        UPDATE vancepay_stores
        SET tax_rate = ?,
            tax_custom_rate_enabled = ?,
            tax_exempt = ?
        WHERE id = ?
    ]], {
        taxRate,
        taxCustomRateEnabled and 1 or 0,
        taxExempt and 1 or 0,
        storeId,
    })

    if not updated or updated < 1 then
        return VancePay.Server.fail('未更新任何税务信息', 'no_change')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'update_store_tax', 'store', storeId, {
        store_id = storeId,
        detail = {
            old_tax_rate = store.tax_rate,
            new_tax_rate = taxRate,
            old_tax_custom_rate_enabled = store.tax_custom_rate_enabled,
            new_tax_custom_rate_enabled = taxCustomRateEnabled,
            old_tax_exempt = store.tax_exempt,
            new_tax_exempt = taxExempt,
        }
    })

    return VancePay.Server.ok(Stores.fetchById(storeId), '税务设置已更新')
end

function Stores.updateCommissionSettings(source, payload)
    Stores.ensureReady()

    payload = payload or {}

    local storeId = tonumber(payload.store_id or payload.id)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    local allowed, accessOrMessage = VancePay.Permissions.checkAccess(source, storeId, 'manage')
    if not allowed and not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail(accessOrMessage, 'forbidden')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    local commissionRate = normalizeCommissionRate(
        payload.commission_rate ~= nil and payload.commission_rate or store.commission_rate
    )

    if commissionRate == store.commission_rate then
        return VancePay.Server.fail('提成比例未发生变化', 'no_change')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_stores
        SET commission_rate = ?
        WHERE id = ?
    ]], {
        commissionRate,
        storeId,
    })

    if not updated or updated < 1 then
        return VancePay.Server.fail('未更新任何提成信息', 'no_change')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'update_store_commission', 'store', storeId, {
        store_id = storeId,
        detail = {
            old_commission_rate = store.commission_rate,
            new_commission_rate = commissionRate,
        }
    })

    return VancePay.Server.ok(Stores.fetchById(storeId), '提成设置已更新')
end

function Stores.updateTaxDefaults(source, payload)
    Stores.ensureReady()

    payload = payload or {}

    if not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail('只有管理员可以修改全局税务设置', 'forbidden')
    end

    local oldDefaultTaxRate = Stores.getDefaultTaxRate()
    local oldTaxSettlement = Stores.getTaxSettlementTarget(nil)
    local defaultTaxRate = normalizeTaxRate(payload.default_tax_rate ~= nil and payload.default_tax_rate or oldDefaultTaxRate)
    local taxSettlementMode = normalizeSettlementMode(
        payload.tax_settlement_mode ~= nil and payload.tax_settlement_mode or oldTaxSettlement.mode
    )

    if taxSettlementMode == VancePay.StoreSettlementModes.publicAccount and not Stores.supportsPublicAccountSettlement() then
        return VancePay.Server.fail('当前银行适配器不支持绑定公账', 'unsupported_settlement_mode')
    end

    local taxSettlementAccountIdentifier, settlementError = sanitizeSettlementAccountIdentifier(
        payload.tax_settlement_account_identifier ~= nil
            and payload.tax_settlement_account_identifier
            or payload.tax_public_account_identifier
            or oldTaxSettlement.identifier,
        taxSettlementMode
    )
    if settlementError then
        return VancePay.Server.fail(settlementError, 'invalid_tax_settlement_account')
    end

    if defaultTaxRate == oldDefaultTaxRate
        and taxSettlementMode == oldTaxSettlement.mode
        and taxSettlementAccountIdentifier == oldTaxSettlement.identifier then
        return VancePay.Server.fail('全局税务设置未发生变化', 'no_change')
    end

    setSettingValue(SettingKeys.defaultTaxRate, defaultTaxRate)
    setSettingValue(SettingKeys.taxSettlementMode, taxSettlementMode)
    setSettingValue(SettingKeys.taxSettlementAccountIdentifier, taxSettlementAccountIdentifier or '')

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'update_tax_defaults', 'config', 'tax_defaults', {
        detail = {
            old_default_tax_rate = oldDefaultTaxRate,
            new_default_tax_rate = defaultTaxRate,
            old_tax_settlement_mode = oldTaxSettlement.mode,
            new_tax_settlement_mode = taxSettlementMode,
            old_tax_settlement_account_identifier = oldTaxSettlement.identifier,
            new_tax_settlement_account_identifier = taxSettlementAccountIdentifier,
        }
    })

    return VancePay.Server.ok(Stores.getTaxDefaults(), '全局税务设置已更新')
end

function Stores.archive(source, storeId)
    Stores.ensureReady()

    storeId = tonumber(storeId)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    local allowed, accessOrMessage = VancePay.Permissions.checkAccess(source, storeId, 'manage')
    if not allowed and not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail(accessOrMessage, 'forbidden')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_stores
        SET status = 'archived', archived_at = CURRENT_TIMESTAMP
        WHERE id = ? AND status <> 'archived'
    ]], { storeId })

    if not updated or updated < 1 then
        return VancePay.Server.fail('店铺已归档或无法归档', 'no_change')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'archive_store', 'store', storeId, {
        store_id = storeId,
        detail = { name = store.name }
    })

    local ownerSource = VancePay.Server.getSourceByCitizenId(store.owner_citizenid)
    if ownerSource then
        VancePay.Server.notify(ownerSource, ('店铺 %s 已归档，新的收款请求已停止'):format(store.name), 'warning')
    end

    if VancePay.Terminals and VancePay.Terminals.refreshFixedTerminalCache then
        VancePay.Terminals.refreshFixedTerminalCache(true)
    end

    return VancePay.Server.ok(Stores.fetchById(storeId), '店铺已归档')
end

function Stores.restore(source, storeId)
    Stores.ensureReady()

    storeId = tonumber(storeId)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    local allowed, accessOrMessage = VancePay.Permissions.checkAccess(source, storeId, 'manage')
    if not allowed and not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail(accessOrMessage, 'forbidden')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_stores
        SET status = 'active', archived_at = NULL
        WHERE id = ? AND status = 'archived'
    ]], { storeId })

    if not updated or updated < 1 then
        return VancePay.Server.fail('店铺未归档或无法取消归档', 'no_change')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'restore_store', 'store', storeId, {
        store_id = storeId,
        detail = { name = store.name }
    })

    local ownerSource = VancePay.Server.getSourceByCitizenId(store.owner_citizenid)
    if ownerSource then
        VancePay.Server.notify(ownerSource, ('店铺 %s 已恢复启用，可继续发起新交易'):format(store.name), 'success')
    end

    if VancePay.Terminals and VancePay.Terminals.refreshFixedTerminalCache then
        VancePay.Terminals.refreshFixedTerminalCache(true)
    end

    return VancePay.Server.ok(Stores.fetchById(storeId), '店铺已取消归档')
end

function Stores.changeOwner(source, payload)
    Stores.ensureReady()

    if not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail('只有管理员可以更换店主', 'forbidden')
    end

    local storeId = tonumber(payload.store_id or payload.id)
    local newOwnerCitizenId = Utils.trim(payload.owner_citizenid)
    if not storeId or Utils.isBlank(newOwnerCitizenId) then
        return VancePay.Server.fail('参数不完整', 'invalid_payload')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    local success = MySQL.transaction.await({
        {
            query = [[
                UPDATE vancepay_stores
                SET owner_citizenid = ?
                WHERE id = ?
            ]],
            values = { newOwnerCitizenId, storeId }
        },
        {
            query = [[
                UPDATE vancepay_employees
                SET role = 'manager',
                    employee_source = 'manual',
                    employee_source_key = NULL
                WHERE store_id = ? AND role = 'owner' AND citizenid <> ?
            ]],
            values = { storeId, newOwnerCitizenId }
        },
        {
            query = [[
                INSERT INTO vancepay_employees (
                    store_id,
                    citizenid,
                    role,
                    can_refund,
                    can_discount,
                    employee_source,
                    employee_source_key
                ) VALUES (?, ?, 'owner', 1, 1, 'manual', NULL)
                ON DUPLICATE KEY UPDATE
                    role = VALUES(role),
                    can_refund = VALUES(can_refund),
                    can_discount = VALUES(can_discount),
                    employee_source = VALUES(employee_source),
                    employee_source_key = VALUES(employee_source_key),
                    updated_at = CURRENT_TIMESTAMP
            ]],
            values = { storeId, newOwnerCitizenId }
        }
    })

    if not success then
        return VancePay.Server.fail('更换店主失败', 'db_error')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'change_owner', 'store', storeId, {
        store_id = storeId,
        detail = {
            old_owner_citizenid = store.owner_citizenid,
            new_owner_citizenid = newOwnerCitizenId,
        }
    })

    local oldOwnerSource = VancePay.Server.getSourceByCitizenId(store.owner_citizenid)
    if oldOwnerSource then
        VancePay.Server.notify(
            oldOwnerSource,
            ('你已不再是店铺 %s 的店主，当前店主为 %s'):format(store.name, newOwnerCitizenId),
            'warning'
        )
    end

    local newOwnerSource = VancePay.Server.getSourceByCitizenId(newOwnerCitizenId)
    if newOwnerSource then
        VancePay.Server.notify(newOwnerSource, ('你已成为店铺 %s 的店主'):format(store.name), 'success')
    end

    Stores.notifyLeadership(
        storeId,
        ('店铺 %s 店主已变更为 %s'):format(store.name, newOwnerCitizenId),
        'inform',
        { actorCitizenId, store.owner_citizenid, newOwnerCitizenId }
    )

    return VancePay.Server.ok(Stores.fetchById(storeId), '店主已更新')
end

function Stores.payout(source, payload)
    Stores.ensureReady()

    payload = payload or {}

    local storeId = tonumber(payload.store_id or payload.id)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    local amount = Utils.roundCurrency(Utils.ensureNumber(payload.amount or payload.payout_amount, 0))
    if amount <= 0 then
        return VancePay.Server.fail('提现金额必须大于 0', 'invalid_amount')
    end

    local payoutReason = payload.reason ~= nil and Utils.trim(tostring(payload.reason)) or nil
    if Utils.isBlank(payoutReason) then
        payoutReason = nil
    end
    if payoutReason and #payoutReason > 255 then
        return VancePay.Server.fail('提现备注不能超过 255 个字符', 'reason_too_long')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    if not VancePay.Permissions.isAdmin(source) then
        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    if Stores.isPublicAccountStore(store) then
        return VancePay.Server.fail('当前店铺为公账直入模式，不支持提现到店主账户', 'payout_not_supported')
    end

    if Utils.isBlank(store.owner_citizenid) then
        return VancePay.Server.fail('当前店铺没有可用的店主账户', 'missing_owner')
    end

    local currentBalance = Stores.getPayoutAvailableBalance(store)
    if currentBalance < amount then
        return VancePay.Server.fail(
            ('店铺余额不足，当前仅剩 %s'):format(Utils.formatCurrency(currentBalance)),
            'insufficient_store_balance'
        )
    end

    local deposited = VancePay.Banking.deposit(
        store.owner_citizenid,
        amount,
        ('vancepay:payout:store:%s'):format(storeId)
    )
    if not deposited then
        return VancePay.Server.fail('打款到店主账户失败', 'deposit_failed')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_stores
        SET balance = balance - ?
        WHERE id = ?
            AND balance >= ?
    ]], { amount, storeId, amount })

    if not updated or updated < 1 then
        local rolledBack = VancePay.Banking.withdraw(
            store.owner_citizenid,
            amount,
            ('vancepay:payout_rollback:store:%s'):format(storeId)
        )

        if not rolledBack then
            Utils.debug('Store payout rollback failed', storeId, amount, store.owner_citizenid)
        end

        return VancePay.Server.fail('店铺余额更新失败，已尝试回滚打款', 'db_error')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    local refreshedStore = Stores.fetchById(storeId)
    local remainingBalance = refreshedStore and Utils.roundCurrency(refreshedStore.balance) or Utils.roundCurrency(currentBalance - amount)

    VancePay.Audit.log(actorCitizenId, 'payout_store', 'store', storeId, {
        store_id = storeId,
        detail = {
            amount = amount,
            owner_citizenid = store.owner_citizenid,
            reason = payoutReason,
            balance_before = currentBalance,
            balance_after = remainingBalance,
        }
    })

    local ownerSource = VancePay.Server.getSourceByCitizenId(store.owner_citizenid)
    if ownerSource and store.owner_citizenid ~= actorCitizenId then
        VancePay.Server.notify(
            ownerSource,
            ('店铺 %s 已向你的银行账户结算 %s'):format(store.name, Utils.formatCurrency(amount)),
            'success'
        )
    end

    Stores.notifyLeadership(
        storeId,
        ('店铺 %s 已提现 %s，剩余余额 %s'):format(
            store.name,
            Utils.formatCurrency(amount),
            Utils.formatCurrency(remainingBalance)
        ),
        'inform',
        { actorCitizenId, store.owner_citizenid }
    )

    return VancePay.Server.ok({
        store = refreshedStore,
        amount = amount,
        owner_citizenid = store.owner_citizenid,
        remaining_balance = remainingBalance,
    }, ('已向店主账户结算 %s'):format(Utils.formatCurrency(amount)))
end

function Stores.listEmployees(source, storeId)
    Stores.ensureReady()

    storeId = tonumber(storeId)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    if not VancePay.Permissions.isAdmin(source) then
        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    local rows = MySQL.query.await([[
        SELECT *
        FROM vancepay_employees
        WHERE store_id = ?
        ORDER BY FIELD(role, 'owner', 'manager', 'cashier'), id ASC
    ]], { storeId }) or {}

    for index = 1, #rows do
        rows[index] = decorateEmployeeRow(rows[index])
    end

    populateEmployeeNames(rows)

    return VancePay.Server.ok(rows)
end

function Stores.resolveCitizenIdByPlayerId(source, payload)
    Stores.ensureReady()

    payload = payload or {}

    local storeId = tonumber(payload.store_id or payload.id)
    local isAdmin = VancePay.Permissions.isAdmin(source)

    if not isAdmin then
        if not storeId then
            return VancePay.Server.fail('缺少店铺上下文，无法验证权限', 'missing_store_id')
        end

        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    local targetSource = tonumber(payload.player_id or payload.source or payload.target_source or payload.target_id)
    if not targetSource or targetSource < 1 then
        return VancePay.Server.fail('请填写有效的在线玩家 ID', 'invalid_player_id')
    end

    local record = VancePay.Server.getPlayerRecord(targetSource)
    if not record then
        return VancePay.Server.fail('未找到该在线玩家', 'player_not_found')
    end

    local citizenid = Utils.trim(record.citizenid)
    if Utils.isBlank(citizenid) then
        return VancePay.Server.fail('该玩家当前没有可用的 CitizenID', 'missing_citizenid')
    end

    return VancePay.Server.ok({
        source = targetSource,
        citizenid = citizenid,
        name = record.name,
    }, ('已找到 %s 的 CitizenID'):format(record.name or ('玩家 #' .. tostring(targetSource))))
end

function Stores.saveEmployee(source, payload)
    Stores.ensureReady()

    local storeId = tonumber(payload.store_id)
    local citizenid = Utils.trim(payload.citizenid)
    local role = Utils.trim(payload.role or VancePay.EmployeeRoles.cashier)
    local canRefund = Utils.parseBool(payload.can_refund)
    local canDiscount = Utils.parseBool(payload.can_discount)
    local isAdmin = VancePay.Permissions.isAdmin(source)

    if not storeId or Utils.isBlank(citizenid) then
        return VancePay.Server.fail('员工参数不完整', 'invalid_payload')
    end

    if role ~= VancePay.EmployeeRoles.owner
        and role ~= VancePay.EmployeeRoles.manager
        and role ~= VancePay.EmployeeRoles.cashier then
        return VancePay.Server.fail('员工角色无效', 'invalid_role')
    end

    if role == VancePay.EmployeeRoles.owner then
        return VancePay.Server.fail('更换店主请使用单独功能', 'owner_change_required')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    if not isAdmin then
        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    local existing = VancePay.Permissions.getEmployee(storeId, citizenid)
    if existing and existing.role == VancePay.EmployeeRoles.owner then
        return VancePay.Server.fail('不能通过员工编辑修改店主', 'cannot_edit_owner')
    end

    if not existing and not isAdmin then
        return VancePay.Server.fail('当前平板不支持手动添加员工，请改用同步功能', 'manual_employee_create_disabled')
    end

    local employeeSource = EmployeeSources.manual
    local employeeSourceKey = nil

    if existing and normalizeEmployeeSource(existing.employee_source) == EmployeeSources.publicAccountSync then
        employeeSource = EmployeeSources.publicAccountSync
        employeeSourceKey = Utils.trim(existing.employee_source_key)
    end

    local success = MySQL.insert.await([[
        INSERT INTO vancepay_employees (
            store_id,
            citizenid,
            role,
            can_refund,
            can_discount,
            employee_source,
            employee_source_key
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            role = VALUES(role),
            can_refund = VALUES(can_refund),
            can_discount = VALUES(can_discount),
            employee_source = VALUES(employee_source),
            employee_source_key = VALUES(employee_source_key),
            updated_at = CURRENT_TIMESTAMP
    ]], {
        storeId,
        citizenid,
        role,
        canRefund and 1 or 0,
        canDiscount and 1 or 0,
        employeeSource,
        employeeSourceKey,
    })

    if success == nil then
        return VancePay.Server.fail('保存员工失败', 'db_error')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'save_employee', 'employee', citizenid, {
        store_id = storeId,
        detail = {
            citizenid = citizenid,
            role = role,
            can_refund = canRefund,
            can_discount = canDiscount,
        }
    })

    local employeeSource = VancePay.Server.getSourceByCitizenId(citizenid)
    if employeeSource then
        VancePay.Server.notify(
            employeeSource,
            (existing and '你在店铺 %s 的权限已更新：%s' or '你已加入店铺 %s：%s'):format(
                store.name,
                describeEmployeeAccess(role, canRefund, canDiscount)
            ),
            existing and 'inform' or 'success'
        )
    end

    if VancePay.Terminals and VancePay.Terminals.refreshFixedTerminalCache then
        VancePay.Terminals.refreshFixedTerminalCache(true)
    end

    return Stores.listEmployees(source, storeId)
end

function Stores.syncPublicAccountEmployees(source, payload)
    Stores.ensureReady()

    payload = payload or {}

    local storeId = tonumber(payload.store_id or payload.id)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    if not Stores.isPublicAccountStore(store) then
        return VancePay.Server.fail('当前店铺未绑定产业账户，无法同步人员', 'store_not_public_account')
    end

    if not VancePay.Permissions.isAdmin(source) then
        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    local syncData, syncError, syncCode = collectPublicAccountEmployees(store)
    if not syncData then
        return VancePay.Server.fail(syncError, syncCode or 'sync_unavailable')
    end

    if next(syncData.members or {}) == nil and Utils.isBlank(syncData.job_name) then
        return VancePay.Server.fail('当前产业账户没有可识别的成员来源，无法同步', 'empty_sync_source')
    end

    local accountIdentifier = syncData.account_identifier
    local members = syncData.members or {}
    local candidateIds = {}
    local candidateSet = {}

    for citizenid, _ in pairs(members) do
        if citizenid ~= store.owner_citizenid then
            candidateIds[#candidateIds + 1] = citizenid
            candidateSet[citizenid] = true
        end
    end

    table.sort(candidateIds)

    local staleRows = MySQL.query.await([[
        SELECT *
        FROM vancepay_employees
        WHERE store_id = ?
            AND employee_source = ?
            AND employee_source_key = ?
            AND role <> 'owner'
    ]], {
        storeId,
        EmployeeSources.publicAccountSync,
        accountIdentifier,
    }) or {}

    local existingRows = {}
    if #candidateIds > 0 then
        local params = { storeId }
        for index = 1, #candidateIds do
            params[#params + 1] = candidateIds[index]
        end

        existingRows = MySQL.query.await(([[
            SELECT *
            FROM vancepay_employees
            WHERE store_id = ?
                AND citizenid IN (%s)
        ]]):format(buildPlaceholders(#candidateIds)), params) or {}
    end

    local existingByCitizenId = {}
    for index = 1, #existingRows do
        local row = decorateEmployeeRow(existingRows[index])
        existingByCitizenId[row.citizenid] = row
    end

    local upserts = {}
    local addedCitizenIds = {}
    local updatedCitizenIds = {}
    local removedCitizenIds = {}
    local unchangedCount = 0

    for index = 1, #candidateIds do
        local citizenid = candidateIds[index]
        local member = members[citizenid]
        local existing = existingByCitizenId[citizenid]
        local targetRole = member.role
        local targetCanRefund = member.can_refund
        local targetCanDiscount = member.can_discount

        if existing then
            targetRole = existing.role
            targetCanRefund = Utils.parseBool(existing.can_refund)
            targetCanDiscount = Utils.parseBool(existing.can_discount)
        end

        upserts[#upserts + 1] = {
            query = [[
                INSERT INTO vancepay_employees (
                    store_id,
                    citizenid,
                    role,
                    can_refund,
                    can_discount,
                    employee_source,
                    employee_source_key
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    role = VALUES(role),
                    can_refund = VALUES(can_refund),
                    can_discount = VALUES(can_discount),
                    employee_source = VALUES(employee_source),
                    employee_source_key = VALUES(employee_source_key),
                    updated_at = CURRENT_TIMESTAMP
            ]],
            values = {
                storeId,
                citizenid,
                targetRole,
                targetCanRefund and 1 or 0,
                targetCanDiscount and 1 or 0,
                EmployeeSources.publicAccountSync,
                accountIdentifier,
            }
        }

        if not existing then
            addedCitizenIds[#addedCitizenIds + 1] = citizenid
        else
            local changed = existing.role ~= targetRole
                or Utils.parseBool(existing.can_refund) ~= targetCanRefund
                or Utils.parseBool(existing.can_discount) ~= targetCanDiscount
                or normalizeEmployeeSource(existing.employee_source) ~= EmployeeSources.publicAccountSync
                or Utils.trim(existing.employee_source_key) ~= accountIdentifier

            if changed then
                updatedCitizenIds[#updatedCitizenIds + 1] = citizenid
            else
                unchangedCount = unchangedCount + 1
            end
        end
    end

    for index = 1, #staleRows do
        local row = decorateEmployeeRow(staleRows[index])
        if not candidateSet[row.citizenid] then
            removedCitizenIds[#removedCitizenIds + 1] = row.citizenid
        end
    end

    table.sort(removedCitizenIds)

    local statements = {}
    for index = 1, #upserts do
        statements[#statements + 1] = upserts[index]
    end

    if #removedCitizenIds > 0 then
        local values = {
            storeId,
            EmployeeSources.publicAccountSync,
            accountIdentifier,
        }

        for index = 1, #removedCitizenIds do
            values[#values + 1] = removedCitizenIds[index]
        end

        statements[#statements + 1] = {
            query = ([[
                DELETE FROM vancepay_employees
                WHERE store_id = ?
                    AND employee_source = ?
                    AND employee_source_key = ?
                    AND role <> 'owner'
                    AND citizenid IN (%s)
            ]]):format(buildPlaceholders(#removedCitizenIds)),
            values = values,
        }
    end

    if #statements > 0 then
        local success = MySQL.transaction.await(statements)
        if not success then
            return VancePay.Server.fail('同步产业账户人员失败', 'db_error')
        end
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    local addedCount = #addedCitizenIds
    local updatedCount = #updatedCitizenIds
    local removedCount = #removedCitizenIds
    local changedCount = addedCount + updatedCount + removedCount

    VancePay.Audit.log(actorCitizenId, 'sync_store_employees', 'store', storeId, {
        store_id = storeId,
        detail = {
            settlement_account_identifier = accountIdentifier,
            account_type = syncData.account and syncData.account.type or nil,
            job_name = syncData.job_name,
            added_count = addedCount,
            updated_count = updatedCount,
            removed_count = removedCount,
            unchanged_count = unchangedCount,
            synced_members = candidateIds,
            removed_members = removedCitizenIds,
        }
    })

    for index = 1, #addedCitizenIds do
        local citizenid = addedCitizenIds[index]
        local playerSource = VancePay.Server.getSourceByCitizenId(citizenid)
        local member = members[citizenid]
        local existing = existingByCitizenId[citizenid]
        local role = existing and existing.role or (member and member.role) or VancePay.EmployeeRoles.cashier
        local canRefund = existing and Utils.parseBool(existing.can_refund) or (member and member.can_refund) or false
        local canDiscount = existing and Utils.parseBool(existing.can_discount) or (member and member.can_discount) or false
        if playerSource and member then
            VancePay.Server.notify(
                playerSource,
                ('你已通过产业账户同步加入店铺 %s：%s'):format(
                    store.name,
                    describeEmployeeAccess(role, canRefund, canDiscount)
                ),
                'success'
            )
        end
    end

    for index = 1, #updatedCitizenIds do
        local citizenid = updatedCitizenIds[index]
        local playerSource = VancePay.Server.getSourceByCitizenId(citizenid)
        local member = members[citizenid]
        local existing = existingByCitizenId[citizenid]
        local role = existing and existing.role or (member and member.role) or VancePay.EmployeeRoles.cashier
        local canRefund = existing and Utils.parseBool(existing.can_refund) or (member and member.can_refund) or false
        local canDiscount = existing and Utils.parseBool(existing.can_discount) or (member and member.can_discount) or false
        if playerSource and member then
            VancePay.Server.notify(
                playerSource,
                ('你在店铺 %s 的产业同步权限已更新：%s'):format(
                    store.name,
                    describeEmployeeAccess(role, canRefund, canDiscount)
                ),
                'inform'
            )
        end
    end

    for index = 1, #removedCitizenIds do
        local citizenid = removedCitizenIds[index]
        local playerSource = VancePay.Server.getSourceByCitizenId(citizenid)
        if playerSource then
            VancePay.Server.notify(
                playerSource,
                ('你已因产业账户同步变更而从店铺 %s 移除'):format(store.name),
                'warning'
            )
        end
    end

    if changedCount > 0 and VancePay.Terminals and VancePay.Terminals.refreshFixedTerminalCache then
        VancePay.Terminals.refreshFixedTerminalCache(true)
    end

    if changedCount > 0 then
        Stores.notifyLeadership(
            storeId,
            ('店铺 %s 已同步产业账户人员：新增 %d，更新 %d，移除 %d'):format(
                store.name,
                addedCount,
                updatedCount,
                removedCount
            ),
            'inform',
            actorCitizenId
        )
    end

    local employeeResponse = Stores.listEmployees(source, storeId)
    if employeeResponse and employeeResponse.ok then
        return VancePay.Server.ok({
            employees = employeeResponse.data,
            summary = {
                added_count = addedCount,
                updated_count = updatedCount,
                removed_count = removedCount,
                unchanged_count = unchangedCount,
                settlement_account_identifier = accountIdentifier,
            }
        }, changedCount > 0
            and ('产业账户人员已同步：新增 %d，更新 %d，移除 %d'):format(addedCount, updatedCount, removedCount)
            or '产业账户人员已同步，当前无变化')
    end

    return VancePay.Server.ok({
        summary = {
            added_count = addedCount,
            updated_count = updatedCount,
            removed_count = removedCount,
            unchanged_count = unchangedCount,
            settlement_account_identifier = accountIdentifier,
        }
    }, changedCount > 0
        and ('产业账户人员已同步：新增 %d，更新 %d，移除 %d'):format(addedCount, updatedCount, removedCount)
        or '产业账户人员已同步，当前无变化')
end

function Stores.removeEmployee(source, payload)
    Stores.ensureReady()

    local storeId = tonumber(payload.store_id)
    local citizenid = Utils.trim(payload.citizenid)
    local isAdmin = VancePay.Permissions.isAdmin(source)

    if not storeId or Utils.isBlank(citizenid) then
        return VancePay.Server.fail('员工参数不完整', 'invalid_payload')
    end

    local store = Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'not_found')
    end

    if not isAdmin then
        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    local employee = VancePay.Permissions.getEmployee(storeId, citizenid)
    if not employee then
        return VancePay.Server.fail('员工不存在', 'not_found')
    end

    if employee.role == VancePay.EmployeeRoles.owner then
        return VancePay.Server.fail('不能直接移除店主', 'cannot_remove_owner')
    end

    if not isAdmin then
        return VancePay.Server.fail('当前平板不支持手动移除员工，请改用同步功能', 'manual_employee_remove_disabled')
    end

    local deleted = MySQL.update.await([[
        DELETE FROM vancepay_employees
        WHERE store_id = ? AND citizenid = ?
    ]], { storeId, citizenid })

    if not deleted or deleted < 1 then
        return VancePay.Server.fail('移除员工失败', 'db_error')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'remove_employee', 'employee', citizenid, {
        store_id = storeId,
        detail = {
            citizenid = citizenid,
            removed_role = employee.role,
        }
    })

    local employeeSource = VancePay.Server.getSourceByCitizenId(citizenid)
    if employeeSource then
        VancePay.Server.notify(employeeSource, ('你已从店铺 %s 移除'):format(store.name), 'warning')
    end

    if VancePay.Terminals and VancePay.Terminals.refreshFixedTerminalCache then
        VancePay.Terminals.refreshFixedTerminalCache(true)
    end

    return Stores.listEmployees(source, storeId)
end

lib.callback.register('vancepay:server:getStores', function(source, filters)
    return VancePay.Server.ok(Stores.listForSource(source, filters))
end)

lib.callback.register('vancepay:server:saveStore', function(source, payload)
    payload = payload or {}

    if payload.id or payload.store_id then
        return Stores.update(source, payload)
    end

    return Stores.create(source, payload)
end)

lib.callback.register('vancepay:server:saveStoreTaxSettings', function(source, payload)
    return Stores.updateTaxSettings(source, payload or {})
end)

lib.callback.register('vancepay:server:saveStoreCommissionSettings', function(source, payload)
    return Stores.updateCommissionSettings(source, payload or {})
end)

lib.callback.register('vancepay:server:saveTaxDefaults', function(source, payload)
    return Stores.updateTaxDefaults(source, payload or {})
end)

lib.callback.register('vancepay:server:archiveStore', function(source, storeId)
    return Stores.archive(source, storeId)
end)

lib.callback.register('vancepay:server:restoreStore', function(source, storeId)
    return Stores.restore(source, storeId)
end)

lib.callback.register('vancepay:server:changeStoreOwner', function(source, payload)
    return Stores.changeOwner(source, payload or {})
end)

lib.callback.register('vancepay:server:storePayout', function(source, payload)
    return Stores.payout(source, payload or {})
end)

lib.callback.register('vancepay:server:getEmployees', function(source, storeId)
    return Stores.listEmployees(source, storeId)
end)

lib.callback.register('vancepay:server:saveEmployee', function(source, payload)
    return Stores.saveEmployee(source, payload or {})
end)

lib.callback.register('vancepay:server:resolveCitizenIdByPlayerId', function(source, payload)
    return Stores.resolveCitizenIdByPlayerId(source, payload or {})
end)

lib.callback.register('vancepay:server:syncStoreEmployees', function(source, payload)
    return Stores.syncPublicAccountEmployees(source, payload or {})
end)

lib.callback.register('vancepay:server:removeEmployee', function(source, payload)
    return Stores.removeEmployee(source, payload or {})
end)
