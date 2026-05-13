VancePay.Loans = VancePay.Loans or {}

local Loans = VancePay.Loans

Loans._ready = Loans._ready or false
Loans._initializing = Loans._initializing or false

local LoanStatuses = {
    active = 'active',
    paid = 'paid',
    defaulted = 'defaulted',
    cancelled = 'cancelled',
}

local CollectionTaskStatuses = {
    open = 'open',
    claimed = 'claimed',
    completed = 'completed',
    cancelled = 'cancelled',
}

local CREATE_LOANS_TABLE = [[
    CREATE TABLE IF NOT EXISTS vancepay_loans (
        id INT AUTO_INCREMENT PRIMARY KEY,
        loan_code VARCHAR(32) NOT NULL UNIQUE,
        citizenid VARCHAR(50) NOT NULL,
        principal_amount DECIMAL(15,2) NOT NULL,
        interest_amount DECIMAL(15,2) NOT NULL,
        total_due DECIMAL(15,2) NOT NULL,
        repaid_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
        interest_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
        term_days INT NOT NULL DEFAULT 7,
        trust_score INT DEFAULT NULL,
        trust_band VARCHAR(32) DEFAULT NULL,
        status ENUM('active', 'paid', 'defaulted', 'cancelled') NOT NULL DEFAULT 'active',
        due_at TIMESTAMP NOT NULL,
        overdue_at TIMESTAMP NULL DEFAULT NULL,
        overdue_processed_at TIMESTAMP NULL DEFAULT NULL,
        ctifo_credit_event_id INT UNSIGNED DEFAULT NULL,
        repaid_at TIMESTAMP NULL DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_citizen_status (citizenid, status, due_at),
        INDEX idx_due_status (status, due_at),
        INDEX idx_overdue_processing (status, due_at, overdue_processed_at),
        INDEX idx_ctifo_credit_event (ctifo_credit_event_id)
    ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local CREATE_COLLECTION_TASKS_TABLE = [[
    CREATE TABLE IF NOT EXISTS vancepay_collection_tasks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        task_code VARCHAR(32) NOT NULL UNIQUE,
        loan_id INT NOT NULL,
        loan_code VARCHAR(32) NOT NULL,
        debtor_citizenid VARCHAR(50) NOT NULL,
        debtor_name_snapshot VARCHAR(100) DEFAULT NULL,
        debtor_phone_snapshot VARCHAR(50) DEFAULT NULL,
        principal_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
        total_due DECIMAL(15,2) NOT NULL DEFAULT 0,
        outstanding_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
        reward_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
        reward_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
        status ENUM('open', 'claimed', 'completed', 'cancelled') NOT NULL DEFAULT 'open',
        claimed_by_citizenid VARCHAR(50) DEFAULT NULL,
        claimed_by_name_snapshot VARCHAR(100) DEFAULT NULL,
        claimed_at TIMESTAMP NULL DEFAULT NULL,
        completed_at TIMESTAMP NULL DEFAULT NULL,
        reward_claimed_at TIMESTAMP NULL DEFAULT NULL,
        clue_snapshot JSON DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uk_collection_loan (loan_id),
        INDEX idx_collection_status (status, created_at),
        INDEX idx_collection_debtor (debtor_citizenid, status),
        INDEX idx_collection_claimed (claimed_by_citizenid, status, claimed_at),
        FOREIGN KEY (loan_id) REFERENCES vancepay_loans(id) ON DELETE CASCADE
    ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local DEFAULT_PRODUCTS = {
    {
        key = 'excellent',
        label = '卓越授信',
        minScore = 750,
        maxPrincipal = 50000,
        interestRate = 4.0,
        termDays = { 7, 14, 30 },
    },
    {
        key = 'stable',
        label = '稳定授信',
        minScore = 680,
        maxPrincipal = 30000,
        interestRate = 6.5,
        termDays = { 7, 14, 21 },
    },
    {
        key = 'watch',
        label = '观察授信',
        minScore = 600,
        maxPrincipal = 12000,
        interestRate = 10.0,
        termDays = { 7, 14 },
    },
}

local CTIFO_RESOURCE_FALLBACKS = {
    'VanceCtifo',
    'vance_ctifo',
}

local function getLoanConfig()
    return Config.Loans or {}
end

local function getCollectionsConfig()
    local config = getLoanConfig().Collections
    return type(config) == 'table' and config or {}
end

local function shouldEnable()
    return getLoanConfig().enabled ~= false
end

local function shouldEnableCollections()
    return shouldEnable() and getCollectionsConfig().enabled ~= false
end

local function shouldRunSchemaMigrations()
    local databaseConfig = Config.Database or {}
    return databaseConfig.autoMigrate == true
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

local function fetchColumnExists(tableName, columnName)
    return MySQL.single.await([[
        SELECT 1 AS present
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = ?
            AND COLUMN_NAME = ?
        LIMIT 1
    ]], { tableName, columnName })
end

local function fetchIndexExists(tableName, indexName)
    return MySQL.single.await([[
        SELECT 1 AS present
        FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = ?
            AND INDEX_NAME = ?
        LIMIT 1
    ]], { tableName, indexName })
end

local function ensureColumn(tableName, columnName, definition)
    if fetchColumnExists(tableName, columnName) then
        return
    end

    MySQL.query.await(('ALTER TABLE %s ADD COLUMN %s %s'):format(tableName, columnName, definition))
end

local function ensureIndex(tableName, indexName, definition)
    if fetchIndexExists(tableName, indexName) then
        return
    end

    MySQL.query.await(('ALTER TABLE %s ADD INDEX %s %s'):format(tableName, indexName, definition))
end

local function collectionRewardColumnsAvailable()
    return fetchColumnExists('vancepay_collection_tasks', 'reward_rate')
        and fetchColumnExists('vancepay_collection_tasks', 'reward_amount')
        and fetchColumnExists('vancepay_collection_tasks', 'reward_claimed_at')
end

local function ensureSchema()
    MySQL.query.await(CREATE_LOANS_TABLE)
    ensureColumn('vancepay_loans', 'overdue_at', 'TIMESTAMP NULL DEFAULT NULL AFTER due_at')
    ensureColumn('vancepay_loans', 'overdue_processed_at', 'TIMESTAMP NULL DEFAULT NULL AFTER overdue_at')
    ensureColumn('vancepay_loans', 'ctifo_credit_event_id', 'INT UNSIGNED DEFAULT NULL AFTER overdue_processed_at')
    ensureIndex('vancepay_loans', 'idx_overdue_processing', '(status, due_at, overdue_processed_at)')
    ensureIndex('vancepay_loans', 'idx_ctifo_credit_event', '(ctifo_credit_event_id)')

    MySQL.query.await(CREATE_COLLECTION_TASKS_TABLE)
    ensureColumn('vancepay_collection_tasks', 'reward_rate', 'DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER outstanding_amount')
    ensureColumn('vancepay_collection_tasks', 'reward_amount', 'DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER reward_rate')
    ensureColumn('vancepay_collection_tasks', 'reward_claimed_at', 'TIMESTAMP NULL DEFAULT NULL AFTER completed_at')
    ensureIndex('vancepay_collection_tasks', 'idx_collection_status', '(status, created_at)')
    ensureIndex('vancepay_collection_tasks', 'idx_collection_debtor', '(debtor_citizenid, status)')
    ensureIndex('vancepay_collection_tasks', 'idx_collection_claimed', '(claimed_by_citizenid, status, claimed_at)')
end

local function addCtifoResourceName(resourceNames, seen, value)
    if type(value) ~= 'string' then
        return
    end

    value = Utils.trim(value)
    if Utils.isBlank(value) then
        return
    end

    local key = tostring(value):lower()
    if seen[key] then
        return
    end

    seen[key] = true
    resourceNames[#resourceNames + 1] = value
end

local function addCtifoResourceList(resourceNames, seen, values)
    if type(values) ~= 'table' then
        addCtifoResourceName(resourceNames, seen, values)
        return
    end

    for index = 1, #values do
        addCtifoResourceName(resourceNames, seen, values[index])
    end
end

local function getCtifoResourceNames()
    local resourceNames = {}
    local seen = {}
    local config = getLoanConfig()

    addCtifoResourceList(resourceNames, seen, config.ctifoResource)
    addCtifoResourceList(resourceNames, seen, config.ctifoResourceAliases)

    for index = 1, #CTIFO_RESOURCE_FALLBACKS do
        addCtifoResourceName(resourceNames, seen, CTIFO_RESOURCE_FALLBACKS[index])
    end

    return resourceNames
end

local function resolveCtifoResourceName()
    local resourceNames = getCtifoResourceNames()

    for index = 1, #resourceNames do
        local resourceName = resourceNames[index]
        if GetResourceState(resourceName) == 'started' then
            return resourceName, resourceNames
        end
    end

    return nil, resourceNames
end

local function isCtifoResourceName(resourceName)
    resourceName = Utils.trim(resourceName)
    if Utils.isBlank(resourceName) then
        return false
    end

    local resourceNames = getCtifoResourceNames()
    for index = 1, #resourceNames do
        if resourceNames[index] == resourceName then
            return true
        end
    end

    return false
end

local function getMinAmount()
    return Utils.roundCurrency(math.max(tonumber(getLoanConfig().minAmount) or 500, 1))
end

local function getMaxActiveLoans()
    return math.max(math.floor(tonumber(getLoanConfig().maxActiveLoans) or 2), 1)
end

local function getHistoryLimit()
    return math.min(math.max(math.floor(tonumber(getLoanConfig().historyLimit) or 12), 1), 50)
end

local function getOverdueSweepIntervalMs()
    return math.max(math.floor(tonumber(getLoanConfig().overdueSweepIntervalMs) or 300000), 30000)
end

local function getOverdueCreditImpact()
    local impact = math.floor(tonumber(getLoanConfig().overdueCreditImpact) or -60)
    if impact > 0 then
        impact = -impact
    end

    return impact
end

local function getOverduePaidCreditImpact()
    local impact = math.floor(tonumber(getLoanConfig().overduePaidCreditImpact) or -15)
    if impact > 0 then
        impact = -impact
    end

    return impact
end

local function getCollectionTabletItem()
    local itemName = Utils.trim(getCollectionsConfig().tabletItem)
    if Utils.isBlank(itemName) then
        itemName = 'vp_debt_tablet'
    end

    return itemName
end

local function getCollectionTaskLimit()
    return math.min(math.max(math.floor(tonumber(getCollectionsConfig().taskLimit) or 30), 1), 100)
end

local function getCollectionClaimLimit()
    return math.max(math.floor(tonumber(getCollectionsConfig().claimLimitPerCollector) or 1), 1)
end

local function getCollectionRewardRate()
    return Utils.roundCurrency(math.min(math.max(tonumber(getCollectionsConfig().rewardRate) or 5, 0), 100))
end

local function getCollectionMapAreaConfig()
    local config = getCollectionsConfig().mapArea
    if type(config) ~= 'table' then
        config = {}
    end

    local radius = math.min(math.max(tonumber(config.radius or config.radiusMeters) or 350.0, 50.0), 3000.0)
    local centerJitter = tonumber(config.centerJitter or config.centerJitterMeters)
    if centerJitter == nil then
        centerJitter = math.min(radius * 0.35, 150.0)
    end
    centerJitter = math.min(math.max(centerJitter, 0.0), radius * 0.75)

    return {
        enabled = config.enabled ~= false,
        radius = radius,
        center_jitter = centerJitter,
        color = math.min(math.max(math.floor(tonumber(config.color or config.blipColor) or 5), 0), 85),
        alpha = math.min(math.max(math.floor(tonumber(config.alpha or config.radiusAlpha) or 90), 20), 180),
        center_sprite = math.max(math.floor(tonumber(config.centerSprite or config.blipSprite) or 161), 1),
        center_scale = math.min(math.max(tonumber(config.centerScale or config.blipScale) or 0.75, 0.4), 1.4),
        show_center = config.showCenterBlip ~= false and config.show_center ~= false,
        route = config.route == true,
    }
end

local function calculateCollectionRewardAmount(task, rewardRate)
    if not task then
        return 0
    end

    rewardRate = Utils.roundCurrency(rewardRate or getCollectionRewardRate())
    if rewardRate <= 0 then
        return 0
    end

    local baseAmount = Utils.roundCurrency(task.outstanding_amount or 0)
    if baseAmount <= 0 then
        baseAmount = Utils.roundCurrency(task.loan_repaid_amount or task.repaid_amount or 0)
    end

    if baseAmount <= 0 then
        baseAmount = Utils.roundCurrency(task.loan_total_due or task.total_due or 0)
    end

    return Utils.roundCurrency(math.max(baseAmount * (rewardRate / 100), 0))
end

local function getConfigMaxAmount()
    return Utils.roundCurrency(math.max(tonumber(getLoanConfig().maxAmount) or 50000, getMinAmount()))
end

local function buildUnavailableState(reason, code)
    return {
        enabled = shouldEnable(),
        schema_available = code ~= 'db_schema_outdated',
        trust = {
            available = false,
            reason = reason,
            code = code,
        },
        offer = {
            eligible = false,
            reason = reason,
            min_amount = getMinAmount(),
            available_amount = 0,
            max_principal = 0,
            interest_rate = 0,
            term_days = {},
        },
        summary = {
            active_count = 0,
            outstanding_amount = 0,
            active_principal_amount = 0,
            next_due_at = nil,
            next_due_in = 0,
            overdue_count = 0,
            lifetime_principal_amount = 0,
            lifetime_interest_amount = 0,
        },
        items = {},
    }
end

local function normalizeTermDays(rawTerms)
    local values = {}
    local seen = {}

    if type(rawTerms) ~= 'table' then
        rawTerms = { tonumber(getLoanConfig().defaultTermDays) or 7 }
    end

    for index = 1, #rawTerms do
        local term = math.floor(tonumber(rawTerms[index]) or 0)
        if term > 0 and term <= 365 and not seen[term] then
            values[#values + 1] = term
            seen[term] = true
        end
    end

    if #values == 0 then
        values[1] = math.max(math.floor(tonumber(getLoanConfig().defaultTermDays) or 7), 1)
    end

    table.sort(values)
    return values
end

local function normalizeProduct(product)
    product = type(product) == 'table' and product or {}
    local maxPrincipal = Utils.roundCurrency(math.min(
        math.max(tonumber(product.maxPrincipal or product.max_principal) or 0, 0),
        getConfigMaxAmount()
    ))

    return {
        key = Utils.trim(product.key) or 'loan',
        label = Utils.trim(product.label) or '授信额度',
        min_score = math.floor(tonumber(product.minScore or product.min_score) or 0),
        max_principal = maxPrincipal,
        interest_rate = Utils.roundCurrency(tonumber(product.interestRate or product.interest_rate) or 0),
        term_days = normalizeTermDays(product.termDays or product.term_days or product.terms),
    }
end

local function getLoanProducts()
    local configured = getLoanConfig().products
    if type(configured) ~= 'table' or #configured == 0 then
        configured = DEFAULT_PRODUCTS
    end

    local products = {}
    for index = 1, #configured do
        local product = normalizeProduct(configured[index])
        if product.max_principal >= getMinAmount() then
            products[#products + 1] = product
        end
    end

    table.sort(products, function(a, b)
        return a.min_score > b.min_score
    end)

    return products
end

local function resolveProduct(score)
    local products = getLoanProducts()
    for index = 1, #products do
        if score >= products[index].min_score then
            return products[index]
        end
    end

    return nil
end

local function termAllowed(termDays, allowedTerms)
    for index = 1, #allowedTerms do
        if tonumber(allowedTerms[index]) == tonumber(termDays) then
            return true
        end
    end

    return false
end

local function calculateInterest(amount, interestRate)
    return Utils.roundCurrency(Utils.roundCurrency(amount) * ((tonumber(interestRate) or 0) / 100))
end

local function getCurrentUnixTime(row)
    if type(row) == 'table' then
        local databaseUnixTime = tonumber(row.current_unix_time)
        if databaseUnixTime then
            return databaseUnixTime
        end
    end

    return os.time()
end

local function normalizeLoan(row)
    if not row then
        return nil
    end

    row = Utils.normalizeDbRow(row)
    row.id = tonumber(row.id)
    row.principal_amount = Utils.roundCurrency(row.principal_amount or 0)
    row.interest_amount = Utils.roundCurrency(row.interest_amount or 0)
    row.total_due = Utils.roundCurrency(row.total_due or 0)
    row.repaid_amount = Utils.roundCurrency(row.repaid_amount or 0)
    row.outstanding_amount = Utils.roundCurrency(math.max(row.total_due - row.repaid_amount, 0))
    row.interest_rate = Utils.roundCurrency(row.interest_rate or 0)
    row.term_days = math.floor(tonumber(row.term_days) or 0)
    row.trust_score = tonumber(row.trust_score)
    row.trust_band = Utils.trim(row.trust_band)
    row.status = Utils.trim(row.status)
    row.ctifo_credit_event_id = tonumber(row.ctifo_credit_event_id)
    row.due_at_unix = tonumber(row.due_at_unix)
    row.current_unix_time = tonumber(row.current_unix_time)

    local currentUnixTime = getCurrentUnixTime(row)
    local dueAtTimestamp = row.due_at_unix or Utils.parseSqlDateTime(row.due_at)
    row.due_in = math.max(0, (dueAtTimestamp or currentUnixTime) - currentUnixTime)
    row.is_overdue = row.status == LoanStatuses.active and dueAtTimestamp ~= nil and dueAtTimestamp <= currentUnixTime

    return row
end

local function normalizeSummary(row)
    row = row or {}
    row.next_due_unix = tonumber(row.next_due_unix)
    row.current_unix_time = tonumber(row.current_unix_time)
    local currentUnixTime = getCurrentUnixTime(row)
    local nextDueTimestamp = row.next_due_unix or Utils.parseSqlDateTime(row.next_due_at)

    return {
        active_count = tonumber(row.active_count) or 0,
        active_principal_amount = Utils.roundCurrency(row.active_principal_amount or 0),
        outstanding_amount = Utils.roundCurrency(row.outstanding_amount or 0),
        next_due_at = row.next_due_at,
        next_due_in = math.max(0, (nextDueTimestamp or currentUnixTime) - currentUnixTime),
        overdue_count = tonumber(row.overdue_count) or 0,
        lifetime_principal_amount = Utils.roundCurrency(row.lifetime_principal_amount or 0),
        lifetime_interest_amount = Utils.roundCurrency(row.lifetime_interest_amount or 0),
    }
end

local function getEmptySummary()
    return normalizeSummary({})
end

function Loans.ensureReady()
    if Loans._ready then
        return true
    end

    while Loans._initializing do
        Wait(50)
        if Loans._ready then
            return true
        end
    end

    Loans._initializing = true
    local ok, err = pcall(function()
        if shouldRunSchemaMigrations() then
            ensureSchema()
        end
    end)
    Loans._initializing = false

    if not ok then
        error(err)
    end

    Loans._ready = true
    return true
end

function Loans.ensureSchemaAvailable()
    Loans.ensureReady()

    if fetchTableExists('vancepay_loans') then
        return true
    end

    return false, '数据库结构未升级到最新版本，请先执行 sql/migrate_to_latest.sql'
end

function Loans.ensureCollectionsSchemaAvailable()
    local schemaAvailable, schemaError = Loans.ensureSchemaAvailable()
    if not schemaAvailable then
        return false, schemaError
    end

    if not fetchColumnExists('vancepay_loans', 'overdue_at')
        or not fetchColumnExists('vancepay_loans', 'overdue_processed_at')
        or not fetchColumnExists('vancepay_loans', 'ctifo_credit_event_id') then
        return false, '贷款逾期字段缺失，请先执行 sql/migrate_to_latest.sql'
    end

    if not fetchTableExists('vancepay_collection_tasks') then
        return false, '追债任务数据库结构未升级到最新版本，请先执行 sql/migrate_to_latest.sql'
    end

    if not collectionRewardColumnsAvailable() then
        return false, '追债任务奖励字段缺失，请先执行 sql/migrate_to_latest.sql'
    end

    return true
end

function Loans.getTrustScore(citizenid)
    citizenid = Utils.trim(citizenid)
    if Utils.isBlank(citizenid) then
        return nil, 'missing_citizenid'
    end

    local resourceName, checkedResourceNames = resolveCtifoResourceName()
    if not resourceName then
        Utils.debug('VanceCtifo resource not started; checked', table.concat(checkedResourceNames or {}, ', '))
        return nil, 'ctifo_unavailable'
    end

    local api = exports[resourceName]
    if not api or type(api.GetTrustScore) ~= 'function' then
        return nil, 'ctifo_export_missing'
    end

    local ok, scoreData = pcall(api.GetTrustScore, api, citizenid)
    if not ok then
        Utils.debug('VanceCtifo trust score export failed', scoreData)
        return nil, 'ctifo_error'
    end

    if type(scoreData) ~= 'table' or tonumber(scoreData.score) == nil then
        return nil, 'trust_profile_missing'
    end

    return {
        available = true,
        score = tonumber(scoreData.score),
        band = Utils.trim(scoreData.band),
        outlook = Utils.trim(scoreData.outlook),
        resource = resourceName,
        range = scoreData.range or {},
        factors = type(scoreData.factors) == 'table' and scoreData.factors or {},
        risk_flags = type(scoreData.riskFlags) == 'table' and scoreData.riskFlags or {},
        summary = type(scoreData.summary) == 'table' and scoreData.summary or {},
        next_actions = type(scoreData.nextActions) == 'table' and scoreData.nextActions or {},
    }
end

function Loans.getSummaryByCitizenId(citizenid)
    Loans.ensureReady()

    citizenid = Utils.trim(citizenid)
    if Utils.isBlank(citizenid) or not fetchTableExists('vancepay_loans') then
        return getEmptySummary()
    end

    local row = MySQL.single.await([[
        SELECT
            UNIX_TIMESTAMP(CURRENT_TIMESTAMP) AS current_unix_time,
            COALESCE(SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END), 0) AS active_count,
            COALESCE(SUM(CASE WHEN status = 'active' THEN principal_amount ELSE 0 END), 0) AS active_principal_amount,
            COALESCE(SUM(CASE WHEN status = 'active' THEN GREATEST(total_due - repaid_amount, 0) ELSE 0 END), 0) AS outstanding_amount,
            MIN(CASE WHEN status = 'active' THEN due_at ELSE NULL END) AS next_due_at,
            UNIX_TIMESTAMP(MIN(CASE WHEN status = 'active' THEN due_at ELSE NULL END)) AS next_due_unix,
            COALESCE(SUM(CASE WHEN status = 'active' AND due_at <= CURRENT_TIMESTAMP THEN 1 ELSE 0 END), 0) AS overdue_count,
            COALESCE(SUM(CASE WHEN status <> 'cancelled' THEN principal_amount ELSE 0 END), 0) AS lifetime_principal_amount,
            COALESCE(SUM(CASE WHEN status = 'paid' THEN interest_amount ELSE 0 END), 0) AS lifetime_interest_amount
        FROM vancepay_loans
        WHERE citizenid = ?
    ]], { citizenid })

    return normalizeSummary(row)
end

function Loans.listByCitizenId(citizenid, limit)
    Loans.ensureReady()

    citizenid = Utils.trim(citizenid)
    if Utils.isBlank(citizenid) or not fetchTableExists('vancepay_loans') then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT
            *,
            UNIX_TIMESTAMP(CURRENT_TIMESTAMP) AS current_unix_time,
            UNIX_TIMESTAMP(due_at) AS due_at_unix
        FROM vancepay_loans
        WHERE citizenid = ?
        ORDER BY
            FIELD(status, 'active', 'defaulted', 'paid', 'cancelled'),
            CASE WHEN status = 'active' THEN due_at ELSE created_at END ASC,
            id DESC
        LIMIT ?
    ]], { citizenid, math.min(math.max(tonumber(limit) or getHistoryLimit(), 1), 50) }) or {}

    for index = 1, #rows do
        rows[index] = normalizeLoan(rows[index])
    end

    return rows
end

function Loans.buildOffer(citizenid, trustData, summary)
    summary = summary or Loans.getSummaryByCitizenId(citizenid)

    local minAmount = getMinAmount()
    local baseOffer = {
        eligible = false,
        reason = '暂时无法评估授信',
        min_amount = minAmount,
        available_amount = 0,
        max_principal = 0,
        interest_rate = 0,
        term_days = {},
        default_term_days = math.max(math.floor(tonumber(getLoanConfig().defaultTermDays) or 7), 1),
        max_active_loans = getMaxActiveLoans(),
        active_count = summary.active_count or 0,
    }

    if not trustData or trustData.available ~= true or not trustData.score then
        baseOffer.reason = trustData and trustData.reason or 'VanceCtifo 暂不可用'
        return baseOffer
    end

    local product = resolveProduct(tonumber(trustData.score) or 0)
    if not product then
        baseOffer.reason = '信誉分未达到贷款准入线'
        return baseOffer
    end

    local usedPrincipalAmount = Utils.roundCurrency(summary.active_principal_amount or 0)
    local availableAmount = Utils.roundCurrency(math.max(product.max_principal - usedPrincipalAmount, 0))

    baseOffer.product_key = product.key
    baseOffer.product_label = product.label
    baseOffer.max_principal = product.max_principal
    baseOffer.used_principal_amount = usedPrincipalAmount
    baseOffer.available_amount = availableAmount
    baseOffer.interest_rate = product.interest_rate
    baseOffer.term_days = product.term_days
    baseOffer.default_term_days = product.term_days[1] or baseOffer.default_term_days

    if (summary.active_count or 0) >= getMaxActiveLoans() then
        baseOffer.reason = '当前未结清贷款数量已达上限'
        return baseOffer
    end

    if availableAmount < minAmount then
        baseOffer.reason = '当前未还贷款本金占用额度，暂无可借额度'
        return baseOffer
    end

    baseOffer.eligible = true
    baseOffer.reason = '可申请贷款'
    return baseOffer
end

function Loans.getCustomerState(citizenid)
    if not shouldEnable() then
        return buildUnavailableState('贷款功能未启用', 'disabled')
    end

    local schemaAvailable, schemaError = Loans.ensureSchemaAvailable()
    if not schemaAvailable then
        return buildUnavailableState(schemaError, 'db_schema_outdated')
    end

    local summary = Loans.getSummaryByCitizenId(citizenid)
    local trustData, trustError = Loans.getTrustScore(citizenid)
    if not trustData then
        local messages = {
            ctifo_unavailable = 'VanceCtifo 未启动，暂时无法读取信誉分',
            ctifo_export_missing = 'VanceCtifo 未暴露信誉分接口',
            ctifo_error = '信誉分读取失败',
            trust_profile_missing = 'VanceCtifo 中还没有你的信誉档案',
            missing_citizenid = '未找到玩家身份',
        }

        trustData = {
            available = false,
            code = trustError,
            reason = messages[trustError] or '暂时无法读取信誉分',
        }
    end

    return {
        enabled = true,
        schema_available = true,
        trust = trustData,
        offer = Loans.buildOffer(citizenid, trustData, summary),
        summary = summary,
        items = Loans.listByCitizenId(citizenid, getHistoryLimit()),
    }
end

local function refreshClientState(citizenid, reason)
    local target = VancePay.Server and VancePay.Server.getSourceByCitizenId
        and VancePay.Server.getSourceByCitizenId(citizenid)
        or nil

    if target and target > 0 then
        TriggerClientEvent(VancePay.Events.client.refreshLBPhoneState, target, {
            reason = reason or 'loan_update',
        })
    end
end

local function refreshAllClientStates(reason)
    if not VancePay.Events or not VancePay.Events.client or not VancePay.Events.client.refreshLBPhoneState then
        return
    end

    TriggerClientEvent(VancePay.Events.client.refreshLBPhoneState, -1, {
        reason = reason or 'loan_update',
    })
end

local function decodeJsonField(value, fallback)
    if value == nil or value == '' then
        return fallback
    end

    if type(value) ~= 'string' then
        return value
    end

    local ok, decoded = pcall(json.decode, value)
    if ok then
        return decoded
    end

    return fallback
end

local function callCtifoExport(method, ...)
    local resourceName, checkedResourceNames = resolveCtifoResourceName()
    if not resourceName then
        return false, nil, 'ctifo_unavailable', checkedResourceNames
    end

    local api = exports[resourceName]
    if not api or type(api[method]) ~= 'function' then
        return false, nil, 'ctifo_export_missing', resourceName
    end

    local ok, result, extra = pcall(api[method], api, ...)
    if not ok then
        Utils.debug('VanceCtifo export failed', method, result)
        return false, nil, 'ctifo_error', result
    end

    return true, result, extra, resourceName
end

local function fetchCtifoProfile(citizenid)
    citizenid = Utils.trim(citizenid)
    if Utils.isBlank(citizenid) then
        return nil
    end

    local resourceName = resolveCtifoResourceName()
    if not resourceName then
        return nil
    end

    local api = exports[resourceName]
    if not api or type(api.GetProfileSnapshot) ~= 'function' then
        return nil
    end

    local ok, snapshot = pcall(api.GetProfileSnapshot, citizenid)
    if not ok or type(snapshot) ~= 'table' then
        ok, snapshot = pcall(api.GetProfileSnapshot, api, citizenid)
    end

    if not ok or type(snapshot) ~= 'table' then
        return nil
    end

    local profile = type(snapshot.profile) == 'table' and snapshot.profile or snapshot
    local name = Utils.trim(profile.fullName or profile.full_name)
    local phone = Utils.trim(profile.phone)

    return {
        citizenid = profile.citizenid or citizenid,
        name = name,
        phone = phone,
        profile = profile,
    }
end

local function getProfileName(profile)
    if type(profile) ~= 'table' then
        return nil
    end

    local name = Utils.trim(profile.name or profile.fullName or profile.full_name)
    if not Utils.isBlank(name) then
        return name
    end

    name = Utils.trim(('%s %s'):format(profile.firstName or profile.first_name or '', profile.lastName or profile.last_name or ''))
    if not Utils.isBlank(name) then
        return name
    end

    return nil
end

local function normalizeCollectionTask(row)
    if not row then
        return nil
    end

    row = Utils.normalizeDbRow(row)
    row.id = tonumber(row.id)
    row.loan_id = tonumber(row.loan_id)
    row.principal_amount = Utils.roundCurrency(row.principal_amount or 0)
    row.total_due = Utils.roundCurrency(row.total_due or 0)
    row.outstanding_amount = Utils.roundCurrency(row.outstanding_amount or 0)
    row.reward_rate = Utils.roundCurrency(row.reward_rate or 0)
    row.reward_amount = Utils.roundCurrency(row.reward_amount or 0)
    row.status = Utils.trim(row.status)
    row.clue_snapshot = decodeJsonField(row.clue_snapshot, nil)

    if row.loan_total_due then
        row.loan_total_due = Utils.roundCurrency(row.loan_total_due)
    end

    if row.loan_repaid_amount then
        row.loan_repaid_amount = Utils.roundCurrency(row.loan_repaid_amount)
    end

    if row.status == CollectionTaskStatuses.completed
        and not Utils.isBlank(row.claimed_by_citizenid)
        and row.reward_amount <= 0 then
        local rewardRate = row.reward_rate > 0 and row.reward_rate or getCollectionRewardRate()
        row.reward_rate = rewardRate
        row.reward_amount = calculateCollectionRewardAmount(row, rewardRate)
    end

    row.reward_claimed = not Utils.isBlank(row.reward_claimed_at)

    return row
end

local function sourceHasCollectionTablet(source)
    local itemName = getCollectionTabletItem()
    if Utils.isBlank(itemName) then
        return false
    end

    local ok, count = pcall(function()
        return exports.ox_inventory:Search(source, 'count', itemName)
    end)

    return ok and (tonumber(count) or 0) > 0
end

local function requireCollectionAccess(source)
    if not shouldEnableCollections() then
        return nil, VancePay.Server.fail('追债任务未启用', 'disabled')
    end

    local schemaAvailable, schemaError = Loans.ensureCollectionsSchemaAvailable()
    if not schemaAvailable then
        return nil, VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) then
        return nil, VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    if not sourceHasCollectionTablet(source) then
        return nil, VancePay.Server.fail('需要携带追债平板才能查看任务', 'missing_tablet')
    end

    local record = VancePay.Server.getPlayerRecord(source)
    return {
        source = source,
        citizenid = citizenid,
        name = record and record.name or citizenid,
    }
end

local function getSourceCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return nil
    end

    local ok, coords = pcall(GetEntityCoords, ped)
    if not ok or not coords then
        return nil
    end

    return {
        x = tonumber(coords.x) or tonumber(coords[1]) or 0.0,
        y = tonumber(coords.y) or tonumber(coords[2]) or 0.0,
        z = tonumber(coords.z) or tonumber(coords[3]) or 0.0,
    }
end

local function getDistanceBetweenSources(source, targetSource)
    local sourceCoords = getSourceCoords(source)
    local targetCoords = getSourceCoords(targetSource)
    if not sourceCoords or not targetCoords then
        return nil
    end

    local dx = sourceCoords.x - targetCoords.x
    local dy = sourceCoords.y - targetCoords.y
    local dz = sourceCoords.z - targetCoords.z
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function getDistanceBand(distance)
    distance = tonumber(distance)
    if not distance then
        return '未知距离'
    end

    if distance <= 250 then
        return '极近'
    end

    if distance <= 750 then
        return '附近'
    end

    if distance <= 2000 then
        return '同城区'
    end

    if distance <= 5000 then
        return '较远'
    end

    return '远距离'
end

local function normalizeCollectionLocationCoords(location)
    if type(location) ~= 'table' or type(location.coords) ~= 'table' then
        return nil
    end

    local coords = location.coords
    local x = tonumber(coords.x) or tonumber(coords[1])
    local y = tonumber(coords.y) or tonumber(coords[2])
    if not x or not y then
        return nil
    end

    return {
        x = x,
        y = y,
        z = tonumber(coords.z) or tonumber(coords[3]) or 0.0,
    }
end

local function roundMapCoord(value)
    value = tonumber(value) or 0.0
    if value >= 0 then
        return math.floor(value * 10 + 0.5) / 10
    end

    return math.ceil(value * 10 - 0.5) / 10
end

local function buildCollectionSearchArea(coords)
    local mapConfig = getCollectionMapAreaConfig()
    if not mapConfig.enabled or type(coords) ~= 'table' then
        return nil
    end

    local centerX = coords.x
    local centerY = coords.y
    local centerZ = coords.z
    if mapConfig.center_jitter > 0 then
        local angle = math.random() * math.pi * 2
        local offset = math.sqrt(math.random()) * mapConfig.center_jitter
        centerX = centerX + math.cos(angle) * offset
        centerY = centerY + math.sin(angle) * offset
    end

    local radius = math.floor(mapConfig.radius + 0.5)
    return {
        x = roundMapCoord(centerX),
        y = roundMapCoord(centerY),
        z = roundMapCoord(centerZ),
        radius = radius,
        label = ('追债搜索范围（%dm）'):format(radius),
        color = mapConfig.color,
        alpha = mapConfig.alpha,
        center_sprite = mapConfig.center_sprite,
        center_scale = mapConfig.center_scale,
        show_center = mapConfig.show_center,
        route = mapConfig.route,
    }
end

local function buildCollectionClue(source, task)
    task = normalizeCollectionTask(task)
    if not task then
        return nil
    end

    local profile = fetchCtifoProfile(task.debtor_citizenid) or {}
    local debtorSource = VancePay.Server.getSourceByCitizenId(task.debtor_citizenid)
    local debtorRecord = debtorSource and VancePay.Server.getPlayerRecord(debtorSource) or nil
    local debtorName = debtorRecord and debtorRecord.name
        or getProfileName(profile)
        or task.debtor_name_snapshot
        or task.debtor_citizenid
    local debtorPhone = profile.phone or task.debtor_phone_snapshot

    local clue = {
        mode = Utils.trim(getCollectionsConfig().clueMode) or 'fuzzy',
        generated_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        online = debtorSource ~= nil,
        debtor = {
            citizenid = task.debtor_citizenid,
            name = debtorName,
            phone = debtorPhone,
        },
        loan = {
            loan_code = task.loan_code,
            total_due = task.total_due,
            outstanding_amount = task.outstanding_amount,
            due_at = task.due_at,
        },
    }

    if not debtorSource then
        clue.status = 'current_offline'
        clue.notice = '当前离线'
        return clue
    end

    local location = VancePay.Server.safeClientCallback('vancepay:client:getCollectionLocation', debtorSource) or {}
    local distance = getDistanceBetweenSources(source, debtorSource)
    local searchArea = buildCollectionSearchArea(normalizeCollectionLocationCoords(location))

    clue.status = 'online'
    clue.location = {
        zone = Utils.trim(location.zone) or '未知区域',
        street = Utils.trim(location.street) or '未知街区',
        cross_street = Utils.trim(location.cross_street),
        search_area = searchArea,
    }
    clue.distance = {
        meters = distance and math.floor(distance + 0.5) or nil,
        band = getDistanceBand(distance),
    }

    return clue
end

local function updateTaskClueSnapshot(source, task)
    local clue = buildCollectionClue(source, task)
    if not clue then
        return nil
    end

    MySQL.update.await([[
        UPDATE vancepay_collection_tasks
        SET clue_snapshot = ?
        WHERE id = ?
    ]], { json.encode(clue), task.id })

    return clue
end

local markCtifoOverdueEventPaid

local function completeCollectionTasksForPaidLoans()
    if not fetchTableExists('vancepay_collection_tasks') then
        return 0
    end

    local paidRows = MySQL.query.await([[
        SELECT l.*
        FROM vancepay_collection_tasks t
        INNER JOIN vancepay_loans l ON l.id = t.loan_id
        WHERE t.status IN ('open', 'claimed')
            AND l.status = 'paid'
            AND (
                l.ctifo_credit_event_id IS NOT NULL
                OR l.overdue_at IS NOT NULL
                OR l.overdue_processed_at IS NOT NULL
            )
    ]], {}) or {}

    for index = 1, #paidRows do
        local loan = normalizeLoan(paidRows[index])
        local event, eventErr = markCtifoOverdueEventPaid(loan, loan.repaid_amount)
        local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)

        if eventId and not loan.ctifo_credit_event_id then
            MySQL.update.await([[
                UPDATE vancepay_loans
                SET ctifo_credit_event_id = ?
                WHERE id = ?
                    AND ctifo_credit_event_id IS NULL
            ]], { eventId, loan.id })
        elseif not eventId then
            Utils.debug('VanceCtifo overdue credit event paid reconciliation failed', loan.loan_code, eventErr)
        end
    end

    local rewardRate = getCollectionRewardRate()
    return MySQL.update.await([[
        UPDATE vancepay_collection_tasks t
        INNER JOIN vancepay_loans l ON l.id = t.loan_id
        SET t.status = 'completed',
            t.completed_at = COALESCE(l.repaid_at, CURRENT_TIMESTAMP),
            t.reward_rate = CASE
                WHEN t.claimed_by_citizenid IS NOT NULL AND t.reward_rate <= 0 THEN ?
                ELSE t.reward_rate
            END,
            t.reward_amount = CASE
                WHEN t.claimed_by_citizenid IS NOT NULL AND t.reward_amount <= 0 THEN
                    ROUND((CASE WHEN t.outstanding_amount > 0 THEN t.outstanding_amount ELSE GREATEST(l.repaid_amount, l.total_due, 0) END) * ? / 100, 2)
                ELSE t.reward_amount
            END,
            t.outstanding_amount = 0
        WHERE t.status IN ('open', 'claimed')
            AND l.status = 'paid'
    ]], { rewardRate, rewardRate }) or 0
end

local function fetchCollectionTaskById(taskId)
    local row = MySQL.single.await([[
        SELECT
            t.*,
            l.due_at,
            l.status AS loan_status,
            l.repaid_amount AS loan_repaid_amount,
            l.total_due AS loan_total_due
        FROM vancepay_collection_tasks t
        INNER JOIN vancepay_loans l ON l.id = t.loan_id
        WHERE t.id = ?
        LIMIT 1
    ]], { tonumber(taskId) })

    return normalizeCollectionTask(row)
end

function Loans.getCollectionState(source)
    local actor, accessError = requireCollectionAccess(source)
    if not actor then
        return accessError
    end

    completeCollectionTasksForPaidLoans()

    local limit = getCollectionTaskLimit()
    local availableRows = MySQL.query.await([[
        SELECT
            t.*,
            l.due_at,
            l.status AS loan_status,
            l.repaid_amount AS loan_repaid_amount,
            l.total_due AS loan_total_due
        FROM vancepay_collection_tasks t
        INNER JOIN vancepay_loans l ON l.id = t.loan_id
        WHERE t.status = 'open'
            AND l.status = 'active'
        ORDER BY l.due_at ASC, t.id ASC
        LIMIT ?
    ]], { limit }) or {}

    local myRows = MySQL.query.await([[
        SELECT
            t.*,
            l.due_at,
            l.status AS loan_status,
            l.repaid_amount AS loan_repaid_amount,
            l.total_due AS loan_total_due
        FROM vancepay_collection_tasks t
        INNER JOIN vancepay_loans l ON l.id = t.loan_id
        WHERE t.claimed_by_citizenid = ?
            AND (
                (t.status = 'claimed' AND l.status = 'active')
                OR t.status = 'completed'
            )
        ORDER BY FIELD(t.status, 'claimed', 'completed'),
            COALESCE(t.completed_at, t.claimed_at, t.created_at) DESC,
            t.id DESC
        LIMIT ?
    ]], { actor.citizenid, limit }) or {}

    local available = {}
    for index = 1, #availableRows do
        available[#available + 1] = normalizeCollectionTask(availableRows[index])
    end

    local mine = {}
    for index = 1, #myRows do
        mine[#mine + 1] = normalizeCollectionTask(myRows[index])
    end

    local myActiveCount = 0
    for index = 1, #mine do
        if mine[index].status == CollectionTaskStatuses.claimed then
            myActiveCount = myActiveCount + 1
        end
    end

    return VancePay.Server.ok({
        enabled = true,
        player_citizenid = actor.citizenid,
        tablet_item = getCollectionTabletItem(),
        config = {
            clue_mode = Utils.trim(getCollectionsConfig().clueMode) or 'fuzzy',
            task_limit = limit,
            claim_limit = getCollectionClaimLimit(),
            reward_rate = getCollectionRewardRate(),
            map_area = getCollectionMapAreaConfig(),
        },
        summary = {
            available_count = #available,
            my_active_count = myActiveCount,
            claim_limit = getCollectionClaimLimit(),
        },
        available_tasks = available,
        my_tasks = mine,
    })
end

function Loans.claimCollectionTask(source, payload)
    payload = payload or {}

    local actor, accessError = requireCollectionAccess(source)
    if not actor then
        return accessError
    end

    completeCollectionTasksForPaidLoans()

    local activeClaimRow = MySQL.single.await([[
        SELECT COUNT(*) AS count
        FROM vancepay_collection_tasks
        WHERE claimed_by_citizenid = ?
            AND status = 'claimed'
    ]], { actor.citizenid }) or {}
    local activeClaims = tonumber(activeClaimRow.count) or 0

    local claimLimit = getCollectionClaimLimit()
    if activeClaims >= claimLimit then
        return VancePay.Server.fail(('你同时最多领取 %d 个追债任务'):format(claimLimit), 'claim_limit')
    end

    local taskId = tonumber(payload.task_id or payload.taskId or payload.id)
    if not taskId then
        return VancePay.Server.fail('缺少任务 ID', 'missing_task_id')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_collection_tasks t
        INNER JOIN vancepay_loans l ON l.id = t.loan_id
        SET t.status = 'claimed',
            t.claimed_by_citizenid = ?,
            t.claimed_by_name_snapshot = ?,
            t.claimed_at = CURRENT_TIMESTAMP
        WHERE t.id = ?
            AND t.status = 'open'
            AND l.status = 'active'
    ]], { actor.citizenid, actor.name, taskId })

    if not updated or updated < 1 then
        return VancePay.Server.fail('任务已被领取或不再有效', 'claim_failed')
    end

    local task = fetchCollectionTaskById(taskId)
    local clue = updateTaskClueSnapshot(source, task)

    VancePay.Audit.log(actor.citizenid, 'claim_collection_task', 'collection_task', task and task.task_code or taskId, {
        detail = {
            task_id = taskId,
            loan_code = task and task.loan_code or nil,
            debtor_citizenid = task and task.debtor_citizenid or nil,
        }
    })

    local state = Loans.getCollectionState(source)
    if state and state.ok then
        state.data.claimed_task = task
        state.data.claimed_clue = clue
        state.message = '任务已领取'
    end

    return state or VancePay.Server.ok({ claimed_task = task, claimed_clue = clue }, '任务已领取')
end

function Loans.claimCollectionReward(source, payload)
    payload = payload or {}

    local actor, accessError = requireCollectionAccess(source)
    if not actor then
        return accessError
    end

    completeCollectionTasksForPaidLoans()

    local taskId = tonumber(payload.task_id or payload.taskId or payload.id)
    if not taskId then
        return VancePay.Server.fail('缺少任务 ID', 'missing_task_id')
    end

    local task = fetchCollectionTaskById(taskId)
    if not task or task.status ~= CollectionTaskStatuses.completed or task.claimed_by_citizenid ~= actor.citizenid then
        return VancePay.Server.fail('只能领取自己已完成任务的奖励', 'forbidden')
    end

    if task.reward_claimed then
        return VancePay.Server.fail('该任务奖励已领取', 'reward_already_claimed')
    end

    local rewardRate = task.reward_rate > 0 and task.reward_rate or getCollectionRewardRate()
    local rewardAmount = task.reward_amount > 0 and task.reward_amount or calculateCollectionRewardAmount(task, rewardRate)
    if rewardAmount <= 0 then
        return VancePay.Server.fail('该任务没有可领取奖励', 'no_reward')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_collection_tasks
        SET reward_rate = CASE WHEN reward_rate <= 0 THEN ? ELSE reward_rate END,
            reward_amount = CASE WHEN reward_amount <= 0 THEN ? ELSE reward_amount END,
            reward_claimed_at = CURRENT_TIMESTAMP
        WHERE id = ?
            AND status = 'completed'
            AND claimed_by_citizenid = ?
            AND reward_claimed_at IS NULL
    ]], { rewardRate, rewardAmount, taskId, actor.citizenid }) or 0

    if updated < 1 then
        return VancePay.Server.fail('该任务奖励已领取或不可领取', 'reward_claim_failed')
    end

    local deposited = VancePay.Banking.deposit(actor.citizenid, rewardAmount, ('vancepay:collection_reward:%s'):format(task.task_code or taskId))
    if not deposited then
        MySQL.update.await([[
            UPDATE vancepay_collection_tasks
            SET reward_claimed_at = NULL
            WHERE id = ?
                AND claimed_by_citizenid = ?
        ]], { taskId, actor.citizenid })

        return VancePay.Server.fail('追债奖励打款失败', 'banking_failed')
    end

    VancePay.Audit.log(actor.citizenid, 'claim_collection_reward', 'collection_task', task.task_code or taskId, {
        detail = {
            task_id = taskId,
            loan_code = task.loan_code,
            debtor_citizenid = task.debtor_citizenid,
            reward_rate = rewardRate,
            reward_amount = rewardAmount,
        }
    })

    VancePay.Server.notify(source, ('追债奖励 %s 已到账'):format(Utils.formatCurrency(rewardAmount)), 'success')

    local state = Loans.getCollectionState(source)
    if state and state.ok then
        state.data.rewarded_task = fetchCollectionTaskById(taskId)
        state.message = ('奖励已领取：%s'):format(Utils.formatCurrency(rewardAmount))
        return state
    end

    return VancePay.Server.ok({
        rewarded_task = fetchCollectionTaskById(taskId),
        reward_amount = rewardAmount,
    }, ('奖励已领取：%s'):format(Utils.formatCurrency(rewardAmount)))
