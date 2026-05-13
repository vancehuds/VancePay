VancePay.LBPhone = VancePay.LBPhone or {}

local LBPhone = VancePay.LBPhone
local SharedUtils = VancePay.Utils or rawget(_G, 'Utils')

LBPhone.state = LBPhone.state or {
    appRegistered = false,
    appOpen = false,
    intents = {},
    activity = {},
    bankBalance = 0,
    balanceSummary = {},
    balanceHistory = {},
    loans = {},
    pendingOpen = nil,
    pendingOpenThread = false,
}

local DEFERRED_OPEN_RETRY_MS = 250
local DEFERRED_OPEN_TIMEOUT_MS = 10000
local DEFAULT_ACTIVITY_PER_PAGE = 12
local DEFAULT_BALANCE_HISTORY_PER_PAGE = 20

local function trimValue(value)
    if SharedUtils and type(SharedUtils.trim) == 'function' then
        return SharedUtils.trim(value)
    end

    if type(value) ~= 'string' then
        return value
    end

    return value:match('^%s*(.-)%s*$')
end

local function debugLog(...)
    if SharedUtils and type(SharedUtils.debug) == 'function' then
        SharedUtils.debug(...)
    end
end

local function getCurrentUnixTime()
    if SharedUtils and type(SharedUtils.getUnixTime) == 'function' then
        local currentTime = SharedUtils.getUnixTime()
        if type(currentTime) == 'number' then
            return currentTime
        end
    end

    local ok, gameTimer = pcall(GetGameTimer)
    if ok and type(gameTimer) == 'number' then
        return math.floor(gameTimer / 1000)
    end

    return 0
end

local function getConfig()
    return Config.LBPhone or {}
end

local function getPhoneResourceName()
    local config = getConfig()
    local resourceName = trimValue(config.resource)

    if resourceName == '' then
        resourceName = 'lb-phone'
    end

    return resourceName
end

local function getAppIdentifier()
    local config = getConfig()
    local identifier = trimValue(config.appIdentifier)

    if identifier == '' then
        identifier = 'vancepay'
    end

    return identifier
end

local function getAppUiPath()
    return ('%s/html/lbphone/index.html'):format(VancePay.ResourceName)
end

local function callPhoneExport(method, ...)
    local resourceName = getPhoneResourceName()
    if GetResourceState(resourceName) ~= 'started' then
        return false, 'resource_not_started'
    end

    local api = exports[resourceName]
    if not api or type(api[method]) ~= 'function' then
        return false, 'export_not_found'
    end

    local ok, result, extra = pcall(api[method], api, ...)
    if not ok then
        debugLog('LB Phone export failed', method, result)
        return false, result
    end

    if result == nil then
        return true, extra
    end

    return result, extra
end

local function shouldEnable()
    local config = getConfig()
    return config.enabled ~= false
end

local function isAnyNuiFocused()
    local ok, focused = pcall(IsNuiFocused)
    if ok then
        return focused == true
    end

    return VancePay.Client
        and VancePay.Client.ui
        and VancePay.Client.ui.open == true
end

local function isPhoneOpen()
    local resourceName = getPhoneResourceName()
    if GetResourceState(resourceName) ~= 'started' then
        return false
    end

    local api = exports[resourceName]
    if not api or type(api.IsOpen) ~= 'function' then
        return false
    end

    local ok, result = pcall(api.IsOpen, api)
    if not ok then
        debugLog('LB Phone export failed', 'IsOpen', result)
        return false
    end

    return result == true
end

local function canOpenAppNow()
    if isPhoneOpen() then
        return true
    end

    return not isAnyNuiFocused()
end

