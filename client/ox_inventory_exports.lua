local function trimValue(value)
    if type(value) ~= 'string' then
        return value
    end

    return value:match('^%s*(.-)%s*$')
end

local function isBlank(value)
    return value == nil or trimValue(value) == ''
end

local function getCollectionTabletItemName()
    local loanConfig = Config.Loans or {}
    local collectionsConfig = loanConfig.Collections or {}
    local itemName = trimValue(collectionsConfig.tabletItem)

    if isBlank(itemName) then
        itemName = 'vp_debt_tablet'
    end

    return itemName
end

local function getPoliceTicketBookItemName()
    local policeConfig = Config.PoliceTickets or {}
    local itemName = trimValue(policeConfig.ticketBookItem)

    if isBlank(itemName) then
        itemName = 'vp_ticket_book'
    end

    return itemName
end

local function getPoliceTicketManagerItemName()
    local policeConfig = Config.PoliceTickets or {}
    local itemName = trimValue(policeConfig.managementTabletItem)

    if isBlank(itemName) then
        itemName = 'vp_ticket_tablet'
    end

    return itemName
end

local function getPoliceTicketItemName()
    local policeConfig = Config.PoliceTickets or {}
    local itemName = trimValue(policeConfig.ticketItem)

    if isBlank(itemName) then
        itemName = 'vp_police_ticket'
    end

    return itemName
end

local function normalizeClientItem(slot)
    if type(slot) ~= 'table' then
        return {}
    end

    return {
        name = slot.name,
        slot = tonumber(slot.slot),
        metadata = type(slot.metadata) == 'table' and slot.metadata or {},
    }
end

local function useInventoryItem(itemName, slot)
    TriggerServerEvent(VancePay.Events.server.useInventoryItem, itemName, normalizeClientItem(slot))
end

exports('usePortablePos', function(_, data, slot)
    useInventoryItem(Config.PortablePOSItem, slot or data)
end)

exports('useTablet', function(_, data, slot)
    useInventoryItem(Config.TabletItem, slot or data)
end)

exports('useDebtTablet', function(_, data, slot)
    useInventoryItem(getCollectionTabletItemName(), slot or data)
end)

exports('usePoliceTicketBook', function(_, data, slot)
    useInventoryItem(getPoliceTicketBookItemName(), slot or data)
end)

exports('usePoliceTicketManager', function(_, data, slot)
    useInventoryItem(getPoliceTicketManagerItemName(), slot or data)
end)

exports('usePoliceTicket', function(_, data, slot)
    useInventoryItem(getPoliceTicketItemName(), slot or data)
end)
