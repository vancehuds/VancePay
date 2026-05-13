VancePay.Admin = VancePay.Admin or {}

local Admin = VancePay.Admin
local SharedUtils = VancePay.Utils or rawget(_G, 'Utils')

Admin.context = Admin.context or nil
Admin.launchPayload = Admin.launchPayload or nil

local applyBootstrap

local function trimValue(value)
    if SharedUtils and type(SharedUtils.trim) == 'function' then
        return SharedUtils.trim(value)
    end

    if type(value) ~= 'string' then
        return value
    end

    return value:match('^%s*(.-)%s*$')
end

local function isBlankValue(value)
    if SharedUtils and type(SharedUtils.isBlank) == 'function' then
        return SharedUtils.isBlank(value)
    end

    return value == nil or trimValue(value) == ''
end

local function deepCopy(value)
    local utils = SharedUtils
    if utils and type(utils.deepCopy) == 'function' then
        return utils.deepCopy(value)
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

local function collectPlacementData()
    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, -1.0)

    return {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    }, GetEntityHeading(ped)
end

local function findContextTerminal(terminalId)
    terminalId = tonumber(terminalId)
    if not terminalId or not Admin.context or type(Admin.context.terminals) ~= 'table' then
        return nil
    end

    for index = 1, #Admin.context.terminals do
        local terminal = Admin.context.terminals[index]
        if tonumber(terminal.id) == terminalId then
            return terminal
        end
    end

    return nil
end

local function isStoreTabletContext()
    return Admin.context and Admin.context.mode == 'store'
end

local function hasContextEmployee(citizenid)
    citizenid = trimValue(citizenid)
    if isBlankValue(citizenid) or not Admin.context or type(Admin.context.employees) ~= 'table' then
        return false
    end

    for index = 1, #Admin.context.employees do
        local employee = Admin.context.employees[index]
        if trimValue(employee and employee.citizenid) == citizenid then
            return true
        end
    end

    return false
end

local function resolveTerminalModelName(modelKey, terminal)
    modelKey = trimValue(modelKey or (terminal and terminal.model_key) or Config.DefaultTerminalModelKey)

    if Admin.context and type(Admin.context.active_terminal_models) == 'table' then
        for index = 1, #Admin.context.active_terminal_models do
            local model = Admin.context.active_terminal_models[index]
            if model.model_key == modelKey and not isBlankValue(model.model_name) then
                return model.model_name, model.model_key
            end
        end
    end

    if terminal and terminal.model_key == modelKey and not isBlankValue(terminal.model_name) then
        return terminal.model_name, terminal.model_key
    end

    if modelKey and Config.POSModels[modelKey] and not isBlankValue(Config.POSModels[modelKey].model) then
        return Config.POSModels[modelKey].model, modelKey
    end

    local fallback = Config.POSModels[Config.DefaultTerminalModelKey]
    return fallback and fallback.model or nil, Config.DefaultTerminalModelKey
end

local function finishFixedTerminalPlacement(data, placementResult)
    if not placementResult or not placementResult.ok then
        VancePay.Client.setPlacementMode(false, {
            message = placementResult and placementResult.message or '已取消固定 POS 摆放',
            tone = 'neutral',
        })
        return
    end

    data.coords = placementResult.coords
    data.heading = placementResult.heading

    local response = lib.callback.await('vancepay:server:saveTerminal', false, data)
    local message = response and response.message or '终端保存失败'
    local tone = 'error'

    if response and response.ok then
        tone = 'success'
        local refreshed = Admin.refresh()
        if refreshed and not refreshed.ok then
            message = ('%s，但管理面板刷新失败'):format(message)
        end
    else
        VancePay.Client.notify(message, 'error')
    end

    VancePay.Client.setPlacementMode(false, {
        message = message,
        tone = tone,
    })
end

