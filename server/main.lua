VancePay.Server = VancePay.Server or {}

local Server = VancePay.Server

Server.FixedTerminalCache = Server.FixedTerminalCache or {}

local oxInventoryUseHandlers = {}

local function dispatchOxInventoryUse(handlerName, ...)
    local handler = oxInventoryUseHandlers[handlerName]
    if type(handler) ~= 'function' then
        Utils.debug('Inventory export used before handler was ready', handlerName)
        return
    end

    return handler(...)
end

exports('usePortablePos', function(...)
    return dispatchOxInventoryUse('usePortablePos', ...)
end)

exports('useTablet', function(...)
    return dispatchOxInventoryUse('useTablet', ...)
end)

exports('useDebtTablet', function(...)
    return dispatchOxInventoryUse('useDebtTablet', ...)
end)

exports('usePoliceTicketBook', function(...)
    return dispatchOxInventoryUse('usePoliceTicketBook', ...)
end)

exports('usePoliceTicketManager', function(...)
    return dispatchOxInventoryUse('usePoliceTicketManager', ...)
end)

exports('usePoliceTicket', function(...)
    return dispatchOxInventoryUse('usePoliceTicket', ...)
end)

local UTF8MB4_TABLES = {
    'vancepay_stores',
    'vancepay_employees',
    'vancepay_terminals',
    'vancepay_terminal_binding_codes',
    'vancepay_terminal_models',
    'vancepay_balance_entries',
    'vancepay_settings',
    'vancepay_payment_intents',
    'vancepay_transactions',
    'vancepay_audit_logs',
    'vancepay_loans',
    'vancepay_collection_tasks',
    'vancepay_police_tickets',
}

local UTF8MB4_COLLATION = 'utf8mb4_unicode_ci'

local function getLBPhoneConfig()
    return Config.LBPhone or {}
end

local function getLBPhoneResourceName()
    local config = getLBPhoneConfig()
    local resourceName = Utils.trim(config.resource)

    if resourceName == '' then
        resourceName = 'lb-phone'
    end

    return resourceName
end

local function getLBPhoneAppIdentifier()
    local config = getLBPhoneConfig()
    local identifier = Utils.trim(config.appIdentifier)

    if identifier == '' then
        identifier = 'vancepay'
    end

    return identifier
end

local function getDatabaseConfig()
    return Config.Database or {}
end

local function getCollectionTabletItemName()
    local loanConfig = Config.Loans or {}
    local collectionsConfig = loanConfig.Collections or {}
    local itemName = Utils.trim(collectionsConfig.tabletItem)

    if Utils.isBlank(itemName) then
        itemName = 'vp_debt_tablet'
    end

    return itemName
end

local function shouldEnableCollections()
    local loanConfig = Config.Loans or {}
    local collectionsConfig = loanConfig.Collections or {}
    return loanConfig.enabled ~= false and collectionsConfig.enabled ~= false
end

local function getPoliceTicketBookItemName()
    local policeConfig = Config.PoliceTickets or {}
    local itemName = Utils.trim(policeConfig.ticketBookItem)

    if Utils.isBlank(itemName) then
        itemName = 'vp_ticket_book'
    end

    return itemName
end

local function getPoliceTicketManagerItemName()
    local policeConfig = Config.PoliceTickets or {}
    local itemName = Utils.trim(policeConfig.managementTabletItem)

    if Utils.isBlank(itemName) then
        itemName = 'vp_ticket_tablet'
    end

    return itemName
end

local function getPoliceTicketItemName()
    local policeConfig = Config.PoliceTickets or {}
    local itemName = Utils.trim(policeConfig.ticketItem)

    if Utils.isBlank(itemName) then
        itemName = 'vp_police_ticket'
    end

    return itemName
end

local function shouldEnablePoliceTickets()
    local policeConfig = Config.PoliceTickets or {}
    return policeConfig.enabled ~= false
end

local function shouldEnsureUtf8mb4Schema()
    local config = getDatabaseConfig()
    return config.autoMigrate == true or config.enforceUtf8mb4 == true
end

