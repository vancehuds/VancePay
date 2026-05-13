VancePay.CustomerRequest = VancePay.CustomerRequest or {}

local CustomerRequest = VancePay.CustomerRequest

CustomerRequest.pendingIntents = CustomerRequest.pendingIntents or {}
CustomerRequest.currentIntent = CustomerRequest.currentIntent or nil
CustomerRequest.cardOverlayVisible = CustomerRequest.cardOverlayVisible or false
CustomerRequest.cardPromptThread = CustomerRequest.cardPromptThread or false
CustomerRequest.cardSyncThread = CustomerRequest.cardSyncThread or false

local CARD_DISCOVERY_INTERVAL_MS = 1500

local function getCurrentUnixTime()
    local utils = VancePay.Utils or rawget(_G, 'Utils')
    if not utils or type(utils.getUnixTime) ~= 'function' then
        return nil
    end

    local currentTime = utils.getUnixTime()
    if type(currentTime) == 'number' then
        return currentTime
    end

    return nil
end

local function hideCardSwipePrompt()
    if CustomerRequest.cardOverlayVisible then
        VancePay.Client.hideCardSwipeOverlay()
        CustomerRequest.cardOverlayVisible = false
    end
end

local function isIntentFinished(intent)
    if not intent then
        return true
    end

    return intent.status == VancePay.IntentStatuses.completed
        or intent.status == VancePay.IntentStatuses.cancelled
        or intent.status == VancePay.IntentStatuses.expired
        or intent.status == VancePay.IntentStatuses.failed
end

local function getPendingIntent(intentId)
    if not intentId then
        return nil
    end

    return CustomerRequest.pendingIntents[tostring(intentId)]
end

local function upsertPendingIntent(intent)
    if not intent or not intent.intent_id then
        return nil
    end

    CustomerRequest.pendingIntents[tostring(intent.intent_id)] = intent
    return intent
end

local function removePendingIntent(intentId)
    if not intentId then
        return
    end

    CustomerRequest.pendingIntents[tostring(intentId)] = nil

    if CustomerRequest.currentIntent and CustomerRequest.currentIntent.intent_id == intentId then
        CustomerRequest.currentIntent = nil
    end
end

local function countPendingIntents(method)
    local count = 0

    for _, intent in pairs(CustomerRequest.pendingIntents) do
        if not isIntentFinished(intent) and (not method or intent.method == method) then
            count = count + 1
        end
    end

    return count
end

local function getIntentExpiryWeight(intent)
    if not intent then
        return math.huge
    end

    local expiresIn = tonumber(intent.expires_in)
    if expiresIn then
        return math.max(0, expiresIn)
    end

    local utils = VancePay.Utils or rawget(_G, 'Utils')
    if utils and type(utils.parseSqlDateTime) == 'function' then
        local expiresAt = utils.parseSqlDateTime(intent.expires_at)
        local currentTime = getCurrentUnixTime()
        if expiresAt and currentTime then
            return math.max(0, expiresAt - currentTime)
        end
    end

    return math.huge
end

local function isHigherPriorityIntent(left, right)
    if not right then
        return true
    end

    local leftExpiry = getIntentExpiryWeight(left)
    local rightExpiry = getIntentExpiryWeight(right)

    if leftExpiry == rightExpiry then
        return (tonumber(left.intent_id) or 0) > (tonumber(right.intent_id) or 0)
    end

    return leftExpiry < rightExpiry
end

local function getPreferredPhoneIntent()
    local currentIntent = CustomerRequest.currentIntent
    if currentIntent and currentIntent.method == VancePay.PaymentMethods.phone then
        local trackedIntent = getPendingIntent(currentIntent.intent_id)
        if trackedIntent and not isIntentFinished(trackedIntent) then
            return trackedIntent
        end
    end

    local selectedIntent = nil

    for _, intent in pairs(CustomerRequest.pendingIntents) do
        if intent.method == VancePay.PaymentMethods.phone
            and not isIntentFinished(intent)
            and isHigherPriorityIntent(intent, selectedIntent) then
            selectedIntent = intent
        end
    end

    return selectedIntent