local function beginFixedTerminalPlacement(data, terminal)
    local placement = VancePay.FixedTerminalPlacement

    if not placement or type(placement.start) ~= 'function' then
        data.coords, data.heading = collectPlacementData()
        return lib.callback.await('vancepay:server:saveTerminal', false, data)
    end

    local modelName, resolvedModelKey = resolveTerminalModelName(data.model_key, terminal)
    local interactionOnly = Utils.isInteractionOnlyTerminalModel(resolvedModelKey, modelName)
    data.model_key = resolvedModelKey

    local started, reason = placement.start({
        model_key = resolvedModelKey,
        model_name = modelName,
        coords = terminal and terminal.coords or nil,
        heading = terminal and terminal.heading or nil,
    }, function(result)
        CreateThread(function()
            finishFixedTerminalPlacement(data, result)
        end)
    end)

    if not started then
        return {
            ok = false,
            message = reason or '无法开始固定 POS 摆放',
        }
    end

    VancePay.Client.setPlacementMode(true, {
        message = interactionOnly
            and '固定 POS 摆放中：红色标记是交互点，R 对准台面，方向键微调，Enter 确认'
            or '固定 POS 摆放中：R 对准台面，方向键微调，Enter 确认',
        tone = 'neutral',
    })

    return {
        ok = true,
        message = '已进入固定 POS 摆放模式',
    }
end

function Admin.refresh(optionalPayload)
    local requestPayload = deepCopy(Admin.launchPayload or {})
    optionalPayload = type(optionalPayload) == 'table' and optionalPayload or {}

    for key, value in pairs(optionalPayload) do
        requestPayload[key] = value
    end

    local response = lib.callback.await('vancepay:server:getAdminBootstrap', false, requestPayload)
    if not response or not response.ok then
        VancePay.Client.notify(response and response.message or '平板初始化失败', 'error')
        return response or { ok = false, message = '平板初始化失败' }
    end

    applyBootstrap(response.data)
    return response
end

applyBootstrap = function(payload)
    if type(payload) ~= 'table' then
        return false
    end

    Admin.launchPayload = Admin.launchPayload or {}
    Admin.context = payload
    Admin.launchPayload.store_id = payload.selected_store_id

    if VancePay.Client.ui.view == 'admin' then
        VancePay.Client.updateView('admin', payload)
    else
        VancePay.Client.openView('admin', payload)
    end

    return true
end

function Admin.open(payload)
    payload = type(payload) == 'table' and payload or {}

    if payload.binding_required then
        local bindingData = VancePay.Client.redeemBindingCode({
            terminal_type = payload.terminal_type or VancePay.TerminalTypes.tablet,
            item_name = payload.item_name or Config.TabletItem,
            item = payload.item or {},
            prompt_message = payload.prompt_message,
        })

        if bindingData then
            payload.binding_required = false
            payload.serial_number = bindingData.launch_serial_number
            payload.item = bindingData.metadata or payload.item
            payload.bootstrap = nil
        elseif type(payload.bootstrap) ~= 'table' and type(payload.fallback_bootstrap) == 'table' then
            payload.bootstrap = payload.fallback_bootstrap
        elseif type(payload.bootstrap) ~= 'table' then
            return
        end
    end

    local bootstrap = type(payload.bootstrap) == 'table' and payload.bootstrap or nil
    local launchPayload = deepCopy(payload)
    launchPayload.bootstrap = nil
    Admin.launchPayload = launchPayload

    VancePay.Client.playDeviceAnimation('tablet')

    if not applyBootstrap(bootstrap) then
        Admin.refresh()
    end
end

local function refreshAfterMutation(response, cb)
    if response and response.ok then
        Admin.refresh()
    else
        VancePay.Client.notify(response and response.message or '操作失败', 'error')
    end

    cb(response or { ok = false, message = '操作失败' })
end

RegisterNUICallback('refreshAdmin', function(data, cb)
    data = data or {}
    if Admin.launchPayload then
        Admin.launchPayload.store_id = data.store_id or Admin.launchPayload.store_id
    end

    cb(Admin.refresh(data))
end)

