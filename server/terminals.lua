VancePay.Terminals = VancePay.Terminals or {}

local Terminals = VancePay.Terminals
local ensureModelDataReady

local TERMINAL_SELECT = [[
    SELECT
        t.*,
        s.name AS store_name,
        s.status AS store_status,
        s.balance AS store_balance,
        tm.label AS model_label,
        tm.model_name AS model_name,
        tm.status AS model_status
    FROM vancepay_terminals t
    LEFT JOIN vancepay_stores s ON s.id = t.store_id
    LEFT JOIN vancepay_terminal_models tm ON tm.model_key = t.model_key
]]

local BINDING_CODE_SELECT = [[
    SELECT
        bc.*,
        s.name AS store_name
    FROM vancepay_terminal_binding_codes bc
    LEFT JOIN vancepay_stores s ON s.id = bc.store_id
]]

local function getDatabaseConfig()
    return Config.Database or {}
end

local function shouldRunSchemaMigrations()
    return getDatabaseConfig().autoMigrate == true
end

local function getBindingCodeConfig()
    return Config.BindingCodes or {}
end

local function ensureBindingCodeSchema()
    if Terminals.__bindingCodeSchemaChecked or not shouldRunSchemaMigrations() then
        return
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS vancepay_terminal_binding_codes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            code VARCHAR(24) NOT NULL UNIQUE,
            store_id INT NOT NULL,
            terminal_type ENUM('portable', 'tablet') NOT NULL,
            created_by_citizenid VARCHAR(50) DEFAULT NULL,
            used_by_citizenid VARCHAR(50) DEFAULT NULL,
            used_terminal_id INT DEFAULT NULL,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP NULL DEFAULT NULL,
            revoked_at TIMESTAMP NULL DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_store_type_status (store_id, terminal_type, expires_at, used_at, revoked_at),
            CONSTRAINT fk_vancepay_binding_code_store
                FOREIGN KEY (store_id) REFERENCES vancepay_stores(id) ON DELETE CASCADE,
            CONSTRAINT fk_vancepay_binding_code_terminal
                FOREIGN KEY (used_terminal_id) REFERENCES vancepay_terminals(id) ON DELETE SET NULL
        ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    Terminals.__bindingCodeSchemaChecked = true
end

local function buildPlaceholders(count)
    return ('?,'):rep(count):sub(1, count * 2 - 1)
end

local function normalizeTerminal(row)
    if not row then
        return nil
    end

    row = Utils.normalizeDbRow(row)
    if row.coords then
        row.coords = Utils.decodeCoords(row.coords)
    end

    return row
end

local function normalizeBindingCode(row)
    if not row then
        return nil
    end

    row = Utils.normalizeDbRow(row)
    row.code = Utils.trim(row.code)
    row.terminal_type = Utils.trim(row.terminal_type)
    row.expires_at_unix = Utils.parseSqlDateTime(row.expires_at)
    row.used_at_unix = Utils.parseSqlDateTime(row.used_at)
    row.revoked_at_unix = Utils.parseSqlDateTime(row.revoked_at)

    return row
end

function Terminals.ensureReady()
    ensureModelDataReady()
    ensureBindingCodeSchema()
end

local function isValidTerminalType(terminalType)
    return terminalType == VancePay.TerminalTypes.fixed
        or terminalType == VancePay.TerminalTypes.portable
        or terminalType == VancePay.TerminalTypes.tablet
end

local function isBindableTerminalType(terminalType)
    return terminalType == VancePay.TerminalTypes.portable
        or terminalType == VancePay.TerminalTypes.tablet
end

local function isValidTerminalStatus(status)
    return status == VancePay.TerminalStatuses.active
        or status == VancePay.TerminalStatuses.disabled
        or status == VancePay.TerminalStatuses.archived
end

local function getTerminalUsePermission(terminalType)
    if terminalType == VancePay.TerminalTypes.tablet then
        return 'manage'
    end

    return 'collect'
end

local function resolveTerminalUsageContext(source, terminal)
    if not terminal then
        return nil, VancePay.Server.fail('终端不存在', 'terminal_not_found')
    end

    if terminal.status ~= VancePay.TerminalStatuses.active then
        if terminal.type == VancePay.TerminalTypes.tablet then
            return nil, VancePay.Server.fail('此平板已被停用', 'terminal_inactive')
        end

        return nil, VancePay.Server.fail('此 POS 已被停用', 'terminal_inactive')
    end

    if not terminal.store_id then
        if terminal.type ~= VancePay.TerminalTypes.tablet then
            return nil, VancePay.Server.fail('此 POS 未绑定任何店铺', 'store_unbound')
        end

        if not VancePay.Permissions.isAdmin(source) then
            return nil, VancePay.Server.fail('空白平板不会授予管理员权限', 'forbidden')
        end

        return {
            terminal = terminal,
            store = nil,
            access = nil,
            mode = 'admin',
            is_admin = true,
        }
    end

    local store = VancePay.Stores.fetchById(terminal.store_id)
    if not store then
        if terminal.type == VancePay.TerminalTypes.tablet then
            return nil, VancePay.Server.fail('平板绑定的店铺不存在', 'store_not_found')
        end

        return nil, VancePay.Server.fail('终端绑定的店铺不存在', 'store_not_found')
    end

    if store.status ~= VancePay.StoreStatuses.active then
        if terminal.type == VancePay.TerminalTypes.tablet then
            return nil, VancePay.Server.fail('平板绑定的店铺已归档，无法继续使用', 'store_archived')
        end

        return nil, VancePay.Server.fail('该店铺已归档，不能再发起新交易', 'store_archived')
    end

    local allowed, accessOrReason = VancePay.Permissions.checkAccess(source, store.id, getTerminalUsePermission(terminal.type))
    if not allowed then
        return nil, VancePay.Server.fail(accessOrReason, 'forbidden')
    end

    return {
        terminal = terminal,
        store = store,
        access = accessOrReason,
        mode = 'store',
        is_admin = VancePay.Permissions.isAdmin(source),
    }