end

local function getCardIntentDistance(intent)
    if not intent or intent.method ~= VancePay.PaymentMethods.card or isIntentFinished(intent) then
        return nil
    end

    local ped = PlayerPedId()
    local myCoords = GetEntityCoords(ped)
    local maxDistance = Config.TargetingDistance + 0.5

    if intent.terminal_type == VancePay.TerminalTypes.fixed and type(intent.terminal_coords) == 'table' then
        local coords = vector3(intent.terminal_coords.x, intent.terminal_coords.y, intent.terminal_coords.z)
        local distance = #(myCoords - coords)
        if distance <= maxDistance then
            return distance
        end

        return nil
    end

    local cashierSource = GetPlayerFromServerId(intent.cashier_source or 0)
    if cashierSource ~= -1 then
        local cashierPed = GetPlayerPed(cashierSource)
        if DoesEntityExist(cashierPed) then
            local distance = #(myCoords - GetEntityCoords(cashierPed))
            if distance <= maxDistance then
                return distance
            end
        end
    end

    return nil
end

local function getReachableCardIntent()
    local selectedIntent = nil
    local selectedDistance = nil
    local pendingCount = 0

    for _, intent in pairs(CustomerRequest.pendingIntents) do
        if intent.method == VancePay.PaymentMethods.card and not isIntentFinished(intent) then
            pendingCount = pendingCount + 1

            local distance = getCardIntentDistance(intent)
            if distance and (not selectedIntent
                or distance < selectedDistance
                or (distance == selectedDistance and isHigherPriorityIntent(intent, selectedIntent))) then
                selectedIntent = intent
                selectedDistance = distance
            end
        end
    end

    return selectedIntent, pendingCount
end

local startCardSwipePromptThread
local startCardIntentSyncThread

local function trimValue(value)
    if type(value) ~= 'string' then
        return ''
    end

    return value:match('^%s*(.-)%s*$') or ''
end

local function formatQuantity(value)
    local amount = tonumber(value) or 0
    if math.abs(amount - math.floor(amount)) < 0.0001 then
        return tostring(math.floor(amount))
    end

    return ('%.3f'):format(amount):gsub('0+$', ''):gsub('%.$', '')
end