RegisterNUICallback('saveStore', function(data, cb)
    data = data or {}

    if isStoreTabletContext() and not (data.id or data.store_id) then
        cb({
            ok = false,
            message = '店铺平板不支持新建店铺',
        })
        return
    end

    refreshAfterMutation(lib.callback.await('vancepay:server:saveStore', false, data), cb)
end)

RegisterNUICallback('saveStoreTaxSettings', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:saveStoreTaxSettings', false, data or {}), cb)
end)

RegisterNUICallback('saveStoreCommissionSettings', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:saveStoreCommissionSettings', false, data or {}), cb)
end)

RegisterNUICallback('saveTaxDefaults', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:saveTaxDefaults', false, data or {}), cb)
end)

RegisterNUICallback('archiveStore', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:archiveStore', false, data and data.store_id or nil), cb)
end)

RegisterNUICallback('restoreStore', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:restoreStore', false, data and data.store_id or nil), cb)
end)

RegisterNUICallback('changeStoreOwner', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:changeStoreOwner', false, data or {}), cb)
end)

RegisterNUICallback('storePayout', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:storePayout', false, data or {}), cb)
end)

RegisterNUICallback('saveEmployee', function(data, cb)
    data = data or {}

    if Admin.launchPayload and Admin.launchPayload.store_id and not data.store_id then
        data.store_id = Admin.launchPayload.store_id
    end

    if isStoreTabletContext() and not hasContextEmployee(data.citizenid) then
        cb({
            ok = false,
            message = '店铺平板不支持手动添加员工，请先同步产业账户人员',
        })
        return
    end

    refreshAfterMutation(lib.callback.await('vancepay:server:saveEmployee', false, data), cb)
end)

RegisterNUICallback('syncStoreEmployees', function(data, cb)
    data = data or {}

    if Admin.launchPayload and Admin.launchPayload.store_id and not data.store_id then
        data.store_id = Admin.launchPayload.store_id
    end

    refreshAfterMutation(lib.callback.await('vancepay:server:syncStoreEmployees', false, data), cb)
end)

RegisterNUICallback('removeEmployee', function(data, cb)
    if isStoreTabletContext() then
        cb({
            ok = false,
            message = '店铺平板不支持手动移除员工，请使用同步功能维护成员',
        })
        return
    end

    refreshAfterMutation(lib.callback.await('vancepay:server:removeEmployee', false, data or {}), cb)
end)

RegisterNUICallback('resolveCitizenIdByPlayerId', function(data, cb)
    data = data or {}

    if not data.store_id then
        data.store_id = (Admin.context and Admin.context.selected_store_id)
            or (Admin.launchPayload and Admin.launchPayload.store_id)
    end

    cb(lib.callback.await('vancepay:server:resolveCitizenIdByPlayerId', false, data) or {
        ok = false,
        message = '查询 CitizenID 失败',
    })
end)

RegisterNUICallback('saveTerminal', function(data, cb)
    data = data or {}

    if Admin.launchPayload and Admin.launchPayload.store_id and data.mode ~= 'admin' and not data.store_id then
        data.store_id = Admin.launchPayload.store_id
    end

    if data.type == VancePay.TerminalTypes.fixed
        and not (data.terminal_id or data.id)
        and not (Admin.context and Admin.context.is_admin)
    then
        cb({
            ok = false,
            message = '只有管理员可以新建固定 POS',
        })
        return
    end

    if data.type == VancePay.TerminalTypes.fixed and not data.coords then
        local terminal = findContextTerminal(data.terminal_id or data.id)
        local shouldPlace = data.place_terminal == true

        if terminal and type(terminal.coords) == 'table' and not shouldPlace then
            data.coords = deepCopy(terminal.coords)
            data.heading = terminal.heading
        else
            cb(beginFixedTerminalPlacement(data, terminal))
            return
        end
    end

    refreshAfterMutation(lib.callback.await('vancepay:server:saveTerminal', false, data), cb)
end)

