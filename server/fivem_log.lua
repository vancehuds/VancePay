VancePay.FiveMLog = VancePay.FiveMLog or {}

local FiveMLog = VancePay.FiveMLog

FiveMLog._warnedExportFailure = FiveMLog._warnedExportFailure or false
FiveMLog._warnedUnavailable = FiveMLog._warnedUnavailable or false
FiveMLog._warnedRejected = FiveMLog._warnedRejected or false
FiveMLog._warnedFallback = FiveMLog._warnedFallback or false

local VALID_SEVERITIES = {
    info = true,
    success = true,
    warning = true,
    error = true,
}

local AUDIT_SEVERITY = {
    archive_store = 'warning',
    restore_store = 'success',
    change_owner = 'warning',
    payout_store = 'warning',
    remove_employee = 'warning',
    sync_store_employees = 'info',
    archive_terminal = 'warning',
    archive_terminal_model = 'warning',
    refund_transaction = 'warning',
    force_refund = 'warning',
    withdraw_balance = 'success',
    create_loan = 'success',
    repay_loan = 'success',
    update_loan = 'warning',
    loan_overdue = 'warning',
    loan_overdue_credit_event_failed = 'error',
    create_collection_task = 'warning',
    cancel_collection_task = 'warning',
    claim_collection_task = 'info',
    claim_collection_reward = 'success',
}

local INTENT_SEVERITY = {
    created = 'info',
    cancelled = 'warning',
    expired = 'warning',
    failed = 'error',
}

local TRANSACTION_SEVERITY = {
    payment_completed = 'success',
    refund_completed = 'warning',
}

local TRANSACTION_MESSAGES = {
    payment_completed = 'VancePay payment completed',
    refund_completed = 'VancePay refund completed',
}

local function getConfig()
    return Config.VanceFiveMLog or {}
end

local function getConfigValue(key, fallback)
    local config = getConfig()
    local value = config[key]
    if value == nil then
        return fallback
    end

    return value
end

local function getResourceName()
    local resourceName = Utils.trim(getConfigValue('resource', 'vancefivemlog'))
    if Utils.isBlank(resourceName) then
        return 'vancefivemlog'
    end

    return resourceName
end

local function readConvar(name)
    name = Utils.trim(name)
    if Utils.isBlank(name) then
        return nil
    end

    local value = Utils.trim(GetConvar(name, ''))
    if Utils.isBlank(value) then
        return nil
    end

    return value
end

local function redact(value)
    value = Utils.trim(value)
    if Utils.isBlank(value) then
        return '<empty>'
    end

    value = tostring(value)
    if #value <= 12 then
        return '<redacted>'
    end

    return value:sub(1, 4) .. '...' .. value:sub(-4)
end

local function getDirectEndpoint()
    local endpoint = readConvar(getConfigValue('endpointConvar', 'vfl_endpoint'))
    if not Utils.isBlank(endpoint) then
        return endpoint
    end

    endpoint = Utils.trim(getConfigValue('endpoint', nil))
    if Utils.isBlank(endpoint) then
        return nil
    end

    return endpoint
end

local function getDirectApiKey()
    local apiKey = readConvar(getConfigValue('apiKeyConvar', 'vfl_api_key'))
    if not Utils.isBlank(apiKey) then
        return apiKey
    end

    apiKey = Utils.trim(getConfigValue('apiKey', nil))
    if Utils.isBlank(apiKey) then
        return nil
    end

    return apiKey
end

local function isCategoryEnabled(category)
    if Utils.isBlank(category) then
        return true
    end

    local categories = getConfigValue('categories', {})
    if type(categories) ~= 'table' or categories[category] == nil then
        return true
    end

    return categories[category] == true
end

local function shouldWarnUnavailable()
    return getConfigValue('warnIfUnavailable', false) == true
end

local function isDebugEnabled()
    return getConfigValue('debug', false) == true or Config.Debug == true
end

local function debugLog(...)
    if not isDebugEnabled() then
        return
    end

    Utils.debug(...)
end

