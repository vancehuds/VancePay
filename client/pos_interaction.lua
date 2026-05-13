VancePay.PosInteraction = VancePay.PosInteraction or {}

local PosInteraction = VancePay.PosInteraction

PosInteraction.fixedEntities = PosInteraction.fixedEntities or {}

local function requestModel(modelHash)
    if not IsModelValid(modelHash) then
        return false
    end

    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(modelHash) do
        Wait(0)
        if GetGameTimer() > timeout then
            return false
        end
    end

    return true
end

function PosInteraction.clearFixedTerminals()
    for terminalId, entry in pairs(PosInteraction.fixedEntities) do
        if entry.zoneId and GetResourceState('ox_target') == 'started' then
            pcall(function()
                exports.ox_target:removeZone(entry.zoneId)
            end)
        end

        if entry.entity and DoesEntityExist(entry.entity) then
            if GetResourceState('ox_target') == 'started' and entry.targetName then
                pcall(function()
                    exports.ox_target:removeLocalEntity(entry.entity, { entry.targetName })
                end)
            end

            DeleteEntity(entry.entity)
        end

        PosInteraction.fixedEntities[terminalId] = nil
    end
end

local function canAccessTerminal(terminal)
    return terminal and terminal.can_access == true
end

local function buildTargetOptions(terminal, targetName)
    return {
        {
            name = targetName,
            icon = canAccessTerminal(terminal) and 'fa-solid fa-cash-register' or 'fa-solid fa-lock',
            label = canAccessTerminal(terminal)
                and ('使用 %s'):format(terminal.store_name or 'POS')
                or ('无权使用 %s'):format(terminal.store_name or 'POS'),
            distance = Config.FixedPosInteractDistance,
            canInteract = function()
                return canAccessTerminal(terminal)
            end,
            onSelect = function()
                if not canAccessTerminal(terminal) then
                    VancePay.Client.notify('你没有权限使用这个 POS', 'error')
                    return
                end

                if VancePay.PaymentFlow and VancePay.PaymentFlow.open then
                    VancePay.PaymentFlow.open({
                        launch = 'fixed',
                        terminal_id = terminal.id,
                    })
                end
            end
        }
    }
end

local function createTarget(entity, terminal)
    if GetResourceState('ox_target') ~= 'started' then
        return nil
    end

    local targetName = ('vancepay_fixed_terminal_%s'):format(terminal.id)

    local ok = pcall(function()
        exports.ox_target:addLocalEntity(entity, buildTargetOptions(terminal, targetName))
    end)

    return ok and targetName or nil
end

local function createZoneTarget(coords, terminal)
    if GetResourceState('ox_target') ~= 'started' then
        return nil, nil
    end

    local targetName = ('vancepay_fixed_terminal_%s'):format(terminal.id)
    local ok, zoneId = pcall(function()
        return exports.ox_target:addSphereZone({
            coords = coords,
            radius = tonumber(Config.FixedPosInteractRadius) or 0.35,
            debug = Config.Debug == true,
            drawSprite = false,
            options = buildTargetOptions(terminal, targetName),
        })
    end)

    if not ok then
        return nil, nil
    end

    return zoneId, targetName
end

local function spawnFixedTerminal(terminal)
    if type(terminal.coords) ~= 'table' then
        return
    end

    local coords = vector3(terminal.coords.x, terminal.coords.y, terminal.coords.z)
    if Utils.isInteractionOnlyTerminalModel(terminal.model_key, terminal.model_name) then
        local zoneId, targetName = createZoneTarget(coords, terminal)
        if zoneId then
            PosInteraction.fixedEntities[terminal.id] = {
                zoneId = zoneId,
                terminal = terminal,
                targetName = targetName,
            }
        end
        return
    end

    local modelName = terminal.model_name
        or (terminal.model_key and Config.POSModels[terminal.model_key] and Config.POSModels[terminal.model_key].model)
        or Config.POSModels[Config.DefaultTerminalModelKey].model
    local modelHash = joaat(modelName)

    if not requestModel(modelHash) then
        return
    end

    local entity = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z, false, false, false)

    if not entity or entity == 0 then
        return
    end

    SetEntityHeading(entity, tonumber(terminal.heading) or 0.0)
    FreezeEntityPosition(entity, true)
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityInvincible(entity, true)

    PosInteraction.fixedEntities[terminal.id] = {
        entity = entity,
        terminal = terminal,
        targetName = createTarget(entity, terminal),
    }

    SetModelAsNoLongerNeeded(modelHash)
end

function PosInteraction.syncFixedTerminals(terminals)
    PosInteraction.clearFixedTerminals()

    for index = 1, #terminals do
        spawnFixedTerminal(terminals[index])
    end
end