end

local function notifyTerminalLeadership(storeId, message, notifyType, excludedCitizenIds)
    if not storeId or not VancePay.Stores or not VancePay.Stores.notifyLeadership then
        return
    end

    VancePay.Stores.notifyLeadership(storeId, message, notifyType, excludedCitizenIds)
end

local function describeTerminalUpdate(existing, terminal)
    if not existing then
        return '终端已绑定'
    end

    local changes = {}

    if existing.status ~= terminal.status then
        changes[#changes + 1] = ('状态改为 %s'):format(terminal.status)
    end

    if existing.type ~= terminal.type then
        changes[#changes + 1] = ('类型改为 %s'):format(terminal.type)
    end

    if existing.serial_number ~= terminal.serial_number then
        changes[#changes + 1] = '序列号已更新'
    end

    if existing.model_key ~= terminal.model_key then
        changes[#changes + 1] = ('型号改为 %s'):format(terminal.model_label or terminal.model_key or '未设置')
    end

    local oldCoords = Utils.encodeCoords(existing.coords)
    local newCoords = Utils.encodeCoords(terminal.coords)
    if oldCoords ~= newCoords or tonumber(existing.heading or 0) ~= tonumber(terminal.heading or 0) then
        changes[#changes + 1] = '位置已更新'
    end

    if #changes == 0 then
        return '配置已更新'
    end

    return table.concat(changes, '，')
end

ensureModelDataReady = function()
    if VancePay.Models and VancePay.Models.ensureReady then
        VancePay.Models.ensureReady()
    end
end

function Terminals.fetchById(terminalId)
    ensureModelDataReady()

    if not tonumber(terminalId) then
        return nil
    end

    local row = MySQL.single.await(TERMINAL_SELECT .. ' WHERE t.id = ? LIMIT 1', { tonumber(terminalId) })
    return normalizeTerminal(row)
end

function Terminals.fetchBySerial(serialNumber)
    ensureModelDataReady()

    if Utils.isBlank(serialNumber) then
        return nil
    end

    local row = MySQL.single.await(TERMINAL_SELECT .. ' WHERE t.serial_number = ? LIMIT 1', { serialNumber })
    return normalizeTerminal(row)
end

function Terminals.fetchByReference(payload)
    payload = payload or {}

    if payload.terminal_id or payload.id then
        return Terminals.fetchById(payload.terminal_id or payload.id)
    end

    return Terminals.fetchBySerial(payload.serial_number or payload.serial)
end

local function hasTerminalReference(payload)
    payload = payload or {}

    if tonumber(payload.terminal_id or payload.id) then
        return true
    end

    return not Utils.isBlank(payload.serial_number or payload.serial)
end

local function getManagedTabletStore(source, payload)
    payload = payload or {}
    local requestedStoreId = tonumber(payload.store_id)

    if requestedStoreId then
        local allowed = VancePay.Permissions.checkAccess(source, requestedStoreId, 'manage')
        if allowed then
            local requestedStore = VancePay.Stores.fetchById(requestedStoreId)
            if requestedStore then
                return requestedStore
            end
        end
    end

    local stores = VancePay.Stores.listForSource(source, {})

    for index = 1, #stores do
        local store = stores[index]
        local allowed = VancePay.Permissions.checkAccess(source, store.id, 'manage')
        if allowed then
            return store
        end
    end

    return nil
end

local function getFallbackTabletBootstrap(source, payload)
    if hasTerminalReference(payload) then
        return nil
    end

    if VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.ok({
            mode = 'admin',
            terminal = nil,
            is_admin = true,
            store = nil,
        })
    end

    local store = getManagedTabletStore(source, payload)
    if not store then
        return VancePay.Server.fail('该平板未绑定终端，且你没有可管理的店铺', 'forbidden')
    end

    return VancePay.Server.ok({
        mode = 'store',
        terminal = nil,
        is_admin = false,
        store = store,
    })
end

local function getDeviceLabel(terminalType)
    if terminalType == VancePay.TerminalTypes.portable then
        return '便携 POS'
    end

    if terminalType == VancePay.TerminalTypes.tablet then
        return '管理平板'
    end

    return '终端'
end

local function getDeviceItemName(terminalType)
    if terminalType == VancePay.TerminalTypes.portable then
        return Config.PortablePOSItem
    end

    if terminalType == VancePay.TerminalTypes.tablet then
        return Config.TabletItem
    end

    return nil
end

local function buildTerminalItemMetadata(terminal)
    return {
        serial_number = terminal and terminal.serial_number or nil,
        terminal_id = terminal and terminal.id or nil,
        store_id = terminal and terminal.store_id or nil,
        store_name = terminal and terminal.store_name or nil,
        terminal_type = terminal and terminal.type or nil,
    }
end

local function fetchActiveBindingCode(code)
    ensureBindingCodeSchema()

    code = string.upper(Utils.trim(code or ''))
    if Utils.isBlank(code) then
        return nil
    end

    local row = MySQL.single.await(BINDING_CODE_SELECT .. [[
        WHERE bc.code = ?
            AND bc.used_at IS NULL
            AND bc.revoked_at IS NULL
            AND bc.expires_at >= UTC_TIMESTAMP()
        LIMIT 1
    ]], { code })

    return normalizeBindingCode(row)
end

local function giveTerminalItem(source, terminal)
    local itemName = getDeviceItemName(terminal and terminal.type or nil)
    if Utils.isBlank(itemName) then
        return false, '只有便携 POS 和管理平板可以发放为背包物品'
    end

    local metadata = buildTerminalItemMetadata(terminal)
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
        Utils.debug('Failed to give terminal item', itemName, source, success)
        return false, '发放终端物品时调用库存失败'
    end

    if success == false then
        return false, response or '终端物品发放失败'
    end

    return true, ('%s已发放到你的背包'):format(getDeviceLabel(terminal.type))
end

local function getItemMetadata(item)
    if type(item) ~= 'table' then
        return {}
    end

    if type(item.metadata) == 'table' then
        return Utils.deepCopy(item.metadata)
    end

    if type(item.info) == 'table' then
        return Utils.deepCopy(item.info)
    end

    return {}
end

local function resolveItemSlot(source, itemName, item, metadata)
    local slot = tonumber(item and (item.slot or item.slot_id or item.slotId))
    if slot then
        return slot
    end

    local serialNumber = Utils.trim(metadata and metadata.serial_number or nil)
    if not Utils.isBlank(serialNumber) then
        local ok, slotId = pcall(function()
            return exports.ox_inventory:GetSlotIdWithItem(source, itemName, {
                serial_number = serialNumber,
            }, false)
        end)

        if ok and slotId then
            return tonumber(slotId)
        end
    end

    local ok, slotData = pcall(function()
        return exports.ox_inventory:GetSlotWithItem(source, itemName, metadata, false)
    end)

    if ok and slotData and slotData.slot then
        return tonumber(slotData.slot)
    end

    return nil
end

local function syncItemMetadata(source, itemName, item, metadata)
    local slot = resolveItemSlot(source, itemName, item, metadata)
    if not slot then
        return false
    end

    local ok, err = pcall(function()
        exports.ox_inventory:SetMetadata(source, slot, metadata)
    end)

    if not ok then
        Utils.debug('Failed to sync item metadata', itemName, source, err)
        return false
    end

    return true
end

local function getManageableActiveStores(source)
    local stores = VancePay.Stores.listForSource(source, {
        status = VancePay.StoreStatuses.active,
    })
    local managed = {}

    for index = 1, #stores do
        local store = stores[index]
        local allowed = VancePay.Permissions.checkAccess(source, store.id, 'manage')
        if allowed then
            managed[#managed + 1] = store
        end
    end

    return managed
end

local function resolveProvisionStore(source, terminalType, payload)
    payload = payload or {}

    local requestedStoreId = tonumber(payload.store_id)
    if requestedStoreId then
        local store = VancePay.Stores.fetchById(requestedStoreId)
        if not store then
            return nil, '店铺不存在'
        end

        if store.status ~= VancePay.StoreStatuses.active then
            return nil, '店铺已归档，无法绑定新设备'
        end

        local allowed = VancePay.Permissions.checkAccess(source, requestedStoreId, 'manage')
        if not allowed then
            return nil, '你没有该店铺的管理权限'
        end

        return store
    end

    if terminalType == VancePay.TerminalTypes.tablet and VancePay.Permissions.isAdmin(source) then
        return nil, nil
    end

    local stores = getManageableActiveStores(source)
    if #stores == 1 then
        return stores[1]
    end

    if #stores == 0 then
        if terminalType == VancePay.TerminalTypes.portable then
            return nil, '当前没有可自动绑定的启用店铺，请先在管理平板中绑定此便携 POS'
        end

        return nil, '当前没有可自动绑定的启用店铺'
    end

    if terminalType == VancePay.TerminalTypes.portable then
        return nil, '你管理多个启用中的店铺，无法自动绑定此便携 POS，请先在管理平板中绑定终端'
    end

    return nil, '你管理多个启用中的店铺，无法自动固定此平板归属'
end

local function provisionInventoryTerminal(source, terminalType, metadata, payload)
    metadata = metadata or {}
    payload = payload or {}

    local store, storeError = resolveProvisionStore(source, terminalType, payload)
    if storeError then
        return VancePay.Server.fail(storeError, 'auto_bind_unavailable')
    end

    local saveResponse = Terminals.save(source, {
        serial_number = Utils.trim(metadata.serial_number or metadata.serial),
        store_id = store and store.id or nil,
        type = terminalType,
        status = VancePay.TerminalStatuses.active,
    })

    if not saveResponse or not saveResponse.ok then
        return saveResponse or VancePay.Server.fail('设备初始化失败', 'device_init_failed')
    end

    local terminal = saveResponse.data
    local message

    if store then
        message = ('%s已自动绑定到店铺 %s'):format(getDeviceLabel(terminalType), store.name or ('#' .. tostring(store.id)))
    elseif terminalType == VancePay.TerminalTypes.tablet then
        message = '管理平板已自动初始化为全局设备'
    else
        message = ('%s已自动初始化'):format(getDeviceLabel(terminalType))
    end

    return VancePay.Server.ok({
        terminal = terminal,
        store = store,
    }, message)
end

local function buildBindingRequiredResponse(source, terminalType, metadata, provisionResponse)
    local message = ('此%s尚未绑定，请输入绑定码继续'):format(getDeviceLabel(terminalType))
    if provisionResponse and not Utils.isBlank(provisionResponse.message) then
        message = ('无法自动绑定：%s。请输入绑定码继续'):format(provisionResponse.message)
    end

    local fallbackBootstrap = nil
    if terminalType == VancePay.TerminalTypes.tablet then
        local fallback = getFallbackTabletBootstrap(source, {})
        if fallback and fallback.ok then
            fallbackBootstrap = fallback.data
            message = message .. '；取消后会以临时权限模式打开'
        end
    end

    return VancePay.Server.ok({
        terminal = nil,
        metadata = metadata,
        launch_serial_number = nil,
        metadata_written = false,
        initialized = false,
        fallback_only = false,
        binding_required = true,
        terminal_type = terminalType,
        fallback_bootstrap = fallbackBootstrap,
    }, message)
end

function Terminals.prepareInventoryDevice(source, itemName, terminalType, item, payload)
    payload = payload or {}

    local metadata = getItemMetadata(item)
    local serialNumber = Utils.trim(metadata.serial_number or metadata.serial)
    local terminal = not Utils.isBlank(serialNumber) and Terminals.fetchBySerial(serialNumber) or nil
    local wroteMetadata = false
    local message = nil
    local fallbackOnly = false
    local initialized = false

    if terminal and terminal.type ~= terminalType then
        return VancePay.Server.fail(('该道具绑定的是%s，不是%s'):format(
            getDeviceLabel(terminal.type),
            getDeviceLabel(terminalType)
        ), 'type_mismatch')
    end

    if not terminal then
        local provisionResponse = provisionInventoryTerminal(source, terminalType, metadata, payload)
        if provisionResponse and provisionResponse.ok then
            terminal = provisionResponse.data.terminal
            metadata.serial_number = terminal.serial_number
            message = provisionResponse.message
            initialized = true
            wroteMetadata = syncItemMetadata(source, itemName, item, metadata)

            if not wroteMetadata then
                message = ('%s，但未能写回道具 metadata'):format(message or '设备已初始化')
            end
        elseif isBindableTerminalType(terminalType) then
            return buildBindingRequiredResponse(source, terminalType, metadata, provisionResponse)
        else
            return provisionResponse or VancePay.Server.fail('设备初始化失败', 'device_init_failed')
        end
    elseif Utils.trim(metadata.serial_number) ~= terminal.serial_number then
        metadata.serial_number = terminal.serial_number
        wroteMetadata = syncItemMetadata(source, itemName, item, metadata)
        if not wroteMetadata then
            message = '设备序列号已识别，但未能写回道具 metadata'
        end
    end

    if terminal then
        local _, accessError = resolveTerminalUsageContext(source, terminal)
        if accessError then
            return accessError
        end
    end

    return VancePay.Server.ok({
        terminal = terminal,
        metadata = metadata,
        launch_serial_number = terminal and terminal.serial_number or nil,
        metadata_written = wroteMetadata,
        initialized = initialized,
        fallback_only = fallbackOnly,
    }, message)
end

function Terminals.listForSource(source, filters)
    ensureModelDataReady()

    filters = filters or {}
    local query = TERMINAL_SELECT
    local params = {}
    local conditions = { '1=1' }

    if filters.store_id then
        conditions[#conditions + 1] = 't.store_id = ?'
        params[#params + 1] = tonumber(filters.store_id)
    end

    if filters.type and filters.type ~= 'all' then
        conditions[#conditions + 1] = 't.type = ?'
        params[#params + 1] = filters.type
    end

    if filters.status and filters.status ~= 'all' then
        conditions[#conditions + 1] = 't.status = ?'
        params[#params + 1] = filters.status
    end

    if not VancePay.Permissions.isAdmin(source) then
        local citizenid = VancePay.Permissions.getCitizenId(source)
        local storeIds = VancePay.Stores.getManagedStoreIds(citizenid)
        if #storeIds == 0 then
            return {}
        end

        conditions[#conditions + 1] = ('t.store_id IN (%s)'):format(buildPlaceholders(#storeIds))
        for index = 1, #storeIds do
            params[#params + 1] = storeIds[index]
        end
    end

    query = query .. ' WHERE ' .. table.concat(conditions, ' AND ') .. ' ORDER BY t.id DESC'
    local rows = MySQL.query.await(query, params) or {}

    for index = 1, #rows do
        rows[index] = normalizeTerminal(rows[index])
    end

    return rows
end

function Terminals.listFixedActive()
    ensureModelDataReady()

    local rows = MySQL.query.await(TERMINAL_SELECT .. [[
        WHERE t.type = 'fixed'
            AND t.status = 'active'
            AND t.coords IS NOT NULL
            AND (s.id IS NULL OR s.status = 'active')
        ORDER BY t.id ASC
    ]]) or {}

    local items = {}

    for index = 1, #rows do
        local row = normalizeTerminal(rows[index])
        if row.coords then
            items[#items + 1] = row
        end
    end

    return items
end

function Terminals.listFixedForSource(source)
    local terminals = VancePay.Server.FixedTerminalCache or Terminals.listFixedActive()
    local isAdmin = VancePay.Permissions.isAdmin(source)
    local allowedStoreIds = {}

    if not isAdmin then
        local citizenid = VancePay.Permissions.getCitizenId(source)
        local storeIds = VancePay.Stores.getEmployeeStoreIds(citizenid)
        for index = 1, #storeIds do
            allowedStoreIds[tonumber(storeIds[index])] = true
        end
    end

    local visible = {}

    for index = 1, #terminals do
        local terminal = Utils.deepCopy(terminals[index])
        terminal.can_access = isAdmin or allowedStoreIds[tonumber(terminal.store_id)] == true
        visible[#visible + 1] = terminal
    end

    return visible
end

function Terminals.refreshFixedTerminalCache(broadcast)
    VancePay.Server.FixedTerminalCache = Terminals.listFixedActive()

    if broadcast then
        -- Clients refetch a source-filtered terminal list on update; avoid broadcasting raw terminal data.
        TriggerClientEvent(VancePay.Events.client.fixedTerminalsUpdated, -1)
    end

    return VancePay.Server.FixedTerminalCache
end

local function validateTerminalWrite(source, payload, existing)
    local terminalType = Utils.trim(payload.type or (existing and existing.type) or VancePay.TerminalTypes.portable)
    local status = Utils.trim(payload.status or (existing and existing.status) or VancePay.TerminalStatuses.active)
    local storeId = tonumber(payload.store_id)
    local isAdmin = VancePay.Permissions.isAdmin(source)

    if not isValidTerminalType(terminalType) then
        return nil, '终端类型无效'
    end

    if not isValidTerminalStatus(status) then
        return nil, '终端状态无效'
    end

    if existing and not isAdmin then
        if existing.type ~= terminalType then
            return nil, '只有管理员可以修改终端类型'
        end
    end

    if terminalType == VancePay.TerminalTypes.tablet and not storeId and not isAdmin then
        return nil, '只有管理员可以创建全局平板'
    end

    if terminalType == VancePay.TerminalTypes.fixed and not existing and not isAdmin then
        return nil, '只有管理员可以新建固定 POS'
    end

    if terminalType ~= VancePay.TerminalTypes.fixed then
        payload.coords = nil
        payload.heading = nil
        payload.model_key = nil
    else
        payload.model_key = Utils.trim(payload.model_key or (existing and existing.model_key) or Config.DefaultTerminalModelKey)

        local modelDefinition = VancePay.Models and VancePay.Models.fetchByKey(payload.model_key) or nil
        if not modelDefinition then
            return nil, '固定 POS 型号无效'
        end

        if modelDefinition.status ~= 'active' then
            local isCurrentModel = existing and existing.model_key == modelDefinition.model_key
            if not isCurrentModel or status == VancePay.TerminalStatuses.active then
                return nil, '该 POS 型号已停用，请更换为可用型号'
            end
        end

        if type(payload.coords) ~= 'table' then
            return nil, '固定 POS 缺少放置坐标'
        end
    end

    if not isAdmin then
        if storeId then
            local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
            if not allowed then
                return nil, reason
            end
        elseif existing and existing.store_id then
            local allowed, reason = VancePay.Permissions.checkAccess(source, existing.store_id, 'manage')
            if not allowed then
                return nil, reason
            end
        else
            return nil, '只有管理员可以管理未绑定终端'
        end

        if existing and existing.store_id and storeId and existing.store_id ~= storeId then
            return nil, '只有管理员可以跨店铺重绑终端'
        end
    end

    return {
        type = terminalType,
        status = status,
        store_id = storeId,
        serial_number = Utils.trim(payload.serial_number or payload.serial),
        model_key = payload.model_key,
        coords = payload.coords,
        heading = tonumber(payload.heading) or 0.0,
    }
end

local function generateTerminalSerial()
    return ('VP-%s'):format(tostring(exports.qbx_core:GenerateUniqueIdentifier('SerialNumber')))
end

local function persistInventoryBindingTerminal(actorCitizenId, storeId, terminalType, serialNumber)
    local existing = not Utils.isBlank(serialNumber) and Terminals.fetchBySerial(serialNumber) or nil

    if existing and existing.type ~= terminalType then
        return nil, existing, VancePay.Server.fail(('该道具绑定的是%s，不是%s'):format(
            getDeviceLabel(existing.type),
            getDeviceLabel(terminalType)
        ), 'type_mismatch')
    end

    if existing and existing.store_id and existing.store_id ~= storeId then
        return nil, existing, VancePay.Server.fail('该设备已绑定到其他店铺，不能重复绑定', 'already_bound')
    end

    if Utils.isBlank(serialNumber) then
        serialNumber = generateTerminalSerial()
    end

    if existing then
        local updated = MySQL.update.await([[
            UPDATE vancepay_terminals
            SET store_id = ?,
                type = ?,
                serial_number = ?,
                status = ?,
                model_key = NULL,
                coords = NULL,
                heading = 0,
                archived_at = NULL
            WHERE id = ?
        ]], {
            storeId,
            terminalType,
            serialNumber,
            VancePay.TerminalStatuses.active,
            existing.id,
        })

        if not updated or updated < 1 then
            return nil, existing, VancePay.Server.fail('终端绑定失败', 'db_error')
        end
    else
        local insertedId = MySQL.insert.await([[
            INSERT INTO vancepay_terminals (
                store_id,
                type,
                serial_number,
                status,
                model_key,
                coords,
                heading,
                created_by_citizenid
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            storeId,
            terminalType,
            serialNumber,
            VancePay.TerminalStatuses.active,
            nil,
            nil,
            0.0,
            actorCitizenId,
        })

        if not insertedId then
            return nil, nil, VancePay.Server.fail('终端绑定失败，序列号可能重复', 'db_error')
        end
    end

    local terminal = Terminals.fetchBySerial(serialNumber)
    if not terminal then
        return nil, existing, VancePay.Server.fail('终端绑定后回查失败', 'post_fetch_failed')
    end

    return terminal, existing, nil
end

function Terminals.save(source, payload)
    payload = payload or {}
    local existing = Terminals.fetchByReference(payload)
    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    local previousStoreId = existing and existing.store_id or nil
    local shouldGrantItem = payload.grant_item == true

    if shouldGrantItem and not VancePay.Permissions.isAdmin(source) then
        return VancePay.Server.fail('只有管理员可以直接发放终端物品', 'forbidden')
    end

    local validated, validationError = validateTerminalWrite(source, payload, existing)
    if not validated then
        return VancePay.Server.fail(validationError, 'invalid_terminal')
    end

    if shouldGrantItem and not isBindableTerminalType(validated.type) then
        return VancePay.Server.fail('只有便携 POS 和管理平板可以直接发放物品', 'invalid_terminal_type')
    end

    local serialNumber = validated.serial_number
    if Utils.isBlank(serialNumber) then
        serialNumber = generateTerminalSerial()
    end

    local coordsJson = validated.coords and Utils.encodeCoords(validated.coords) or nil

    if existing then
        local updated = MySQL.update.await([[
            UPDATE vancepay_terminals
            SET store_id = ?,
                type = ?,
                serial_number = ?,
                status = ?,
                model_key = ?,
                coords = ?,
                heading = ?,
                archived_at = CASE WHEN ? = 'archived' THEN CURRENT_TIMESTAMP ELSE NULL END
            WHERE id = ?
        ]], {
            validated.store_id,
            validated.type,
            serialNumber,
            validated.status,
            validated.model_key,
            coordsJson,
            validated.heading,
            validated.status,
            existing.id,
        })

        if not updated or updated < 1 then
            return VancePay.Server.fail('终端更新失败', 'db_error')
        end
    else
        local insertedId = MySQL.insert.await([[
            INSERT INTO vancepay_terminals (
                store_id,
                type,
                serial_number,
                status,
                model_key,
                coords,
                heading,
                created_by_citizenid
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            validated.store_id,
            validated.type,
            serialNumber,
            validated.status,
            validated.model_key,
            coordsJson,
            validated.heading,
            actorCitizenId,
        })

        if not insertedId then
            return VancePay.Server.fail('终端创建失败，序列号可能重复', 'db_error')
        end
    end

    local terminal = Terminals.fetchBySerial(serialNumber)
    if not terminal then
        return VancePay.Server.fail('终端保存后回查失败', 'post_fetch_failed')
    end

    VancePay.Audit.log(actorCitizenId, existing and 'update_terminal' or 'create_terminal', 'terminal', terminal.id, {
        store_id = terminal.store_id,
        terminal_id = terminal.id,
        detail = {
            serial_number = terminal.serial_number,
            type = terminal.type,
            status = terminal.status,
            store_id = terminal.store_id,
            coords = terminal.coords,
            heading = terminal.heading,
        }
    })

    if terminal.type == VancePay.TerminalTypes.fixed or (existing and existing.type == VancePay.TerminalTypes.fixed) then
        Terminals.refreshFixedTerminalCache(true)
    end

    if not existing then
        if terminal.store_id then
            notifyTerminalLeadership(
                terminal.store_id,
                ('终端 %s 已绑定到店铺 %s'):format(terminal.serial_number, terminal.store_name or ('#' .. tostring(terminal.store_id))),
                'inform',
                actorCitizenId
            )
        end
    elseif previousStoreId ~= terminal.store_id then
        if previousStoreId then
            notifyTerminalLeadership(
                previousStoreId,
                ('终端 %s 已从本店解绑'):format(terminal.serial_number),
                'warning',
                actorCitizenId
            )
        end

        if terminal.store_id then
            notifyTerminalLeadership(
                terminal.store_id,
                ('终端 %s 已绑定到店铺 %s'):format(terminal.serial_number, terminal.store_name or ('#' .. tostring(terminal.store_id))),
                'inform',
                actorCitizenId
            )
        end
    elseif terminal.store_id then
        notifyTerminalLeadership(
            terminal.store_id,
            ('终端 %s 已更新：%s'):format(terminal.serial_number, describeTerminalUpdate(existing, terminal)),
            'inform',
            actorCitizenId
        )
    end

    local message = existing and '终端已更新' or '终端已创建'

    if shouldGrantItem then
        local granted, grantMessage = giveTerminalItem(source, terminal)
        if granted then
            message = ('%s，并已将对应物品发放到你的背包'):format(message)
            VancePay.Audit.log(actorCitizenId, 'grant_terminal_item', 'terminal', terminal.id, {
                store_id = terminal.store_id,
                terminal_id = terminal.id,
                detail = {
                    serial_number = terminal.serial_number,
                    terminal_type = terminal.type,
                    granted_item = getDeviceItemName(terminal.type),
                }
            })
        else
            message = ('%s，但发放终端物品失败：%s'):format(message, grantMessage or '未知错误')
        end
    end

    return VancePay.Server.ok(terminal, message)
end

function Terminals.generateBindingCode(source, payload)
    ensureBindingCodeSchema()

    payload = payload or {}
    local storeId = tonumber(payload.store_id)
    local terminalType = Utils.trim(payload.terminal_type or payload.type)
    local actorCitizenId = VancePay.Permissions.getCitizenId(source)

    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    if not isBindableTerminalType(terminalType) then
        return VancePay.Server.fail('绑定码仅支持便携 POS 和管理平板', 'invalid_terminal_type')
    end

    local store = VancePay.Stores.fetchById(storeId)
    if not store then
        return VancePay.Server.fail('店铺不存在', 'store_not_found')
    end

    if store.status ~= VancePay.StoreStatuses.active then
        return VancePay.Server.fail('店铺已归档，不能生成新的绑定码', 'store_archived')
    end

    local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
    if not allowed then
        return VancePay.Server.fail(reason, 'forbidden')
    end

    local config = getBindingCodeConfig()
    local prefix = Utils.trim(config.prefix or 'VP')
    local codeLength = math.max(tonumber(config.length) or 6, 4)
    local expiryMinutes = math.max(tonumber(config.expiryMinutes) or 30, 1)

    local insertedId = nil
    local generatedCode = nil

    for _ = 1, 6 do
        generatedCode = Utils.generateCode(prefix, codeLength)
        insertedId = MySQL.insert.await([[
            INSERT INTO vancepay_terminal_binding_codes (
                code,
                store_id,
                terminal_type,
                created_by_citizenid,
                expires_at
            ) VALUES (?, ?, ?, ?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? MINUTE))
        ]], {
            generatedCode,
            storeId,
            terminalType,
            actorCitizenId,
            expiryMinutes,
        })

        if insertedId then
            break
        end
    end

    if not insertedId then
        return VancePay.Server.fail('绑定码生成失败，请稍后重试', 'db_error')
    end

    local bindingCode = normalizeBindingCode(MySQL.single.await(BINDING_CODE_SELECT .. ' WHERE bc.id = ? LIMIT 1', {
        insertedId,
    }))

    if not bindingCode then
        return VancePay.Server.fail('绑定码生成后读取失败', 'post_fetch_failed')
    end

    VancePay.Audit.log(actorCitizenId, 'create_binding_code', 'binding_code', bindingCode.id, {
        store_id = storeId,
        detail = {
            terminal_type = terminalType,
            expires_at = bindingCode.expires_at,
            binding_code_hint = bindingCode.code and bindingCode.code:sub(math.max(#bindingCode.code - 3, 1)) or nil,
        }
    })

    return VancePay.Server.ok(bindingCode, ('%s绑定码 %s 已生成'):format(
        getDeviceLabel(terminalType),
        bindingCode.code
    ))
end

function Terminals.redeemBindingCode(source, payload)
    ensureBindingCodeSchema()

    payload = payload or {}
    local bindingCode = fetchActiveBindingCode(payload.binding_code or payload.code)
    local terminalType = Utils.trim(payload.terminal_type or payload.type)
    local itemName = getDeviceItemName(terminalType)
    local item = type(payload.item) == 'table' and payload.item or {}
    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    local slot = tonumber(item.slot or item.slot_id or item.slotId)

    if not isBindableTerminalType(terminalType) then
        return VancePay.Server.fail('绑定码设备类型无效', 'invalid_terminal_type')
    end

    if not itemName then
        return VancePay.Server.fail('无法识别对应的设备物品', 'invalid_item')
    end

    if not slot then
        return VancePay.Server.fail('请通过背包里的实际设备物品执行绑定', 'missing_slot')
    end

    local slotOk, slotData = pcall(function()
        return exports.ox_inventory:GetSlot(source, slot)
    end)

    if not slotOk or type(slotData) ~= 'table' or slotData.name ~= itemName then
        return VancePay.Server.fail('当前槽位不是可绑定的设备物品', 'invalid_item')
    end

    if not bindingCode then
        return VancePay.Server.fail('绑定码无效、已过期或已被使用', 'binding_code_invalid')
    end

    if bindingCode.terminal_type ~= terminalType then
        return VancePay.Server.fail(('该绑定码仅适用于%s'):format(
            getDeviceLabel(bindingCode.terminal_type)
        ), 'type_mismatch')
    end

    local store = VancePay.Stores.fetchById(bindingCode.store_id)
    if not store then
        return VancePay.Server.fail('绑定码对应的店铺不存在', 'store_not_found')
    end

    if store.status ~= VancePay.StoreStatuses.active then
        return VancePay.Server.fail('绑定码对应的店铺已归档，无法继续绑定', 'store_archived')
    end

    local metadata = getItemMetadata(item)
    local serialNumber = Utils.trim(metadata.serial_number or metadata.serial)
    local terminal, existingTerminal, bindError = persistInventoryBindingTerminal(
        actorCitizenId,
        store.id,
        terminalType,
        serialNumber
    )

    if not terminal then
        return bindError or VancePay.Server.fail('终端绑定失败', 'bind_failed')
    end

    metadata.serial_number = terminal.serial_number
    metadata.terminal_id = terminal.id
    metadata.store_id = terminal.store_id
    metadata.store_name = terminal.store_name
    metadata.terminal_type = terminal.type

    local wroteMetadata = syncItemMetadata(source, itemName, item, metadata)

    local consumed = MySQL.update.await([[
        UPDATE vancepay_terminal_binding_codes
        SET used_by_citizenid = ?,
            used_terminal_id = ?,
            used_at = UTC_TIMESTAMP()
        WHERE id = ?
            AND used_at IS NULL
            AND revoked_at IS NULL
            AND expires_at >= UTC_TIMESTAMP()
    ]], {
        actorCitizenId,
        terminal.id,
        bindingCode.id,
    })

    if not consumed or consumed < 1 then
        return VancePay.Server.fail('绑定码已失效，请重新生成新的绑定码', 'binding_code_invalid')
    end

    local bindAction = existingTerminal and 'update_terminal' or 'create_terminal'
    VancePay.Audit.log(actorCitizenId, bindAction, 'terminal', terminal.id, {
        store_id = terminal.store_id,
        terminal_id = terminal.id,
        detail = {
            serial_number = terminal.serial_number,
            type = terminal.type,
            status = terminal.status,
            store_id = terminal.store_id,
            source = 'binding_code',
        }
    })

    VancePay.Audit.log(actorCitizenId, 'consume_binding_code', 'binding_code', bindingCode.id, {
        store_id = terminal.store_id,
        terminal_id = terminal.id,
        detail = {
            terminal_type = terminal.type,
            terminal_serial_number = terminal.serial_number,
            binding_code_hint = bindingCode.code and bindingCode.code:sub(math.max(#bindingCode.code - 3, 1)) or nil,
            metadata_written = wroteMetadata,
        }
    })

    notifyTerminalLeadership(
        terminal.store_id,
        ('终端 %s 已通过绑定码接入店铺 %s'):format(
            terminal.serial_number,
            terminal.store_name or ('#' .. tostring(terminal.store_id))
        ),
        'inform',
        actorCitizenId
    )

    local message = ('%s绑定成功，已接入店铺 %s'):format(
        getDeviceLabel(terminal.type),
        terminal.store_name or ('#' .. tostring(terminal.store_id))
    )

    if not wroteMetadata then
        message = message .. '，但未能写回道具 metadata'
    end

    return VancePay.Server.ok({
        terminal = terminal,
        metadata = metadata,
        launch_serial_number = terminal.serial_number,
        metadata_written = wroteMetadata,
        binding_code_id = bindingCode.id,
    }, message)
end

function Terminals.archive(source, terminalId)
    terminalId = tonumber(terminalId)
    if not terminalId then
        return VancePay.Server.fail('缺少终端 ID', 'missing_terminal_id')
    end

    local terminal = Terminals.fetchById(terminalId)
    if not terminal then
        return VancePay.Server.fail('终端不存在', 'not_found')
    end

    if not VancePay.Permissions.isAdmin(source) then
        if not terminal.store_id then
            return VancePay.Server.fail('只有管理员可以归档未绑定终端', 'forbidden')
        end

        local allowed, reason = VancePay.Permissions.checkAccess(source, terminal.store_id, 'manage')
        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_terminals
        SET status = 'archived',
            archived_at = CURRENT_TIMESTAMP
        WHERE id = ? AND status <> 'archived'
    ]], { terminalId })

    if not updated or updated < 1 then
        return VancePay.Server.fail('终端已归档或无法归档', 'no_change')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    VancePay.Audit.log(actorCitizenId, 'archive_terminal', 'terminal', terminalId, {
        store_id = terminal.store_id,
        terminal_id = terminalId,
        detail = {
            serial_number = terminal.serial_number,
        }
    })

    if terminal.type == VancePay.TerminalTypes.fixed then
        Terminals.refreshFixedTerminalCache(true)
    end

    if terminal.store_id then
        notifyTerminalLeadership(
            terminal.store_id,
            ('终端 %s 已归档，不能再继续收款'):format(terminal.serial_number),
            'warning',
            actorCitizenId
        )
    end

    return VancePay.Server.ok(Terminals.fetchById(terminalId), '终端已归档')
end

function Terminals.getPosBootstrap(source, payload)
    payload = payload or {}
    local terminal = Terminals.fetchByReference(payload)
    if not terminal then
        return VancePay.Server.fail('未找到对应的 POS 终端', 'terminal_not_found')
    end

    if payload.launch == 'fixed' and terminal.type ~= VancePay.TerminalTypes.fixed then
        return VancePay.Server.fail('终端类型不匹配', 'type_mismatch')
    end

    if payload.launch == 'portable' and terminal.type ~= VancePay.TerminalTypes.portable then
        return VancePay.Server.fail('该道具未绑定便携 POS 终端', 'type_mismatch')
    end

    local usageContext, usageError = resolveTerminalUsageContext(source, terminal)
    if not usageContext then
        return usageError
    end

    local store = usageContext.store
    local access = usageContext.access

    local overview = VancePay.Reports and VancePay.Reports.getStoreOverview(store.id) or nil
    local recentTransactions = VancePay.Transactions and VancePay.Transactions.listInternal({
        store_id = store.id,
        page = 1,
        per_page = 5,
    }).items or {}
    local activeIntent = VancePay.Intents and VancePay.Intents.fetchActiveByTerminalId(terminal.id) or nil

    return VancePay.Server.ok({
        terminal = terminal,
        store = store,
        access = access,
        overview = overview,
        recent_transactions = recentTransactions,
        active_intent = activeIntent and VancePay.Intents.buildClientPayload(activeIntent, {
            status = activeIntent.status,
        }) or nil,
        active_terminal_models = VancePay.Models and VancePay.Models.list({ status = 'active' }) or {},
    })
end

function Terminals.getTabletBootstrap(source, payload)
    payload = payload or {}
    local terminal = Terminals.fetchByReference(payload)
    if not terminal then
        local fallback = getFallbackTabletBootstrap(source, payload)
        if fallback then
            return fallback
        end

        return VancePay.Server.fail('未找到对应的管理平板', 'terminal_not_found')
    end

    if terminal.type ~= VancePay.TerminalTypes.tablet then
        return VancePay.Server.fail('该物品未绑定管理平板终端', 'type_mismatch')
    end

    local usageContext, usageError = resolveTerminalUsageContext(source, terminal)
    if not usageContext then
        return usageError
    end

    return VancePay.Server.ok({
        mode = usageContext.mode,
        terminal = terminal,
        is_admin = usageContext.is_admin,
        store = usageContext.store,
    })
end

lib.callback.register('vancepay:server:getFixedTerminals', function(source)
    return VancePay.Server.ok(Terminals.listFixedForSource(source))
end)

lib.callback.register('vancepay:server:getPosBootstrap', function(source, payload)
    return Terminals.getPosBootstrap(source, payload or {})
end)

lib.callback.register('vancepay:server:getTabletBootstrap', function(source, payload)
    return Terminals.getTabletBootstrap(source, payload or {})
end)

lib.callback.register('vancepay:server:getTerminals', function(source, filters)
    return VancePay.Server.ok(Terminals.listForSource(source, filters or {}))
end)

lib.callback.register('vancepay:server:saveTerminal', function(source, payload)
    return Terminals.save(source, payload or {})
end)

lib.callback.register('vancepay:server:generateBindingCode', function(source, payload)
    return Terminals.generateBindingCode(source, payload or {})
end)

lib.callback.register('vancepay:server:redeemBindingCode', function(source, payload)
    return Terminals.redeemBindingCode(source, payload or {})
end)

lib.callback.register('vancepay:server:archiveTerminal', function(source, terminalId)
    return Terminals.archive(source, terminalId)
end)