local function warnExportFailure(message)
    if FiveMLog._warnedExportFailure then
        return
    end

    FiveMLog._warnedExportFailure = true
    print(('[VancePay] VanceFiveMLog export failed: %s'):format(tostring(message)))
end

local function warnRejected(eventType)
    if FiveMLog._warnedRejected then
        return
    end

    FiveMLog._warnedRejected = true
    print(('[VancePay] VanceFiveMLog rejected event "%s"; check VanceFiveMLog queue, API key, endpoint, and metadata size.'):format(tostring(eventType)))
end

local function warnFallback(eventType, reason)
    if FiveMLog._warnedFallback then
        return
    end

    FiveMLog._warnedFallback = true
    print(('[VancePay] VanceFiveMLog export path failed for "%s" (%s); using server event fallback.'):format(
        tostring(eventType),
        tostring(reason or 'unknown')
    ))
end

local function emitFallbackEvent(event)
    local logResource = getResourceName()

    local ok, result = pcall(function()
        return exports[logResource]:LogEvent(event)
    end)

    if ok and result ~= false then
        return true, 'fallback_export_log_event'
    end

    debugLog('VanceFiveMLog LogEvent export fallback failed', event.event_type, result)
    TriggerEvent('VanceFiveMLog:server:LogEvent', event)
    return true, 'fallback_server_event'
end

local function warnUnavailable()
    if FiveMLog._warnedUnavailable or not shouldWarnUnavailable() then
        return
    end

    FiveMLog._warnedUnavailable = true
    print(('[VancePay] VanceFiveMLog is enabled but resource "%s" is not started.'):format(getResourceName()))
end

local function normalizeSeverity(severity, fallback)
    severity = Utils.trim(severity or fallback or 'info')
    severity = tostring(severity):lower()

    if VALID_SEVERITIES[severity] then
        return severity
    end

    return 'info'
end