function Server.ok(data, message)
    return {
        ok = true,
        data = data,
        message = message,
    }
end

function Server.fail(message, code, data)
    return {
        ok = false,
        code = code,
        message = message,
        data = data,
    }
end

local function getSchemaValue(row, ...)
    if type(row) ~= 'table' then
        return nil
    end

    for index = 1, select('#', ...) do
        local key = select(index, ...)
        if row[key] ~= nil then
            return row[key]
        end
    end

    return nil
end

function Server.ensureUtf8mb4Schema()
    if Server.__utf8mb4Checked or not shouldEnsureUtf8mb4Schema() then
        return true
    end

    for index = 1, #UTF8MB4_TABLES do
        local tableName = UTF8MB4_TABLES[index]
        local tableMetadata = MySQL.single.await([[
            SELECT TABLE_COLLATION
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = ?
            LIMIT 1
        ]], { tableName })

        local tableCollation = tostring(getSchemaValue(tableMetadata, 'TABLE_COLLATION', 'table_collation') or '')
        if tableCollation ~= '' and not tableCollation:find('utf8mb4_', 1, true) then
            MySQL.query.await(([[
                ALTER TABLE %s
                CONVERT TO CHARACTER SET utf8mb4
                COLLATE %s
            ]]):format(tableName, UTF8MB4_COLLATION))
        end
    end

    Server.__utf8mb4Checked = true
    return true
end

function Server.notify(target, text, notifyType)
    if not target or target < 1 then
        return
    end

    TriggerClientEvent('ox_lib:notify', target, {
        title = 'VancePay',
        description = text,
        type = notifyType or 'inform',
        position = Config.Notifications.position,
        duration = Config.Notifications.duration,
    })
end

function Server.isLBPhoneAvailable()
    local config = getLBPhoneConfig()
    return config.enabled ~= false and GetResourceState(getLBPhoneResourceName()) == 'started'
end

function Server.callLBPhoneExport(method, ...)
    if not Server.isLBPhoneAvailable() then
        return false, 'resource_not_started'
    end

    local resourceName = getLBPhoneResourceName()
    local api = exports[resourceName]
    if not api or type(api[method]) ~= 'function' then
        return false, 'export_not_found'
    end

    local ok, result, extra = pcall(api[method], api, ...)
    if not ok then
        Utils.debug('LB Phone server export failed', method, result)
        return false, result
    end

    if result == nil then
        return true, extra
    end

    return result, extra
end

function Server.sendLBPhoneNotification(target, payload)
    if not target or target < 1 then
        return false, 'invalid_target'
    end

    payload = type(payload) == 'table' and Utils.deepCopy(payload) or {}

    if Utils.isBlank(payload.app) then
        payload.app = getLBPhoneAppIdentifier()
    end

    if payload.duration == nil then
        payload.duration = Config.Notifications.duration
    end

    return Server.callLBPhoneExport('SendNotification', target, payload)
end

function Server.notifyLBPhonePaymentRequest(target, intent)
    if not target or target < 1 or not intent or intent.method ~= VancePay.PaymentMethods.phone then
        return false
    end

    local config = getLBPhoneConfig()
    if config.enabled == false or config.showPhoneNotification == false then
        return false
    end

    local notification = {
        app = getLBPhoneAppIdentifier(),
        title = intent.store_name or (config.appName or 'VancePay'),
        content = ('新的付款请求 %s'):format(Utils.formatCurrency(intent.final_amount or 0)),
        sound = true,
        customData = {
            intent_id = intent.id,
            store_id = intent.store_id,
        },
        buttons = {
            {
                title = '打开',
                event = 'vancepay:client:openLbPhoneApp',
                data = {
                    intent_id = intent.id,
                },
            }
        }
    }

    return Server.sendLBPhoneNotification(target, notification)
end

function Server.getPlayerObject(source)
    return exports.qbx_core:GetPlayer(source)
end

local function extractPlayerSource(player)
    if not player then
        return nil
    end

    local data = player.PlayerData or player
    return data.source or player.source
end