end

function Loans.getCollectionTaskClue(source, payload)
    payload = payload or {}

    local actor, accessError = requireCollectionAccess(source)
    if not actor then
        return accessError
    end

    completeCollectionTasksForPaidLoans()

    local taskId = tonumber(payload.task_id or payload.taskId or payload.id)
    if not taskId then
        return VancePay.Server.fail('缺少任务 ID', 'missing_task_id')
    end

    local task = fetchCollectionTaskById(taskId)
    if not task or task.status ~= CollectionTaskStatuses.claimed or task.claimed_by_citizenid ~= actor.citizenid then
        return VancePay.Server.fail('只能查看自己已领取任务的线索', 'forbidden')
    end

    local clue = updateTaskClueSnapshot(source, task)
    task.clue_snapshot = clue

    return VancePay.Server.ok({
        task = task,
        clue = clue,
    })
end

local function parseCreditEventResult(result)
    if type(result) ~= 'table' then
        return result ~= false, result
    end

    if result.ok == false then
        return false, nil, result.error or result.message or result.code
    end

    if result.ok == true then
        return true, result.data or result.event or result.credit_event or result
    end

    return true, result
end

local function createCtifoOverdueEvent(loan)
    if not loan or Utils.isBlank(loan.loan_code) or Utils.isBlank(loan.citizenid) then
        return nil, 'invalid_loan'
    end

    local payload = {
        citizenid = loan.citizenid,
        source_resource = 'VancePay',
        source_ref = loan.loan_code,
        event_type = 'loan_overdue',
        impact = getOverdueCreditImpact(),
        title = 'VancePay 贷款逾期',
        summary = ('贷款 %s 已逾期，应还 %s。'):format(loan.loan_code, Utils.formatCurrency(loan.outstanding_amount or loan.total_due or 0)),
        metadata = {
            status = 'overdue',
            repayment_status = 'overdue',
            loan_id = loan.id,
            loan_code = loan.loan_code,
            principal_amount = loan.principal_amount,
            interest_amount = loan.interest_amount,
            total_due = loan.total_due,
            repaid_amount = loan.repaid_amount,
            outstanding_amount = loan.outstanding_amount,
            due_at = loan.due_at,
        },
    }

    local ok, result, err = callCtifoExport('CreateCreditEvent', payload)
    if not ok then
        return nil, err
    end

    local parsedOk, event, parseErr = parseCreditEventResult(result)
    if not parsedOk then
        return nil, parseErr or 'ctifo_error'
    end

    return event
