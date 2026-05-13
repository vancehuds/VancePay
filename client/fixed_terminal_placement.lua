VancePay.FixedTerminalPlacement = VancePay.FixedTerminalPlacement or {}

local Placement = VancePay.FixedTerminalPlacement

Placement.active = Placement.active or false
Placement.state = Placement.state or nil
Placement.completion = Placement.completion or nil

local RAYCAST_FLAGS = 1 | 2 | 16
local HELP_TEXT = '固定 POS 摆放中  ~INPUT_RELOAD~ 对准准星台面  ~INPUT_FRONTEND_UP~/~INPUT_FRONTEND_DOWN~/~INPUT_FRONTEND_LEFT~/~INPUT_FRONTEND_RIGHT~ 微调  ~INPUT_CONTEXT~/~INPUT_COVER~ 升降  滚轮旋转  ~INPUT_FRONTEND_ACCEPT~ 确认  ~INPUT_FRONTEND_CANCEL~ 取消  按住 ~INPUT_SPRINT~ 加速'

local function requestModel(modelHash)
    if not IsModelValid(modelHash) then
        return false
    end

    RequestModel(modelHash)
    local timeoutAt = GetGameTimer() + 5000

    while not HasModelLoaded(modelHash) do
        Wait(0)
        if GetGameTimer() > timeoutAt then
            return false
        end
    end

    return true
end

local function normalizeHeading(heading)
    heading = tonumber(heading) or 0.0
    heading = heading % 360.0

    if heading < 0.0 then
        heading = heading + 360.0
    end

    return heading
end

local function vectorFromTable(coords)
    if type(coords) ~= 'table' then
        return nil
    end

    return vector3(
        tonumber(coords.x) or 0.0,
        tonumber(coords.y) or 0.0,
        tonumber(coords.z) or 0.0
    )
end

local function getCameraDirection()
    local rotation = GetGameplayCamRot(2)
    local rotationX = math.rad(rotation.x)
    local rotationZ = math.rad(rotation.z)
    local cosX = math.abs(math.cos(rotationX))

    return vector3(
        -math.sin(rotationZ) * cosX,
        math.cos(rotationZ) * cosX,
        math.sin(rotationX)
    )
end

local function getFlatCameraAxes()
    local direction = getCameraDirection()
    local magnitude = math.sqrt((direction.x * direction.x) + (direction.y * direction.y))

    if magnitude <= 0.0001 then
        return vector3(0.0, 1.0, 0.0), vector3(1.0, 0.0, 0.0)
    end

    local forward = vector3(direction.x / magnitude, direction.y / magnitude, 0.0)
    local right = vector3(forward.y, -forward.x, 0.0)

    return forward, right
end

local function getModelBaseOffset(modelHash)
    local minDim, maxDim = GetModelDimensions(modelHash)
    if type(minDim) ~= 'vector3' or type(maxDim) ~= 'vector3' then
        return 0.0
    end

    return math.abs(minDim.z)
end

local function raycastFromCamera()
    local ped = PlayerPedId()
    local cameraCoords = GetGameplayCamCoord()
    local direction = getCameraDirection()
    local distance = 8.0
    local targetCoords = vector3(
        cameraCoords.x + (direction.x * distance),
        cameraCoords.y + (direction.y * distance),
        cameraCoords.z + (direction.z * distance)
    )

    local handle = StartShapeTestRay(
        cameraCoords.x, cameraCoords.y, cameraCoords.z,
        targetCoords.x, targetCoords.y, targetCoords.z,
        RAYCAST_FLAGS,
        ped,
        0
    )

    local result, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(handle)
    local timeoutAt = GetGameTimer() + 100

    while result == 1 and GetGameTimer() <= timeoutAt do
        Wait(0)
        result, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(handle)
    end

    if result ~= 2 then
        return false, nil, nil, nil
    end

    return hit == 1 or hit == true, endCoords, surfaceNormal, entityHit
end