function Server.getPlayerRecord(source)
    local player = Server.getPlayerObject(source)
    if not player then
        return nil
    end

    local data = player.PlayerData or player
    local charinfo = data.charinfo or {}
    local firstname = charinfo.firstname or data.firstname or ''
    local lastname = charinfo.lastname or data.lastname or ''
    local name = Utils.trim(('%s %s'):format(firstname, lastname))

    if Utils.isBlank(name) then
        name = data.name or ('Player #' .. tostring(source))
    end

    return {
        source = tonumber(source),
        citizenid = data.citizenid or data.citizenId,
        name = name,
        player = player,
        data = data,
    }
end

function Server.getSourceByCitizenId(citizenid)
    if Utils.isBlank(citizenid) then
        return nil
    end

    local player = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    return extractPlayerSource(player)
end

local function sendCommandMessage(source, text, notifyType)
    if not source or source == 0 then
        print(('[VancePay] %s'):format(text))
        return
    end

    Server.notify(source, text, notifyType)
end

local function formatCitizenIdRecord(record)
    local playerName = record.name or ('Player #' .. tostring(record.source or '?'))
    local sourceLabel = tostring(record.source or '?')
    local citizenid = record.citizenid or 'nil'

    return ('玩家: %s | ID: %s | CID: %s'):format(playerName, sourceLabel, citizenid)
end

local function resolveOnlinePlayerRecord(argument)
    local targetSource = tonumber(argument)
    if not targetSource or targetSource < 1 then
        return nil, '请填写在线玩家的服务器 ID'
    end

    local record = Server.getPlayerRecord(targetSource)
    if not record then
        return nil, '未找到该在线玩家'
    end

    return record
end

local function normalizeDeviceCommandType(argument)
    argument = string.lower(Utils.trim(tostring(argument or '')))

    if argument == 'portable'
        or argument == 'pos'
        or argument == 'portable_pos'
        or argument == 'portablepos' then
        return VancePay.TerminalTypes.portable
    end

    if argument == 'tablet'
        or argument == 'tab'
        or argument == 'pad' then
        return VancePay.TerminalTypes.tablet
    end

    return nil
end

local function normalizeDeviceCommandScope(argument, terminalType)
    argument = Utils.trim(argument)
    if Utils.isBlank(argument) then
        if terminalType == VancePay.TerminalTypes.tablet then
            return {
                mode = 'admin',
            }
        end

        return {
            mode = 'blank',
        }
    end

    local normalized = string.lower(argument)
    if normalized == 'admin' or normalized == 'global' then
        return {
            mode = 'admin',
        }
    end

    if normalized == 'blank' or normalized == 'unbound' or normalized == 'empty' then
        return {
            mode = 'blank',
        }
    end

    local storeId = tonumber(argument)
    if storeId and storeId > 0 then
        return {
            mode = 'store',
            store_id = storeId,
        }
    end

    return nil, '第二个参数需填写 admin / blank / 店铺ID'
end

local function getCommandDeviceLabel(terminalType)
    if terminalType == VancePay.TerminalTypes.tablet then
        return '管理平板'
    end

    return '便携 POS'
end

local function giveQuickInventoryItem(source, itemName, metadata, label)
    metadata = type(metadata) == 'table' and Utils.deepCopy(metadata) or {}

    local canCarryOk, canCarry = pcall(function()
        return exports.ox_inventory:CanCarryItem(source, itemName, 1, metadata)
    end)

    if canCarryOk and canCarry == false then
        return false, '背包空间不足'
    end

    local addOk, success, response = pcall(function()
        return exports.ox_inventory:AddItem(source, itemName, 1, metadata)
    end)

    if not addOk then
        Utils.debug('Failed to give quick inventory item', itemName, source, success)
        return false, '发放测试设备时调用库存失败'
    end

    if success == false then
        return false, response or '测试设备发放失败'
    end

    return true, (label or '设备') .. '已发放到你的背包'
end

