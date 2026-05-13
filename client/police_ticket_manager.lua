VancePay.PoliceTicketManager = VancePay.PoliceTicketManager or {}

local Manager = VancePay.PoliceTicketManager

Manager.launchPayload = Manager.launchPayload or nil
Manager.state = Manager.state or {}

local function deepCopy(value)
    if VancePay.Utils and type(VancePay.Utils.deepCopy) == 'function' then
        return VancePay.Utils.deepCopy(value)
    end

    if type(value) ~= 'table' then
        return value
    end

    local copy = {}
    for key, innerValue in pairs(value) do
        copy[key] = deepCopy(innerValue)
    end

    return copy
end

local function applyBootstrap(payload)
    payload = type(payload) == 'table' and payload or {}
    Manager.state = payload

    if VancePay.Client.ui.view == 'policeTicketManager' then
        VancePay.Client.updateView('policeTicketManager', payload)
    else
        VancePay.Client.openView('policeTicketManager', payload)
    end

    return true
end

function Manager.refresh(filters)
    local requestPayload = deepCopy(filters or {})
    local response = lib.callback.await('vancepay:server:getPoliceTicketManagerBootstrap', false, requestPayload)
    if not response or not response.ok then
        VancePay.Client.notify(response and response.message or '罚单管理刷新失败', 'error')
        return response or { ok = false, message = '罚单管理刷新失败' }
    end

    applyBootstrap(response.data or {})
    return response
end

local function getDefaultManagerPage()
    local perPage = tonumber(Config.TransPerPage) or 15

    return {
        items = {},
        page = 1,
        per_page = perPage,
        total = 0,
        total_pages = 1,
        has_prev = false,
        has_more = false,
    }
end

local function getLoadingBootstrap()
    return {
        scope = {
            title = '罚单管理',
            subtitle = '正在加载罚单管理数据...',
            can_audit = false,
            is_admin = false,
            is_boss = false,
        },
        agencies = {},
        ticket_types = {},
        ticket_styles = {},
        filters = {
            page = 1,
            per_page = tonumber(Config.TransPerPage) or 15,
        },
        summary = {},
        tickets = getDefaultManagerPage(),
        audit = getDefaultManagerPage(),
    }
end

local function playOpenAnimation()
    CreateThread(function()
        VancePay.Client.playDeviceAnimation('tablet')
    end)
end

function Manager.open(payload)
    payload = type(payload) == 'table' and payload or {}
    Manager.launchPayload = payload
    playOpenAnimation()

    if type(payload.bootstrap) == 'table' then
        applyBootstrap(payload.bootstrap)
        return
    end

    applyBootstrap(getLoadingBootstrap())

    CreateThread(function()
        Manager.refresh(payload.filters or {})
    end)
end

local function refreshAfterMutation(response, cb)
    if response and response.ok then
        Manager.refresh(Manager.state and Manager.state.filters or {})
    else
        VancePay.Client.notify(response and response.message or '操作失败', 'error')
    end

    cb(response or { ok = false, message = '操作失败' })
end

RegisterNUICallback('refreshPoliceTicketManager', function(data, cb)
    cb(Manager.refresh(data or {}))
end)

RegisterNUICallback('getPoliceTicketManagerAudit', function(data, cb)
    cb(lib.callback.await('vancepay:server:getPoliceTicketManagerAudit', false, data or {}) or {
        ok = false,
        message = '获取罚单审计失败',
    })
end)

RegisterNUICallback('cancelManagedPoliceTicket', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:cancelManagedPoliceTicket', false, data or {}), cb)
end)

RegisterNUICallback('restoreManagedPoliceTicket', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:restoreManagedPoliceTicket', false, data or {}), cb)
end)

local function trimValue(value)
    if type(value) ~= 'string' then
        return ''
    end

    return value:match('^%s*(.-)%s*$') or ''
end

local function getManagementCommandNames()
    local policeConfig = Config.PoliceTickets or {}
    local commandConfig = type(policeConfig.managementCommand) == 'table' and policeConfig.managementCommand or {}
    local names = {}
    local seen = {}

    if commandConfig.enabled == false then
        return names
    end

    local function add(name)
        name = trimValue(name)
        if name == '' then
            return
        end

        local key = name:lower()
        if seen[key] then
            return
        end

        seen[key] = true
        names[#names + 1] = name
    end

    add(commandConfig.name)
    add('vpfineadmin')

    if #names < 1 then
        names[1] = 'vpfineadmin'
    end

    return names
end

local function openFromCommand()
    TriggerServerEvent(VancePay.Events.server.openPoliceTicketManager)
end

for _, commandName in ipairs(getManagementCommandNames()) do
    RegisterCommand(commandName, openFromCommand, false)
end
