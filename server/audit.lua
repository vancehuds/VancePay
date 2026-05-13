VancePay.Audit = VancePay.Audit or {}

local Audit = VancePay.Audit

function Audit.log(actorCitizenId, action, targetType, targetId, options)
    if Utils.isBlank(actorCitizenId) or Utils.isBlank(action) or Utils.isBlank(targetType) then
        return false
    end

    options = options or {}

    local insertedId = MySQL.insert.await([[
        INSERT INTO vancepay_audit_logs (
            actor_citizenid,
            store_id,
            terminal_id,
            action,
            target_type,
            target_id,
            detail
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        actorCitizenId,
        options.store_id,
        options.terminal_id,
        action,
        targetType,
        targetId and tostring(targetId) or nil,
        options.detail and json.encode(options.detail) or nil,
    })

    if insertedId and VancePay.Kook and VancePay.Kook.logAudit then
        options.audit_log_id = insertedId
        VancePay.Kook.logAudit(actorCitizenId, action, targetType, targetId, options)
    end

    if insertedId and VancePay.FiveMLog and VancePay.FiveMLog.logAudit then
        options.audit_log_id = insertedId
        VancePay.FiveMLog.logAudit(actorCitizenId, action, targetType, targetId, options)
    end

    return insertedId ~= nil
end

function Audit.list(filters)
    filters = filters or {}
    local page, perPage, offset = Utils.getPageOffset(filters.page, filters.per_page or Config.TransPerPage)
    local conditions = { '1=1' }
    local params = {}

    if filters.store_id then
        conditions[#conditions + 1] = 'store_id = ?'
        params[#params + 1] = tonumber(filters.store_id)
    end

    if filters.actor_citizenid then
        conditions[#conditions + 1] = 'actor_citizenid = ?'
        params[#params + 1] = filters.actor_citizenid
    end

    local query = ([[
        SELECT *
        FROM vancepay_audit_logs
        WHERE %s
        ORDER BY id DESC
        LIMIT ? OFFSET ?
    ]]):format(table.concat(conditions, ' AND '))

    params[#params + 1] = perPage
    params[#params + 1] = offset

    local rows = MySQL.query.await(query, params) or {}

    for index = 1, #rows do
        rows[index] = Utils.normalizeDbRow(rows[index])
    end

    return {
        items = rows,
        page = page,
        per_page = perPage,
    }
end

lib.callback.register('vancepay:server:getAuditLogs', function(source, filters)
    filters = filters or {}
    local isAdmin = VancePay.Permissions.isAdmin(source)
    local storeId = tonumber(filters.store_id)

    if not isAdmin then
        if not storeId then
            return VancePay.Server.fail('店铺审计查询缺少 store_id', 'missing_store_id')
        end

        local allowed = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            return VancePay.Server.fail('你没有查看该店铺审计的权限', 'forbidden')
        end
    end

    return VancePay.Server.ok(Audit.list(filters))
end)