local function issueQuickDevice(source, terminalType, scope)
    local deviceLabel = getCommandDeviceLabel(terminalType)

    if scope.mode == 'store' then
        local store = VancePay.Stores and VancePay.Stores.fetchById and VancePay.Stores.fetchById(scope.store_id) or nil
        if not store then
            return VancePay.Server.fail('店铺不存在', 'store_not_found')
        end

        if store.status ~= VancePay.StoreStatuses.active then
            return VancePay.Server.fail('店铺已归档，不能发放测试设备', 'store_archived')
        end

        local response = VancePay.Terminals.save(source, {
            store_id = store.id,
            type = terminalType,
            status = VancePay.TerminalStatuses.active,
            grant_item = true,
        })

        if response and response.ok then
            response.message = ('店铺 %s 的%s已发放'):format(store.name or ('#' .. tostring(store.id)), deviceLabel)
        end

        return response
    end

    if scope.mode == 'admin' then
        if terminalType == VancePay.TerminalTypes.tablet then
            local response = VancePay.Terminals.save(source, {
                type = VancePay.TerminalTypes.tablet,
                status = VancePay.TerminalStatuses.active,
                grant_item = true,
            })

            if response and response.ok then
                response.message = '管理员平板已发放'
            end

            return response
        end

        scope = {
            mode = 'blank',
        }
    end

    local itemName = terminalType == VancePay.TerminalTypes.tablet and Config.TabletItem or Config.PortablePOSItem
    local ok, message = giveQuickInventoryItem(source, itemName, {}, ('未绑定%s'):format(deviceLabel))
    if not ok then
        return VancePay.Server.fail(message, 'inventory_error')
    end

    local suffix = terminalType == VancePay.TerminalTypes.portable
        and '，可直接用于绑定码测试'
        or '，首次使用时会按权限自动初始化或要求输入绑定码'

    return VancePay.Server.ok({
        terminal_type = terminalType,
        mode = scope.mode,
        item_name = itemName,
    }, message .. suffix)
end

local function handleQuickDeviceCommand(source, args)
    if not source or source == 0 then
        sendCommandMessage(source, '该命令只能由在线管理员使用', 'error')
        return
    end

    if not VancePay.Permissions.isAdmin(source) then
        sendCommandMessage(source, '只有管理员可以使用该命令', 'error')
        return
    end

    local terminalType = normalizeDeviceCommandType(args and args[1] or nil)
    if not terminalType then
        sendCommandMessage(source, '用法: /vpdevice <portable|tablet> [admin|blank|storeId]', 'error')
        return
    end

    local scope, scopeError = normalizeDeviceCommandScope(args and args[2] or nil, terminalType)
    if not scope then
        sendCommandMessage(source, scopeError or '设备范围参数无效', 'error')
        return
    end

    local response = issueQuickDevice(source, terminalType, scope)
    sendCommandMessage(
        source,
        response and response.message or '测试设备发放失败',
        response and response.ok and 'success' or 'error'
    )
end

function Server.safeClientCallback(name, playerId, ...)
    local ok, response = pcall(lib.callback.await, name, playerId, ...)
    if not ok then
        Utils.debug('Client callback failed', name, playerId, response)
        return nil
    end

    return response
end

local function getDeviceNoticeType(response)
    if not response or not response.data then
        return 'inform'
    end

    if response.data.fallback_only then
        return 'warning'
    end

    if response.data.initialized and not response.data.metadata_written then
        return 'warning'
    end

    if response.data.initialized or response.data.metadata_written then
        return 'success'
    end

    return 'inform'
end

local function getDeviceUseTimestamp()
    local ok, value = pcall(GetGameTimer)
    if ok and type(value) == 'number' then
        return value
    end

    return math.floor(os.clock() * 1000)
end

local function normalizeUsedItem(item)
    if type(item) ~= 'table' then
        return {}
    end

    local normalized = Utils.deepCopy(item)

    if type(normalized.metadata) ~= 'table' and type(normalized.info) == 'table' then
        normalized.metadata = Utils.deepCopy(normalized.info)
    end

    return normalized
end

local function shouldHandleDeviceUse(source, itemName)
    Server.DeviceUseLocks = Server.DeviceUseLocks or {}

    local key = ('%s:%s'):format(tonumber(source) or 0, tostring(itemName or 'unknown'))
    local now = getDeviceUseTimestamp()
    local lastUsedAt = Server.DeviceUseLocks[key]

    if lastUsedAt and (now - lastUsedAt) < 1000 then
        return false
    end

    Server.DeviceUseLocks[key] = now
    return true
