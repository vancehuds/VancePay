VancePay.Collections = VancePay.Collections or {}

local Collections = VancePay.Collections

Collections.state = Collections.state or {}
Collections.launchPayload = Collections.launchPayload or nil
Collections.mapRanges = Collections.mapRanges or {}

local function getTaskId(value)
    if type(value) == 'table' then
        value = value.id or value.task_id or value.taskId
    end

    local taskId = tonumber(value)
    if not taskId then
        return nil
    end

    return tostring(math.floor(taskId))
end

local function removeMapBlip(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
end

local function setBlipName(blip, name)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(name or '追债搜索范围')
    EndTextCommandSetBlipName(blip)
end

local function getAreaCoord(area, key, index)
    if type(area) ~= 'table' then
        return nil
    end

    local value = tonumber(area[key])
    if value ~= nil then
        return value
    end

    if type(area.coords) == 'table' then
        return tonumber(area.coords[key]) or tonumber(area.coords[index])
    end

    return nil
end

local function getSearchArea(clue)
    if type(clue) ~= 'table' or clue.online ~= true then
        return nil
    end

    local location = type(clue.location) == 'table' and clue.location or {}
    local area = type(location.search_area) == 'table' and location.search_area or clue.search_area
    if type(area) ~= 'table' then
        return nil
    end

    local x = getAreaCoord(area, 'x', 1)
    local y = getAreaCoord(area, 'y', 2)
    local z = getAreaCoord(area, 'z', 3) or 0.0
    local radius = tonumber(area.radius)
    if not x or not y or not radius or radius <= 0 then
        return nil
    end

    return area, x, y, z, radius
end

function Collections.clearMapRange(taskId)
    taskId = getTaskId(taskId)
    if not taskId then
        return
    end

    local entry = Collections.mapRanges[taskId]
    if not entry then
        return
    end

    removeMapBlip(entry.radius)
    removeMapBlip(entry.center)
    Collections.mapRanges[taskId] = nil
end

function Collections.clearMapRanges()
    local taskIds = {}
    for taskId in pairs(Collections.mapRanges) do
        taskIds[#taskIds + 1] = taskId
    end

    for index = 1, #taskIds do
        local taskId = taskIds[index]
        Collections.clearMapRange(taskId)
    end
end

function Collections.applyMapRange(task, clue)
    local taskId = getTaskId(task)
    if not taskId then
        return false
    end

    local area, x, y, z, radius = getSearchArea(clue)
    if not area then
        Collections.clearMapRange(taskId)
        return false
    end

    Collections.clearMapRange(taskId)

    local color = math.floor(tonumber(area.color) or 5)
    local alpha = math.floor(tonumber(area.alpha) or 90)
    local label = area.label or ('追债搜索范围 #' .. taskId)
    local radiusBlip = AddBlipForRadius(x, y, z, radius + 0.0)
    SetBlipColour(radiusBlip, color)
    SetBlipAlpha(radiusBlip, alpha)
    SetBlipHighDetail(radiusBlip, true)

    local centerBlip = nil
    if area.show_center ~= false then
        centerBlip = AddBlipForCoord(x, y, z)
        SetBlipSprite(centerBlip, math.floor(tonumber(area.center_sprite or area.sprite) or 161))
        SetBlipScale(centerBlip, tonumber(area.center_scale or area.scale) or 0.75)
        SetBlipColour(centerBlip, color)
        SetBlipAsShortRange(centerBlip, false)
        setBlipName(centerBlip, label)

        if area.route == true then
            SetBlipRoute(centerBlip, true)
            SetBlipRouteColour(centerBlip, color)
        end
    end

    Collections.mapRanges[taskId] = {
        radius = radiusBlip,
        center = centerBlip,
        generated_at = clue.generated_at,
    }

    return true
end

local function syncMapRanges(payload)
    local activeTaskIds = {}
    local tasks = type(payload) == 'table' and type(payload.my_tasks) == 'table' and payload.my_tasks or {}

    for index = 1, #tasks do
        local task = tasks[index]
        local taskId = getTaskId(task)
        if taskId and task.status == 'claimed' and task.loan_status ~= 'paid' then
            activeTaskIds[taskId] = true
            if type(task.clue_snapshot) == 'table' then
                Collections.applyMapRange(task, task.clue_snapshot)
            end
        end
    end

    local staleTaskIds = {}
    for taskId in pairs(Collections.mapRanges) do
        if not activeTaskIds[taskId] then
            staleTaskIds[#staleTaskIds + 1] = taskId
        end
    end

    for index = 1, #staleTaskIds do
        Collections.clearMapRange(staleTaskIds[index])
    end
end

local function shouldClearMapRanges(response)
    local code = response and response.code
    return code == 'missing_tablet'
        or code == 'missing_citizenid'
        or code == 'disabled'
        or code == 'db_schema_outdated'
end

local function applyState(payload)
    payload = type(payload) == 'table' and payload or {}
    Collections.state = payload
    syncMapRanges(payload)

    if VancePay.Client.ui.view == 'collections' then
        VancePay.Client.updateView('collections', payload)
    else
        VancePay.Client.openView('collections', payload)
    end
end

local function notifyFailure(response, fallback)
    if shouldClearMapRanges(response) then
        Collections.clearMapRanges()
    end

    VancePay.Client.notify(response and response.message or fallback or '追债平板操作失败', 'error')
end

function Collections.refresh()
    local response = lib.callback.await('vancepay:server:getCollectionTasks', false)
    if response and response.ok then
        applyState(response.data or {})
    else
        notifyFailure(response, '追债任务刷新失败')
    end

    return response or {
        ok = false,
        message = '追债任务刷新失败',
    }
end

function Collections.open(payload)
    Collections.launchPayload = type(payload) == 'table' and payload or {}
    VancePay.Client.playDeviceAnimation('tablet')
    Collections.refresh()
end

local function refreshAfterResponse(response)
    if response and response.ok and type(response.data) == 'table' and response.data.available_tasks then
        applyState(response.data)
        return
    end

    if response and response.ok then
        Collections.refresh()
    end
end

RegisterNUICallback('refreshCollections', function(_, cb)
    cb(Collections.refresh())
end)

RegisterNUICallback('claimCollectionTask', function(data, cb)
    local response = lib.callback.await('vancepay:server:claimCollectionTask', false, data or {})
    if response and response.ok then
        refreshAfterResponse(response)
        if type(response.data) == 'table' and response.data.claimed_clue then
            Collections.applyMapRange(response.data.claimed_task or data, response.data.claimed_clue)
        end
    else
        notifyFailure(response, '任务领取失败')
    end

    cb(response or {
        ok = false,
        message = '任务领取失败',
    })
end)

RegisterNUICallback('claimCollectionReward', function(data, cb)
    local response = lib.callback.await('vancepay:server:claimCollectionReward', false, data or {})
    if response and response.ok then
        refreshAfterResponse(response)
    else
        notifyFailure(response, '奖励领取失败')
    end

    cb(response or {
        ok = false,
        message = '奖励领取失败',
    })
end)

RegisterNUICallback('getCollectionTaskClue', function(data, cb)
    local response = lib.callback.await('vancepay:server:getCollectionTaskClue', false, data or {})
    if response and response.ok then
        if type(response.data) == 'table' and response.data.clue then
            Collections.applyMapRange(response.data.task or data, response.data.clue)
        end
        Collections.refresh()
    else
        notifyFailure(response, '线索刷新失败')
    end

    cb(response or {
        ok = false,
        message = '线索刷新失败',
    })
end)

lib.callback.register('vancepay:client:getCollectionLocation', function()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return {}
    end

    local coords = GetEntityCoords(ped)
    local streetHash, crossStreetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or nil
    local crossStreet = crossStreetHash and crossStreetHash ~= 0 and GetStreetNameFromHashKey(crossStreetHash) or nil
    local zoneName = GetNameOfZone(coords.x, coords.y, coords.z)
    local zoneLabel = zoneName and GetLabelText(zoneName) or nil

    if zoneLabel == 'NULL' or zoneLabel == '' then
        zoneLabel = zoneName
    end

    return {
        street = street,
        cross_street = crossStreet,
        zone = zoneLabel,
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
        },
    }
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == VancePay.ResourceName then
        Collections.clearMapRanges()
    end
end)