local function buildIntentSummary(intent)
    local description = trimValue(intent and intent.item_description)
    if description ~= '' then
        return description
    end

    local itemLines = intent and intent.item_lines
    if type(itemLines) ~= 'table' or #itemLines < 1 then
        return ''
    end

    local parts = {}
    local previewCount = math.min(#itemLines, 2)

    for index = 1, previewCount do
        local line = itemLines[index]
        parts[#parts + 1] = ('%s x%s'):format(
            trimValue(line and line.name) ~= '' and trimValue(line.name) or '商品',
            formatQuantity(line and line.quantity or 0)
        )
    end

    if #itemLines > previewCount then
        parts[#parts + 1] = ('等 %d 项'):format(#itemLines)
    end

    return table.concat(parts, ' · ')
end

local function showCardSwipePrompt(intent, pendingCount)
    if not intent then
        hideCardSwipePrompt()
        return
    end

    VancePay.Client.showCardSwipeOverlay({
        intent_id = intent.intent_id,
        store_name = intent.store_name,
        final_amount = intent.final_amount,
        expires_at = intent.expires_at,
        expires_in = getIntentExpiryWeight(intent),
        helper_text = '按 E 刷卡支付',
        queue_text = pendingCount > 1 and ('另有 %d 笔待处理订单'):format(pendingCount - 1) or '任何靠近终端的持卡人都可以完成付款',
        summary = buildIntentSummary(intent),
        terminal_serial_number = intent.terminal_serial_number,
    })
    CustomerRequest.cardOverlayVisible = true
end

local function clearCardPendingIntents()
    for intentId, intent in pairs(CustomerRequest.pendingIntents) do
        if intent.method == VancePay.PaymentMethods.card then
            CustomerRequest.pendingIntents[intentId] = nil
        end
    end
end

local function syncReachableCardIntents(items)
    clearCardPendingIntents()

    for index = 1, #(items or {}) do
        upsertPendingIntent(items[index])
    end

    if countPendingIntents(VancePay.PaymentMethods.card) > 0 then
        startCardSwipePromptThread()
    else
        hideCardSwipePrompt()
    end
end

local function refreshReachableCardIntents()
    local response = lib.callback.await('vancepay:server:getReachableCardIntents', false, {
        limit = 20,
    })

    if not response or not response.ok then
        return response or {
            ok = false,
            message = '同步附近刷卡订单失败',
        }
    end

    syncReachableCardIntents(response.data and response.data.items or {})
    return response
end

local function syncPhoneView()
    local nextPhoneIntent = getPreferredPhoneIntent()
    CustomerRequest.currentIntent = nextPhoneIntent

    if not nextPhoneIntent then
        if VancePay.Client.ui.view == 'customer' then
            VancePay.Client.closeView()
        end

        return
    end

    if VancePay.Client.ui.view == 'customer' then
        VancePay.Client.updateView('customer', {
            intent = nextPhoneIntent,
        })
        return
    end

    VancePay.Client.openView('customer', {
        intent = nextPhoneIntent,
    })
end

function CustomerRequest.restorePendingIntents(options)
    options = options or {}

    local response = lib.callback.await('vancepay:server:getCustomerPendingIntents', false, {
        limit = options.limit or 20,
    })

    if not response or not response.ok then
        return response or {
            ok = false,
            message = '恢复待支付请求失败',
        }
    end

    CustomerRequest.pendingIntents = {}
    CustomerRequest.currentIntent = nil
    hideCardSwipePrompt()

    local useLbPhoneForPhoneIntents = VancePay.LBPhone
        and type(VancePay.LBPhone.isAvailable) == 'function'
        and VancePay.LBPhone.isAvailable()
    local items = response.data and response.data.items or {}

    for index = 1, #items do
        local intent = items[index]
        if intent and intent.intent_id then
            if intent.method == VancePay.PaymentMethods.phone and useLbPhoneForPhoneIntents then
                -- LB Phone refreshes its own pending requests on startup; keep fallback state clean.
            else
                upsertPendingIntent(intent)
            end
        end
    end

    syncPhoneView()
    refreshReachableCardIntents()

    return {
        ok = true,
        data = {
            pending_count = countPendingIntents(),
        },
        message = '待支付请求已恢复',
    }
end

startCardSwipePromptThread = function()
    if CustomerRequest.cardPromptThread then
        return
    end

    CustomerRequest.cardPromptThread = true

    CreateThread(function()
        while countPendingIntents(VancePay.PaymentMethods.card) > 0 do
            local targetIntent = nil
            local pendingCount = 0

            if not VancePay.Client.ui.open then
                targetIntent, pendingCount = getReachableCardIntent()
            end

            if targetIntent then
                showCardSwipePrompt(targetIntent, pendingCount)

                if IsControlJustReleased(0, Config.CardSwipeControl) then
                    VancePay.Client.playDeviceAnimation('swipe')

                    local response = lib.callback.await('vancepay:server:swipeIntent', false, {
                        intent_id = targetIntent.intent_id,
                    })

                    if not response or not response.ok then
                        VancePay.Client.notify(response and response.message or '刷卡失败', 'error')
                        refreshReachableCardIntents()
                    else
                        removePendingIntent(targetIntent.intent_id)
                    end
                end
            else
                hideCardSwipePrompt()
            end

            Wait(0)
        end

        hideCardSwipePrompt()
        CustomerRequest.cardPromptThread = false
        syncPhoneView()
    end)
end

startCardIntentSyncThread = function()
    if CustomerRequest.cardSyncThread then
        return
    end

    CustomerRequest.cardSyncThread = true

    CreateThread(function()
        while true do
            refreshReachableCardIntents()
            Wait(CARD_DISCOVERY_INTERVAL_MS)
        end
    end)
end

function CustomerRequest.open(payload)
    if payload
        and payload.method == VancePay.PaymentMethods.phone
        and VancePay.LBPhone
        and type(VancePay.LBPhone.handleIncomingIntent) == 'function'
        and VancePay.LBPhone.handleIncomingIntent(payload) then
        removePendingIntent(payload.intent_id)
        syncPhoneView()
        return
    end

    if not payload or not payload.intent_id then
        return
    end

    upsertPendingIntent(payload)

    if payload.method == VancePay.PaymentMethods.card then
        startCardSwipePromptThread()
        return
    end

    syncPhoneView()
end

function CustomerRequest.handleIntentUpdate(payload)
    if not payload or not payload.intent_id then
        return
    end

    if payload.method == VancePay.PaymentMethods.phone
        and VancePay.LBPhone
        and type(VancePay.LBPhone.handleIntentUpdate) == 'function'
        and VancePay.LBPhone.handleIntentUpdate(payload) then
        removePendingIntent(payload.intent_id)
        syncPhoneView()
        return
    end

    local trackedIntent = getPendingIntent(payload.intent_id)
    if not trackedIntent then
        return
    end

    local isCurrentPhoneIntent = CustomerRequest.currentIntent
        and CustomerRequest.currentIntent.method == VancePay.PaymentMethods.phone
        and CustomerRequest.currentIntent.intent_id == payload.intent_id

    if isIntentFinished(payload) then
        if payload.method == VancePay.PaymentMethods.phone
            and isCurrentPhoneIntent
            and VancePay.Client.ui.view == 'customer' then
            upsertPendingIntent(payload)
            CustomerRequest.currentIntent = payload
            VancePay.Client.updateView('customer', {
                intent = payload,
            })

            CreateThread(function()
                Wait(1500)
                removePendingIntent(payload.intent_id)
                syncPhoneView()
            end)
            return
        end

        removePendingIntent(payload.intent_id)

        if payload.method == VancePay.PaymentMethods.card then
            hideCardSwipePrompt()
        end

        syncPhoneView()
        return
    end

    upsertPendingIntent(payload)

    if payload.method == VancePay.PaymentMethods.card then
        startCardSwipePromptThread()
        return
    end

    syncPhoneView()
end

RegisterNUICallback('confirmPayment', function(data, cb)
    local intent = CustomerRequest.currentIntent and getPendingIntent(CustomerRequest.currentIntent.intent_id)
        or CustomerRequest.currentIntent

    if not intent or intent.method ~= VancePay.PaymentMethods.phone or isIntentFinished(intent) then
        cb({ ok = false, message = '当前没有待确认订单' })
        return
    end

    data = data or {}
    data.intent_id = intent.intent_id

    local response = lib.callback.await('vancepay:server:confirmIntent', false, data)

    if not response or not response.ok then
        CustomerRequest.restorePendingIntents({
            limit = 20,
        })
        VancePay.Client.notify(response and response.message or '支付失败', 'error')
    end

    cb(response or { ok = false, message = '支付失败' })
end)

RegisterNUICallback('declinePayment', function(data, cb)
    local intent = CustomerRequest.currentIntent and getPendingIntent(CustomerRequest.currentIntent.intent_id)
        or CustomerRequest.currentIntent

    if not intent or intent.method ~= VancePay.PaymentMethods.phone or isIntentFinished(intent) then
        cb({ ok = false, message = '当前没有待确认订单' })
        return
    end

    data = data or {}
    data.intent_id = intent.intent_id

    local response = lib.callback.await('vancepay:server:cancelIntent', false, data)
    if not response or not response.ok then
        CustomerRequest.restorePendingIntents({
            limit = 20,
        })
        VancePay.Client.notify(response and response.message or '取消失败', 'error')
    end

    cb(response or { ok = false, message = '取消失败' })
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= VancePay.ResourceName then
        return
    end

    CreateThread(function()
        Wait(1500)
        CustomerRequest.restorePendingIntents({
            limit = 20,
        })
        startCardIntentSyncThread()
    end)
end)
