VancePay.PoliceTickets = VancePay.PoliceTickets or {}

local PoliceTickets = VancePay.PoliceTickets

PoliceTickets.state = PoliceTickets.state or {}

local function trimValue(value)
    if type(value) ~= 'string' then
        return value
    end

    return value:match('^%s*(.-)%s*$')
end

local function isBlank(value)
    return value == nil or trimValue(value) == ''
end

local function formatMoney(value)
    return VancePay.Utils.formatCurrency(value)
end

local function normalizeDialogOptions(options, fallback)
    if type(options) ~= 'table' or #options < 1 then
        return fallback
    end

    local normalized = {}
    for index = 1, #options do
        local option = options[index]
        if type(option) == 'table' then
            local value = option.value or option[1]
            if value ~= nil then
                normalized[#normalized + 1] = {
                    label = option.label or option[2] or value,
                    value = value,
                }
            end
        end
    end

    return #normalized > 0 and normalized or fallback
end

local function getDialogTargetOptions(players)
    local options = {}

    for index = 1, #(players or {}) do
        local player = players[index]
        local source = tonumber(player.source)
        if source then
            options[#options + 1] = {
                label = ('%s | ID %s | %.1fm'):format(player.name or ('Player #' .. source), source, tonumber(player.distance) or 0),
                value = source,
            }
        end
    end

    return options
end