local function resolveAimCoords(baseOffset)
    local hit, hitCoords, surfaceNormal = raycastFromCamera()
    if not hit or type(hitCoords) ~= 'vector3' then
        return nil, '请把准星对准台面或地面'
    end

    if type(surfaceNormal) == 'vector3' and math.abs(surfaceNormal.z or 0.0) < 0.35 then
        return nil, '请把准星对准较为水平的表面'
    end

    return vector3(hitCoords.x, hitCoords.y, hitCoords.z + baseOffset)
end

local function resolveFallbackCoords(baseOffset)
    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.9, -1.0 + baseOffset)

    return vector3(coords.x, coords.y, coords.z)
end

local function applyPreviewState(state)
    if not state or not state.entity or not DoesEntityExist(state.entity) then
        return
    end

    SetEntityCoordsNoOffset(state.entity, state.coords.x, state.coords.y, state.coords.z, false, false, false)
    SetEntityHeading(state.entity, state.heading)
end

local function drawMarkerPreview(state)
    if not state or not state.interactionOnly or type(state.coords) ~= 'vector3' then
        return
    end

    local coords = state.coords

    DrawMarker(
        1,
        coords.x, coords.y, coords.z - 0.02,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.34, 0.34, 0.08,
        255, 96, 96, 160,
        false, false, 2, false, nil, nil, false
    )
    DrawMarker(
        28,
        coords.x, coords.y, coords.z + 0.03,
        0.0, 0.0, 0.0,
        0.0, 0.0, state.heading,
        0.1, 0.1, 0.1,
        255, 255, 255, 220,
        false, false, 2, false, nil, nil, false
    )
    DrawLine(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z + 0.45, 255, 96, 96, 220)
end

local function isPreviewActive(state)
    if not state then
        return false
    end

    if state.interactionOnly then
        return type(state.coords) == 'vector3'
    end

    return state.entity and DoesEntityExist(state.entity)
end

local function cleanupPreview()
    local state = Placement.state
    if state and state.entity and DoesEntityExist(state.entity) then
        DeleteEntity(state.entity)
    end

    if state and state.modelHash then
        SetModelAsNoLongerNeeded(state.modelHash)
    end

    Placement.active = false
    Placement.state = nil
    Placement.completion = nil
end

local function finishPlacement(result)
    local completion = Placement.completion
    cleanupPreview()

    if type(completion) == 'function' then
        completion(result)
    end
end

function Placement.cancel(message, silent)
    if not Placement.active then
        return false
    end

    local result = {
        ok = false,
        cancelled = true,
        message = message or '已取消固定 POS 摆放',
    }

    if silent then
        cleanupPreview()
    else
        finishPlacement(result)
    end

    return true
end

