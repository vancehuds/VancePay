VancePay.Kook = VancePay.Kook or {}

local Kook = VancePay.Kook

Kook._queue = Kook._queue or {}
Kook._workerStarted = Kook._workerStarted or false
Kook._warnedMissingConfig = Kook._warnedMissingConfig or false

local function getConfig()
    return Config.Kook or {}
end

local function getConfigValue(key, fallback)
    local config = getConfig()
    local value = config[key]
    if value == nil then
        return fallback
    end

    return value
end

local function truncateText(value, maxLength)
    value = tostring(value or '')
    maxLength = math.max(tonumber(maxLength) or 0, 16)

    if #value <= maxLength then
        return value
    end

    return value:sub(1, maxLength - 3) .. '...'
end

local function sanitizeText(value)
    value = tostring(value or '')
    value = value:gsub('\r\n', '\n'):gsub('\r', '\n')
    value = value:gsub('`', "'")
    return value
end

local function readConfigSecret(rawValue, convarName)
    local directValue = type(rawValue) == 'string' and Utils.trim(rawValue) or rawValue
    if type(convarName) == 'string' and convarName ~= '' then
        local convarValue = Utils.trim(GetConvar(convarName, ''))
        if not Utils.isBlank(convarValue) then
            return convarValue
        end
    end

    return directValue
end

local function isCategoryEnabled(category)
    local categories = getConfigValue('categories', {})
    if type(categories) ~= 'table' then
        return true
    end

    if categories[category] == nil then
        return true
    end

    return categories[category] == true
end

local function serializeValue(value)
    if value == nil then
        return nil
    end

    local valueType = type(value)
    if valueType == 'table' then
        local ok, encoded = pcall(json.encode, value)
        if ok then
            return encoded
        end

        return '[unserializable table]'
    end

    if valueType == 'boolean' then
        return value and 'true' or 'false'
    end

    return tostring(value)
end

local function formatCurrencyLabel(value)
    if value == nil then
        return nil
    end

    return Utils.formatCurrency(value)
end

local function formatStoreLabel(storeId, storeName)
    if storeId and not Utils.isBlank(storeName) then
        return ('#%s %s'):format(storeId, storeName)
    end

    if storeId then
        return '#' .. tostring(storeId)
    end

    if not Utils.isBlank(storeName) then
        return storeName
    end

    return nil
end

local function formatTerminalLabel(terminalId, serialNumber)
    if terminalId and not Utils.isBlank(serialNumber) then
        return ('#%s %s'):format(terminalId, serialNumber)
    end

    if terminalId then
        return '#' .. tostring(terminalId)
    end

    if not Utils.isBlank(serialNumber) then
        return serialNumber
    end

    return nil
end

local function resolveCitizenLabel(citizenid)
    if Utils.isBlank(citizenid) then
        return nil
    end

    if not VancePay.Server or not VancePay.Server.getSourceByCitizenId then
        return citizenid
    end

    local source = VancePay.Server.getSourceByCitizenId(citizenid)
    if not source then
        return citizenid
    end

    local record = VancePay.Server.getPlayerRecord(source)
    if record and not Utils.isBlank(record.name) then
        return ('%s (%s / src:%s)'):format(record.name, citizenid, source)
    end

    return ('%s (src:%s)'):format(citizenid, source)
end

local function nowUtc()
    return os.date('!%Y-%m-%d %H:%M:%S UTC')
end

local function buildDetailBlock(detail)
    if detail == nil then
        return nil
    end

    local serialized = serializeValue(detail)
    if Utils.isBlank(serialized) then
        return nil
    end

    serialized = sanitizeText(truncateText(serialized, getConfigValue('maxDetailLength', 1200)))
    return ('```json\n%s\n```'):format(serialized)
end