end

markCtifoOverdueEventPaid = function(loan, repaidAmount)
    if not loan or Utils.isBlank(loan.loan_code) then
        return nil, 'invalid_loan'
    end

    local payload = {
        citizenid = loan.citizenid,
        source_resource = 'VancePay',
        source_ref = loan.loan_code,
        event_type = 'loan_overdue',
        impact = getOverduePaidCreditImpact(),
        title = 'VancePay 贷款逾期（已还清）',
        summary = ('贷款 %s 曾发生逾期，现已还清，保留历史信用记录。'):format(loan.loan_code),
        metadata = {
            status = 'paid',
            repayment_status = 'paid',
            loan_id = loan.id,
            loan_code = loan.loan_code,
            principal_amount = loan.principal_amount,
            interest_amount = loan.interest_amount,
            total_due = loan.total_due,
            repaid_amount = repaidAmount or loan.total_due,
            outstanding_amount = 0,
            due_at = loan.due_at,
            paid_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        },
    }

    local ok, result, err = callCtifoExport('CreateCreditEvent', payload)
    if not ok then
        return nil, err
    end

    local parsedOk, event, parseErr = parseCreditEventResult(result)
    if not parsedOk then
        return nil, parseErr or 'ctifo_error'
    end

    return event
end

local function upsertCollectionTaskForLoan(loan)
    if not loan then
        return nil
    end

    local profile = fetchCtifoProfile(loan.citizenid) or {}
    local taskCode = Utils.generateCode('DC', 10)

    local existing = MySQL.single.await([[
        SELECT id
        FROM vancepay_collection_tasks
        WHERE loan_id = ?
        LIMIT 1
    ]], { loan.id })

    if existing then
        MySQL.update.await([[
            UPDATE vancepay_collection_tasks
            SET debtor_name_snapshot = COALESCE(?, debtor_name_snapshot),
                debtor_phone_snapshot = COALESCE(?, debtor_phone_snapshot),
                principal_amount = ?,
                total_due = ?,
                outstanding_amount = ?
            WHERE loan_id = ?
        ]], {
            getProfileName(profile),
            profile.phone,
            loan.principal_amount,
            loan.total_due,
            loan.outstanding_amount,
            loan.id,
        })

        return existing.id
    end

    return MySQL.insert.await([[
        INSERT INTO vancepay_collection_tasks (
            task_code,
            loan_id,
            loan_code,
            debtor_citizenid,
            debtor_name_snapshot,
            debtor_phone_snapshot,
            principal_amount,
            total_due,
            outstanding_amount,
            status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open')
    ]], {
        taskCode,
        loan.id,
        loan.loan_code,
        loan.citizenid,
        getProfileName(profile),
        profile.phone,
        loan.principal_amount,
        loan.total_due,
        loan.outstanding_amount,
    })
end

local function hasLoanOverdueHistory(loan)
    return loan
        and (
            loan.is_overdue == true
            or loan.ctifo_credit_event_id ~= nil
            or not Utils.isBlank(loan.overdue_at)
            or not Utils.isBlank(loan.overdue_processed_at)
        )
end

local function markLoanOverdueProcessed(loan)
    if not loan or not loan.id then
        return false
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_loans
        SET overdue_at = COALESCE(overdue_at, CURRENT_TIMESTAMP),
            overdue_processed_at = COALESCE(overdue_processed_at, CURRENT_TIMESTAMP)
        WHERE id = ?
            AND due_at <= CURRENT_TIMESTAMP
            AND (
                overdue_at IS NULL
                OR overdue_processed_at IS NULL
            )
    ]], { loan.id }) or 0

    if updated > 0 then
        loan.overdue_at = loan.overdue_at or true
        loan.overdue_processed_at = loan.overdue_processed_at or true
        return true
    end

    return false