function Placement.start(payload, completion)
    if Placement.active then
        return false, '已有固定 POS 正在摆放'
    end

    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return false, '请下车后再摆放固定 POS'
    end

    payload = payload or {}
    local modelName = payload.model_name
        or (payload.model_key and Config.POSModels[payload.model_key] and Config.POSModels[payload.model_key].model)
        or (Config.POSModels[Config.DefaultTerminalModelKey] and Config.POSModels[Config.DefaultTerminalModelKey].model)
    local interactionOnly = Utils.isInteractionOnlyTerminalModel(payload.model_key, modelName)

    if not interactionOnly and not modelName then
        return false, '固定 POS 缺少有效模型'
    end

    local modelHash = nil
    local entity = nil
    local baseOffset = interactionOnly and 0.02 or 0.0

    if not interactionOnly then
        modelHash = joaat(modelName)
        if not requestModel(modelHash) then
            return false, '固定 POS 模型加载失败'
        end

        entity = CreateObjectNoOffset(modelHash, 0.0, 0.0, 0.0, false, false, false)
        if not entity or entity == 0 then
            SetModelAsNoLongerNeeded(modelHash)
            return false, '固定 POS 预览创建失败'
        end

        SetEntityAsMissionEntity(entity, true, true)
        SetEntityCollision(entity, false, false)
        FreezeEntityPosition(entity, true)
        SetEntityInvincible(entity, true)
        SetEntityAlpha(entity, 180, false)

        baseOffset = getModelBaseOffset(modelHash)
    end

    local previewCoords = nil
    local existingCoords = vectorFromTable(payload.coords)

    if existingCoords then
        local pedCoords = GetEntityCoords(PlayerPedId())
        if #(pedCoords - existingCoords) <= 10.0 then
            previewCoords = existingCoords
        end
    end

    if not previewCoords then
        previewCoords = resolveAimCoords(baseOffset) or resolveFallbackCoords(baseOffset)
    end

    Placement.active = true
    Placement.completion = completion
    Placement.state = {
        entity = entity,
        modelHash = modelHash,
        modelName = modelName,
        baseOffset = baseOffset,
        coords = previewCoords,
        heading = normalizeHeading(payload.heading or GetEntityHeading(PlayerPedId())),
        interactionOnly = interactionOnly,
    }

    applyPreviewState(Placement.state)

    CreateThread(function()
        while Placement.active and isPreviewActive(Placement.state) do
            Wait(0)

            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 177, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 201, true)
            DisableControlAction(0, 322, true)

            VancePay.Client.showHelpText(HELP_TEXT)

            local state = Placement.state
            drawMarkerPreview(state)
            local moveStep = IsControlPressed(0, 21) and 0.05 or 0.015
            local rotateStep = IsControlPressed(0, 21) and 5.0 or 1.0
            local moved = false

            if IsDisabledControlJustPressed(0, 45) then
                local snappedCoords, errorMessage = resolveAimCoords(state.baseOffset)
                if snappedCoords then
                    state.coords = snappedCoords
                    moved = true
                else
                    VancePay.Client.notify(errorMessage or '当前无法对准摆放点', 'error')
                end
            end

            local forwardAxis, rightAxis = getFlatCameraAxes()

            if IsControlPressed(0, 172) then
                state.coords = vector3(
                    state.coords.x + (forwardAxis.x * moveStep),
                    state.coords.y + (forwardAxis.y * moveStep),
                    state.coords.z
                )
                moved = true
            end

            if IsControlPressed(0, 173) then
                state.coords = vector3(
                    state.coords.x - (forwardAxis.x * moveStep),
                    state.coords.y - (forwardAxis.y * moveStep),
                    state.coords.z
                )
                moved = true
            end

            if IsControlPressed(0, 174) then
                state.coords = vector3(
                    state.coords.x - (rightAxis.x * moveStep),
                    state.coords.y - (rightAxis.y * moveStep),
                    state.coords.z
                )
                moved = true
            end

            if IsControlPressed(0, 175) then
                state.coords = vector3(
                    state.coords.x + (rightAxis.x * moveStep),
                    state.coords.y + (rightAxis.y * moveStep),
                    state.coords.z
                )
                moved = true
            end

            if IsDisabledControlPressed(0, 38) then
                state.coords = vector3(state.coords.x, state.coords.y, state.coords.z + moveStep)
                moved = true
            end

            if IsDisabledControlPressed(0, 44) then
                state.coords = vector3(state.coords.x, state.coords.y, state.coords.z - moveStep)
                moved = true
            end

            if IsDisabledControlJustPressed(0, 14) then
                state.heading = normalizeHeading(state.heading + rotateStep)
                moved = true
            end

            if IsDisabledControlJustPressed(0, 15) then
                state.heading = normalizeHeading(state.heading - rotateStep)
                moved = true
            end

            if moved then
                applyPreviewState(state)
            end

            if IsDisabledControlJustPressed(0, 201) or IsControlJustPressed(0, 191) then
                finishPlacement({
                    ok = true,
                    coords = {
                        x = state.coords.x,
                        y = state.coords.y,
                        z = state.coords.z,
                    },
                    heading = normalizeHeading(state.heading),
                })
                return
            end

            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 322) then
                finishPlacement({
                    ok = false,
                    cancelled = true,
                    message = '已取消固定 POS 摆放',
                })
                return
            end
        end

        if Placement.active then
            finishPlacement({
                ok = false,
                cancelled = true,
                message = '固定 POS 摆放已中断',
            })
        end
    end)

    return true
end