local function buildMessage(title, fields, detail)
    local lines = {}
    local prefix = Utils.trim(getConfigValue('prefix', '[VancePay]'))
    local mention = Utils.trim(getConfigValue('mention', ''))

    if not Utils.isBlank(mention) then
        lines[#lines + 1] = sanitizeText(mention)
    end

    if not Utils.isBlank(prefix) then
        lines[#lines + 1] = ('**%s %s**'):format(sanitizeText(prefix), sanitizeText(title))
    else
        lines[#lines + 1] = ('**%s**'):format(sanitizeText(title))
    end

    for index = 1, #(fields or {}) do
        local field = fields[index]
        local value = field and serializeValue(field.value) or nil
        if field and not Utils.isBlank(field.label) and not Utils.isBlank(value) then
            lines[#lines + 1] = ('`%s` %s'):format(
                sanitizeText(field.label),
                sanitizeText(truncateText(value, 320))
            )
        end
    end

    local detailBlock = buildDetailBlock(detail)
    if detailBlock then
        lines[#lines + 1] = '`详情`'
        lines[#lines + 1] = detailBlock
    end

    local content = table.concat(lines, '\n')
    return truncateText(content, getConfigValue('maxMessageLength', 3500))
end

function Kook.getBotToken()
    return readConfigSecret(getConfigValue('botToken', ''), getConfigValue('botTokenConvar', ''))
end

function Kook.getChannelId()
    return readConfigSecret(getConfigValue('channelId', ''), getConfigValue('channelIdConvar', ''))
end

function Kook.isEnabled()
    if getConfigValue('enabled', false) ~= true then
        return false
    end

    return not Utils.isBlank(Kook.getBotToken()) and not Utils.isBlank(Kook.getChannelId())
end

local function emitConfigWarning()
    if Kook._warnedMissingConfig then
        return
    end

    Kook._warnedMissingConfig = true
    print('[VancePay] KOOK logging is enabled but botToken/channelId is missing. Check Config.Kook and your server.cfg convars.')
end

local function postMessage(content)
    local apiBaseUrl = tostring(getConfigValue('apiBaseUrl', 'https://www.kookapp.cn/api/v3')):gsub('/+$', '')
    local body = json.encode({
        type = 9,
        target_id = Kook.getChannelId(),
        content = content,
    })

    PerformHttpRequest(apiBaseUrl .. '/message/create', function(statusCode, responseBody)
        if not statusCode or statusCode < 200 or statusCode >= 300 then
            print(('[VancePay] KOOK request failed (%s): %s'):format(
                tostring(statusCode),
                truncateText(sanitizeText(responseBody or 'empty response'), 400)
            ))
            return
        end

        local ok, decoded = pcall(json.decode, responseBody or '')
        local apiCode = ok and type(decoded) == 'table' and tonumber(decoded.code) or nil
        if apiCode and apiCode ~= 0 then
            print(('[VancePay] KOOK request rejected (code=%s): %s'):format(
                tostring(decoded.code),
                sanitizeText(decoded.message or 'unknown error')
            ))
        end
    end, 'POST', body, {
        ['Authorization'] = ('Bot %s'):format(Kook.getBotToken()),
        ['Content-Type'] = 'application/json; charset=utf-8',
        ['Accept-Language'] = 'zh-CN',
    })
end

local function ensureWorker()
    if Kook._workerStarted then
        return
    end

    Kook._workerStarted = true

    CreateThread(function()
        while true do
            local item = table.remove(Kook._queue, 1)
            if item then
                if Kook.isEnabled() then
                    postMessage(item.content)
                    Wait(math.max(tonumber(getConfigValue('rateLimitMs', 1000)) or 1000, 250))
                else
                    emitConfigWarning()
                    Wait(1000)
                end
            else
                Wait(250)
            end
        end
    end)
end

function Kook.enqueue(category, title, fields, detail)
    if getConfigValue('enabled', false) ~= true then
        return false
    end

    if not isCategoryEnabled(category) then
        return false
    end

    if not Kook.isEnabled() then
        emitConfigWarning()
        return false
    end

    ensureWorker()

    Kook._queue[#Kook._queue + 1] = {
        content = buildMessage(title, fields, detail),
    }

    return true
end

local auditActionLabels = {
    create_store = '创建店铺',
    update_store = '更新店铺',
    archive_store = '归档店铺',
    restore_store = '取消归档店铺',
    change_owner = '更换店主',
    payout_store = '店铺提现',
    save_employee = '保存员工',
    sync_store_employees = '同步产业人员',
    remove_employee = '移除员工',
    create_terminal_model = '创建终端模型',
    update_terminal_model = '更新终端模型',
    archive_terminal_model = '归档终端模型',
    create_terminal = '创建终端',
    update_terminal = '更新终端',
    archive_terminal = '归档终端',
    create_binding_code = '生成绑定码',
    consume_binding_code = '使用绑定码',
    grant_terminal_item = '发放终端物品',
    refund_transaction = '退款交易',
    force_refund = '强制退款',
    create_loan = '发放贷款',
    repay_loan = '贷款还款',
    update_loan = '调整贷款',
    loan_overdue = '贷款逾期',
    loan_overdue_credit_event_failed = '逾期信用事件失败',
    create_collection_task = '生成催收任务',
    cancel_collection_task = '取消催收任务',
    claim_collection_task = '领取催收任务',
    claim_collection_reward = '领取催收奖励',
    create_police_ticket = '开具警察罚单',
    pay_police_ticket = '缴纳警察罚单',
}

local intentEventLabels = {
    created = '支付订单已创建',
    cancelled = '支付订单已取消',
    expired = '支付订单已超时',
    failed = '支付订单失败',
}

local transactionEventLabels = {
    payment_completed = '支付完成',
}

local paymentMethodLabels = {
    phone = '手机支付',
    card = '刷卡支付',
}

function Kook.logAudit(actorCitizenId, action, targetType, targetId, options)
    options = options or {}

    return Kook.enqueue('audit', auditActionLabels[action] or ('审计事件 ' .. tostring(action)), {
        { label = '时间', value = nowUtc() },
        { label = '动作', value = action },
        { label = '操作人', value = resolveCitizenLabel(actorCitizenId) or actorCitizenId },
        { label = '目标类型', value = targetType },
        { label = '目标 ID', value = targetId and tostring(targetId) or nil },
        { label = '店铺', value = formatStoreLabel(options.store_id, options.store_name) },
        { label = '终端', value = formatTerminalLabel(options.terminal_id, options.terminal_serial_number) },
        { label = '审计 ID', value = options.audit_log_id },
    }, options.detail)
end

function Kook.logIntent(eventName, intent, options)
    if not intent then
        return false
    end

    options = options or {}

    local detail = options.detail or {
        subtotal_amount = Utils.roundCurrency(intent.subtotal_amount or 0),
        discount_rate = Utils.roundCurrency(intent.discount_rate or 0),
        discount_amount = Utils.roundCurrency(intent.discount_amount or 0),
        tip_amount = Utils.roundCurrency(intent.tip_amount or 0),
        fee_amount = Utils.roundCurrency(intent.fee_amount or 0),
        tax_rate = Utils.roundCurrency(intent.tax_rate or 0),
        tax_exempt = Utils.parseBool(intent.tax_exempt),
        tax_amount = Utils.roundCurrency(intent.tax_amount or 0),
        tax_settlement_mode = intent.tax_settlement_mode,
        tax_settlement_account_identifier = Utils.trim(intent.tax_settlement_account_identifier),
        final_amount = Utils.roundCurrency(intent.final_amount or 0),
        net_amount = Utils.roundCurrency(intent.net_amount or 0),
        reason = options.reason or intent.cancelled_reason,
        expires_at = intent.expires_at,
    }

    return Kook.enqueue('intents', intentEventLabels[eventName] or ('订单事件 ' .. tostring(eventName)), {
        { label = '时间', value = nowUtc() },
        { label = '订单号', value = intent.intent_code or intent.id },
        { label = '状态', value = options.status or intent.status },
        { label = '支付方式', value = paymentMethodLabels[intent.method] or intent.method },
        { label = '金额', value = formatCurrencyLabel(intent.final_amount) },
        { label = '实收', value = formatCurrencyLabel(intent.net_amount) },
        { label = '店铺', value = formatStoreLabel(intent.store_id, intent.store_name) },
        { label = '终端', value = formatTerminalLabel(intent.terminal_id, intent.terminal_serial_number) },
        { label = '收银员', value = resolveCitizenLabel(intent.cashier_citizenid) or intent.cashier_citizenid },
        { label = '顾客', value = resolveCitizenLabel(intent.target_citizenid) or intent.target_citizenid or (intent.method == 'card' and '附近任意顾客' or nil) },
        { label = '操作人', value = resolveCitizenLabel(options.actor_citizenid) or options.actor_citizenid },
        { label = '原因', value = options.reason },
    }, detail)
end

function Kook.logTransaction(eventName, transaction, options)
    if not transaction then
        return false
    end

    options = options or {}
    local intent = options.intent or {}
    local detail = options.detail or {
        subtotal_amount = Utils.roundCurrency(transaction.subtotal_amount or 0),
        discount_rate = Utils.roundCurrency(transaction.discount_rate or 0),
        discount_amount = Utils.roundCurrency(transaction.discount_amount or 0),
        tip_amount = Utils.roundCurrency(transaction.tip_amount or 0),
        fee_amount = Utils.roundCurrency(transaction.fee_amount or 0),
        tax_rate = Utils.roundCurrency(transaction.tax_rate or 0),
        tax_exempt = Utils.parseBool(transaction.tax_exempt),
        tax_amount = Utils.roundCurrency(transaction.tax_amount or 0),
        tax_settlement_mode = transaction.tax_settlement_mode,
        tax_settlement_account_identifier = Utils.trim(transaction.tax_settlement_account_identifier),
        final_amount = Utils.roundCurrency(transaction.final_amount or 0),
        net_amount = Utils.roundCurrency(transaction.net_amount or 0),
        refunded_final_amount = Utils.roundCurrency(transaction.refunded_final_amount or 0),
        refunded_net_amount = Utils.roundCurrency(transaction.refunded_net_amount or 0),
        refunded_tax_amount = Utils.roundCurrency(transaction.refunded_tax_amount or 0),
        refund_reason = transaction.refund_reason,
        intent_code = intent.intent_code,
    }

    return Kook.enqueue('transactions', transactionEventLabels[eventName] or ('交易事件 ' .. tostring(eventName)), {
        { label = '时间', value = nowUtc() },
        { label = '交易号', value = transaction.tx_code or transaction.id },
        { label = '交易类型', value = transaction.type },
        { label = '状态', value = transaction.status },
        { label = '支付方式', value = paymentMethodLabels[transaction.method] or transaction.method },
        { label = '金额', value = formatCurrencyLabel(transaction.final_amount) },
        { label = '入账', value = formatCurrencyLabel(transaction.net_amount) },
        { label = '店铺', value = formatStoreLabel(transaction.store_id, transaction.store_name_snapshot or intent.store_name) },
        { label = '终端', value = formatTerminalLabel(transaction.terminal_id, transaction.terminal_serial_snapshot or intent.terminal_serial_number) },
        { label = '收银员', value = resolveCitizenLabel(transaction.cashier_citizenid) or transaction.cashier_citizenid },
        { label = '顾客', value = resolveCitizenLabel(transaction.customer_citizenid) or transaction.customer_citizenid },
        { label = '处理人', value = resolveCitizenLabel(transaction.processed_by_citizenid) or transaction.processed_by_citizenid },
        { label = '订单号', value = intent.intent_code or transaction.intent_id },
    }, detail)
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= VancePay.ResourceName then
        return
    end

    if getConfigValue('enabled', false) ~= true then
        return
    end

    if not Kook.isEnabled() then
        emitConfigWarning()
        return
    end

    ensureWorker()

    Kook.enqueue('resource', 'KOOK 日志已启动', {
        { label = '时间', value = nowUtc() },
        { label = '资源', value = VancePay.ResourceName },
        { label = '版本', value = GetResourceMetadata(VancePay.ResourceName, 'version', 0) or 'unknown' },
        { label = '频道 ID', value = Kook.getChannelId() },
    })
end)
