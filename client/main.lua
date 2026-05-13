VancePay.Client = VancePay.Client or {}

local Client = VancePay.Client

Client.ui = Client.ui or {
    open = false,
    view = nil,
}

local function trimValue(value)
    if type(value) ~= 'string' then
        return value
    end

    return value:match('^%s*(.-)%s*$')
end

function Client.notify(message, notifyType)
    lib.notify({
        title = 'VancePay',
        description = message,
        type = notifyType or 'inform',
        position = Config.Notifications.position,
        duration = Config.Notifications.duration,
    })
end

function Client.requestAnimDict(dict)
    if not dict or dict == '' then
        return false
    end

    RequestAnimDict(dict)
    local timeoutAt = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dict) do
        Wait(0)
        if GetGameTimer() > timeoutAt then
            return false
        end
    end

    return true
end

function Client.playAnimation(dict, clip, duration, flags)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return false
    end

    if not Client.requestAnimDict(dict) then
        return false
    end

    TaskPlayAnim(ped, dict, clip, 4.0, 4.0, duration or -1, flags or 49, 0.0, false, false, false)
    Wait(duration or 1000)
    StopAnimTask(ped, dict, clip, 1.0)

    return true
end

function Client.playScenario(scenarioName, duration)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return false
    end

    TaskStartScenarioInPlace(ped, scenarioName, 0, true)
    Wait(duration or 1000)
    ClearPedTasks(ped)

    return true
end

function Client.playDeviceAnimation(kind)
    local settings = Config.Animations and Config.Animations[kind]
    if type(settings) ~= 'table' then
        return false
    end

    if settings.scenario then
        return Client.playScenario(settings.scenario, settings.duration)
    end

    if settings.dict and settings.clip then
        return Client.playAnimation(settings.dict, settings.clip, settings.duration, settings.flags)
    end

    return false
end