end

local function useInventoryDevice(source, item, itemName, terminalType, clientEvent, launch)
    local prepared = VancePay.Terminals.prepareInventoryDevice(source, itemName, terminalType, item or {})
    if not prepared or not prepared.ok then
        Server.notify(source, prepared and prepared.message or '设备初始化失败', 'error')
        return
    end

    if prepared.message then
        Server.notify(source, prepared.message, getDeviceNoticeType(prepared))
    end

    local launchPayload = {
        launch = launch,
        serial_number = prepared.data and prepared.data.launch_serial_number or nil,
        binding_required = prepared.data and prepared.data.binding_required == true or false,
        prompt_message = prepared.message,
        terminal_type = terminalType,
        item_name = itemName,
        item = item and Utils.deepCopy(item) or {},
        fallback_bootstrap = prepared.data and prepared.data.fallback_bootstrap or nil,
    }

    if prepared.data and prepared.data.metadata then
        launchPayload.item.metadata = Utils.deepCopy(prepared.data.metadata)
        launchPayload.item.info = Utils.deepCopy(prepared.data.metadata)
    end

    if terminalType == VancePay.TerminalTypes.tablet and VancePay.Reports and VancePay.Reports.getAdminBootstrap then
        if launchPayload.binding_required then
            launchPayload.bootstrap = launchPayload.fallback_bootstrap
        else
            local bootstrapResponse = VancePay.Reports.getAdminBootstrap(source, launchPayload)
            if not bootstrapResponse or not bootstrapResponse.ok then
                Server.notify(source, bootstrapResponse and bootstrapResponse.message or '平板初始化失败', 'error')
                return
            end

            launchPayload.bootstrap = bootstrapResponse.data
        end
    end

    TriggerClientEvent(clientEvent, source, launchPayload)
end

local function handleInventoryDeviceUse(source, itemName, item)
    if not source or source < 1 or Utils.isBlank(itemName) then
        return false
    end

    if not shouldHandleDeviceUse(source, itemName) then
        return true
    end

    item = normalizeUsedItem(item)

    if itemName == Config.PortablePOSItem then
        useInventoryDevice(
            source,
            item,
            Config.PortablePOSItem,
            VancePay.TerminalTypes.portable,
            VancePay.Events.client.openPos,
            'portable'
        )
        return true
    end

    if itemName == Config.TabletItem then
        useInventoryDevice(
            source,
            item,
            Config.TabletItem,
            VancePay.TerminalTypes.tablet,
            VancePay.Events.client.openAdmin,
            'tablet'
        )
        return true
    end

    if shouldEnableCollections() and itemName == getCollectionTabletItemName() then
        TriggerClientEvent(VancePay.Events.client.openCollections, source, {
            item_name = itemName,
            item = item and Utils.deepCopy(item) or {},
        })
        return true
    end

    if shouldEnablePoliceTickets() and itemName == getPoliceTicketBookItemName() then
        if VancePay.PoliceTickets and VancePay.PoliceTickets.openTicketBook then
            VancePay.PoliceTickets.openTicketBook(source)
        end
        return true
    end

    if shouldEnablePoliceTickets() and itemName == getPoliceTicketManagerItemName() then
        if VancePay.PoliceTickets and VancePay.PoliceTickets.openManager then
            VancePay.PoliceTickets.openManager(source, item)
        end
        return true
    end

    if shouldEnablePoliceTickets() and itemName == getPoliceTicketItemName() then
        if VancePay.PoliceTickets and VancePay.PoliceTickets.openTicket then
            VancePay.PoliceTickets.openTicket(source, item)
        end
        return true
    end

    return false
end

local function getOxInventoryExportMetadata(item, data)
    if type(data) == 'table' then
        if type(data.metadata) == 'table' then
            return data.metadata
        end

        return data
    end

    if type(item) == 'table' and type(item.metadata) == 'table' then
        return item.metadata
    end

    return {}
