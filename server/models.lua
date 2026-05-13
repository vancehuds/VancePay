VancePay.Models = VancePay.Models or {}

local Models = VancePay.Models

Models._ready = Models._ready or false

local function getDatabaseConfig()
    return Config.Database or {}
end

local function shouldEnsureUtf8mb4()
    local config = getDatabaseConfig()
    return config.autoMigrate == true or config.enforceUtf8mb4 == true
end

local MODEL_SELECT = [[
    SELECT *
    FROM vancepay_terminal_models
]]

local MODELS_TABLE_NAME = 'vancepay_terminal_models'
local MODELS_TABLE_COLLATION = 'utf8mb4_unicode_ci'

local CREATE_MODELS_TABLE = [[
    CREATE TABLE IF NOT EXISTS vancepay_terminal_models (
        model_key VARCHAR(50) PRIMARY KEY,
        label VARCHAR(100) NOT NULL,
        model_name VARCHAR(100) NOT NULL,
        status ENUM('active', 'archived') NOT NULL DEFAULT 'active',
        is_system TINYINT(1) NOT NULL DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        archived_at TIMESTAMP NULL DEFAULT NULL
    ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local function normalizeModel(row)
    if not row then
        return nil
    end

    return Utils.normalizeDbRow(row)
end

local function isValidStatus(status)
    return status == 'active' or status == 'archived'
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

local function ensureSchema()
    MySQL.query.await(CREATE_MODELS_TABLE)

    if not shouldEnsureUtf8mb4() then
        return
    end

    local tableMetadata = MySQL.single.await([[
        SELECT TABLE_COLLATION
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = ?
        LIMIT 1
    ]], { MODELS_TABLE_NAME })

    local tableCollation = tostring(getSchemaValue(tableMetadata, 'TABLE_COLLATION', 'table_collation') or '')
    if not tableCollation:find('utf8mb4_', 1, true) then
        MySQL.query.await(([[
            ALTER TABLE %s
            CONVERT TO CHARACTER SET utf8mb4
            COLLATE %s
        ]]):format(MODELS_TABLE_NAME, MODELS_TABLE_COLLATION))
    end
end

function Models.ensureReady()
    if Models._ready then
        return true
    end

    ensureSchema()

    for modelKey, definition in pairs(Config.POSModels or {}) do
        local label = Utils.trim(definition.label) or modelKey
        local modelName = Utils.trim(definition.model)

        if not Utils.isBlank(modelKey) and not Utils.isBlank(modelName) then
            MySQL.insert.await([[
                INSERT INTO vancepay_terminal_models (
                    model_key,
                    label,
                    model_name,
                    status,
                    is_system
                ) VALUES (?, ?, ?, 'active', 1)
                ON DUPLICATE KEY UPDATE
                    is_system = VALUES(is_system)
            ]], {
                modelKey,
                label,
                modelName,
            })
        end
    end

    Models._ready = true
    return true
end

function Models.fetchByKey(modelKey)
    Models.ensureReady()

    if Utils.isBlank(modelKey) then
        return nil
    end

    local row = MySQL.single.await(MODEL_SELECT .. ' WHERE model_key = ? LIMIT 1', { modelKey })
    return normalizeModel(row)
end

function Models.fetchActiveByKey(modelKey)
    Models.ensureReady()

    if Utils.isBlank(modelKey) then
        return nil
    end

    local row = MySQL.single.await(MODEL_SELECT .. ' WHERE model_key = ? AND status = \'active\' LIMIT 1', { modelKey })
    return normalizeModel(row)
end

function Models.list(filters)
    Models.ensureReady()

    filters = filters or {}
    local query = MODEL_SELECT
    local params = {}
    local conditions = { '1=1' }

    if filters.status and filters.status ~= 'all' then
        conditions[#conditions + 1] = 'status = ?'
        params[#params + 1] = filters.status
    end

    query = query .. ' WHERE ' .. table.concat(conditions, ' AND ') .. [[
        ORDER BY
            FIELD(status, 'active', 'archived'),
            is_system DESC,
            label ASC,
            model_key ASC
    ]]

    local rows = MySQL.query.await(query, params) or {}

    for index = 1, #rows do
        rows[index] = normalizeModel(rows[index])
    end

    return rows
end

local function canManageModels(source)
    return VancePay.Permissions.isAdmin(source)
end

local function ensureArchiveAllowed(model)
    if not model then
        return false, 'POS 型号不存在'
    end

    if model.model_key == Config.DefaultTerminalModelKey then
        return false, '默认 POS 型号不能归档'
    end

    local activeTerminal = MySQL.single.await([[
        SELECT id
        FROM vancepay_terminals
        WHERE type = 'fixed'
            AND model_key = ?
            AND status <> 'archived'
        LIMIT 1
    ]], { model.model_key })

    if activeTerminal then
        return false, '仍有固定 POS 在使用该型号，不能归档'
    end

    return true
end

local function refreshTerminalWorldIfNeeded(existing, updated)
    if not VancePay.Terminals or not VancePay.Terminals.refreshFixedTerminalCache then
        return
    end

    if not existing then
        return
    end

    if existing.model_name ~= updated.model_name
        or existing.label ~= updated.label
        or existing.status ~= updated.status then
        VancePay.Terminals.refreshFixedTerminalCache(true)
    end
end

function Models.save(source, payload)
    if not canManageModels(source) then
        return VancePay.Server.fail('只有管理员可以管理 POS 型号库', 'forbidden')
    end

    Models.ensureReady()

    payload = payload or {}
    local modelKey = Utils.trim(payload.model_key or payload.key)
    local label = Utils.trim(payload.label)
    local modelName = Utils.trim(payload.model_name or payload.model)
    local status = Utils.trim(payload.status or 'active')

    if Utils.isBlank(modelKey) or Utils.isBlank(label) or Utils.isBlank(modelName) then
        return VancePay.Server.fail('型号 key、名称和模型名不能为空', 'invalid_payload')
    end

    if #modelKey > 50 or not modelKey:match('^[%w_%-]+$') then
        return VancePay.Server.fail('型号 key 只能包含字母、数字、下划线和中划线', 'invalid_model_key')
    end

    if #label > 100 or #modelName > 100 then
        return VancePay.Server.fail('型号名称或模型名过长', 'invalid_payload')
    end

    if not isValidStatus(status) then
        return VancePay.Server.fail('型号状态无效', 'invalid_status')
    end

    local existing = Models.fetchByKey(modelKey)
    if status == 'archived' then
        local allowed, reason = ensureArchiveAllowed(existing or { model_key = modelKey })
        if not allowed then
            return VancePay.Server.fail(reason, 'archive_not_allowed')
        end
    end

    if existing then
        local updated = MySQL.update.await([[
            UPDATE vancepay_terminal_models
            SET label = ?,
                model_name = ?,
                status = ?,
                archived_at = CASE WHEN ? = 'archived' THEN CURRENT_TIMESTAMP ELSE NULL END
            WHERE model_key = ?
        ]], {
            label,
            modelName,
            status,
            status,
            modelKey,
        })

        if not updated or updated < 1 then
            return VancePay.Server.fail('POS 型号更新失败', 'db_error')
        end
    else
        local inserted = MySQL.insert.await([[
            INSERT INTO vancepay_terminal_models (
                model_key,
                label,
                model_name,
                status,
                is_system
            ) VALUES (?, ?, ?, ?, 0)
        ]], {
            modelKey,
            label,
            modelName,
            status,
        })

        if not inserted then
            return VancePay.Server.fail('POS 型号创建失败，key 可能重复', 'db_error')
        end
    end

    local updatedModel = Models.fetchByKey(modelKey)
    local actorCitizenId = VancePay.Permissions.getCitizenId(source)

    if actorCitizenId then
        VancePay.Audit.log(actorCitizenId, existing and 'update_terminal_model' or 'create_terminal_model', 'terminal_model', modelKey, {
            detail = {
                model_key = modelKey,
                label = label,
                model_name = modelName,
                status = status,
                is_system = updatedModel and updatedModel.is_system or 0,
            }
        })
    end

    refreshTerminalWorldIfNeeded(existing, updatedModel)

    return VancePay.Server.ok(updatedModel, existing and 'POS 型号已更新' or 'POS 型号已创建')
end

function Models.archive(source, payload)
    if not canManageModels(source) then
        return VancePay.Server.fail('只有管理员可以管理 POS 型号库', 'forbidden')
    end

    local modelKey = type(payload) == 'table'
        and Utils.trim(payload.model_key or payload.key)
        or Utils.trim(payload)
    local model = Models.fetchByKey(modelKey)
    local allowed, reason = ensureArchiveAllowed(model)
    if not allowed then
        return VancePay.Server.fail(reason, 'archive_not_allowed')
    end

    local updated = MySQL.update.await([[
        UPDATE vancepay_terminal_models
        SET status = 'archived',
            archived_at = CURRENT_TIMESTAMP
        WHERE model_key = ?
            AND status <> 'archived'
    ]], { modelKey })

    if not updated or updated < 1 then
        return VancePay.Server.fail('POS 型号已归档或无法归档', 'no_change')
    end

    local actorCitizenId = VancePay.Permissions.getCitizenId(source)
    if actorCitizenId then
        VancePay.Audit.log(actorCitizenId, 'archive_terminal_model', 'terminal_model', modelKey, {
            detail = {
                model_key = modelKey,
                label = model.label,
            }
        })
    end

    return VancePay.Server.ok(Models.fetchByKey(modelKey), 'POS 型号已归档')
end

lib.callback.register('vancepay:server:getTerminalModels', function(source, filters)
    if not canManageModels(source) then
        return VancePay.Server.fail('只有管理员可以查看 POS 型号库', 'forbidden')
    end

    return VancePay.Server.ok(Models.list(filters or {}))
end)

lib.callback.register('vancepay:server:saveTerminalModel', function(source, payload)
    return Models.save(source, payload or {})
end)

lib.callback.register('vancepay:server:archiveTerminalModel', function(source, payload)
    return Models.archive(source, payload)
end)