end

function Loans.completeCollectionTasksForLoan(loan, repaidAmount)
    if not loan then
        return
    end

    local overdueHistory = hasLoanOverdueHistory(loan)
    if loan.is_overdue == true and markLoanOverdueProcessed(loan) then
        overdueHistory = true
    end

    if fetchTableExists('vancepay_collection_tasks') then
        if collectionRewardColumnsAvailable() then
            local rewardRate = getCollectionRewardRate()
            MySQL.update.await([[
                UPDATE vancepay_collection_tasks
                SET status = 'completed',
                    completed_at = CURRENT_TIMESTAMP,
                    reward_rate = CASE
                        WHEN claimed_by_citizenid IS NOT NULL AND reward_rate <= 0 THEN ?
                        ELSE reward_rate
                    END,
                    reward_amount = CASE
                        WHEN claimed_by_citizenid IS NOT NULL AND reward_amount <= 0 THEN
                            ROUND((CASE WHEN outstanding_amount > 0 THEN outstanding_amount ELSE ? END) * ? / 100, 2)
                        ELSE reward_amount
                    END,
                    outstanding_amount = 0
                WHERE loan_id = ?
                    AND status IN ('open', 'claimed')
            ]], { rewardRate, repaidAmount or loan.total_due or 0, rewardRate, loan.id })
        else
            MySQL.update.await([[
                UPDATE vancepay_collection_tasks
                SET status = 'completed',
                    completed_at = CURRENT_TIMESTAMP,
                    outstanding_amount = 0
                WHERE loan_id = ?
                    AND status IN ('open', 'claimed')
            ]], { loan.id })
        end
    end

    if overdueHistory then
        local event, eventErr = markCtifoOverdueEventPaid(loan, repaidAmount)
        local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)

        if eventId and not loan.ctifo_credit_event_id then
            MySQL.update.await([[
                UPDATE vancepay_loans
                SET ctifo_credit_event_id = ?
                WHERE id = ?
                    AND ctifo_credit_event_id IS NULL
            ]], { eventId, loan.id })
        elseif not eventId then
            Utils.debug('VanceCtifo overdue credit event paid update failed', loan.loan_code, eventErr)
        end
    end