end

local function getOxInventorySlotItem(source, slot)
    slot = tonumber(slot)
    if not slot then
        return nil
    end

    local ok, slotData = pcall(function()
        return exports.ox_inventory:GetSlot(source, slot)
    end)

    if ok and type(slotData) == 'table' then
        return slotData
    end

    return nil
end

local function handleOxInventoryExportUse(itemName, event, itemDefinition, inventory, slot, data)
    if event ~= 'usedItem' then
        return
    end

    local source = inventory and tonumber(inventory.id) or nil
    if not source or source < 1 then
        return
    end

    local item = getOxInventorySlotItem(source, slot)

    if type(item) ~= 'table' then
        item = {
            slot = tonumber(slot),
            metadata = getOxInventoryExportMetadata(itemDefinition, data),
        }
    end

    handleInventoryDeviceUse(source, itemName, item)
end

local function handleClientInventoryItemUse(source, itemName, item)
    if type(item) ~= 'table' or not tonumber(item.slot) then
        return false
    end

    local slotItem = getOxInventorySlotItem(source, item.slot)
    if type(slotItem) ~= 'table' or slotItem.name ~= itemName then
        return false
    end

    return handleInventoryDeviceUse(source, itemName, slotItem)
end

function Server.registerUsableItems()
    if Server.__itemsRegistered then
        return
    end

    exports.qbx_core:CreateUseableItem(Config.PortablePOSItem, function(source, item)
        handleInventoryDeviceUse(source, Config.PortablePOSItem, item)
    end)

    exports.qbx_core:CreateUseableItem(Config.TabletItem, function(source, item)
        handleInventoryDeviceUse(source, Config.TabletItem, item)
    end)

    local collectionTabletItem = getCollectionTabletItemName()
    if collectionTabletItem ~= Config.PortablePOSItem and collectionTabletItem ~= Config.TabletItem then
        exports.qbx_core:CreateUseableItem(collectionTabletItem, function(source, item)
            handleInventoryDeviceUse(source, collectionTabletItem, item)
        end)
    end

    local ticketBookItem = getPoliceTicketBookItemName()
    if ticketBookItem ~= Config.PortablePOSItem
        and ticketBookItem ~= Config.TabletItem
        and ticketBookItem ~= collectionTabletItem then
        exports.qbx_core:CreateUseableItem(ticketBookItem, function(source, item)
            handleInventoryDeviceUse(source, ticketBookItem, item)
        end)
    end

    local ticketManagerItem = getPoliceTicketManagerItemName()
    if ticketManagerItem ~= Config.PortablePOSItem
        and ticketManagerItem ~= Config.TabletItem
        and ticketManagerItem ~= collectionTabletItem
        and ticketManagerItem ~= ticketBookItem then
        exports.qbx_core:CreateUseableItem(ticketManagerItem, function(source, item)
            handleInventoryDeviceUse(source, ticketManagerItem, item)
        end)
    end

    local ticketItem = getPoliceTicketItemName()
    if ticketItem ~= Config.PortablePOSItem
        and ticketItem ~= Config.TabletItem
        and ticketItem ~= collectionTabletItem
        and ticketItem ~= ticketBookItem
        and ticketItem ~= ticketManagerItem then
        exports.qbx_core:CreateUseableItem(ticketItem, function(source, item)
            handleInventoryDeviceUse(source, ticketItem, item)
        end)
    end

    Server.__itemsRegistered = true
end