function Client.showHelpText(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

function Client.showTextUI(text)
    pcall(function()
        lib.showTextUI(text)
    end)
end

function Client.hideTextUI()
    pcall(function()
        lib.hideTextUI()
    end)
end

function Client.promptBindingCode(terminalType, promptMessage)
    local deviceLabel = terminalType == VancePay.TerminalTypes.tablet and '管理平板' or '便携 POS'
    local result = lib.inputDialog(('绑定%s'):format(deviceLabel), {
        {
            type = 'input',
            label = '绑定码',
            description = promptMessage or '输入店主 / 经理 / 管理员生成的一次性绑定码',
            placeholder = '例如 VPABC123',
            required = true,
            min = 4,
            max = 24,
        }
    })

    if not result then
        return nil
    end

    local code = string.upper(trimValue(result[1] or ''))
    if code == '' then
        return nil
    end

    return code
end

function Client.redeemBindingCode(payload)
    payload = type(payload) == 'table' and payload or {}

    local bindingCode = Client.promptBindingCode(payload.terminal_type, payload.prompt_message)
    if not bindingCode then
        return nil, 'cancelled'
    end

    local response = lib.callback.await('vancepay:server:redeemBindingCode', false, {
        binding_code = bindingCode,
        terminal_type = payload.terminal_type,
        item_name = payload.item_name,
        item = payload.item or {},
    })

    if not response or not response.ok then
        Client.notify(response and response.message or '设备绑定失败', 'error')
        return nil, response
    end

    if response.message then
        local notifyType = response.data and response.data.metadata_written == false and 'warning' or 'success'
        Client.notify(response.message, notifyType)
    end

    return response.data, response
end

function Client.setFocus(focus)
    Client.ui.open = focus == true
    SetNuiFocus(Client.ui.open, Client.ui.open)
    SetNuiFocusKeepInput(false)
end

function Client.setPlacementMode(active, payload)
    active = active == true

    if active then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    elseif Client.ui.open then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
    end

    Client.sendNui('placementMode', {
        active = active,
        message = payload and payload.message or nil,
        tone = payload and payload.tone or nil,
    })
end

function Client.sendNui(action, payload)
    SendNUIMessage({
        action = action,
        data = payload or {},
    })
end

function Client.openView(view, payload)
    Client.ui.view = view
    Client.setFocus(true)
    Client.sendNui('open', {
        view = view,
        payload = payload or {},
    })
end

function Client.updateView(view, payload)
    if Client.ui.view ~= view then
        return
    end

    Client.sendNui('update', {
        view = view,
        payload = payload or {},
    })
end

function Client.closeView()
    Client.ui.view = nil
    Client.setFocus(false)
    Client.sendNui('placementMode', {
        active = false,
    })
    Client.sendNui('close', {})
end

function Client.showCardSwipeOverlay(payload)
    Client.sendNui('cardSwipeOverlay', {
        visible = true,
        payload = payload or {},
    })
end

function Client.hideCardSwipeOverlay()
    Client.sendNui('cardSwipeOverlay', {
        visible = false,
    })
end

local function collectNearbyPlayers(distance)
    local ped = PlayerPedId()
    local myCoords = GetEntityCoords(ped)
    local players = GetActivePlayers()
    local list = {}
    local ids = {}

    for index = 1, #players do
        local player = players[index]
        if player ~= PlayerId() then
            local targetPed = GetPlayerPed(player)
            if DoesEntityExist(targetPed) then
                local distanceToTarget = #(myCoords - GetEntityCoords(targetPed))
                if distanceToTarget <= (distance or Config.TargetingDistance) then
                    local serverId = GetPlayerServerId(player)
                    ids[#ids + 1] = serverId
                    list[#list + 1] = {
                        source = serverId,
                        name = GetPlayerName(player) or ('Player #' .. tostring(serverId)),
                        distance = math.floor(distanceToTarget * 10 + 0.5) / 10,
                    }
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.distance < b.distance
    end)

    return list, ids
end

function Client.getNearbyPlayers(distance)
    return collectNearbyPlayers(distance)
end

RegisterNUICallback('closePanel', function(_, cb)
    Client.closeView()
    cb({ ok = true })
end)

RegisterNUICallback('ping', function(_, cb)
    cb({ ok = true })
end)

RegisterNUICallback('nuiReady', function(_, cb)
    Client.closeView()
    Client.hideCardSwipeOverlay()
    cb({ ok = true })
end)

lib.callback.register('vancepay:client:getNearbyPlayers', function(distance)
    local _, ids = collectNearbyPlayers(distance)
    return ids
end)

lib.callback.register('vancepay:client:isIntentReachable', function(payload)
    payload = payload or {}
    local ped = PlayerPedId()
    local myCoords = GetEntityCoords(ped)
    local maxDistance = tonumber(payload.distance) or Config.TargetingDistance

    if payload.terminal_type == VancePay.TerminalTypes.fixed and type(payload.coords) == 'table' then
        local terminalCoords = vector3(payload.coords.x, payload.coords.y, payload.coords.z)
        return #(myCoords - terminalCoords) <= (maxDistance + 0.5)
    end

    if payload.cashier_source then
        local cashierPlayer = GetPlayerFromServerId(payload.cashier_source)
        if cashierPlayer ~= -1 then
            local cashierPed = GetPlayerPed(cashierPlayer)
            if DoesEntityExist(cashierPed) then
                return #(myCoords - GetEntityCoords(cashierPed)) <= (maxDistance + 0.5)
            end
        end
    end

    return false
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= VancePay.ResourceName then
        return
    end

    CreateThread(function()
        Wait(250)
        Client.closeView()
    end)
end)

RegisterNetEvent(VancePay.Events.client.openPos, function(payload)
    if VancePay.PaymentFlow and VancePay.PaymentFlow.open then
        VancePay.PaymentFlow.open(payload or {})
    end
end)

RegisterNetEvent(VancePay.Events.client.openAdmin, function(payload)
    if VancePay.Admin and VancePay.Admin.open then
        VancePay.Admin.open(payload or {})
    end
end)

RegisterNetEvent(VancePay.Events.client.openCollections, function(payload)
    if VancePay.Collections and VancePay.Collections.open then
        VancePay.Collections.open(payload or {})
    end
end)

RegisterNetEvent(VancePay.Events.client.openPoliceTicketManager, function(payload)
    if VancePay.PoliceTicketManager and VancePay.PoliceTicketManager.open then
        VancePay.PoliceTicketManager.open(payload or {})
    end
end)

RegisterNetEvent(VancePay.Events.client.openCustomerIntent, function(payload)
    if VancePay.CustomerRequest and VancePay.CustomerRequest.open then
        VancePay.CustomerRequest.open(payload or {})
    end
end)

RegisterNetEvent(VancePay.Events.client.intentUpdated, function(payload)
    if VancePay.PaymentFlow and VancePay.PaymentFlow.handleIntentUpdate then
        VancePay.PaymentFlow.handleIntentUpdate(payload)
    end

    if VancePay.CustomerRequest and VancePay.CustomerRequest.handleIntentUpdate then
        VancePay.CustomerRequest.handleIntentUpdate(payload)
    end
end)

local function refreshFixedTerminals()
    if not VancePay.PosInteraction or not VancePay.PosInteraction.syncFixedTerminals then
        return
    end

    local response = lib.callback.await('vancepay:server:getFixedTerminals', false)
    if response and response.ok then
        VancePay.PosInteraction.syncFixedTerminals(response.data or {})
        return
    end

    VancePay.PosInteraction.syncFixedTerminals({})
end

local function clearFixedTerminals()
    if VancePay.PosInteraction and VancePay.PosInteraction.clearFixedTerminals then
        VancePay.PosInteraction.clearFixedTerminals()
    end
end

Client.fixedTerminalRefreshSequence = Client.fixedTerminalRefreshSequence or 0

local function scheduleFixedTerminalRefresh(delays)
    delays = type(delays) == 'table' and delays or { 0 }

    Client.fixedTerminalRefreshSequence = Client.fixedTerminalRefreshSequence + 1
    local sequence = Client.fixedTerminalRefreshSequence

    CreateThread(function()
        for index = 1, #delays do
            local delay = tonumber(delays[index]) or 0
            if delay > 0 then
                Wait(delay)
            end

            if sequence ~= Client.fixedTerminalRefreshSequence then
                return
            end

            refreshFixedTerminals()
        end
    end)
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    scheduleFixedTerminalRefresh({ 0, 2000 })
end)

RegisterNetEvent('QBCore:Client:OnPermissionUpdate', function()
    scheduleFixedTerminalRefresh({ 0 })
end)

RegisterNetEvent('qbx_core:client:onGroupUpdate', function()
    scheduleFixedTerminalRefresh({ 0 })
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    Client.fixedTerminalRefreshSequence = Client.fixedTerminalRefreshSequence + 1
    clearFixedTerminals()
end)

RegisterNetEvent(VancePay.Events.client.fixedTerminalsUpdated, function()
    refreshFixedTerminals()
end)

CreateThread(function()
    scheduleFixedTerminalRefresh({ 1000 })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= VancePay.ResourceName then
        return
    end

    Client.hideTextUI()
    Client.hideCardSwipeOverlay()

    clearFixedTerminals()

    if VancePay.FixedTerminalPlacement and VancePay.FixedTerminalPlacement.cancel then
        VancePay.FixedTerminalPlacement.cancel('固定 POS 摆放已中断', true)
    end

    Client.closeView()
end)