end

function Loans.sweepOverdueLoans(limit)
    if not shouldEnableCollections() then
        return 0
    end

    local schemaAvailable, schemaError = Loans.ensureCollectionsSchemaAvailable()
    if not schemaAvailable then
        Utils.debug('Loan overdue sweep skipped', schemaError)
        return 0
    end

    completeCollectionTasksForPaidLoans()

    local rows = MySQL.query.await([[
        SELECT
            *,
            UNIX_TIMESTAMP(CURRENT_TIMESTAMP) AS current_unix_time,
            UNIX_TIMESTAMP(due_at) AS due_at_unix
        FROM vancepay_loans
        WHERE status = 'active'
            AND due_at <= CURRENT_TIMESTAMP
            AND (
                overdue_processed_at IS NULL
                OR ctifo_credit_event_id IS NULL
            )
        ORDER BY due_at ASC, id ASC
        LIMIT ?
    ]], { math.min(math.max(tonumber(limit) or 25, 1), 100) }) or {}

    local processed = 0
    for index = 1, #rows do
        local loan = normalizeLoan(rows[index])
        local firstProcess = Utils.isBlank(loan.overdue_processed_at)
        local taskId = nil

        if firstProcess then
            MySQL.update.await([[
                UPDATE vancepay_loans
                SET overdue_at = COALESCE(overdue_at, CURRENT_TIMESTAMP),
                    overdue_processed_at = CURRENT_TIMESTAMP
                WHERE id = ?
                    AND overdue_processed_at IS NULL
            ]], { loan.id })

            taskId = upsertCollectionTaskForLoan(loan)
            VancePay.Audit.log(loan.citizenid, 'loan_overdue', 'loan', loan.loan_code, {
                detail = {
                    citizenid = loan.citizenid,
                    loan_code = loan.loan_code,
                    outstanding_amount = loan.outstanding_amount,
                    due_at = loan.due_at,
                    collection_task_id = taskId,
                }
            })
        else
            taskId = upsertCollectionTaskForLoan(loan)
        end

        if not loan.ctifo_credit_event_id then
            local event, eventErr = createCtifoOverdueEvent(loan)
            local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)

            if eventId then
                MySQL.update.await([[
                    UPDATE vancepay_loans
                    SET ctifo_credit_event_id = ?
                    WHERE id = ?
                        AND ctifo_credit_event_id IS NULL
                ]], { eventId, loan.id })
            else
                Utils.debug('VanceCtifo overdue credit event create failed', loan.loan_code, eventErr)
                if firstProcess then
                    VancePay.Audit.log(loan.citizenid, 'loan_overdue_credit_event_failed', 'loan', loan.loan_code, {
                        detail = {
                            citizenid = loan.citizenid,
                            loan_code = loan.loan_code,
                            reason = eventErr,
                            collection_task_id = taskId,
                        }
                    })
                end
            end
        end

        processed = processed + 1
    end

    return processed