function Server.bootstrapResource()
    if Server.__bootstrapStarted then
        return
    end

    Server.__bootstrapStarted = true

    CreateThread(function()
        Wait(250)
        Server.ensureUtf8mb4Schema()

        if getDatabaseConfig().autoMigrate == true then
            if VancePay.Stores and VancePay.Stores.ensureReady then
                VancePay.Stores.ensureReady()
            end

            if VancePay.Intents and VancePay.Intents.ensureReady then
                VancePay.Intents.ensureReady()
            end

            if VancePay.Transactions and VancePay.Transactions.ensureReady then
                VancePay.Transactions.ensureReady()
            end

            if VancePay.Models and VancePay.Models.ensureReady then
                VancePay.Models.ensureReady()
            end

            if VancePay.Terminals and VancePay.Terminals.ensureReady then
                VancePay.Terminals.ensureReady()
            end

            if VancePay.PoliceTickets and VancePay.PoliceTickets.ensureReady then
                VancePay.PoliceTickets.ensureReady()
            end
        end

        Server.registerUsableItems()

        if VancePay.Terminals and VancePay.Terminals.refreshFixedTerminalCache then
            Wait(250)
            VancePay.Terminals.refreshFixedTerminalCache(true)
        end

        Server.__bootstrapCompleted = true
    end)
end

oxInventoryUseHandlers.usePortablePos = function(_, event, item, inventory, slot, data)
    handleOxInventoryExportUse(Config.PortablePOSItem, event, item, inventory, slot, data)
end

oxInventoryUseHandlers.useTablet = function(_, event, item, inventory, slot, data)
    handleOxInventoryExportUse(Config.TabletItem, event, item, inventory, slot, data)
end

oxInventoryUseHandlers.useDebtTablet = function(_, event, item, inventory, slot, data)
    handleOxInventoryExportUse(getCollectionTabletItemName(), event, item, inventory, slot, data)
end

oxInventoryUseHandlers.usePoliceTicketBook = function(_, event, item, inventory, slot, data)
    handleOxInventoryExportUse(getPoliceTicketBookItemName(), event, item, inventory, slot, data)
end

oxInventoryUseHandlers.usePoliceTicketManager = function(_, event, item, inventory, slot, data)
    handleOxInventoryExportUse(getPoliceTicketManagerItemName(), event, item, inventory, slot, data)
end

oxInventoryUseHandlers.usePoliceTicket = function(_, event, item, inventory, slot, data)
    handleOxInventoryExportUse(getPoliceTicketItemName(), event, item, inventory, slot, data)
end

RegisterCommand('mycid', function(source)
    if not source or source == 0 then
        sendCommandMessage(source, '该命令只能由在线玩家使用', 'error')
        return
    end

    local record = Server.getPlayerRecord(source)
    if not record then
        sendCommandMessage(source, '无法读取你的角色信息', 'error')
        return
    end

    sendCommandMessage(source, formatCitizenIdRecord(record), 'inform')
end, false)

RegisterCommand('cid', function(source, args)
    local targetArgument = args and args[1] or nil

    if Utils.isBlank(targetArgument) then
        if not source or source == 0 then
            sendCommandMessage(source, '用法: /cid <serverId>', 'error')
            return
        end

        local record = Server.getPlayerRecord(source)
        if not record then
            sendCommandMessage(source, '无法读取你的角色信息', 'error')
            return
        end

        sendCommandMessage(source, formatCitizenIdRecord(record), 'inform')
        return
    end

    if source ~= 0 and not VancePay.Permissions.isAdmin(source) then
        sendCommandMessage(source, '只有管理员可以查询其他在线玩家的 CID', 'error')
        return
    end

    local targetRecord, err = resolveOnlinePlayerRecord(targetArgument)
    if not targetRecord then
        sendCommandMessage(source, err or '查询失败', 'error')
        return
    end

    sendCommandMessage(source, formatCitizenIdRecord(targetRecord), 'inform')
end, false)

RegisterCommand('vpdevice', function(source, args)
    handleQuickDeviceCommand(source, args or {})
end, false)

RegisterCommand('vptestdevice', function(source, args)
    handleQuickDeviceCommand(source, args or {})
end, false)

AddEventHandler('ox_inventory:usedItem', function(source, itemName, slotId, metadata)
    handleInventoryDeviceUse(source, itemName, {
        slot = tonumber(slotId),
        metadata = type(metadata) == 'table' and metadata or {},
    })
end)

RegisterNetEvent(VancePay.Events.server.useInventoryItem, function(itemName, item)
    handleClientInventoryItemUse(source, itemName, item)
end)

Server.bootstrapResource()

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= VancePay.ResourceName then
        return
    end

    Server.bootstrapResource()
end)