local function getCreditBandDescription(bands)
    if type(bands) ~= 'table' or #bands < 1 then
        return nil
    end

    local parts = {}
    for index = 1, #bands do
        local band = bands[index]
        if type(band) == 'table' then
            local impact = tonumber(band.impact) or 0
            local minAmount = tonumber(band.min) or 0
            local maxAmount = tonumber(band.max)

            if maxAmount then
                parts[#parts + 1] = ('%s-%s: %s'):format(formatMoney(minAmount), formatMoney(maxAmount), impact)
            else
                parts[#parts + 1] = ('%s+: %s'):format(formatMoney(minAmount), impact)
            end
        end
    end

    return table.concat(parts, ' / ')
end

local function notifyResponse(response, fallback, defaultType)
    local notifyType = defaultType or (response and response.ok and 'success' or 'error')
    VancePay.Client.notify(response and response.message or fallback or '操作失败', notifyType)
end

function PoliceTickets.openBook(payload)
    payload = payload or {}
    local distance = tonumber(payload.target_distance) or Config.TargetingDistance
    local players = VancePay.Client.getNearbyPlayers(distance)
    local targetOptions = getDialogTargetOptions(players)

    if #targetOptions < 1 then
        VancePay.Client.notify('附近没有可开罚单的玩家', 'error')
        return
    end

    local creditDescription = getCreditBandDescription(payload.credit_bands)
    local ticketTypes = normalizeDialogOptions(payload.ticket_types, {
        { label = '行政处罚告知单', value = 'notice' },
        { label = '交通违法处罚单', value = 'traffic' },
    })
    local ticketStyles = normalizeDialogOptions(payload.ticket_styles, {
        { label = '泛黄纸张', value = 'aged' },
        { label = '碳复写纸', value = 'carbon' },
    })

    local agencyLabel = '执法机构'
    if type(payload.agencies) == 'table' and type(payload.default_ticket_agency) == 'string' then
        for index = 1, #payload.agencies do
            local agency = payload.agencies[index]
            if type(agency) == 'table' and agency.key == payload.default_ticket_agency then
                agencyLabel = agency.label or agency.key or agencyLabel
                break
            end
        end
    end

    local input = lib.inputDialog(('开具%s 罚单'):format(agencyLabel), {
        {
            type = 'select',
            label = '被罚玩家',
            options = targetOptions,
            required = true,
        },
        {
            type = 'select',
            label = '票据类型',
            description = ('将以 %s 票面开具，外观由配置中的执法机构决定。'):format(agencyLabel),
            options = ticketTypes,
            default = payload.default_ticket_type or 'notice',
            required = true,
        },
        {
            type = 'select',
            label = '票面质感',
            description = '会写入纸质罚单物品，之后查看保持一致。',
            options = ticketStyles,
            default = payload.default_ticket_style or 'aged',
            required = true,
        },
        {
            type = 'number',
            label = '罚款金额',
            description = ('范围 %s - %s'):format(formatMoney(payload.min_amount or 1), formatMoney(payload.max_amount or 50000)),
            required = true,
            min = tonumber(payload.min_amount) or 1,
            max = tonumber(payload.max_amount) or 50000,
        },
        {
            type = 'textarea',
            label = '罚单原因',
            description = creditDescription and ('信誉影响：' .. creditDescription) or nil,
            required = true,
            min = 2,
            max = tonumber(payload.max_reason_length) or 160,
        }
    })

    if not input then
        return
    end

    local targetSource = tonumber(input[1])
    local ticketType = trimValue(input[2] or payload.default_ticket_type or 'notice')
    local ticketStyle = trimValue(input[3] or payload.default_ticket_style or 'aged')
    local amount = tonumber(input[4])
    local reason = trimValue(input[5] or '')

    if not targetSource or not amount or isBlank(reason) then
        VancePay.Client.notify('罚单信息不完整', 'error')
        return
    end

    local response = lib.callback.await('vancepay:server:createPoliceTicket', false, {
        target_source = targetSource,
        amount = amount,
        reason = reason,
        ticket_type = ticketType,
        ticket_style = ticketStyle,
    })

    notifyResponse(response, '罚单创建失败')
end

function PoliceTickets.openTicket(payload)
    payload = payload or {}
    local ticket = payload.ticket
    if type(ticket) ~= 'table' then
        VancePay.Client.notify('罚单数据无效', 'error')
        return
    end

    PoliceTickets.state.currentPayload = payload
    if VancePay.Client.ui.view == 'policeTicket' then
        VancePay.Client.updateView('policeTicket', payload)
        return
    end

    VancePay.Client.openView('policeTicket', payload)
end

function PoliceTickets.payTicket(payload)
    payload = payload or {}
    local response = lib.callback.await('vancepay:server:payPoliceTicket', false, {
        item = payload.item or {},
    })

    if not response or not response.ok then
        notifyResponse(response, '罚单缴款失败')
        return response
    end

    notifyResponse(response, '罚单已缴纳', response.data and response.data.metadata_written == false and 'warning' or 'success')

    if response.data then
        PoliceTickets.openTicket(response.data)
    end

    return response
end

RegisterNUICallback('payPoliceTicket', function(_, cb)
    if VancePay.Client.ui.view ~= 'policeTicket' then
        cb({ ok = false, message = '当前没有打开罚单' })
        return
    end

    local response = PoliceTickets.payTicket(PoliceTickets.state.currentPayload or {})
    cb(response or { ok = false, message = '罚单缴款失败' })
end)

RegisterNetEvent(VancePay.Events.client.openPoliceTicketBook, function(payload)
    PoliceTickets.openBook(payload or {})
end)

RegisterNetEvent(VancePay.Events.client.openPoliceTicket, function(payload)
    PoliceTickets.openTicket(payload or {})
end)

lib.callback.register('vancepay:client:isSourceNearby', function(payload)
    payload = payload or {}
    local targetSource = tonumber(payload.source or payload.target_source or payload.targetSource)
    if not targetSource then
        return false
    end

    local player = GetPlayerFromServerId(targetSource)
    if player == -1 then
        return false
    end

    local targetPed = GetPlayerPed(player)
    local myPed = PlayerPedId()
    if not DoesEntityExist(targetPed) or not DoesEntityExist(myPed) then
        return false
    end

    local distance = tonumber(payload.distance) or Config.TargetingDistance
    return #(GetEntityCoords(myPed) - GetEntityCoords(targetPed)) <= (distance + 0.5)
end)