end

local function isValidLoanStatus(status)
    return status == LoanStatuses.active
        or status == LoanStatuses.paid
        or status == LoanStatuses.defaulted
        or status == LoanStatuses.cancelled
end

local function isValidCollectionTaskStatus(status)
    return status == CollectionTaskStatuses.open
        or status == CollectionTaskStatuses.claimed
        or status == CollectionTaskStatuses.completed
        or status == CollectionTaskStatuses.cancelled
end

local function requireAdminAccess(source)
    if not VancePay.Permissions.isAdmin(source) then
        return nil, VancePay.Server.fail('只有管理员可以管理贷款', 'forbidden')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(actorCitizenId) then
        actorCitizenId = ('source:%s'):format(source)
    end

    return actorCitizenId
end

local function normalizeAdminDateTime(value)
    value = Utils.trim(value)
    if Utils.isBlank(value) then
        return nil
    end

    value = tostring(value):gsub('T', ' ')
    if value:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$') then
        value = value .. ':00'
    end

    if not value:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$') then
        return nil
    end

    if not Utils.parseSqlDateTime(value) then
        return nil
    end

    return value
end

local function buildAdminLoanConditions(filters, includeCollections)
    filters = filters or {}

    local conditions = { '1=1' }
    local params = {}

    local status = Utils.trim(filters.status)
    if not Utils.isBlank(status) and status ~= 'all' and isValidLoanStatus(status) then
        conditions[#conditions + 1] = 'l.status = ?'
        params[#params + 1] = status
    end

    local citizenid = Utils.trim(filters.citizenid)
    if not Utils.isBlank(citizenid) then
        conditions[#conditions + 1] = 'l.citizenid = ?'
        params[#params + 1] = citizenid
    end

    local search = Utils.trim(filters.search)
    if not Utils.isBlank(search) then
        local likeValue = '%' .. search .. '%'
        if includeCollections then
            conditions[#conditions + 1] = '(l.loan_code LIKE ? OR l.citizenid LIKE ? OR t.task_code LIKE ?)'
            params[#params + 1] = likeValue
            params[#params + 1] = likeValue
            params[#params + 1] = likeValue
        else
            conditions[#conditions + 1] = '(l.loan_code LIKE ? OR l.citizenid LIKE ?)'
            params[#params + 1] = likeValue
            params[#params + 1] = likeValue
        end
    end

    local dueState = Utils.trim(filters.due_state or filters.dueState)
    if dueState == 'overdue' then
        conditions[#conditions + 1] = 'l.status = \'active\' AND l.due_at <= CURRENT_TIMESTAMP'
    elseif dueState == 'due_soon' then
        conditions[#conditions + 1] = 'l.status = \'active\' AND l.due_at > CURRENT_TIMESTAMP AND l.due_at <= DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 3 DAY)'
    elseif dueState == 'current' then
        conditions[#conditions + 1] = 'l.status = \'active\' AND l.due_at > CURRENT_TIMESTAMP'
    end

    local collectionStatus = Utils.trim(filters.collection_status or filters.collectionStatus)
    if not Utils.isBlank(collectionStatus) and collectionStatus ~= 'all' then
        if collectionStatus == 'none' then
            if includeCollections then
                conditions[#conditions + 1] = 't.id IS NULL'
            end
        elseif includeCollections and isValidCollectionTaskStatus(collectionStatus) then
            conditions[#conditions + 1] = 't.status = ?'
            params[#params + 1] = collectionStatus
        else
            conditions[#conditions + 1] = '1=0'
        end
    end

    local dateFrom = normalizeAdminDateTime(filters.date_from or filters.dateFrom)
    if dateFrom then
        conditions[#conditions + 1] = 'l.created_at >= ?'
        params[#params + 1] = dateFrom
    elseif not Utils.isBlank(filters.date_from or filters.dateFrom) then
        conditions[#conditions + 1] = 'DATE(l.created_at) >= DATE(?)'
        params[#params + 1] = filters.date_from or filters.dateFrom
    end

    local dateTo = normalizeAdminDateTime(filters.date_to or filters.dateTo)
    if dateTo then
        conditions[#conditions + 1] = 'l.created_at <= ?'
        params[#params + 1] = dateTo
    elseif not Utils.isBlank(filters.date_to or filters.dateTo) then
        conditions[#conditions + 1] = 'DATE(l.created_at) <= DATE(?)'
        params[#params + 1] = filters.date_to or filters.dateTo
    end

    return conditions, params
end

local function normalizeAdminLoan(row)
    row = normalizeLoan(row)
    if not row then
        return nil
    end

    row.collection_task_id = tonumber(row.collection_task_id)
    row.collection_reward_rate = Utils.roundCurrency(row.collection_reward_rate or 0)
    row.collection_reward_amount = Utils.roundCurrency(row.collection_reward_amount or 0)
    row.collection_outstanding_amount = Utils.roundCurrency(row.collection_outstanding_amount or 0)
    row.collection_reward_claimed = not Utils.isBlank(row.collection_reward_claimed_at)

    if row.collection_task_id then
        row.collection_task = {
            id = row.collection_task_id,
            task_code = row.collection_task_code,
            status = row.collection_status,
            claimed_by_citizenid = row.collection_claimed_by_citizenid,
            claimed_by_name_snapshot = row.collection_claimed_by_name_snapshot,
            claimed_at = row.collection_claimed_at,
            completed_at = row.collection_completed_at,
            reward_rate = row.collection_reward_rate,
            reward_amount = row.collection_reward_amount,
            reward_claimed = row.collection_reward_claimed,
            created_at = row.collection_created_at,
        }
    else
        row.collection_task = nil
    end

    return row
end

local function shouldJoinAdminCollections()
    return fetchTableExists('vancepay_collection_tasks') ~= nil and collectionRewardColumnsAvailable()
end

local function getAdminLoanSummary(filters, includeCollections)
    local conditions, params = buildAdminLoanConditions(filters, includeCollections)
    local collectionSelect = includeCollections and [[
            COALESCE(SUM(CASE WHEN t.status = 'open' THEN 1 ELSE 0 END), 0) AS collection_open_count,
            COALESCE(SUM(CASE WHEN t.status = 'claimed' THEN 1 ELSE 0 END), 0) AS collection_claimed_count,
            COALESCE(SUM(CASE WHEN t.status = 'completed' AND t.reward_claimed_at IS NULL AND t.claimed_by_citizenid IS NOT NULL THEN t.reward_amount ELSE 0 END), 0) AS pending_collection_rewards
    ]] or [[
            0 AS collection_open_count,
            0 AS collection_claimed_count,
            0 AS pending_collection_rewards
    ]]
    local collectionJoin = includeCollections and 'LEFT JOIN vancepay_collection_tasks t ON t.loan_id = l.id' or ''

    local row = MySQL.single.await(([[
        SELECT
            COUNT(*) AS total_count,
            COALESCE(SUM(CASE WHEN l.status = 'active' THEN 1 ELSE 0 END), 0) AS active_count,
            COALESCE(SUM(CASE WHEN l.status = 'paid' THEN 1 ELSE 0 END), 0) AS paid_count,
            COALESCE(SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END), 0) AS defaulted_count,
            COALESCE(SUM(CASE WHEN l.status = 'cancelled' THEN 1 ELSE 0 END), 0) AS cancelled_count,
            COALESCE(SUM(CASE WHEN l.status = 'active' AND l.due_at <= CURRENT_TIMESTAMP THEN 1 ELSE 0 END), 0) AS overdue_count,
            COALESCE(SUM(CASE WHEN l.status = 'active' THEN GREATEST(l.total_due - l.repaid_amount, 0) ELSE 0 END), 0) AS outstanding_amount,
            COALESCE(SUM(l.principal_amount), 0) AS principal_amount,
            COALESCE(SUM(l.interest_amount), 0) AS interest_amount,
            COALESCE(SUM(l.total_due), 0) AS total_due,
            COALESCE(SUM(l.repaid_amount), 0) AS repaid_amount,
            %s
        FROM vancepay_loans l
        %s
        WHERE %s
    ]]):format(collectionSelect, collectionJoin, table.concat(conditions, ' AND ')), params) or {}

    return {
        total_count = tonumber(row.total_count) or 0,
        active_count = tonumber(row.active_count) or 0,
        paid_count = tonumber(row.paid_count) or 0,
        defaulted_count = tonumber(row.defaulted_count) or 0,
        cancelled_count = tonumber(row.cancelled_count) or 0,
        overdue_count = tonumber(row.overdue_count) or 0,
        outstanding_amount = Utils.roundCurrency(row.outstanding_amount or 0),
        principal_amount = Utils.roundCurrency(row.principal_amount or 0),
        interest_amount = Utils.roundCurrency(row.interest_amount or 0),
        total_due = Utils.roundCurrency(row.total_due or 0),
        repaid_amount = Utils.roundCurrency(row.repaid_amount or 0),
        collection_open_count = tonumber(row.collection_open_count) or 0,
        collection_claimed_count = tonumber(row.collection_claimed_count) or 0,
        pending_collection_rewards = Utils.roundCurrency(row.pending_collection_rewards or 0),
    }
end

function Loans.getAdminData(filters)
    filters = filters or {}

    local schemaAvailable, schemaError = Loans.ensureSchemaAvailable()
    if not schemaAvailable then
        return {
            enabled = shouldEnable(),
            schema_available = false,
            message = schemaError,
            summary = getEmptySummary(),
            items = {},
            page = 1,
            per_page = Config.TransPerPage,
        }
    end

    local includeCollections = shouldJoinAdminCollections()
    local page, perPage, offset = Utils.getPageOffset(filters.page, math.min(tonumber(filters.per_page) or 25, 100))
    perPage = math.min(perPage, 100)

    local conditions, params = buildAdminLoanConditions(filters, includeCollections)
    local collectionSelect = includeCollections and [[
            t.id AS collection_task_id,
            t.task_code AS collection_task_code,
            t.status AS collection_status,
            t.claimed_by_citizenid AS collection_claimed_by_citizenid,
            t.claimed_by_name_snapshot AS collection_claimed_by_name_snapshot,
            t.claimed_at AS collection_claimed_at,
            t.completed_at AS collection_completed_at,
            t.reward_rate AS collection_reward_rate,
            t.reward_amount AS collection_reward_amount,
            t.reward_claimed_at AS collection_reward_claimed_at,
            t.outstanding_amount AS collection_outstanding_amount,
            t.created_at AS collection_created_at,
    ]] or [[
            NULL AS collection_task_id,
            NULL AS collection_task_code,
            NULL AS collection_status,
            NULL AS collection_claimed_by_citizenid,
            NULL AS collection_claimed_by_name_snapshot,
            NULL AS collection_claimed_at,
            NULL AS collection_completed_at,
            0 AS collection_reward_rate,
            0 AS collection_reward_amount,
            NULL AS collection_reward_claimed_at,
            0 AS collection_outstanding_amount,
            NULL AS collection_created_at,
    ]]
    local collectionJoin = includeCollections and 'LEFT JOIN vancepay_collection_tasks t ON t.loan_id = l.id' or ''

    local query = ([[
        SELECT
            l.*,
            UNIX_TIMESTAMP(CURRENT_TIMESTAMP) AS current_unix_time,
            UNIX_TIMESTAMP(l.due_at) AS due_at_unix,
            %s
            TIMESTAMPDIFF(HOUR, CURRENT_TIMESTAMP, l.due_at) AS due_in_hours
        FROM vancepay_loans l
        %s
        WHERE %s
        ORDER BY
            CASE WHEN l.status = 'active' AND l.due_at <= CURRENT_TIMESTAMP THEN 0 ELSE 1 END,
            FIELD(l.status, 'active', 'defaulted', 'paid', 'cancelled'),
            CASE WHEN l.status = 'active' THEN l.due_at ELSE l.updated_at END ASC,
            l.id DESC
        LIMIT ? OFFSET ?
    ]]):format(collectionSelect, collectionJoin, table.concat(conditions, ' AND '))

    params[#params + 1] = perPage
    params[#params + 1] = offset

    local rows = MySQL.query.await(query, params) or {}
    for index = 1, #rows do
        rows[index] = normalizeAdminLoan(rows[index])
    end

    return {
        enabled = shouldEnable(),
        collections_enabled = shouldEnableCollections(),
        schema_available = true,
        collection_schema_available = includeCollections,
        summary = getAdminLoanSummary(filters, includeCollections),
        items = rows,
        page = page,
        per_page = perPage,
        filters = filters,
    }
end

local function fetchAdminLoanById(loanId)
    loanId = tonumber(loanId)
    if not loanId then
        return nil
    end

    local includeCollections = shouldJoinAdminCollections()
    local collectionSelect = includeCollections and [[
            t.id AS collection_task_id,
            t.task_code AS collection_task_code,
            t.status AS collection_status,
            t.claimed_by_citizenid AS collection_claimed_by_citizenid,
            t.claimed_by_name_snapshot AS collection_claimed_by_name_snapshot,
            t.claimed_at AS collection_claimed_at,
            t.completed_at AS collection_completed_at,
            t.reward_rate AS collection_reward_rate,
            t.reward_amount AS collection_reward_amount,
            t.reward_claimed_at AS collection_reward_claimed_at,
            t.outstanding_amount AS collection_outstanding_amount,
            t.created_at AS collection_created_at,
    ]] or [[
            NULL AS collection_task_id,
            NULL AS collection_task_code,
            NULL AS collection_status,
            NULL AS collection_claimed_by_citizenid,
            NULL AS collection_claimed_by_name_snapshot,
            NULL AS collection_claimed_at,
            NULL AS collection_completed_at,
            0 AS collection_reward_rate,
            0 AS collection_reward_amount,
            NULL AS collection_reward_claimed_at,
            0 AS collection_outstanding_amount,
            NULL AS collection_created_at,
    ]]
    local collectionJoin = includeCollections and 'LEFT JOIN vancepay_collection_tasks t ON t.loan_id = l.id' or ''

    local row = MySQL.single.await(([[
        SELECT
            l.*,
            UNIX_TIMESTAMP(CURRENT_TIMESTAMP) AS current_unix_time,
            UNIX_TIMESTAMP(l.due_at) AS due_at_unix,
            %s
            TIMESTAMPDIFF(HOUR, CURRENT_TIMESTAMP, l.due_at) AS due_in_hours
        FROM vancepay_loans l
        %s
        WHERE l.id = ?
        LIMIT 1
    ]]):format(collectionSelect, collectionJoin), { loanId })

    return normalizeAdminLoan(row)
end

local function buildLoanAuditDetail(existing, updated, extra)
    local detail = extra or {}
    local keys = {
        'principal_amount',
        'interest_amount',
        'total_due',
        'repaid_amount',
        'interest_rate',
        'term_days',
        'status',
        'due_at',
    }

    for index = 1, #keys do
        local key = keys[index]
        local oldValue = existing and existing[key] or nil
        local newValue = updated and updated[key] or nil

        if tostring(oldValue or '') ~= tostring(newValue or '') then
            detail['old_' .. key] = oldValue
            detail['new_' .. key] = newValue
        end
    end

    detail.citizenid = updated and updated.citizenid or existing and existing.citizenid
    detail.loan_code = updated and updated.loan_code or existing and existing.loan_code

    return detail
end

function Loans.saveAdminLoan(source, payload)
    payload = payload or {}

    local actorCitizenId, accessError = requireAdminAccess(source)
    if not actorCitizenId then
        return accessError
    end

    local schemaAvailable, schemaError = Loans.ensureSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local loanId = tonumber(payload.loan_id or payload.loanId or payload.id)
    if not loanId then
        return VancePay.Server.fail('缺少贷款 ID', 'missing_loan_id')
    end

    local existing = fetchAdminLoanById(loanId)
    if not existing then
        return VancePay.Server.fail('贷款不存在', 'loan_not_found')
    end

    local principalAmount = Utils.roundCurrency(Utils.ensureNumber(payload.principal_amount, existing.principal_amount))
    local interestAmount = Utils.roundCurrency(Utils.ensureNumber(payload.interest_amount, existing.interest_amount))
    local totalDue = Utils.roundCurrency(Utils.ensureNumber(payload.total_due, existing.total_due))
    local repaidAmount = Utils.roundCurrency(Utils.ensureNumber(payload.repaid_amount, existing.repaid_amount))
    local interestRate = Utils.roundCurrency(Utils.ensureNumber(payload.interest_rate, existing.interest_rate))
    local termDays = math.floor(tonumber(payload.term_days) or existing.term_days or 1)
    local status = Utils.trim(payload.status or existing.status)

    if not isValidLoanStatus(status) then
        return VancePay.Server.fail('贷款状态无效', 'invalid_status')
    end

    if principalAmount < 0 or interestAmount < 0 or totalDue < 0 or repaidAmount < 0 then
        return VancePay.Server.fail('贷款金额不能为负数', 'invalid_amount')
    end

    if totalDue + 0.005 < repaidAmount then
        return VancePay.Server.fail('已还金额不能超过应还总额', 'invalid_repaid_amount')
    end

    if interestRate < 0 or interestRate > 999.99 then
        return VancePay.Server.fail('利率必须在 0 到 999.99 之间', 'invalid_interest_rate')
    end

    if termDays < 1 or termDays > 3650 then
        return VancePay.Server.fail('贷款期限必须在 1 到 3650 天之间', 'invalid_term_days')
    end

    if status == LoanStatuses.paid then
        repaidAmount = totalDue
    elseif repaidAmount >= totalDue and totalDue > 0 then
        return VancePay.Server.fail('未结清贷款的已还金额必须小于应还总额', 'invalid_repaid_amount')
    end

    local dueAt = existing.due_at
    if payload.due_at ~= nil or payload.dueAt ~= nil then
        dueAt = normalizeAdminDateTime(payload.due_at or payload.dueAt)
        if not dueAt then
            return VancePay.Server.fail('到期时间格式无效', 'invalid_due_at')
        end
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_loans
        SET principal_amount = ?,
            interest_amount = ?,
            total_due = ?,
            repaid_amount = ?,
            interest_rate = ?,
            term_days = ?,
            status = ?,
            due_at = ?,
            repaid_at = CASE
                WHEN ? = 'paid' THEN COALESCE(repaid_at, CURRENT_TIMESTAMP)
                ELSE NULL
            END
        WHERE id = ?
    ]], {
        principalAmount,
        interestAmount,
        totalDue,
        repaidAmount,
        interestRate,
        termDays,
        status,
        dueAt,
        status,
        loanId,
    }) or 0

    if updated < 1 then
        return VancePay.Server.fail('贷款记录未更新', 'db_error')
    end

    local updatedLoan = fetchAdminLoanById(loanId)

    if fetchTableExists('vancepay_collection_tasks') then
        if status == LoanStatuses.paid then
            Loans.completeCollectionTasksForLoan(updatedLoan, updatedLoan and updatedLoan.repaid_amount or repaidAmount)
        elseif status == LoanStatuses.cancelled then
            MySQL.update.await([[
                UPDATE vancepay_collection_tasks
                SET status = 'cancelled'
                WHERE loan_id = ?
                    AND status IN ('open', 'claimed')
            ]], { loanId })
        else
            MySQL.update.await([[
                UPDATE vancepay_collection_tasks
                SET principal_amount = ?,
                    total_due = ?,
                    outstanding_amount = ?
                WHERE loan_id = ?
                    AND status IN ('open', 'claimed')
            ]], {
                principalAmount,
                totalDue,
                updatedLoan and updatedLoan.outstanding_amount or math.max(totalDue - repaidAmount, 0),
                loanId,
            })
        end
    end

    updatedLoan = fetchAdminLoanById(loanId) or updatedLoan

    VancePay.Audit.log(actorCitizenId, 'update_loan', 'loan', updatedLoan and updatedLoan.loan_code or existing.loan_code, {
        detail = buildLoanAuditDetail(existing, updatedLoan),
    })

    refreshClientState(existing.citizenid, 'loan_admin_updated')

    return VancePay.Server.ok(updatedLoan, '贷款已更新')
end

function Loans.createAdminCollectionTask(source, payload)
    payload = payload or {}

    local actorCitizenId, accessError = requireAdminAccess(source)
    if not actorCitizenId then
        return accessError
    end

    if not shouldEnableCollections() then
        return VancePay.Server.fail('追债任务未启用', 'disabled')
    end

    local schemaAvailable, schemaError = Loans.ensureCollectionsSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    completeCollectionTasksForPaidLoans()

    local loanId = tonumber(payload.loan_id or payload.loanId or payload.id)
    if not loanId then
        return VancePay.Server.fail('缺少贷款 ID', 'missing_loan_id')
    end

    local loan = fetchAdminLoanById(loanId)
    if not loan then
        return VancePay.Server.fail('贷款不存在', 'loan_not_found')
    end

    if loan.status ~= LoanStatuses.active or Utils.roundCurrency(loan.outstanding_amount or 0) <= 0 then
        return VancePay.Server.fail('只有未结清的活跃贷款可以生成追债任务', 'loan_not_collectable')
    end

    if not loan.is_overdue then
        return VancePay.Server.fail('只有已逾期贷款可以生成追债任务，请先调整到期时间', 'loan_not_overdue')
    end

    if loan.collection_task and loan.collection_task.status ~= CollectionTaskStatuses.cancelled then
        return VancePay.Server.fail('该贷款已有催收任务', 'task_already_exists')
    end

    markLoanOverdueProcessed(loan)
    local taskId = upsertCollectionTaskForLoan(loan)
    MySQL.update.await([[
        UPDATE vancepay_collection_tasks
        SET status = 'open',
            claimed_by_citizenid = NULL,
            claimed_by_name_snapshot = NULL,
            claimed_at = NULL,
            completed_at = NULL,
            reward_claimed_at = NULL,
            reward_amount = 0
        WHERE id = ?
            AND status = 'cancelled'
    ]], { taskId })

    if not loan.ctifo_credit_event_id then
        local event, eventErr = createCtifoOverdueEvent(loan)
        local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)

        if eventId then
            MySQL.update.await([[
                UPDATE vancepay_loans
                SET ctifo_credit_event_id = ?
                WHERE id = ?
                    AND ctifo_credit_event_id IS NULL
            ]], { eventId, loan.id })
        else
            Utils.debug('VanceCtifo manual overdue credit event create failed', loan.loan_code, eventErr)
        end
    end

    local task = fetchCollectionTaskById(taskId)

    VancePay.Audit.log(actorCitizenId, 'create_collection_task', 'collection_task', task and task.task_code or taskId, {
        detail = {
            loan_id = loan.id,
            loan_code = loan.loan_code,
            citizenid = loan.citizenid,
            outstanding_amount = loan.outstanding_amount,
            due_at = loan.due_at,
        }
    })

    return VancePay.Server.ok({
        loan = fetchAdminLoanById(loanId),
        task = task,
    }, '追债任务已生成')
end

function Loans.cancelAdminCollectionTask(source, payload)
    payload = payload or {}

    local actorCitizenId, accessError = requireAdminAccess(source)
    if not actorCitizenId then
        return accessError
    end

    local schemaAvailable, schemaError = Loans.ensureCollectionsSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local loanId = tonumber(payload.loan_id or payload.loanId)
    local taskId = tonumber(payload.task_id or payload.taskId or payload.id)
    if not loanId and not taskId then
        return VancePay.Server.fail('缺少追债任务 ID', 'missing_task_id')
    end

    local task = taskId and fetchCollectionTaskById(taskId) or nil
    if not task and loanId then
        local row = MySQL.single.await([[
            SELECT id
            FROM vancepay_collection_tasks
            WHERE loan_id = ?
            LIMIT 1
        ]], { loanId })
        task = row and fetchCollectionTaskById(row.id) or nil
    end

    if not task then
        return VancePay.Server.fail('追债任务不存在', 'task_not_found')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_collection_tasks
        SET status = 'cancelled'
        WHERE id = ?
            AND status IN ('open', 'claimed')
    ]], { task.id }) or 0

    if updated < 1 then
        return VancePay.Server.fail('只有待领取或已领取的追债任务可以取消', 'task_not_cancelable')
    end

    VancePay.Audit.log(actorCitizenId, 'cancel_collection_task', 'collection_task', task.task_code or task.id, {
        detail = {
            task_id = task.id,
            loan_id = task.loan_id,
            loan_code = task.loan_code,
            debtor_citizenid = task.debtor_citizenid,
            previous_status = task.status,
        }
    })

    return VancePay.Server.ok({
        loan = fetchAdminLoanById(task.loan_id),
        task = fetchCollectionTaskById(task.id),
    }, '追债任务已取消')
end

function Loans.create(source, payload)
    payload = payload or {}

    if not shouldEnable() then
        return VancePay.Server.fail('贷款功能未启用', 'disabled')
    end

    local schemaAvailable, schemaError = Loans.ensureSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) then
        return VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    local state = Loans.getCustomerState(citizenid)
    local offer = state.offer or {}

    if offer.eligible ~= true then
        return VancePay.Server.fail(offer.reason or '当前不可申请贷款', 'loan_not_eligible', state)
    end

    local amount = Utils.roundCurrency(Utils.ensureNumber(payload.amount or payload.principal_amount, 0))
    if amount < (offer.min_amount or getMinAmount()) then
        return VancePay.Server.fail(
            ('贷款金额至少为 %s'):format(Utils.formatCurrency(offer.min_amount or getMinAmount())),
            'invalid_amount'
        )
    end

    if amount > Utils.roundCurrency(offer.available_amount or 0) then
        return VancePay.Server.fail(
            ('当前最多可借 %s'):format(Utils.formatCurrency(offer.available_amount or 0)),
            'amount_exceeds_limit'
        )
    end

    local termDays = math.floor(tonumber(payload.term_days or payload.termDays or offer.default_term_days) or 0)
    if not termAllowed(termDays, offer.term_days or {}) then
        return VancePay.Server.fail('贷款期限无效', 'invalid_term')
    end

    local interestRate = Utils.roundCurrency(offer.interest_rate or 0)
    local interestAmount = calculateInterest(amount, interestRate)
    local totalDue = Utils.roundCurrency(amount + interestAmount)
    local loanCode = Utils.generateCode('LN', 10)
    local trust = state.trust or {}

    local insertedId = MySQL.insert.await([[
        INSERT INTO vancepay_loans (
            loan_code,
            citizenid,
            principal_amount,
            interest_amount,
            total_due,
            repaid_amount,
            interest_rate,
            term_days,
            trust_score,
            trust_band,
            status,
            due_at
        ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, 'active', DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? DAY))
    ]], {
        loanCode,
        citizenid,
        amount,
        interestAmount,
        totalDue,
        interestRate,
        termDays,
        tonumber(trust.score),
        Utils.trim(trust.band),
        termDays,
    })

    if not insertedId then
        return VancePay.Server.fail('贷款记录写入失败', 'db_error')
    end

    local deposited = VancePay.Banking.deposit(citizenid, amount, ('vancepay:loan:%s'):format(loanCode))
    if not deposited then
        MySQL.update.await([[
            UPDATE vancepay_loans
            SET status = 'cancelled'
            WHERE id = ?
        ]], { insertedId })

        return VancePay.Server.fail('贷款放款失败', 'banking_failed')
    end

    VancePay.Audit.log(citizenid, 'create_loan', 'loan', loanCode, {
        detail = {
            citizenid = citizenid,
            amount = amount,
            interest_amount = interestAmount,
            total_due = totalDue,
            interest_rate = interestRate,
            term_days = termDays,
            trust_score = trust.score,
            trust_band = trust.band,
        }
    })

    refreshClientState(citizenid, 'loan_created')

    return VancePay.Server.ok(Loans.getCustomerState(citizenid), '贷款已发放')
end

local function fetchRepayableLoan(citizenid, loanId)
    local params = { citizenid }
    local idFilter = ''

    if loanId then
        idFilter = 'AND id = ?'
        params[#params + 1] = loanId
    end

    local row = MySQL.single.await(([[
        SELECT
            *,
            UNIX_TIMESTAMP(CURRENT_TIMESTAMP) AS current_unix_time,
            UNIX_TIMESTAMP(due_at) AS due_at_unix
        FROM vancepay_loans
        WHERE citizenid = ?
            AND status = 'active'
            %s
        ORDER BY due_at ASC, id ASC
        LIMIT 1
    ]]):format(idFilter), params)

    return normalizeLoan(row)
end

function Loans.repay(source, payload)
    payload = payload or {}

    if not shouldEnable() then
        return VancePay.Server.fail('贷款功能未启用', 'disabled')
    end

    local schemaAvailable, schemaError = Loans.ensureSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) then
        return VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    local loan = fetchRepayableLoan(citizenid, tonumber(payload.loan_id or payload.loanId))
    if not loan then
        return VancePay.Server.fail('没有可还款贷款', 'loan_not_found')
    end

    local outstandingAmount = Utils.roundCurrency(loan.outstanding_amount or 0)
    if outstandingAmount <= 0 then
        return VancePay.Server.fail('该贷款已结清', 'loan_already_paid')
    end

    local requestedAmount = Utils.roundCurrency(Utils.ensureNumber(payload.amount or payload.repay_amount, outstandingAmount))
    if payload.repay_all == true or payload.repayAll == true then
        requestedAmount = outstandingAmount
    end

    if requestedAmount <= 0 then
        return VancePay.Server.fail('还款金额必须大于 0', 'invalid_amount')
    end

    local amount = Utils.roundCurrency(math.min(requestedAmount, outstandingAmount))
    local withdrawn = VancePay.Banking.withdraw(citizenid, amount, ('vancepay:loan_repay:%s'):format(loan.loan_code))
    if not withdrawn then
        return VancePay.Server.fail('银行卡余额不足或扣款失败', 'banking_failed')
    end

    local newRepaidAmount = Utils.roundCurrency(math.min((loan.repaid_amount or 0) + amount, loan.total_due or 0))
    local paid = newRepaidAmount >= Utils.roundCurrency((loan.total_due or 0) - 0.005)
    local nextStatus = paid and LoanStatuses.paid or LoanStatuses.active
    local updated = MySQL.update.await([[
        UPDATE vancepay_loans
        SET repaid_amount = ?,
            status = ?,
            repaid_at = CASE WHEN ? = 'paid' THEN CURRENT_TIMESTAMP ELSE repaid_at END
        WHERE id = ?
            AND citizenid = ?
            AND status = 'active'
    ]], {
        newRepaidAmount,
        nextStatus,
        nextStatus,
        loan.id,
        citizenid,
    })

    if not updated or updated < 1 then
        local rolledBack = VancePay.Banking.deposit(
            citizenid,
            amount,
            ('vancepay:loan_repay_rollback:%s'):format(loan.loan_code)
        )

        if not rolledBack then
            Utils.debug('VancePay loan repayment rollback failed', citizenid, amount, loan.loan_code)
        end

        return VancePay.Server.fail('还款记录更新失败，已尝试回滚扣款', 'db_error')
    end

    VancePay.Audit.log(citizenid, 'repay_loan', 'loan', loan.loan_code, {
        detail = {
            citizenid = citizenid,
            amount = amount,
            loan_code = loan.loan_code,
            paid = paid,
            repaid_amount = newRepaidAmount,
            total_due = loan.total_due,
        }
    })

    if paid then
        Loans.completeCollectionTasksForLoan(loan, newRepaidAmount)
    end

    refreshClientState(citizenid, paid and 'loan_paid' or 'loan_repaid')

    return VancePay.Server.ok(Loans.getCustomerState(citizenid), paid and '贷款已结清' or '还款成功')
end

lib.callback.register('vancepay:server:createLoan', function(source, payload)
    return Loans.create(source, payload or {})
end)

lib.callback.register('vancepay:server:repayLoan', function(source, payload)
    return Loans.repay(source, payload or {})
end)

lib.callback.register('vancepay:server:getAdminLoans', function(source, filters)
    local actorCitizenId, accessError = requireAdminAccess(source)
    if not actorCitizenId then
        return accessError
    end

    return VancePay.Server.ok(Loans.getAdminData(filters or {}))
end)

lib.callback.register('vancepay:server:saveAdminLoan', function(source, payload)
    return Loans.saveAdminLoan(source, payload or {})
end)

lib.callback.register('vancepay:server:createAdminCollectionTask', function(source, payload)
    return Loans.createAdminCollectionTask(source, payload or {})
end)

lib.callback.register('vancepay:server:cancelAdminCollectionTask', function(source, payload)
    return Loans.cancelAdminCollectionTask(source, payload or {})
end)

lib.callback.register('vancepay:server:getCollectionTasks', function(source)
    return Loans.getCollectionState(source)
end)

lib.callback.register('vancepay:server:claimCollectionTask', function(source, payload)
    return Loans.claimCollectionTask(source, payload or {})
end)

lib.callback.register('vancepay:server:claimCollectionReward', function(source, payload)
    return Loans.claimCollectionReward(source, payload or {})
end)

lib.callback.register('vancepay:server:getCollectionTaskClue', function(source, payload)
    return Loans.getCollectionTaskClue(source, payload or {})
end)

AddEventHandler('onResourceStart', function(resourceName)
    if not shouldEnable() or not isCtifoResourceName(resourceName) then
        return
    end

    CreateThread(function()
        Wait(1200)
        refreshAllClientStates('ctifo_started')
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if shouldEnable() and isCtifoResourceName(resourceName) then
        refreshAllClientStates('ctifo_stopped')
    end
end)

CreateThread(function()
    Wait(5000)

    while true do
        local interval = getOverdueSweepIntervalMs()

        if shouldEnableCollections() then
            local ok, err = pcall(function()
                Loans.sweepOverdueLoans()
            end)

            if not ok then
                Utils.debug('Loan overdue sweep failed', err)
            end
        end

        Wait(interval)
    end
end)