local function normalizeEventType(eventType)
    eventType = Utils.trim(eventType)
    if Utils.isBlank(eventType) then
        return nil
    end

    eventType = tostring(eventType):lower()
    eventType = eventType:gsub('%s+', '_')
    eventType = eventType:gsub('[^%w_]+', '_')
    eventType = eventType:gsub('_+', '_')
    eventType = eventType:gsub('^_+', ''):gsub('_+$', '')

    if Utils.isBlank(eventType) then
        return nil
    end

    local prefix = Utils.trim(getConfigValue('eventPrefix', 'vancepay'))
    if not Utils.isBlank(prefix) then
        prefix = tostring(prefix):lower():gsub('%s+', '_'):gsub('[^%w_]+', '_')
        prefix = prefix:gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
        if not Utils.isBlank(prefix)
            and eventType ~= prefix
            and eventType:sub(1, #prefix + 1) ~= (prefix .. '_') then
            eventType = prefix .. '_' .. eventType
        end
    end

    return eventType
end

local function setMetadataValue(metadata, key, value)
    local valueType = type(value)
    if value ~= nil and valueType ~= 'function' and valueType ~= 'userdata' and valueType ~= 'thread' then
        metadata[key] = value
    end
end

local function mergeMetadata(base, extra)
    local metadata = {}

    if type(base) == 'table' then
        for key, value in pairs(base) do
            setMetadataValue(metadata, key, value)
        end
    end

    if type(extra) == 'table' then
        for key, value in pairs(extra) do
            setMetadataValue(metadata, key, value)
        end
    end

    return metadata
end

local function resolveSourceByCitizenId(citizenid)
    if Utils.isBlank(citizenid)
        or not VancePay.Server
        or type(VancePay.Server.getSourceByCitizenId) ~= 'function' then
        return nil
    end

    local ok, source = pcall(VancePay.Server.getSourceByCitizenId, citizenid)
    if ok then
        return tonumber(source)
    end

    return nil
end

local function rounded(value)
    if value == nil then
        return nil
    end

    return Utils.roundCurrency(value)
end

local function normalizeResourceName(resourceName)
    resourceName = Utils.trim(resourceName)
    if Utils.isBlank(resourceName) then
        return VancePay.ResourceName
    end

    return resourceName
end

function FiveMLog.isEnabled(category)
    if getConfigValue('enabled', true) == false then
        return false
    end

    return isCategoryEnabled(category)
end

function FiveMLog.isAvailable()
    return GetResourceState(getResourceName()) == 'started'
end

function FiveMLog.emit(category, eventType, message, options)
    if not FiveMLog.isEnabled(category) then
        return false, 'disabled'
    end

    if not FiveMLog.isAvailable() then
        warnUnavailable()
        return false, 'resource_unavailable'
    end

    eventType = normalizeEventType(eventType)
    if Utils.isBlank(eventType) then
        return false, 'missing_event_type'
    end

    options = type(options) == 'table' and Utils.deepCopy(options) or {}
    local shouldFlush = options.flush == true
    options.flush = nil
    options.resource = normalizeResourceName(options.resource)
    options.plugin_resource = normalizeResourceName(options.plugin_resource or options.resource)
    options.severity = normalizeSeverity(options.severity)
    options.metadata = mergeMetadata(options.metadata, {
        category = category,
    })

    local event = {
        event_type = eventType,
        severity = options.severity,
        source = options.source,
        player_name = options.player_name,
        license = options.license,
        discord = options.discord,
        steam = options.steam,
        citizenid = options.citizenid,
        resource = options.resource,
        plugin_resource = options.plugin_resource,
        message = message or options.message or eventType,
        coords = options.coords,
        metadata = options.metadata,
        occurred_at = options.occurred_at,
    }

    local ok, result = pcall(function()
        return exports[getResourceName()]:Log(eventType, message or options.message or eventType, options)
    end)

    if not ok then
        warnExportFailure(result)
        warnFallback(eventType, result)
        return emitFallbackEvent(event)
    end

    if result == false then
        warnRejected(eventType)
        warnFallback(eventType, 'rejected')
        return emitFallbackEvent(event)
    end

    debugLog('VanceFiveMLog event queued', eventType, category, options.severity)

    if shouldFlush then
        FiveMLog.flush()
    end

    return true, result
end

function FiveMLog.flush()
    if not FiveMLog.isEnabled() or not FiveMLog.isAvailable() then
        return false
    end

    local ok, result = pcall(function()
        return exports[getResourceName()]:Flush()
    end)

    if not ok then
        warnExportFailure(result)
        return false
    end

    return result ~= false
end

function FiveMLog.test(source)
    local numericSource = tonumber(source)
    local logSource = numericSource and numericSource > 0 and numericSource or nil
    local ok, result = FiveMLog.emit('resource', 'diagnostic_test', 'VancePay VanceFiveMLog diagnostic test', {
        severity = 'info',
        source = logSource,
        metadata = {
            diagnostic = true,
            configured_resource = getResourceName(),
            resource_state = GetResourceState(getResourceName()),
            vancepay_resource = VancePay.ResourceName,
            version = GetResourceMetadata(VancePay.ResourceName, 'version', 0) or 'unknown',
        },
        flush = true,
    })

    print(('[VancePay] VanceFiveMLog diagnostic result ok=%s result=%s resource=%s state=%s'):format(
        tostring(ok),
        tostring(result),
        getResourceName(),
        GetResourceState(getResourceName())
    ))

    return ok, result
end

function FiveMLog.testDirectHttp(source)
    if getConfigValue('directHttpDiagnostic', true) == false then
        return false, 'disabled'
    end

    local endpoint = getDirectEndpoint()
    local apiKey = getDirectApiKey()
    if Utils.isBlank(endpoint) or Utils.isBlank(apiKey) then
        print(('[VancePay] VanceFiveMLog direct diagnostic skipped endpoint=%s api_key=%s'):format(
            endpoint or '<empty>',
            redact(apiKey)
        ))
        return false, 'missing_endpoint_or_api_key'
    end

    local numericSource = tonumber(source)
    local logSource = numericSource and numericSource > 0 and numericSource or nil
    local eventType = normalizeEventType('diagnostic_http_test')
    local payload = json.encode({
        event_type = eventType,
        severity = 'info',
        source = logSource,
        resource = VancePay.ResourceName,
        message = 'VancePay direct VanceFiveMLog diagnostic test',
        metadata = {
            diagnostic = true,
            direct_http = true,
            configured_resource = getResourceName(),
            resource_state = GetResourceState(getResourceName()),
            vancepay_resource = VancePay.ResourceName,
            version = GetResourceMetadata(VancePay.ResourceName, 'version', 0) or 'unknown',
        },
    })

    PerformHttpRequest(endpoint, function(status, body, _headers, errorData)
        print(('[VancePay] VanceFiveMLog direct diagnostic status=%s endpoint=%s api_key=%s body=%s error=%s'):format(
            tostring(status),
            endpoint,
            redact(apiKey),
            tostring(body or ''),
            tostring(errorData or '')
        ))
    end, 'POST', payload, {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = 'Bearer ' .. apiKey,
        ['User-Agent'] = 'VancePay-VanceFiveMLog-Diagnostic/1.0',
    })

    return true, 'request_sent'
end

function FiveMLog.logAudit(actorCitizenId, action, targetType, targetId, options)
    if Utils.isBlank(action) then
        return false
    end

    options = type(options) == 'table' and options or {}
    local metadata = mergeMetadata({
        action = action,
        target_type = targetType,
        target_id = targetId and tostring(targetId) or nil,
        actor_citizenid = actorCitizenId,
        audit_log_id = options.audit_log_id,
        store_id = options.store_id,
        store_name = options.store_name,
        terminal_id = options.terminal_id,
        terminal_serial_number = options.terminal_serial_number,
        detail = options.detail,
    }, options.metadata)

    return FiveMLog.emit('audit', 'audit_' .. tostring(action), ('VancePay audit: %s'):format(action), {
        severity = options.severity or AUDIT_SEVERITY[action] or 'info',
        source = tonumber(options.source) or resolveSourceByCitizenId(actorCitizenId),
        metadata = metadata,
        flush = options.flush == true,
    })
end

function FiveMLog.logIntent(eventName, intent, options)
    if Utils.isBlank(eventName) or type(intent) ~= 'table' then
        return false
    end

    options = type(options) == 'table' and options or {}
    local actorCitizenId = options.actor_citizenid
    local metadata = mergeMetadata({
        intent_id = intent.id,
        intent_code = intent.intent_code,
        event = eventName,
        status = options.status or intent.status,
        method = intent.method,
        store_id = intent.store_id,
        store_name = intent.store_name,
        terminal_id = intent.terminal_id,
        terminal_serial_number = intent.terminal_serial_number,
        cashier_citizenid = intent.cashier_citizenid,
        target_citizenid = intent.target_citizenid,
        actor_citizenid = actorCitizenId,
        subtotal_amount = rounded(intent.subtotal_amount),
        discount_rate = rounded(intent.discount_rate),
        discount_amount = rounded(intent.discount_amount),
        tip_amount = rounded(intent.tip_amount),
        fee_amount = rounded(intent.fee_amount),
        tax_rate = rounded(intent.tax_rate),
        tax_amount = rounded(intent.tax_amount),
        commission_rate = rounded(intent.commission_rate),
        commission_amount = rounded(intent.commission_amount),
        final_amount = rounded(intent.final_amount),
        net_amount = rounded(intent.net_amount),
        item_description = intent.item_description,
        item_lines = intent.item_lines,
        reason = options.reason or intent.cancelled_reason,
        expires_at = intent.expires_at,
    }, options.metadata)

    return FiveMLog.emit('intents', 'intent_' .. tostring(eventName), ('VancePay intent %s'):format(eventName), {
        severity = options.severity or INTENT_SEVERITY[eventName] or 'info',
        source = tonumber(options.source) or resolveSourceByCitizenId(actorCitizenId),
        metadata = metadata,
        flush = options.flush == true,
    })
end

function FiveMLog.logTransaction(eventName, transaction, options)
    if Utils.isBlank(eventName) or type(transaction) ~= 'table' then
        return false
    end

    options = type(options) == 'table' and options or {}
    local intent = type(options.intent) == 'table' and options.intent or {}
    local original = type(options.original) == 'table' and options.original or {}
    local processedByCitizenId = transaction.processed_by_citizenid or options.actor_citizenid
    local metadata = mergeMetadata({
        transaction_id = transaction.id,
        tx_code = transaction.tx_code,
        event = eventName,
        type = transaction.type,
        status = transaction.status,
        method = transaction.method,
        intent_id = transaction.intent_id,
        intent_code = intent.intent_code,
        original_tx_id = transaction.original_tx_id,
        original_tx_code = original.tx_code or transaction.original_tx_code,
        store_id = transaction.store_id,
        store_name = transaction.store_name_snapshot or intent.store_name,
        terminal_id = transaction.terminal_id,
        terminal_serial_number = transaction.terminal_serial_snapshot or intent.terminal_serial_number,
        cashier_citizenid = transaction.cashier_citizenid,
        customer_citizenid = transaction.customer_citizenid,
        processed_by_citizenid = processedByCitizenId,
        subtotal_amount = rounded(transaction.subtotal_amount),
        discount_rate = rounded(transaction.discount_rate),
        discount_amount = rounded(transaction.discount_amount),
        tip_amount = rounded(transaction.tip_amount),
        fee_amount = rounded(transaction.fee_amount),
        tax_rate = rounded(transaction.tax_rate),
        tax_amount = rounded(transaction.tax_amount),
        commission_rate = rounded(transaction.commission_rate),
        commission_amount = rounded(transaction.commission_amount),
        final_amount = rounded(transaction.final_amount),
        net_amount = rounded(transaction.net_amount),
        refunded_final_amount = rounded(transaction.refunded_final_amount),
        refunded_net_amount = rounded(transaction.refunded_net_amount),
        refunded_tax_amount = rounded(transaction.refunded_tax_amount),
        refunded_commission_amount = rounded(transaction.refunded_commission_amount),
        refund_reason = transaction.refund_reason,
        item_description = transaction.item_description,
        item_lines = transaction.item_lines,
    }, options.metadata)

    return FiveMLog.emit('transactions', tostring(eventName), TRANSACTION_MESSAGES[eventName] or ('VancePay transaction ' .. tostring(eventName)), {
        severity = options.severity or TRANSACTION_SEVERITY[eventName] or 'info',
        source = tonumber(options.source) or resolveSourceByCitizenId(processedByCitizenId or transaction.customer_citizenid),
        metadata = metadata,
        flush = options.flush == true,
    })
end

function FiveMLog.logResourceStarted()
    return FiveMLog.emit('resource', 'resource_started', 'VancePay resource started', {
        severity = 'success',
        metadata = {
            resource = VancePay.ResourceName,
            version = GetResourceMetadata(VancePay.ResourceName, 'version', 0) or 'unknown',
        },
    })
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == VancePay.ResourceName then
        CreateThread(function()
            Wait(500)
            FiveMLog.logResourceStarted()
        end)
        return
    end

    if resourceName == getResourceName() then
        CreateThread(function()
            Wait(1000)
            FiveMLog.logResourceStarted()
        end)
    end
end)

RegisterCommand(getConfigValue('testCommand', 'vplogtest'), function(source)
    if source ~= 0
        and (not VancePay.Permissions
            or type(VancePay.Permissions.isAdmin) ~= 'function'
            or not VancePay.Permissions.isAdmin(source)) then
        VancePay.Server.notify(source, '你没有执行 VanceFiveMLog 诊断的权限', 'error')
        return
    end

    local ok, result = FiveMLog.test(source)
    FiveMLog.testDirectHttp(source)
    if source ~= 0 then
        local message = ok and 'VanceFiveMLog 诊断日志已发送' or ('VanceFiveMLog 诊断失败: ' .. tostring(result))
        VancePay.Server.notify(source, message, ok and 'success' or 'error')
    end
end, false)