local function buildIntentList()
    local intents = {}

    for _, intent in pairs(LBPhone.state.intents) do
        intents[#intents + 1] = intent
    end

    table.sort(intents, function(a, b)
        local left = tonumber(a.expires_in) or 0
        local right = tonumber(b.expires_in) or 0

        if left == right then
            return (tonumber(a.intent_id) or 0) > (tonumber(b.intent_id) or 0)
        end

        return left < right
    end)

    return intents
end

local function normalizePagedCollection(value, defaultPerPage)
    local fallbackPerPage = math.max(tonumber(defaultPerPage) or 1, 1)
    local items = {}
    local page = 1
    local perPage = fallbackPerPage
    local total = 0
    local totalPages = 1

    if type(value) == 'table' and type(value.items) == 'table' then
        items = value.items
        page = math.max(tonumber(value.page) or 1, 1)
        perPage = math.max(tonumber(value.per_page) or fallbackPerPage, 1)
        total = math.max(tonumber(value.total) or #items, 0)
        totalPages = math.max(tonumber(value.total_pages) or math.ceil(total / perPage), 1)
    elseif type(value) == 'table' then
        items = value
        total = #items
        totalPages = math.max(math.ceil(total / perPage), 1)
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

local function resolvePageOptions(options)
    local config = getConfig()
    local savedActivity = normalizePagedCollection(LBPhone.state.activity, config.activityLimit or DEFAULT_ACTIVITY_PER_PAGE)
    local savedBalanceHistory = normalizePagedCollection(
        LBPhone.state.balanceHistory,
        config.balanceActivityLimit or DEFAULT_BALANCE_HISTORY_PER_PAGE
    )

    local activityPerPage = math.max(
        tonumber(options.activity_per_page or options.activity_limit) or savedActivity.per_page or config.activityLimit
            or DEFAULT_ACTIVITY_PER_PAGE,
        1
    )
    local balanceHistoryPerPage = math.max(
        tonumber(options.balance_history_per_page or options.balance_history_limit) or savedBalanceHistory.per_page
            or config.balanceActivityLimit or DEFAULT_BALANCE_HISTORY_PER_PAGE,
        1
    )

    return {
        activityPage = math.max(tonumber(options.activity_page) or savedActivity.page or 1, 1),
        activityPerPage = activityPerPage,
        balanceHistoryPage = math.max(tonumber(options.balance_history_page) or savedBalanceHistory.page or 1, 1),
        balanceHistoryPerPage = balanceHistoryPerPage,
        intentLimit = math.max(tonumber(options.intent_limit) or config.intentLimit or 20, 1),
    }
end

local function buildAppState()
    local config = getConfig()

    return {
        balance = tonumber(LBPhone.state.balanceSummary and LBPhone.state.balanceSummary.withdrawable_balance or 0) or 0,
        bank_balance = tonumber(LBPhone.state.bankBalance) or 0,
        balance_summary = LBPhone.state.balanceSummary or {},
        balance_history = normalizePagedCollection(
            LBPhone.state.balanceHistory,
            config.balanceActivityLimit or DEFAULT_BALANCE_HISTORY_PER_PAGE
        ),
        loans = LBPhone.state.loans or {},
        intents = buildIntentList(),
        activity = normalizePagedCollection(LBPhone.state.activity, config.activityLimit or DEFAULT_ACTIVITY_PER_PAGE),
        app_open = LBPhone.state.appOpen == true,
        app_registered = LBPhone.state.appRegistered == true,
        updated_at = getCurrentUnixTime(),
        meta = {
            identifier = getAppIdentifier(),
            app_name = config.appName or 'VancePay',
            phone_resource = getPhoneResourceName(),
            currency = Config.Currency or '$',
        }
    }
end

local function pushState(reason)
    if not LBPhone.state.appRegistered then
        return false
    end

    local ok = callPhoneExport('SendCustomAppMessage', getAppIdentifier(), {
        type = 'state',
        action = 'state',
        reason = reason or 'sync',
        data = buildAppState(),
    })

    return ok == true
end

local function ensureAppInstalled()
    local ok, reason = callPhoneExport('SetAppInstalled', getAppIdentifier(), true)
    if reason == 'export_not_found' then
        return true
    end

    return ok == true
end

local function upsertIntent(intent)
    if not intent or not intent.intent_id then
        return
    end

    LBPhone.state.intents[tostring(intent.intent_id)] = intent

    if intent.current_balance ~= nil then
        LBPhone.state.bankBalance = tonumber(intent.current_balance) or LBPhone.state.bankBalance
    end
end

local function removeIntent(intentId)
    if not intentId then
        return
    end

    LBPhone.state.intents[tostring(intentId)] = nil
end

function LBPhone.isAvailable()
    return shouldEnable() and GetResourceState(getPhoneResourceName()) == 'started'
end

function LBPhone.ensureRegistered()
    if LBPhone.state.appRegistered or not LBPhone.isAvailable() then
        return LBPhone.state.appRegistered
    end

    local config = getConfig()
    local app = {
        identifier = getAppIdentifier(),
        name = config.appName or 'VancePay',
        description = config.appDescription or '查看请求、确认付款、追踪最近活动',
        developer = GetResourceMetadata(VancePay.ResourceName, 'author', 0) or 'Vance',
        defaultApp = true,
        size = 59812,
        ui = getAppUiPath(),
        icon = ('https://cfx-nui-%s/html/lbphone/icon.svg'):format(VancePay.ResourceName),
        fixBlur = true,
        onOpen = function()
            LBPhone.state.appOpen = true
            LBPhone.refreshState()
        end,
        onClose = function()
            LBPhone.state.appOpen = false
        end,
    }

    local ok = callPhoneExport('AddCustomApp', app)
    if ok then
        LBPhone.state.appRegistered = true
        ensureAppInstalled()
        pushState('registered')
    end

    return LBPhone.state.appRegistered
end

function LBPhone.refreshState(options)
    options = options or {}

    if not LBPhone.isAvailable() then
        return {
            ok = false,
            code = 'lbphone_unavailable',
            message = 'LB Phone 未启动',
        }
    end

    LBPhone.ensureRegistered()
    local pageOptions = resolvePageOptions(options)

    local response = lib.callback.await('vancepay:server:getCustomerAppState', false, {
        activity_page = pageOptions.activityPage,
        activity_per_page = pageOptions.activityPerPage,
        activity_limit = pageOptions.activityPerPage,
        balance_history_page = pageOptions.balanceHistoryPage,
        balance_history_per_page = pageOptions.balanceHistoryPerPage,
        balance_history_limit = pageOptions.balanceHistoryPerPage,
        intent_limit = pageOptions.intentLimit,
    })

    if response and response.ok then
        LBPhone.state.bankBalance = tonumber(response.data.bank_balance) or 0
        LBPhone.state.activity = normalizePagedCollection(response.data.activity, pageOptions.activityPerPage)
        LBPhone.state.balanceSummary = response.data.balance_summary or {}
        LBPhone.state.balanceHistory = normalizePagedCollection(
            response.data.balance_history,
            pageOptions.balanceHistoryPerPage
        )
        LBPhone.state.loans = response.data.loans or {}
        LBPhone.state.intents = {}

        local intents = response.data.pending_intents or {}
        for index = 1, #intents do
            upsertIntent(intents[index])
        end

        pushState(options.reason or 'refresh')
    end

    return response or {
        ok = false,
        message = '同步状态失败',
    }
end

local function startDeferredOpenThread()
    if LBPhone.state.pendingOpenThread then
        return
    end

    LBPhone.state.pendingOpenThread = true

    CreateThread(function()
        while LBPhone.state.pendingOpen do
            local pendingOpen = LBPhone.state.pendingOpen

            if not pendingOpen then
                break
            end

            if GetGameTimer() >= (pendingOpen.expiresAt or 0) then
                LBPhone.state.pendingOpen = nil
                break
            end

            if canOpenAppNow() then
                local ok = callPhoneExport('OpenApp', pendingOpen.identifier, pendingOpen.payload)
                if ok == true then
                    LBPhone.state.pendingOpen = nil
                    break
                end
            end

            Wait(DEFERRED_OPEN_RETRY_MS)
        end

        LBPhone.state.pendingOpenThread = false
    end)
end

local function deferOpenApp(payload)
    LBPhone.state.pendingOpen = {
        identifier = getAppIdentifier(),
        payload = type(payload) == 'table' and payload or {},
        expiresAt = GetGameTimer() + DEFERRED_OPEN_TIMEOUT_MS,
    }

    startDeferredOpenThread()

    if VancePay.Client and type(VancePay.Client.notify) == 'function' then
        VancePay.Client.notify('当前界面占用中，关闭后将自动打开手机', 'inform')
    end

    return true
end

function LBPhone.openApp(payload)
    if not LBPhone.ensureRegistered() then
        return false
    end

    if not canOpenAppNow() then
        return deferOpenApp(payload)
    end

    local ok = callPhoneExport('OpenApp', getAppIdentifier(), payload or {})
    if ok == true then
        LBPhone.state.pendingOpen = nil
    end

    return ok == true
end

function LBPhone.handleIncomingIntent(intent)
    if not intent or intent.method ~= VancePay.PaymentMethods.phone then
        return false
    end

    if not LBPhone.ensureRegistered() then
        return false
    end

    upsertIntent(intent)
    pushState('incoming_intent')

    if getConfig().openOnNewIntent then
        LBPhone.openApp({
            intent_id = intent.intent_id,
        })
    end

    return true
end

function LBPhone.handleIntentUpdate(intent)
    if not intent or intent.method ~= VancePay.PaymentMethods.phone then
        return false
    end

    LBPhone.ensureRegistered()

    local trackedIntent = LBPhone.state.intents[tostring(intent.intent_id)]
    if not trackedIntent then
        return false
    end

    if intent.status == VancePay.IntentStatuses.awaitingCustomer then
        upsertIntent(intent)
        pushState('intent_updated')
        return LBPhone.state.appRegistered
    end

    removeIntent(intent.intent_id)
    pushState('intent_resolved')
    LBPhone.refreshState({
        reason = 'intent_resolved',
    })

    return LBPhone.state.appRegistered
end

RegisterNUICallback('lbphoneGetState', function(data, cb)
    local response = LBPhone.refreshState(data or {})
    if response and response.ok then
        cb({
            ok = true,
            data = buildAppState(),
        })
        return
    end

    cb(response or {
        ok = false,
        message = '同步状态失败',
    })
end)

RegisterNUICallback('lbphoneConfirmIntent', function(data, cb)
    local response = lib.callback.await('vancepay:server:confirmIntent', false, data or {})

    if response and response.ok then
        LBPhone.refreshState({
            reason = 'confirm_success',
        })
    else
        LBPhone.refreshState({
            reason = 'confirm_failed',
        })
        VancePay.Client.notify(response and response.message or '支付失败', 'error')
    end

    cb(response or {
        ok = false,
        message = '支付失败',
    })
end)

RegisterNUICallback('lbphoneDeclineIntent', function(data, cb)
    local response = lib.callback.await('vancepay:server:cancelIntent', false, data or {})

    if response and response.ok then
        LBPhone.refreshState({
            reason = 'decline_success',
        })
    else
        LBPhone.refreshState({
            reason = 'decline_failed',
        })
        VancePay.Client.notify(response and response.message or '取消失败', 'error')
    end

    cb(response or {
        ok = false,
        message = '取消失败',
    })
end)

RegisterNUICallback('lbphoneWithdrawBalance', function(data, cb)
    local response = lib.callback.await('vancepay:server:withdrawBalance', false, data or {})

    if response and response.ok then
        LBPhone.refreshState({
            reason = 'withdraw_success',
        })
    else
        LBPhone.refreshState({
            reason = 'withdraw_failed',
        })
        VancePay.Client.notify(response and response.message or '提现失败', 'error')
    end

    cb(response or {
        ok = false,
        message = '提现失败',
    })
end)

RegisterNUICallback('lbphoneCreateLoan', function(data, cb)
    local response = lib.callback.await('vancepay:server:createLoan', false, data or {})

    if response and response.ok then
        LBPhone.refreshState({
            reason = 'loan_created',
        })
    else
        LBPhone.refreshState({
            reason = 'loan_create_failed',
        })
        VancePay.Client.notify(response and response.message or '贷款申请失败', 'error')
    end

    cb(response or {
        ok = false,
        message = '贷款申请失败',
    })
end)

RegisterNUICallback('lbphoneRepayLoan', function(data, cb)
    local response = lib.callback.await('vancepay:server:repayLoan', false, data or {})

    if response and response.ok then
        LBPhone.refreshState({
            reason = 'loan_repaid',
        })
    else
        LBPhone.refreshState({
            reason = 'loan_repay_failed',
        })
        VancePay.Client.notify(response and response.message or '还款失败', 'error')
    end

    cb(response or {
        ok = false,
        message = '还款失败',
    })
end)

RegisterNetEvent('vancepay:client:openLbPhoneApp', function(payload)
    LBPhone.openApp(payload or {})
end)

RegisterNetEvent(VancePay.Events.client.refreshLBPhoneState, function(payload)
    LBPhone.refreshState(payload or {
        reason = 'server_push',
    })
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= VancePay.ResourceName and resourceName ~= getPhoneResourceName() then
        return
    end

    CreateThread(function()
        Wait(1200)
        if LBPhone.ensureRegistered() then
            LBPhone.refreshState({
                reason = 'resource_start',
            })
        end
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == getPhoneResourceName() then
        LBPhone.state.appRegistered = false
        LBPhone.state.appOpen = false
        LBPhone.state.pendingOpen = nil
        return
    end

    if resourceName ~= VancePay.ResourceName or not LBPhone.isAvailable() or not LBPhone.state.appRegistered then
        return
    end

    callPhoneExport('RemoveCustomApp', getAppIdentifier())
end)

CreateThread(function()
    while true do
        Wait(3000)

        if LBPhone.isAvailable() and not LBPhone.state.appRegistered then
            LBPhone.ensureRegistered()
        end
    end
end)