RegisterNUICallback('generateBindingCode', function(data, cb)
    data = data or {}

    if Admin.launchPayload and Admin.launchPayload.store_id and not data.store_id then
        data.store_id = Admin.launchPayload.store_id
    end

    local response = lib.callback.await('vancepay:server:generateBindingCode', false, data)
    if not response or not response.ok then
        VancePay.Client.notify(response and response.message or '绑定码生成失败', 'error')
    end

    cb(response or { ok = false, message = '绑定码生成失败' })
end)

RegisterNUICallback('archiveTerminal', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:archiveTerminal', false, data and data.terminal_id or nil), cb)
end)

RegisterNUICallback('getAdminTransactions', function(data, cb)
    data = data or {}
    data.store_id = data.store_id or (Admin.context and Admin.context.selected_store_id)
    cb(lib.callback.await('vancepay:server:getTransactions', false, data) or { ok = false, message = '获取交易失败' })
end)

RegisterNUICallback('getAdminTransactionDetail', function(data, cb)
    local transactionId = data and (data.transaction_id or data.id) or nil
    cb(lib.callback.await('vancepay:server:getTransactionDetail', false, transactionId) or {
        ok = false,
        message = '获取交易详情失败',
    })
end)

RegisterNUICallback('refundFromAdmin', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:refundTransaction', false, data or {}), cb)
end)

RegisterNUICallback('getAdminLoans', function(data, cb)
    cb(lib.callback.await('vancepay:server:getAdminLoans', false, data or {}) or {
        ok = false,
        message = '获取贷款失败',
    })
end)

RegisterNUICallback('saveAdminLoan', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:saveAdminLoan', false, data or {}), cb)
end)

RegisterNUICallback('createAdminCollectionTask', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:createAdminCollectionTask', false, data or {}), cb)
end)

RegisterNUICallback('cancelAdminCollectionTask', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:cancelAdminCollectionTask', false, data or {}), cb)
end)

RegisterNUICallback('getAuditLogs', function(data, cb)
    data = data or {}
    data.store_id = data.store_id or (Admin.context and Admin.context.selected_store_id)
    cb(lib.callback.await('vancepay:server:getAuditLogs', false, data) or { ok = false, message = '获取审计失败' })
end)

RegisterNUICallback('getStoreOverview', function(data, cb)
    local storeId = data and data.store_id or (Admin.context and Admin.context.selected_store_id)
    cb(lib.callback.await('vancepay:server:getStoreOverview', false, storeId) or { ok = false, message = '获取概览失败' })
end)

RegisterNUICallback('getAdvancedReport', function(data, cb)
    data = data or {}
    data.store_id = data.store_id or (Admin.context and Admin.context.selected_store_id)
    cb(lib.callback.await('vancepay:server:getAdvancedReport', false, data) or { ok = false, message = '获取报表失败' })
end)

RegisterNUICallback('getTaxReport', function(data, cb)
    data = data or {}
    data.store_id = data.store_id or (Admin.context and Admin.context.selected_store_id)
    cb(lib.callback.await('vancepay:server:getTaxReport', false, data) or { ok = false, message = '获取税务统计失败' })
end)

RegisterNUICallback('getCommissionReport', function(data, cb)
    data = data or {}
    data.store_id = data.store_id or (Admin.context and Admin.context.selected_store_id)
    cb(lib.callback.await('vancepay:server:getCommissionReport', false, data) or { ok = false, message = '获取提成统计失败' })
end)

RegisterNUICallback('exportAdminData', function(data, cb)
    data = data or {}
    data.store_id = data.store_id ~= nil and data.store_id or (Admin.context and Admin.context.selected_store_id)
    cb(lib.callback.await('vancepay:server:exportAdminData', false, data) or { ok = false, message = '导出失败' })
end)

RegisterNUICallback('saveTerminalModel', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:saveTerminalModel', false, data or {}), cb)
end)

RegisterNUICallback('archiveTerminalModel', function(data, cb)
    refreshAfterMutation(lib.callback.await('vancepay:server:archiveTerminalModel', false, data or {}), cb)
end)
