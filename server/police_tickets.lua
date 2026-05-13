VancePay.PoliceTickets = VancePay.PoliceTickets or {}

local PoliceTickets = VancePay.PoliceTickets

local TABLE_NAME = 'vancepay_police_tickets'
local CTIFO_RESOURCE_FALLBACKS = {
    'VanceCtifo',
    'vance_ctifo',
}

local REQUIRED_TICKET_COLUMNS = {
    'ticket_code',
    'officer_citizenid',
    'target_citizenid',
    'amount',
    'reason',
    'ticket_type',
    'ticket_style',
    'ticket_agency',
    'status',
    'ctifo_credit_event_id',
    'ctifo_credit_impact',
    'paid_at',
    'created_at',
    'updated_at',
}

local FALLBACK_AGENCY = {
    key = 'lspd',
    label = '洛圣都警察局',
    subtitle = 'LOS SANTOS POLICE DEPARTMENT',
    badge = 'LS',
    watermark = 'LSPD',
    code_prefix = 'LS',
    class_name = 'agency-lspd',
    jobs = { 'police', 'lspd' },
    theme = nil,
}

local CREATE_POLICE_TICKETS_TABLE = [[
    CREATE TABLE IF NOT EXISTS vancepay_police_tickets (
        id INT AUTO_INCREMENT PRIMARY KEY,
        ticket_code VARCHAR(32) NOT NULL UNIQUE,
        officer_citizenid VARCHAR(50) NOT NULL,
        officer_name_snapshot VARCHAR(100) DEFAULT NULL,
        target_citizenid VARCHAR(50) NOT NULL,
        target_name_snapshot VARCHAR(100) DEFAULT NULL,
        amount DECIMAL(15,2) NOT NULL,
        reason VARCHAR(255) NOT NULL,
        ticket_type VARCHAR(24) NOT NULL DEFAULT 'notice',
        ticket_style VARCHAR(24) NOT NULL DEFAULT 'aged',
        ticket_agency VARCHAR(32) NOT NULL DEFAULT 'lspd',
        status ENUM('unpaid', 'paid', 'cancelled') NOT NULL DEFAULT 'unpaid',
        ctifo_credit_event_id INT UNSIGNED DEFAULT NULL,
        ctifo_credit_impact INT NOT NULL DEFAULT 0,
        paid_at TIMESTAMP NULL DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_ticket_target_status (target_citizenid, status, created_at),
        INDEX idx_ticket_officer_time (officer_citizenid, created_at),
        INDEX idx_ticket_agency_status_time (ticket_agency, status, created_at),
        INDEX idx_ticket_status_time (status, created_at),
        INDEX idx_ticket_ctifo_event (ctifo_credit_event_id)
    ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local function getConfig()
    return Config.PoliceTickets or {}
end

local function getCommandConfig()
    local config = getConfig().command
    return type(config) == 'table' and config or {}
end

local function getManagementCommandConfig()
    local config = getConfig().managementCommand
    return type(config) == 'table' and config or {}
end

local function getCreditConfig()
    local config = getConfig().credit
    return type(config) == 'table' and config or {}
end

local function shouldEnable()
    return getConfig().enabled ~= false
end

local function shouldRunSchemaMigrations()
    local databaseConfig = Config.Database or {}
    return databaseConfig.autoMigrate == true
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

local function fetchTableExists(tableName)
    return MySQL.single.await([[
        SELECT 1 AS present
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = ?
        LIMIT 1
    ]], { tableName })
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

local function ensureSchema()
    MySQL.query.await(CREATE_POLICE_TICKETS_TABLE)
    ensureColumn(TABLE_NAME, 'ticket_type', "VARCHAR(24) NOT NULL DEFAULT 'notice' AFTER reason")
    ensureColumn(TABLE_NAME, 'ticket_style', "VARCHAR(24) NOT NULL DEFAULT 'aged' AFTER ticket_type")
    ensureColumn(TABLE_NAME, 'ticket_agency', "VARCHAR(32) NOT NULL DEFAULT 'lspd' AFTER ticket_style")
    ensureColumn(TABLE_NAME, 'ctifo_credit_event_id', 'INT UNSIGNED DEFAULT NULL AFTER status')
    ensureColumn(TABLE_NAME, 'ctifo_credit_impact', 'INT NOT NULL DEFAULT 0 AFTER ctifo_credit_event_id')
    ensureColumn(TABLE_NAME, 'paid_at', 'TIMESTAMP NULL DEFAULT NULL AFTER ctifo_credit_impact')
    ensureColumn(TABLE_NAME, 'updated_at', 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at')
    ensureIndex(TABLE_NAME, 'idx_ticket_target_status', '(target_citizenid, status, created_at)')
    ensureIndex(TABLE_NAME, 'idx_ticket_officer_time', '(officer_citizenid, created_at)')
    ensureIndex(TABLE_NAME, 'idx_ticket_agency_status_time', '(ticket_agency, status, created_at)')
    ensureIndex(TABLE_NAME, 'idx_ticket_status_time', '(status, created_at)')
    ensureIndex(TABLE_NAME, 'idx_ticket_ctifo_event', '(ctifo_credit_event_id)')
end

function PoliceTickets.ensureReady()
    if PoliceTickets._ready then
        return true
    end

    while PoliceTickets._initializing do
        Wait(50)
        if PoliceTickets._ready then
            return true
        end
    end

    PoliceTickets._initializing = true
    local ok, err = pcall(function()
        if shouldRunSchemaMigrations() then
            ensureSchema()
        end
    end)
    PoliceTickets._initializing = false
    if not ok then
        error(err)
    end

    PoliceTickets._ready = true
    return true
end

local function ensureSchemaAvailable()
    PoliceTickets.ensureReady()

    if not fetchTableExists(TABLE_NAME) then
        return false, '数据库结构未升级到最新版本，请先执行 sql/migrate_to_latest.sql'
    end

    for index = 1, #REQUIRED_TICKET_COLUMNS do
        if not fetchColumnExists(TABLE_NAME, REQUIRED_TICKET_COLUMNS[index]) then
            return false, '罚单数据库字段缺失，请先执行 sql/migrate_to_latest.sql'
        end
    end

    return true
end

local function getTicketTypeOptions()
    local configured = getConfig().ticketTypes
    local options = {}
    local seen = {}

    local function addOption(value, label)
        value = tostring(Utils.trim(value) or '')
        label = tostring(Utils.trim(label) or '')
        if Utils.isBlank(value) or seen[value] then
            return
        end

        if value ~= 'notice' and value ~= 'traffic' then
            return
        end

        seen[value] = true
        options[#options + 1] = {
            value = value,
            label = not Utils.isBlank(label) and label or (value == 'traffic' and '交通违法处罚单' or '行政处罚告知单'),
        }
    end

    if type(configured) == 'table' then
        for index = 1, #configured do
            local option = configured[index]
            if type(option) == 'table' then
                addOption(option.value or option[1], option.label or option[2])
            end
        end
    end

    addOption('notice', '行政处罚告知单')
    addOption('traffic', '交通违法处罚单')
    return options
end

local function getTicketStyleOptions()
    local configured = getConfig().ticketStyles
    local options = {}
    local seen = {}

    local function addOption(value, label)
        value = tostring(Utils.trim(value) or '')
        label = tostring(Utils.trim(label) or '')
        if Utils.isBlank(value) or seen[value] then
            return
        end

        if value ~= 'aged' and value ~= 'carbon' then
            return
        end

        seen[value] = true
        options[#options + 1] = {
            value = value,
            label = not Utils.isBlank(label) and label or (value == 'carbon' and '碳复写纸' or '泛黄纸张'),
        }
    end

    if type(configured) == 'table' then
        for index = 1, #configured do
            local option = configured[index]
            if type(option) == 'table' then
                addOption(option.value or option[1], option.label or option[2])
            end
        end
    end

    addOption('aged', '泛黄纸张')
    addOption('carbon', '碳复写纸')
    return options
end

local function sanitizeTicketChoice(value, options, fallback)
    value = tostring(Utils.trim(value) or '')
    if Utils.isBlank(value) then
        value = fallback
    end

    local normalizedValue = value:lower()
    for index = 1, #options do
        local optionValue = tostring(options[index].value or '')
        if optionValue:lower() == normalizedValue then
            return optionValue
        end
    end

    return options[1] and options[1].value or fallback
end

local function sanitizeTicketType(value)
    return sanitizeTicketChoice(value, getTicketTypeOptions(), 'notice')
end

local function sanitizeTicketStyle(value)
    return sanitizeTicketChoice(value, getTicketStyleOptions(), 'aged')
end

local function addResourceName(resourceNames, seen, value)
    if type(value) ~= 'string' then
        return
    end

    value = Utils.trim(value)
    if Utils.isBlank(value) then
        return
    end

    local key = value:lower()
    if seen[key] then
        return
    end

    seen[key] = true
    resourceNames[#resourceNames + 1] = value
end

local function addResourceList(resourceNames, seen, values)
    if type(values) ~= 'table' then
        addResourceName(resourceNames, seen, values)
        return
    end

    for index = 1, #values do
        addResourceName(resourceNames, seen, values[index])
    end
end

local function getCtifoResourceNames()
    local resourceNames = {}
    local seen = {}
    local config = getConfig()

    addResourceList(resourceNames, seen, config.ctifoResource)
    addResourceList(resourceNames, seen, config.ctifoResourceAliases)

    for index = 1, #CTIFO_RESOURCE_FALLBACKS do
        addResourceName(resourceNames, seen, CTIFO_RESOURCE_FALLBACKS[index])
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

local sanitizeTicketAgency

local function normalizeTicket(row)
    row = Utils.normalizeDbRow(row)
    if type(row) ~= 'table' then
        return nil
    end

    row.id = tonumber(row.id)
    row.amount = Utils.roundCurrency(row.amount)
    row.ticket_type = sanitizeTicketType(row.ticket_type)
    row.ticket_style = sanitizeTicketStyle(row.ticket_style)
    row.ticket_agency = sanitizeTicketAgency(row.ticket_agency)
    row.ctifo_credit_event_id = tonumber(row.ctifo_credit_event_id)
    row.ctifo_credit_impact = math.floor(tonumber(row.ctifo_credit_impact) or 0)
    return row
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

local function resolveJobName(job)
    if type(job) ~= 'table' then
        return nil
    end

    return Utils.trim(job.name or job.id or job.key)
end

local function isJobOnDuty(job)
    if type(job) ~= 'table' then
        return false
    end

    local duty = job.onduty
    if duty == nil then
        duty = job.onDuty
    end
    if duty == nil then
        duty = job.duty
    end

    return duty == true or duty == 1
end

local function normalizeText(value, fallback)
    if value ~= nil then
        value = Utils.trim(tostring(value))
        if not Utils.isBlank(value) then
            return value
        end
    end

    return fallback
end

local function normalizeAgencyKey(value)
    value = normalizeText(value, nil)
    if Utils.isBlank(value) then
        return nil
    end

    value = value:lower():gsub('[^%w_-]', '')
    if Utils.isBlank(value) then
        return nil
    end

    return value
end

local function normalizeCompareKey(value)
    value = normalizeText(value, nil)
    if Utils.isBlank(value) then
        return nil
    end

    return value:lower()
end

local function sanitizeClassName(value, fallback)
    value = normalizeText(value, fallback)
    value = tostring(value or ''):gsub('[^%w_%-%s]', ''):gsub('%s+', ' ')
    value = Utils.trim(value)

    if Utils.isBlank(value) then
        return fallback
    end

    return value
end

local function sanitizeCodePrefix(value, fallback)
    value = normalizeText(value, fallback or 'LS')
    value = tostring(value or ''):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)

    if Utils.isBlank(value) then
        return fallback or 'LS'
    end

    return value
end

local function sanitizeCssValue(value, fallback)
    value = normalizeText(value, nil)
    if Utils.isBlank(value) or value:find('[;{}]') then
        return fallback
    end

    return value
end

local function normalizeJobList(values, fallback)
    local jobs = {}
    local seen = {}

    local function addJob(value)
        value = normalizeText(value, nil)
        if Utils.isBlank(value) then
            return
        end

        local key = value:lower()
        if seen[key] then
            return
        end

        seen[key] = true
        jobs[#jobs + 1] = value
    end

    if type(values) == 'string' then
        addJob(values)
    elseif type(values) == 'table' then
        for key, value in pairs(values) do
            if type(key) == 'string' and value == true then
                addJob(key)
            else
                addJob(value)
            end
        end
    end

    if #jobs < 1 then
        addJob(fallback)
    end

    return jobs
end

local function normalizeAgencyTheme(theme, fallback)
    if type(theme) ~= 'table' then
        return nil
    end

    fallback = type(fallback) == 'table' and fallback or {}

    return {
        paper = sanitizeCssValue(theme.paper, fallback.paper),
        paper_deep = sanitizeCssValue(theme.paperDeep or theme.paper_deep, fallback.paper_deep),
        edge = sanitizeCssValue(theme.edge, fallback.edge),
        ink = sanitizeCssValue(theme.ink, fallback.ink),
        ink_soft = sanitizeCssValue(theme.inkSoft or theme.ink_soft, fallback.ink_soft),
        line = sanitizeCssValue(theme.line, fallback.line),
        stamp = sanitizeCssValue(theme.stamp, fallback.stamp),
    }
end

local function normalizeAgencyDefinition(definition, key)
    definition = type(definition) == 'table' and definition or {}
    key = normalizeAgencyKey(definition.key or definition.value or key) or FALLBACK_AGENCY.key

    local badge = sanitizeCodePrefix(definition.badge, FALLBACK_AGENCY.badge)
    return {
        key = key,
        label = normalizeText(definition.label or definition.name, FALLBACK_AGENCY.label),
        subtitle = normalizeText(definition.subtitle, FALLBACK_AGENCY.subtitle),
        badge = badge,
        watermark = normalizeText(definition.watermark, key:upper()),
        code_prefix = sanitizeCodePrefix(definition.codePrefix or definition.code_prefix, badge),
        class_name = sanitizeClassName(definition.className or definition.class_name, ('agency-%s'):format(key)),
        jobs = normalizeJobList(definition.jobs or definition.job, key),
        theme = normalizeAgencyTheme(definition.theme, FALLBACK_AGENCY.theme),
    }
end

local function getAgencyDefinitions()
    local agencies = {}
    local configured = getConfig().agencies

    if type(configured) == 'table' then
        for key, definition in pairs(configured) do
            if type(definition) == 'table' then
                local agency = normalizeAgencyDefinition(definition, key)
                agencies[agency.key] = agency
            end
        end
    end

    if not agencies[FALLBACK_AGENCY.key] then
        agencies[FALLBACK_AGENCY.key] = normalizeAgencyDefinition(FALLBACK_AGENCY, FALLBACK_AGENCY.key)
    end

    return agencies
end

local function getAgencyKeys(agencies)
    local keys = {}
    for key in pairs(agencies or {}) do
        keys[#keys + 1] = key
    end

    table.sort(keys)
    return keys
end

local function getDefaultAgency()
    local agencies = getAgencyDefinitions()
    local defaultKey = normalizeAgencyKey(getConfig().defaultAgency)

    if defaultKey and agencies[defaultKey] then
        return agencies[defaultKey]
    end

    if agencies[FALLBACK_AGENCY.key] then
        return agencies[FALLBACK_AGENCY.key]
    end

    local keys = getAgencyKeys(agencies)
    return agencies[keys[1]] or normalizeAgencyDefinition(FALLBACK_AGENCY, FALLBACK_AGENCY.key)
end

local function getAgencyDefinition(value)
    local agencies = getAgencyDefinitions()
    local key = normalizeAgencyKey(value)

    if key and agencies[key] then
        return agencies[key]
    end

    return getDefaultAgency()
end

local function getAgencyForJob(jobName)
    local normalizedJobName = normalizeCompareKey(jobName)
    local agencies = getAgencyDefinitions()
    local keys = getAgencyKeys(agencies)

    if not Utils.isBlank(normalizedJobName) then
        for index = 1, #keys do
            local agency = agencies[keys[index]]
            if agency and normalizeCompareKey(agency.key) == normalizedJobName then
                return agency
            end
        end

        for index = 1, #keys do
            local agency = agencies[keys[index]]
            local jobs = agency and agency.jobs or {}
            for jobIndex = 1, #jobs do
                if normalizeCompareKey(jobs[jobIndex]) == normalizedJobName then
                    return agency
                end
            end
        end
    end

    return getDefaultAgency()
end

sanitizeTicketAgency = function(value)
    return getAgencyDefinition(value).key
end

local function getAgencyOptions()
    local agencies = getAgencyDefinitions()
    local keys = getAgencyKeys(agencies)
    local options = {}

    for index = 1, #keys do
        options[#options + 1] = Utils.deepCopy(agencies[keys[index]])
    end

    return options
end

local function getAllowedJobs()
    local jobs = {}
    local seen = {}
    local allowedJobs = getConfig().allowedJobs

    local function addJob(value)
        value = normalizeText(value, nil)
        if Utils.isBlank(value) then
            return
        end

        local key = value:lower()
        if seen[key] then
            return
        end

        seen[key] = true
        jobs[#jobs + 1] = value
    end

    if type(allowedJobs) == 'string' then
        addJob(allowedJobs)
    elseif type(allowedJobs) == 'table' then
        for index = 1, #allowedJobs do
            addJob(allowedJobs[index])
        end
    end

    if #jobs < 1 then
        jobs[#jobs + 1] = 'police'
    end

    return jobs
end

local function hasAllowedJob(record)
    local data = record and record.data or {}
    local jobName = resolveJobName(data.job)
    if Utils.isBlank(jobName) then
        return false, 'no_job'
    end

    local allowedJobs = getAllowedJobs()
    local normalizedJobName = jobName:lower()
    local matched = false

    for index = 1, #allowedJobs do
        local allowedJob = Utils.trim(allowedJobs[index])
        if not Utils.isBlank(allowedJob) and allowedJob:lower() == normalizedJobName then
            matched = true
            break
        end
    end

    if not matched then
        return false, 'job_not_allowed'
    end

    if getConfig().requireOnDuty == true and not isJobOnDuty(data.job) then
        return false, 'off_duty'
    end

    return true, jobName
end

local function requireOfficer(source)
    if not shouldEnable() then
        return nil, '罚单功能未启用', 'disabled'
    end

    local record = VancePay.Server.getPlayerRecord(source)
    if not record or Utils.isBlank(record.citizenid) then
        return nil, '未找到玩家身份', 'missing_citizenid'
    end

    local allowed, reason = hasAllowedJob(record)
    if not allowed then
        if reason == 'off_duty' then
            return nil, '你需要上班后才能开罚单', 'off_duty'
        end

        return nil, '你没有开罚单权限', 'forbidden'
    end

    return record
end

local function sanitizeReason(value)
    value = tostring(value or '')
    value = value:gsub('[\r\n]+', ' ')
    value = value:gsub('%s+', ' ')
    value = Utils.trim(value)

    local maxLength = math.max(math.floor(tonumber(getConfig().maxReasonLength) or 160), 1)
    value = Utils.truncateUtf8(value, maxLength)
    return Utils.trim(value)
end

local function getMinAmount()
    return Utils.roundCurrency(math.max(tonumber(getConfig().minAmount) or 1, 1))
end

local function getMaxAmount()
    return Utils.roundCurrency(math.max(tonumber(getConfig().maxAmount) or 50000, getMinAmount()))
end

local function sanitizeAmount(value)
    local amount = Utils.roundCurrency(Utils.ensureNumber(value, 0))
    if amount < getMinAmount() or amount > getMaxAmount() then
        return nil
    end

    return amount
end

local function getTicketItem()
    local itemName = Utils.trim(getConfig().ticketItem)
    if Utils.isBlank(itemName) then
        return 'vp_police_ticket'
    end

    return itemName
end

function PoliceTickets.getTicketBookItem()
    local itemName = Utils.trim(getConfig().ticketBookItem)
    if Utils.isBlank(itemName) then
        return 'vp_ticket_book'
    end

    return itemName
end

function PoliceTickets.getManagementTabletItem()
    local itemName = Utils.trim(getConfig().managementTabletItem)
    if Utils.isBlank(itemName) then
        return 'vp_ticket_tablet'
    end

    return itemName
end

local function getPaymentAccount()
    local account = Utils.trim(getConfig().paymentAccount)
    if Utils.isBlank(account) then
        return 'police'
    end

    return account
end

local function getTargetDistance()
    return math.max(tonumber(getConfig().targetDistance) or Config.TargetingDistance or 3.0, 1.0)
end

local function computeCreditImpact(amount)
    local creditConfig = getCreditConfig()
    if creditConfig.enabled == false then
        return 0
    end

    amount = Utils.roundCurrency(amount)
    local bands = creditConfig.bands
    if type(bands) ~= 'table' then
        return 0
    end

    for index = 1, #bands do
        local band = bands[index]
        if type(band) == 'table' then
            local minAmount = Utils.roundCurrency(tonumber(band.min) or 0)
            local maxAmount = band.max ~= nil and Utils.roundCurrency(tonumber(band.max) or 0) or nil

            if amount >= minAmount and (not maxAmount or amount <= maxAmount) then
                local impact = math.floor(tonumber(band.impact) or 0)
                if impact > 0 then
                    impact = -impact
                end

                return impact
            end
        end
    end

    return 0
end

local function shouldCreateCreditEvent(impact)
    return getCreditConfig().enabled ~= false and tonumber(impact) and tonumber(impact) ~= 0
end

local function buildCreditPayload(ticket, impact, paid)
    local creditConfig = getCreditConfig()
    local eventType = Utils.trim(creditConfig.eventType)
    if Utils.isBlank(eventType) then
        eventType = 'police_ticket'
    end

    local status = paid and 'paid' or 'unpaid'
    local ticketAgency = getAgencyDefinition(ticket.ticket_agency)
    local title = paid and ('VancePay %s 罚单（已缴纳）'):format(ticketAgency.label) or ('VancePay %s 罚单'):format(ticketAgency.label)
    local summary = paid
        and ('%s 罚单 %s 已缴纳，金额 %s。'):format(ticketAgency.label, ticket.ticket_code, Utils.formatCurrency(ticket.amount))
        or ('%s 罚单 %s 未缴纳，金额 %s。'):format(ticketAgency.label, ticket.ticket_code, Utils.formatCurrency(ticket.amount))

    return {
        citizenid = ticket.target_citizenid,
        source_resource = 'VancePay',
        source_ref = ticket.ticket_code,
        event_type = eventType,
        impact = impact,
        title = title,
        summary = summary,
        metadata = {
            status = status,
            payment_status = status,
            ticket_id = ticket.id,
            ticket_code = ticket.ticket_code,
            amount = ticket.amount,
            reason = ticket.reason,
            ticket_type = ticket.ticket_type,
            ticket_style = ticket.ticket_style,
            ticket_agency = ticket.ticket_agency,
            agency_label = ticketAgency.label,
            officer_citizenid = ticket.officer_citizenid,
            officer_name = ticket.officer_name_snapshot,
            target_citizenid = ticket.target_citizenid,
            target_name = ticket.target_name_snapshot,
            created_at = ticket.created_at,
            paid_at = paid and os.date('!%Y-%m-%dT%H:%M:%SZ') or nil,
        },
    }
end

local function createCreditEvent(ticket)
    if not shouldCreateCreditEvent(ticket and ticket.ctifo_credit_impact) then
        return nil, nil
    end

    local ok, result, err = callCtifoExport('CreateCreditEvent', buildCreditPayload(ticket, ticket.ctifo_credit_impact, false))
    if not ok then
        return nil, err
    end

    local parsedOk, event, parseErr = parseCreditEventResult(result)
    if not parsedOk then
        return nil, parseErr or 'ctifo_error'
    end

    return event
end

local function syncPaidCreditEvent(ticket)
    local creditConfig = getCreditConfig()
    if creditConfig.enabled == false or not ticket or Utils.isBlank(ticket.ticket_code) then
        return nil, nil
    end

    if creditConfig.paidKeepsImpact == true then
        local paidImpact = math.floor(tonumber(creditConfig.paidImpact) or 0)
        if paidImpact > 0 then
            paidImpact = -paidImpact
        end

        local ok, result, err = callCtifoExport('CreateCreditEvent', buildCreditPayload(ticket, paidImpact, true))
        if not ok then
            return nil, err
        end

        local parsedOk, event, parseErr = parseCreditEventResult(result)
        if not parsedOk then
            return nil, parseErr or 'ctifo_error'
        end

        return event
    end

    local ok, result, err = callCtifoExport('ResolveCreditEvent', {
        source_resource = 'VancePay',
        source_ref = ticket.ticket_code,
    })
    if not ok then
        return nil, err
    end

    local parsedOk, event, parseErr = parseCreditEventResult(result)
    if not parsedOk then
        return nil, parseErr or 'ctifo_error'
    end

    return event
end

local function getItemMetadata(item)
    if type(item) ~= 'table' then
        return {}
    end

    if type(item.metadata) == 'table' then
        return Utils.deepCopy(item.metadata)
    end

    if type(item.info) == 'table' then
        return Utils.deepCopy(item.info)
    end

    return {}
end

local function resolveItemSlot(source, itemName, item, metadata)
    local slot = tonumber(item and (item.slot or item.slot_id or item.slotId))
    if slot then
        return slot
    end

    local ticketCode = Utils.trim(metadata and metadata.ticket_code)
    if not Utils.isBlank(ticketCode) then
        local ok, slotId = pcall(function()
            return exports.ox_inventory:GetSlotIdWithItem(source, itemName, {
                ticket_code = ticketCode,
            }, false)
        end)

        if ok and slotId then
            return tonumber(slotId)
        end
    end

    local ok, slotData = pcall(function()
        return exports.ox_inventory:GetSlotWithItem(source, itemName, metadata, false)
    end)

    if ok and slotData and slotData.slot then
        return tonumber(slotData.slot)
    end

    return nil
end

local function syncItemMetadata(source, itemName, item, metadata)
    local slot = resolveItemSlot(source, itemName, item, metadata)
    if not slot then
        return false
    end

    local ok, err = pcall(function()
        exports.ox_inventory:SetMetadata(source, slot, metadata)
    end)

    if not ok then
        Utils.debug('Failed to sync police ticket metadata', itemName, source, err)
        return false
    end

    return true
end

local function getTicketTypeLabel(value)
    value = sanitizeTicketType(value)
    local options = getTicketTypeOptions()
    for index = 1, #options do
        if options[index].value == value then
            return options[index].label
        end
    end

    return value == 'traffic' and '交通违法处罚单' or '行政处罚告知单'
end

local function getTicketStyleLabel(value)
    value = sanitizeTicketStyle(value)
    local options = getTicketStyleOptions()
    for index = 1, #options do
        if options[index].value == value then
            return options[index].label
        end
    end

    return value == 'carbon' and '碳复写纸' or '泛黄纸张'
end

local function buildTicketMetadata(ticket)
    if not ticket then
        return {}
    end

    local ticketType = sanitizeTicketType(ticket.ticket_type)
    local ticketStyle = sanitizeTicketStyle(ticket.ticket_style)
    local ticketAgency = getAgencyDefinition(ticket.ticket_agency)

    return {
        label = ('%s 罚单 %s'):format(ticketAgency.label, ticket.ticket_code),
        description = ('%s | %s | %s | %s'):format(
            ticket.status == 'paid' and '已缴纳' or (ticket.status == 'cancelled' and '已取消' or '未缴纳'),
            Utils.formatCurrency(ticket.amount),
            ticketAgency.label,
            Utils.truncateUtf8(ticket.reason or '', 42) or ''
        ),
        ticket_code = ticket.ticket_code,
        status = ticket.status,
        amount = ticket.amount,
        reason = ticket.reason,
        ticket_type = ticketType,
        ticket_style = ticketStyle,
        ticket_agency = ticketAgency.key,
        ticket_type_label = getTicketTypeLabel(ticketType),
        ticket_style_label = getTicketStyleLabel(ticketStyle),
        agency_label = ticketAgency.label,
        agency_subtitle = ticketAgency.subtitle,
        agency_badge = ticketAgency.badge,
        agency_watermark = ticketAgency.watermark,
        agency_code_prefix = ticketAgency.code_prefix,
        agency_class_name = ticketAgency.class_name,
        agency_theme = Utils.deepCopy(ticketAgency.theme),
        officer_citizenid = ticket.officer_citizenid,
        officer_name = ticket.officer_name_snapshot,
        target_citizenid = ticket.target_citizenid,
        target_name = ticket.target_name_snapshot,
        ctifo_credit_impact = ticket.ctifo_credit_impact,
        created_at = ticket.created_at,
        paid_at = ticket.paid_at,
    }
end

local function giveTicketItem(source, ticket)
    local itemName = getTicketItem()
    local metadata = buildTicketMetadata(ticket)

    local canCarryOk, canCarry = pcall(function()
        return exports.ox_inventory:CanCarryItem(source, itemName, 1, metadata)
    end)

    if canCarryOk and canCarry == false then
        return false, '被罚人背包空间不足'
    end

    local addOk, success, response = pcall(function()
        return exports.ox_inventory:AddItem(source, itemName, 1, metadata)
    end)

    if not addOk then
        Utils.debug('Failed to give police ticket item', itemName, source, success)
        return false, '发放纸质罚单时调用库存失败'
    end

    if success == false then
        return false, response or '纸质罚单发放失败'
    end

    return true
end

local function fetchTicketByCode(ticketCode)
    ticketCode = Utils.trim(ticketCode)
    if Utils.isBlank(ticketCode) then
        return nil
    end

    local row = MySQL.single.await([[
        SELECT *
        FROM vancepay_police_tickets
        WHERE ticket_code = ?
        LIMIT 1
    ]], { ticketCode })

    return normalizeTicket(row)
end

local function fetchTicketForItem(source, item)
    local metadata = getItemMetadata(item)
    local ticketCode = Utils.trim(metadata.ticket_code or metadata.ticketCode)
    if Utils.isBlank(ticketCode) then
        return nil, '这张罚单缺少编号', 'missing_ticket_code', metadata
    end

    local ticket = fetchTicketByCode(ticketCode)
    if not ticket then
        return nil, '罚单记录不存在', 'ticket_not_found', metadata
    end

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) then
        return nil, '未找到玩家身份', 'missing_citizenid', metadata
    end

    if ticket.target_citizenid ~= citizenid and not VancePay.Permissions.isAdmin(source) then
        return nil, '这张罚单不属于你', 'forbidden', metadata
    end

    return ticket, nil, nil, metadata
end

local function buildTicketPayload(ticket, item)
    local metadata = getItemMetadata(item)
    local paidKeepsImpact = getCreditConfig().paidKeepsImpact == true
    local itemCopy = item and Utils.deepCopy(item) or {}
    local latestMetadata = buildTicketMetadata(ticket)
    local mergedMetadata = Utils.deepCopy(metadata)

    for key, value in pairs(latestMetadata) do
        mergedMetadata[key] = value
    end

    itemCopy.metadata = Utils.deepCopy(mergedMetadata)
    itemCopy.info = Utils.deepCopy(mergedMetadata)

    return {
        ticket = ticket,
        item_name = getTicketItem(),
        item = itemCopy,
        metadata = mergedMetadata,
        ticket_types = getTicketTypeOptions(),
        ticket_styles = getTicketStyleOptions(),
        agencies = getAgencyOptions(),
        credit = {
            enabled = getCreditConfig().enabled ~= false,
            paid_keeps_impact = paidKeepsImpact,
            paid_impact = paidKeepsImpact and math.floor(tonumber(getCreditConfig().paidImpact) or 0) or 0,
        },
    }
end

local function getTicketStatusLabel(status)
    local labels = {
        unpaid = '未缴纳',
        paid = '已缴纳',
        cancelled = '已取消',
    }

    return labels[status] or '未缴纳'
end

local function sanitizeManagerNote(value)
    value = tostring(value or '')
    value = value:gsub('[\r\n]+', ' ')
    value = value:gsub('%s+', ' ')
    value = Utils.trim(value)

    if Utils.isBlank(value) then
        return nil
    end

    value = Utils.truncateUtf8(value, 180)
    return Utils.trim(value)
end

local function isJobBossData(job)
    if type(job) ~= 'table' then
        return false
    end

    local grade = type(job.grade) == 'table' and job.grade or {}
    return Utils.parseBool(job.isboss)
        or Utils.parseBool(job.isBoss)
        or Utils.parseBool(job.boss)
        or Utils.parseBool(grade.isboss)
        or Utils.parseBool(grade.isBoss)
        or Utils.parseBool(grade.boss)
end

local function sanitizeDateFilter(value)
    value = Utils.trim(value)
    if Utils.isBlank(value) then
        return nil
    end

    value = tostring(value):gsub('T', ' ')
    local dateOnly = value:match('^(%d%d%d%d%-%d%d%-%d%d)$')
    if dateOnly then
        return dateOnly, true
    end

    local dateTime = value:match('^(%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d:%d%d)')
    if dateTime then
        return dateTime, false
    end

    local dateTimeShort = value:match('^(%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d)')
    if dateTimeShort then
        return dateTimeShort .. ':00', false
    end

    return nil
end

local function normalizeManagerFilters(filters)
    filters = type(filters) == 'table' and filters or {}
    local requestedPage = math.max(math.floor(tonumber(filters.page) or 1), 1)
    local perPage = math.min(math.max(math.floor(tonumber(filters.per_page or filters.limit) or Config.TransPerPage), 1), 50)
    local status = Utils.trim(filters.status)
    if Utils.isBlank(status) or status == 'all' then
        status = nil
    end

    if status ~= 'unpaid' and status ~= 'paid' and status ~= 'cancelled' then
        status = nil
    end

    local agency = normalizeAgencyKey(filters.ticket_agency or filters.agency or filters.agency_key)
    local search = Utils.trim(filters.search or filters.query)
    if Utils.isBlank(search) then
        search = nil
    else
        search = Utils.truncateUtf8(search, 64)
        search = Utils.trim(search)
    end

    local dateFrom = sanitizeDateFilter(filters.date_from or filters.dateFrom)
    local dateTo, dateToIsDateOnly = sanitizeDateFilter(filters.date_to or filters.dateTo)

    return {
        page = requestedPage,
        per_page = perPage,
        status = status,
        agency = agency,
        search = search,
        date_from = dateFrom,
        date_to = dateTo,
        date_to_is_date_only = dateToIsDateOnly == true,
    }
end

local function copyArray(values)
    local copied = {}
    for index = 1, #(values or {}) do
        copied[index] = values[index]
    end

    return copied
end

local function requireManagerContext(source)
    local schemaAvailable, schemaError = ensureSchemaAvailable()
    if not schemaAvailable then
        return nil, VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    if not shouldEnable() then
        return nil, VancePay.Server.fail('罚单功能未启用', 'disabled')
    end

    local record = VancePay.Server.getPlayerRecord(source)
    if not record or Utils.isBlank(record.citizenid) then
        return nil, VancePay.Server.fail('未找到玩家身份', 'missing_citizenid')
    end

    if VancePay.Permissions.isAdmin(source) then
        return {
            source = source,
            citizenid = record.citizenid,
            name = record.name,
            record = record,
            is_admin = true,
            is_boss = true,
            can_audit = true,
            can_global = true,
            agency = getDefaultAgency(),
            job_name = resolveJobName(record.data and record.data.job),
        }
    end

    local allowed, jobNameOrReason = hasAllowedJob(record)
    if not allowed then
        if jobNameOrReason == 'off_duty' then
            return nil, VancePay.Server.fail('你需要上班后才能使用罚单管理平板', 'off_duty')
        end

        return nil, VancePay.Server.fail('你没有罚单管理权限', 'forbidden')
    end

    local agency = getAgencyForJob(jobNameOrReason)
    local isBoss = VancePay.Permissions.isJobBoss(source, jobNameOrReason) or isJobBossData(record.data and record.data.job)
    return {
        source = source,
        citizenid = record.citizenid,
        name = record.name,
        record = record,
        is_admin = false,
        is_boss = isBoss,
        can_audit = isBoss,
        can_global = false,
        agency = agency,
        job_name = jobNameOrReason,
    }
end

local function getManageableAgencies(context)
    if context and context.is_admin then
        return getAgencyOptions()
    end

    return context and context.agency and { Utils.deepCopy(context.agency) } or {}
end

local function buildManagerScopePayload(context)
    local agency = context.agency or getDefaultAgency()
    return {
        is_admin = context.is_admin == true,
        is_boss = context.is_boss == true,
        can_audit = context.can_audit == true,
        can_global = context.can_global == true,
        citizenid = context.citizenid,
        name = context.name,
        job_name = context.job_name,
        agency_key = agency.key,
        agency_label = agency.label,
        title = context.is_admin and '全局罚单管理' or ((agency.label or '执法机构') .. '罚单管理'),
        subtitle = context.is_admin and '管理员可以查看和管理全部执法机构罚单' or '仅显示当前职业对应执法机构开具的罚单',
    }
end

local function buildManagedTicketItem(ticket)
    if not ticket then
        return nil
    end

    local item = Utils.deepCopy(ticket)
    local agency = getAgencyDefinition(item.ticket_agency)
    item.ticket_type_label = getTicketTypeLabel(item.ticket_type)
    item.ticket_style_label = getTicketStyleLabel(item.ticket_style)
    item.status_label = getTicketStatusLabel(item.status)
    item.agency_label = agency.label
    item.agency_badge = agency.badge
    item.agency_subtitle = agency.subtitle
    item.can_cancel = item.status == 'unpaid'
    item.can_restore = item.status == 'cancelled'
    item.can_mark_unpaid = item.status == 'cancelled'
    return item
end

local function appendTicketManagerConditions(conditions, params, context, filters, options)
    options = options or {}

    if not context.is_admin then
        conditions[#conditions + 1] = 'ticket_agency = ?'
        params[#params + 1] = context.agency.key
    elseif not Utils.isBlank(filters.agency) then
        conditions[#conditions + 1] = 'ticket_agency = ?'
        params[#params + 1] = sanitizeTicketAgency(filters.agency)
    end

    if options.include_status ~= false and not Utils.isBlank(filters.status) then
        conditions[#conditions + 1] = 'status = ?'
        params[#params + 1] = filters.status
    end

    if not Utils.isBlank(filters.search) then
        local like = '%' .. filters.search .. '%'
        conditions[#conditions + 1] = [[
            (
                ticket_code LIKE ?
                OR officer_citizenid LIKE ?
                OR officer_name_snapshot LIKE ?
                OR target_citizenid LIKE ?
                OR target_name_snapshot LIKE ?
                OR reason LIKE ?
            )
        ]]
        for _ = 1, 6 do
            params[#params + 1] = like
        end
    end

    if not Utils.isBlank(filters.date_from) then
        conditions[#conditions + 1] = 'created_at >= ?'
        params[#params + 1] = filters.date_from
    end

    if not Utils.isBlank(filters.date_to) then
        if filters.date_to_is_date_only then
            conditions[#conditions + 1] = 'created_at < DATE_ADD(?, INTERVAL 1 DAY)'
        else
            conditions[#conditions + 1] = 'created_at <= ?'
        end
        params[#params + 1] = filters.date_to
    end
end

local function listManagedTickets(context, rawFilters)
    local filters = normalizeManagerFilters(rawFilters)
    local conditions = { '1=1' }
    local params = {}
    appendTicketManagerConditions(conditions, params, context, filters, {
        include_status = true,
    })

    local whereSql = table.concat(conditions, ' AND ')
    local totalRow = MySQL.single.await(('SELECT COUNT(*) AS total FROM %s WHERE %s'):format(TABLE_NAME, whereSql), params) or {}
    local total = tonumber(totalRow.total) or 0
    local totalPages = math.max(math.ceil(total / filters.per_page), 1)
    local page = math.min(filters.page, totalPages)
    local offset = (page - 1) * filters.per_page
    local queryParams = copyArray(params)
    local limit = math.floor(filters.per_page)
    local offsetValue = math.floor(offset)

    local rows = MySQL.query.await(([[
        SELECT *
        FROM %s
        WHERE %s
        ORDER BY id DESC
        LIMIT %d OFFSET %d
    ]]):format(TABLE_NAME, whereSql, limit, offsetValue), queryParams) or {}

    local items = {}
    for index = 1, #rows do
        local ticket = normalizeTicket(rows[index])
        if ticket then
            items[#items + 1] = buildManagedTicketItem(ticket)
        end
    end

    return {
        items = items,
        page = page,
        per_page = filters.per_page,
        total = total,
        total_pages = totalPages,
        has_prev = page > 1,
        has_more = page < totalPages,
        filters = filters,
    }
end

local function buildManagerSummary(context, rawFilters)
    local filters = normalizeManagerFilters(rawFilters)
    local conditions = { '1=1' }
    local params = {}
    appendTicketManagerConditions(conditions, params, context, filters, {
        include_status = false,
    })

    local row = MySQL.single.await(([[
        SELECT
            COUNT(*) AS total_count,
            COALESCE(SUM(amount), 0) AS total_amount,
            COALESCE(SUM(CASE WHEN status = 'unpaid' THEN 1 ELSE 0 END), 0) AS unpaid_count,
            COALESCE(SUM(CASE WHEN status = 'paid' THEN 1 ELSE 0 END), 0) AS paid_count,
            COALESCE(SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END), 0) AS cancelled_count,
            COALESCE(SUM(CASE WHEN status = 'unpaid' THEN amount ELSE 0 END), 0) AS unpaid_amount,
            COALESCE(SUM(CASE WHEN status = 'paid' THEN amount ELSE 0 END), 0) AS paid_amount,
            COALESCE(SUM(CASE WHEN status = 'cancelled' THEN amount ELSE 0 END), 0) AS cancelled_amount
        FROM %s
        WHERE %s
    ]]):format(TABLE_NAME, table.concat(conditions, ' AND ')), params) or {}

    return {
        total_count = tonumber(row.total_count) or 0,
        total_amount = Utils.roundCurrency(row.total_amount or 0),
        unpaid_count = tonumber(row.unpaid_count) or 0,
        paid_count = tonumber(row.paid_count) or 0,
        cancelled_count = tonumber(row.cancelled_count) or 0,
        unpaid_amount = Utils.roundCurrency(row.unpaid_amount or 0),
        paid_amount = Utils.roundCurrency(row.paid_amount or 0),
        cancelled_amount = Utils.roundCurrency(row.cancelled_amount or 0),
    }
end

local function normalizeAuditFilters(filters)
    filters = type(filters) == 'table' and filters or {}
    local requestedPage = math.max(math.floor(tonumber(filters.page) or 1), 1)
    local perPage = math.min(math.max(math.floor(tonumber(filters.per_page or filters.limit) or Config.TransPerPage), 1), 50)
    local agency = normalizeAgencyKey(filters.ticket_agency or filters.agency or filters.agency_key)
    local search = Utils.trim(filters.search or filters.query)
    if Utils.isBlank(search) then
        search = nil
    else
        search = Utils.trim(Utils.truncateUtf8(search, 64))
    end

    return {
        page = requestedPage,
        per_page = perPage,
        agency = agency,
        search = search,
    }
end

local function appendAuditManagerConditions(conditions, params, context, filters)
    conditions[#conditions + 1] = "a.target_type = 'police_ticket'"

    if not context.is_admin then
        conditions[#conditions + 1] = 't.ticket_agency = ?'
        params[#params + 1] = context.agency.key
    elseif not Utils.isBlank(filters.agency) then
        conditions[#conditions + 1] = 't.ticket_agency = ?'
        params[#params + 1] = sanitizeTicketAgency(filters.agency)
    end

    if not Utils.isBlank(filters.search) then
        local like = '%' .. filters.search .. '%'
        conditions[#conditions + 1] = '(a.actor_citizenid LIKE ? OR a.action LIKE ? OR a.target_id LIKE ?)'
        params[#params + 1] = like
        params[#params + 1] = like
        params[#params + 1] = like
    end
end

local function listManagedAuditLogs(context, rawFilters)
    if not context.can_audit then
        return {
            items = {},
            page = 1,
            per_page = Config.TransPerPage,
            total = 0,
            total_pages = 1,
            has_prev = false,
            has_more = false,
        }
    end

    local filters = normalizeAuditFilters(rawFilters)
    local conditions = {}
    local params = {}
    appendAuditManagerConditions(conditions, params, context, filters)
    local whereSql = table.concat(conditions, ' AND ')
    local countParams = copyArray(params)
    local totalRow = MySQL.single.await(([[
        SELECT COUNT(*) AS total
        FROM vancepay_audit_logs a
        LEFT JOIN %s t ON t.ticket_code = a.target_id
        WHERE %s
    ]]):format(TABLE_NAME, whereSql), countParams) or {}
    local total = tonumber(totalRow.total) or 0
    local totalPages = math.max(math.ceil(total / filters.per_page), 1)
    local page = math.min(filters.page, totalPages)
    local offset = (page - 1) * filters.per_page
    local queryParams = copyArray(params)
    local limit = math.floor(filters.per_page)
    local offsetValue = math.floor(offset)

    local rows = MySQL.query.await(([[
        SELECT a.*
        FROM vancepay_audit_logs a
        LEFT JOIN %s t ON t.ticket_code = a.target_id
        WHERE %s
        ORDER BY a.id DESC
        LIMIT %d OFFSET %d
    ]]):format(TABLE_NAME, whereSql, limit, offsetValue), queryParams) or {}

    for index = 1, #rows do
        rows[index] = Utils.normalizeDbRow(rows[index])
    end

    return {
        items = rows,
        page = page,
        per_page = filters.per_page,
        total = total,
        total_pages = totalPages,
        has_prev = page > 1,
        has_more = page < totalPages,
        filters = filters,
    }
end

local function fetchManagedTicket(context, ticketCode)
    local ticket = fetchTicketByCode(ticketCode)
    if not ticket then
        return nil, VancePay.Server.fail('罚单不存在', 'ticket_not_found')
    end

    if not context.is_admin and ticket.ticket_agency ~= context.agency.key then
        return nil, VancePay.Server.fail('你不能管理其他职业机构开具的罚单', 'forbidden')
    end

    return ticket
end

local function resolveCancelledCreditEvent(ticket)
    local creditConfig = getCreditConfig()
    if creditConfig.enabled == false or not ticket or Utils.isBlank(ticket.ticket_code) then
        return nil, nil
    end

    local ok, result, err = callCtifoExport('ResolveCreditEvent', {
        source_resource = 'VancePay',
        source_ref = ticket.ticket_code,
    })
    if not ok then
        return nil, err
    end

    local parsedOk, event, parseErr = parseCreditEventResult(result)
    if not parsedOk then
        return nil, parseErr or 'ctifo_error'
    end

    return event
end

local function notifyManagedTicketChange(ticket, message, notifyType)
    if not ticket then
        return
    end

    local targetSource = VancePay.Server.getSourceByCitizenId(ticket.target_citizenid)
    if targetSource then
        VancePay.Server.notify(targetSource, message, notifyType or 'inform')
    end

    local officerSource = VancePay.Server.getSourceByCitizenId(ticket.officer_citizenid)
    if officerSource and officerSource ~= targetSource then
        VancePay.Server.notify(officerSource, message, notifyType or 'inform')
    end
end

local function syncManagedTicketItem(ticket)
    if not ticket or Utils.isBlank(ticket.target_citizenid) then
        return false
    end

    local targetSource = VancePay.Server.getSourceByCitizenId(ticket.target_citizenid)
    if not targetSource then
        return false
    end

    return syncItemMetadata(targetSource, getTicketItem(), {
        metadata = {
            ticket_code = ticket.ticket_code,
        },
    }, buildTicketMetadata(ticket))
end

local function logManagedTicketAction(context, source, action, ticket, detail)
    detail = type(detail) == 'table' and detail or {}
    detail.ticket_code = ticket.ticket_code
    detail.ticket_agency = ticket.ticket_agency
    detail.agency_label = getAgencyDefinition(ticket.ticket_agency).label
    detail.amount = ticket.amount
    detail.target_citizenid = ticket.target_citizenid
    detail.officer_citizenid = ticket.officer_citizenid

    if VancePay.Audit and VancePay.Audit.log then
        VancePay.Audit.log(context.citizenid, action, 'police_ticket', ticket.ticket_code, {
            source = source,
            detail = detail,
        })
    end

    if VancePay.FiveMLog and VancePay.FiveMLog.emit then
        VancePay.FiveMLog.emit('audit', ('police_ticket_%s'):format(action), 'VancePay police ticket management', {
            severity = action == 'cancel_police_ticket' and 'warning' or 'info',
            source = source,
            metadata = detail,
        })
    end
end

function PoliceTickets.getManagerBootstrap(source, payload)
    local context, contextError = requireManagerContext(source)
    if not context then
        return contextError
    end

    payload = type(payload) == 'table' and payload or {}
    local tickets = listManagedTickets(context, payload)
    local audit = context.can_audit and listManagedAuditLogs(context, {
        page = 1,
        per_page = Config.TransPerPage,
        agency = payload.agency or payload.ticket_agency,
    }) or nil

    return VancePay.Server.ok({
        scope = buildManagerScopePayload(context),
        agencies = getManageableAgencies(context),
        ticket_types = getTicketTypeOptions(),
        ticket_styles = getTicketStyleOptions(),
        filters = normalizeManagerFilters(payload),
        summary = buildManagerSummary(context, payload),
        tickets = tickets,
        audit = audit,
    })
end

function PoliceTickets.getManagerAudit(source, payload)
    local context, contextError = requireManagerContext(source)
    if not context then
        return contextError
    end

    if not context.can_audit then
        return VancePay.Server.fail('只有职业 Boss 或管理员可以查看罚单审计日志', 'forbidden')
    end

    return VancePay.Server.ok(listManagedAuditLogs(context, payload or {}))
end

function PoliceTickets.cancelManagedTicket(source, payload)
    local context, contextError = requireManagerContext(source)
    if not context then
        return contextError
    end

    payload = type(payload) == 'table' and payload or {}
    local ticketCode = Utils.trim(payload.ticket_code or payload.ticketCode)
    if Utils.isBlank(ticketCode) then
        return VancePay.Server.fail('缺少罚单编号', 'missing_ticket_code')
    end

    local ticket, ticketError = fetchManagedTicket(context, ticketCode)
    if not ticket then
        return ticketError
    end

    if ticket.status == 'paid' then
        return VancePay.Server.fail('已缴纳罚单不能在平板内取消，请通过管理员线下处理退款', 'invalid_status')
    end

    if ticket.status == 'cancelled' then
        return VancePay.Server.ok({
            ticket = buildManagedTicketItem(ticket),
        }, '该罚单已经取消')
    end

    local note = sanitizeManagerNote(payload.note or payload.reason)
    local updated = MySQL.update.await([[
        UPDATE vancepay_police_tickets
        SET status = 'cancelled'
        WHERE id = ?
            AND status = 'unpaid'
    ]], { ticket.id })

    if not updated or updated < 1 then
        return VancePay.Server.fail('罚单状态已变化，请刷新后重试', 'stale_status')
    end

    local updatedTicket = fetchTicketByCode(ticket.ticket_code) or ticket
    local metadataWritten = syncManagedTicketItem(updatedTicket)
    local event, eventErr = resolveCancelledCreditEvent(updatedTicket)
    local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)
    logManagedTicketAction(context, source, 'cancel_police_ticket', updatedTicket, {
        previous_status = ticket.status,
        new_status = updatedTicket.status,
        note = note,
        metadata_written = metadataWritten,
        ctifo_credit_event_id = eventId or updatedTicket.ctifo_credit_event_id,
        ctifo_error = eventErr,
    })
    notifyManagedTicketChange(updatedTicket, ('罚单 %s 已取消'):format(updatedTicket.ticket_code), 'warning')

    return VancePay.Server.ok({
        ticket = buildManagedTicketItem(updatedTicket),
        metadata_written = metadataWritten,
        ctifo_credit_event = event,
        ctifo_credit_error = eventErr,
    }, eventErr and '罚单已取消，但信誉事件同步失败' or '罚单已取消')
end

function PoliceTickets.restoreManagedTicket(source, payload)
    local context, contextError = requireManagerContext(source)
    if not context then
        return contextError
    end

    payload = type(payload) == 'table' and payload or {}
    local ticketCode = Utils.trim(payload.ticket_code or payload.ticketCode)
    if Utils.isBlank(ticketCode) then
        return VancePay.Server.fail('缺少罚单编号', 'missing_ticket_code')
    end

    local ticket, ticketError = fetchManagedTicket(context, ticketCode)
    if not ticket then
        return ticketError
    end

    if ticket.status ~= 'cancelled' then
        return VancePay.Server.fail('只有已取消罚单可以恢复为未缴纳', 'invalid_status')
    end

    local note = sanitizeManagerNote(payload.note or payload.reason)
    local updated = MySQL.update.await([[
        UPDATE vancepay_police_tickets
        SET status = 'unpaid',
            paid_at = NULL
        WHERE id = ?
            AND status = 'cancelled'
    ]], { ticket.id })

    if not updated or updated < 1 then
        return VancePay.Server.fail('罚单状态已变化，请刷新后重试', 'stale_status')
    end

    local updatedTicket = fetchTicketByCode(ticket.ticket_code) or ticket
    local metadataWritten = syncManagedTicketItem(updatedTicket)
    local event, eventErr = createCreditEvent(updatedTicket)
    local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)
    if eventId then
        MySQL.update.await([[
            UPDATE vancepay_police_tickets
            SET ctifo_credit_event_id = ?
            WHERE id = ?
                AND ctifo_credit_event_id IS NULL
        ]], { eventId, updatedTicket.id })
        updatedTicket.ctifo_credit_event_id = eventId
    end

    logManagedTicketAction(context, source, 'restore_police_ticket', updatedTicket, {
        previous_status = ticket.status,
        new_status = updatedTicket.status,
        note = note,
        metadata_written = metadataWritten,
        ctifo_credit_event_id = eventId or updatedTicket.ctifo_credit_event_id,
        ctifo_error = eventErr,
    })
    notifyManagedTicketChange(updatedTicket, ('罚单 %s 已恢复为未缴纳'):format(updatedTicket.ticket_code), 'warning')

    return VancePay.Server.ok({
        ticket = buildManagedTicketItem(updatedTicket),
        metadata_written = metadataWritten,
        ctifo_credit_event = event,
        ctifo_credit_error = eventErr,
    }, eventErr and '罚单已恢复，但信誉事件同步失败' or '罚单已恢复为未缴纳')
end

function PoliceTickets.openManager(source, item)
    local response = PoliceTickets.safeManagerBootstrap(source, {})
    if not response or not response.ok then
        VancePay.Server.notify(source, response and response.message or '罚单管理平板初始化失败', 'error')
        return false
    end

    TriggerClientEvent(VancePay.Events.client.openPoliceTicketManager, source, {
        item_name = PoliceTickets.getManagementTabletItem(),
        item = type(item) == 'table' and Utils.deepCopy(item) or {},
        bootstrap = response.data,
    })

    return true
end

function PoliceTickets.openManagerCommand(source)
    return PoliceTickets.openManager(source, {
        command_launch = true,
    })
end

function PoliceTickets.safeManagerBootstrap(source, payload)
    local ok, response = pcall(function()
        return PoliceTickets.getManagerBootstrap(source, payload or {})
    end)

    if ok then
        return response
    end

    Utils.debug('Police ticket manager bootstrap failed', response)
    return VancePay.Server.fail('罚单管理平板初始化失败，请检查数据库迁移和服务器控制台错误', 'bootstrap_error')
end

function PoliceTickets.getTicketDetail(source, item)
    local schemaAvailable, schemaError = ensureSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local ticket, message, code = fetchTicketForItem(source, item or {})
    if not ticket then
        return VancePay.Server.fail(message or '罚单读取失败', code or 'ticket_error')
    end

    return VancePay.Server.ok(buildTicketPayload(ticket, item or {}))
end

function PoliceTickets.create(source, payload)
    local schemaAvailable, schemaError = ensureSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    local officer, officerError, officerCode = requireOfficer(source)
    if not officer then
        return VancePay.Server.fail(officerError, officerCode)
    end

    payload = type(payload) == 'table' and payload or {}
    local targetSource = tonumber(payload.target_source or payload.targetSource or payload.source)
    if not targetSource or targetSource < 1 or targetSource == source then
        return VancePay.Server.fail('请选择被罚玩家', 'invalid_target')
    end

    local target = VancePay.Server.getPlayerRecord(targetSource)
    if not target or Utils.isBlank(target.citizenid) then
        return VancePay.Server.fail('被罚玩家不在线或身份读取失败', 'target_not_found')
    end

    local nearby = VancePay.Server.safeClientCallback('vancepay:client:isSourceNearby', source, {
        source = targetSource,
        distance = getTargetDistance(),
    })
    if nearby ~= true then
        return VancePay.Server.fail('被罚玩家不在开票范围内', 'out_of_range')
    end

    local amount = sanitizeAmount(payload.amount)
    if not amount then
        return VancePay.Server.fail(
            ('罚单金额必须在 %s 到 %s 之间'):format(Utils.formatCurrency(getMinAmount()), Utils.formatCurrency(getMaxAmount())),
            'invalid_amount'
        )
    end

    local reason = sanitizeReason(payload.reason)
    if Utils.isBlank(reason) then
        return VancePay.Server.fail('请填写罚单原因', 'missing_reason')
    end

    local ticketType = sanitizeTicketType(payload.ticket_type or payload.ticketType)
    local ticketStyle = sanitizeTicketStyle(payload.ticket_style or payload.ticketStyle)
    local ticketAgency = getAgencyForJob(resolveJobName(officer.data and officer.data.job))
    local ticketCode = Utils.generateCode('PF', 10)
    local impact = computeCreditImpact(amount)
    local insertedId = MySQL.insert.await([[
        INSERT INTO vancepay_police_tickets (
            ticket_code,
            officer_citizenid,
            officer_name_snapshot,
            target_citizenid,
            target_name_snapshot,
            amount,
            reason,
            ticket_type,
            ticket_style,
            ticket_agency,
            status,
            ctifo_credit_impact
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'unpaid', ?)
    ]], {
        ticketCode,
        officer.citizenid,
        officer.name,
        target.citizenid,
        target.name,
        amount,
        reason,
        ticketType,
        ticketStyle,
        ticketAgency.key,
        impact,
    })

    if not insertedId then
        return VancePay.Server.fail('罚单创建失败', 'db_error')
    end

    local ticket = fetchTicketByCode(ticketCode)
    local itemGiven, itemError = giveTicketItem(targetSource, ticket)
    if not itemGiven then
        MySQL.update.await([[
            UPDATE vancepay_police_tickets
            SET status = 'cancelled'
            WHERE id = ?
        ]], { insertedId })
        return VancePay.Server.fail(itemError or '纸质罚单发放失败', 'inventory_error')
    end

    local event, eventErr = createCreditEvent(ticket)
    local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)
    if eventId then
        MySQL.update.await([[
            UPDATE vancepay_police_tickets
            SET ctifo_credit_event_id = ?
            WHERE id = ?
                AND ctifo_credit_event_id IS NULL
        ]], { eventId, ticket.id })
        ticket.ctifo_credit_event_id = eventId
    elseif eventErr then
        Utils.debug('Police ticket credit event create failed', ticket.ticket_code, eventErr)
    end

    if VancePay.Audit and VancePay.Audit.log then
        VancePay.Audit.log(officer.citizenid, 'create_police_ticket', 'police_ticket', ticket.ticket_code, {
            source = source,
            detail = {
                ticket_code = ticket.ticket_code,
                target_citizenid = target.citizenid,
                target_name = target.name,
                amount = amount,
                reason = reason,
                ticket_type = ticketType,
                ticket_style = ticketStyle,
                ticket_agency = ticketAgency.key,
                agency_label = ticketAgency.label,
                ctifo_credit_impact = impact,
                ctifo_credit_event_id = ticket.ctifo_credit_event_id,
                ctifo_error = eventErr,
            },
        })
    end

    if VancePay.FiveMLog and VancePay.FiveMLog.emit then
        VancePay.FiveMLog.emit('transactions', 'police_ticket_created', 'VancePay police ticket created', {
            severity = 'warning',
            source = source,
            metadata = {
                ticket_code = ticket.ticket_code,
                officer_citizenid = officer.citizenid,
                target_citizenid = target.citizenid,
                amount = amount,
                reason = reason,
                ticket_type = ticketType,
                ticket_style = ticketStyle,
                ticket_agency = ticketAgency.key,
                agency_label = ticketAgency.label,
                ctifo_credit_impact = impact,
            },
        })
    end

    local issuedPayload = buildTicketPayload(ticket, {
        metadata = buildTicketMetadata(ticket),
    })
    issuedPayload.just_issued = true

    VancePay.Server.notify(targetSource, ('你收到一张罚单：%s'):format(Utils.formatCurrency(amount)), 'warning')
    TriggerClientEvent(VancePay.Events.client.openPoliceTicket, targetSource, issuedPayload)
    VancePay.Server.notify(source, ('罚单 %s 已开具'):format(ticket.ticket_code), 'success')

    return VancePay.Server.ok({
        ticket = ticket,
        ticket_payload = issuedPayload,
        ctifo_credit_event = event,
        ctifo_credit_error = eventErr,
    }, '罚单已开具')
end

function PoliceTickets.pay(source, item)
    local schemaAvailable, schemaError = ensureSchemaAvailable()
    if not schemaAvailable then
        return VancePay.Server.fail(schemaError, 'db_schema_outdated')
    end

    item = type(item) == 'table' and item or {}
    local ticket, message, code, metadata = fetchTicketForItem(source, item)
    if not ticket then
        return VancePay.Server.fail(message or '罚单读取失败', code or 'ticket_error')
    end

    if ticket.status == 'paid' then
        local paidMetadata = buildTicketMetadata(ticket)
        syncItemMetadata(source, getTicketItem(), item, paidMetadata)
        return VancePay.Server.ok(buildTicketPayload(ticket, {
            slot = item.slot,
            metadata = paidMetadata,
        }), '这张罚单已经缴清')
    end

    if ticket.status ~= 'unpaid' then
        return VancePay.Server.fail('这张罚单当前不能缴款', 'invalid_status')
    end

    local citizenid = VancePay.Permissions.getCitizenId(source)
    if Utils.isBlank(citizenid) or citizenid ~= ticket.target_citizenid then
        return VancePay.Server.fail('只有被罚人本人可以缴纳这张罚单', 'forbidden')
    end

    if not VancePay.Banking.hasFunds(citizenid, ticket.amount) then
        local missing = Utils.roundCurrency(ticket.amount - VancePay.Banking.getBalance(citizenid))
        return VancePay.Server.fail(('余额不足，还差 %s'):format(Utils.formatCurrency(missing)), 'insufficient_funds')
    end

    local account = getPaymentAccount()
    local withdrawn = VancePay.Banking.withdraw(citizenid, ticket.amount, ('vancepay:police_ticket:%s'):format(ticket.ticket_code))
    if not withdrawn then
        return VancePay.Server.fail('扣款失败', 'withdraw_failed')
    end

    local deposited = VancePay.Banking.deposit(account, ticket.amount, ('vancepay:police_ticket:%s'):format(ticket.ticket_code))
    if not deposited then
        VancePay.Banking.deposit(citizenid, ticket.amount, ('vancepay:police_ticket_rollback:%s'):format(ticket.ticket_code))
        return VancePay.Server.fail('警局公账入账失败，已尝试退回扣款', 'deposit_failed')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_police_tickets
        SET status = 'paid',
            paid_at = CURRENT_TIMESTAMP
        WHERE id = ?
            AND status = 'unpaid'
    ]], { ticket.id })

    if not updated or updated < 1 then
        VancePay.Banking.withdraw(account, ticket.amount, ('vancepay:police_ticket_deposit_rollback:%s'):format(ticket.ticket_code))
        VancePay.Banking.deposit(citizenid, ticket.amount, ('vancepay:police_ticket_rollback:%s'):format(ticket.ticket_code))
        return VancePay.Server.fail('罚单状态更新失败，已尝试回滚', 'db_error')
    end

    ticket = fetchTicketByCode(ticket.ticket_code)
    local updatedMetadata = buildTicketMetadata(ticket)
    local wroteMetadata = syncItemMetadata(source, getTicketItem(), item, updatedMetadata)

    local event, eventErr = syncPaidCreditEvent(ticket)
    local eventId = type(event) == 'table' and tonumber(event.id) or tonumber(event)
    if eventId and not ticket.ctifo_credit_event_id then
        MySQL.update.await([[
            UPDATE vancepay_police_tickets
            SET ctifo_credit_event_id = ?
            WHERE id = ?
                AND ctifo_credit_event_id IS NULL
        ]], { eventId, ticket.id })
    elseif eventErr then
        Utils.debug('Police ticket paid credit event sync failed', ticket.ticket_code, eventErr)
    end

    if VancePay.Audit and VancePay.Audit.log then
        VancePay.Audit.log(citizenid, 'pay_police_ticket', 'police_ticket', ticket.ticket_code, {
            source = source,
            detail = {
                ticket_code = ticket.ticket_code,
                officer_citizenid = ticket.officer_citizenid,
                amount = ticket.amount,
                ticket_agency = ticket.ticket_agency,
                payment_account = account,
                metadata_written = wroteMetadata,
                ctifo_credit_event_id = eventId or ticket.ctifo_credit_event_id,
                ctifo_error = eventErr,
            },
        })
    end

    if VancePay.FiveMLog and VancePay.FiveMLog.emit then
        VancePay.FiveMLog.emit('transactions', 'police_ticket_paid', 'VancePay police ticket paid', {
            severity = 'success',
            source = source,
            metadata = {
                ticket_code = ticket.ticket_code,
                target_citizenid = ticket.target_citizenid,
                officer_citizenid = ticket.officer_citizenid,
                amount = ticket.amount,
                ticket_agency = ticket.ticket_agency,
                payment_account = account,
                metadata_written = wroteMetadata,
            },
        })
    end

    local officerSource = VancePay.Server.getSourceByCitizenId(ticket.officer_citizenid)
    if officerSource then
        VancePay.Server.notify(officerSource, ('罚单 %s 已缴纳'):format(ticket.ticket_code), 'success')
    end

    VancePay.Server.notify(source, ('罚单已缴纳：%s'):format(Utils.formatCurrency(ticket.amount)), 'success')

    local response = buildTicketPayload(ticket, {
        slot = item.slot,
        metadata = updatedMetadata,
    })
    response.metadata_written = wroteMetadata
    response.ctifo_credit_event = event
    response.ctifo_credit_error = eventErr

    return VancePay.Server.ok(response, wroteMetadata and '罚单已缴纳' or '罚单已缴纳，但未能写回纸质罚单状态')
end

function PoliceTickets.openTicketBook(source)
    local officer, officerError, officerCode = requireOfficer(source)
    if not officer then
        VancePay.Server.notify(source, officerError or '你没有开罚单权限', 'error')
        return false, officerCode
    end

    TriggerClientEvent(VancePay.Events.client.openPoliceTicketBook, source, {
        officer = {
            citizenid = officer.citizenid,
            name = officer.name,
        },
        min_amount = getMinAmount(),
        max_amount = getMaxAmount(),
        max_reason_length = math.max(math.floor(tonumber(getConfig().maxReasonLength) or 160), 1),
        target_distance = getTargetDistance(),
        credit_bands = getCreditConfig().bands or {},
        ticket_types = getTicketTypeOptions(),
        ticket_styles = getTicketStyleOptions(),
        agencies = getAgencyOptions(),
        default_ticket_type = sanitizeTicketType(getConfig().defaultTicketType),
        default_ticket_style = sanitizeTicketStyle(getConfig().defaultTicketStyle),
        default_ticket_agency = getAgencyForJob(resolveJobName(officer.data and officer.data.job)).key,
    })

    return true
end

function PoliceTickets.openTicket(source, item)
    local response = PoliceTickets.getTicketDetail(source, item or {})
    if not response or not response.ok then
        VancePay.Server.notify(source, response and response.message or '罚单读取失败', 'error')
        return false
    end

    TriggerClientEvent(VancePay.Events.client.openPoliceTicket, source, response.data)
    return true
end

function PoliceTickets.handleCommand(source)
    if not source or source == 0 then
        print('[VancePay] /vpfine can only be used in-game.')
        return
    end

    PoliceTickets.openTicketBook(source)
end

function PoliceTickets.handleManagementCommand(source)
    if not source or source == 0 then
        print('[VancePay] /vpfineadmin can only be used in-game.')
        return
    end

    PoliceTickets.openManagerCommand(source)
end

function PoliceTickets.registerCommand()
    if PoliceTickets._legacyCommandRegistered and not PoliceTickets._ticketBookCommandRegistered then
        PoliceTickets._ticketBookCommandRegistered = true
    end

    local commandConfig = getCommandConfig()
    if commandConfig.enabled ~= false and not PoliceTickets._ticketBookCommandRegistered then
        local commandName = Utils.trim(commandConfig.name)
        if Utils.isBlank(commandName) then
            commandName = 'vpfine'
        end

        RegisterCommand(commandName, function(source)
            PoliceTickets.handleCommand(source)
        end, false)
        PoliceTickets._ticketBookCommandRegistered = true
    end

    local managementCommandConfig = getManagementCommandConfig()
    if managementCommandConfig.enabled ~= false and not PoliceTickets._managerCommandRegistered then
        local managementCommandName = Utils.trim(managementCommandConfig.name)
        if Utils.isBlank(managementCommandName) then
            managementCommandName = 'vpfineadmin'
        end

        RegisterCommand(managementCommandName, function(source)
            PoliceTickets.handleManagementCommand(source)
        end, false)

        if managementCommandName ~= 'vpfineadmin' then
            RegisterCommand('vpfineadmin', function(source)
                PoliceTickets.handleManagementCommand(source)
            end, false)
        end

        PoliceTickets._managerCommandRegistered = true
    end
end

lib.callback.register('vancepay:server:createPoliceTicket', function(source, payload)
    return PoliceTickets.create(source, payload or {})
end)

lib.callback.register('vancepay:server:getPoliceTicketDetail', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    return PoliceTickets.getTicketDetail(source, payload.item or payload)
end)

lib.callback.register('vancepay:server:payPoliceTicket', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    return PoliceTickets.pay(source, payload.item or payload)
end)

lib.callback.register('vancepay:server:getPoliceTicketManagerBootstrap', function(source, payload)
    return PoliceTickets.safeManagerBootstrap(source, payload or {})
end)

lib.callback.register('vancepay:server:getPoliceTicketManagerAudit', function(source, payload)
    return PoliceTickets.getManagerAudit(source, payload or {})
end)

lib.callback.register('vancepay:server:cancelManagedPoliceTicket', function(source, payload)
    return PoliceTickets.cancelManagedTicket(source, payload or {})
end)

lib.callback.register('vancepay:server:restoreManagedPoliceTicket', function(source, payload)
    return PoliceTickets.restoreManagedTicket(source, payload or {})
end)

RegisterNetEvent(VancePay.Events.server.openPoliceTicketManager, function()
    PoliceTickets.handleManagementCommand(source)
end)

RegisterNetEvent('vancepay:server:openPoliceTicketManager', function()
    PoliceTickets.handleManagementCommand(source)
end)

PoliceTickets.registerCommand()
