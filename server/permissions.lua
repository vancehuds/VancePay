VancePay.Permissions = VancePay.Permissions or {}

local Permissions = VancePay.Permissions

local function hasQbxPermission(source, permission)
    if Utils.isBlank(permission) then
        return false
    end

    local ok, result = pcall(function()
        return exports.qbx_core:HasPermission(source, permission)
    end)

    return ok and result == true
end

local function parseJobData(rawJob)
    if type(rawJob) == 'string' then
        local ok, decoded = pcall(json.decode, rawJob)
        if ok then
            rawJob = decoded
        end
    end

    if type(rawJob) ~= 'table' then
        return nil
    end

    local grade = type(rawJob.grade) == 'table' and rawJob.grade or {}
    local gradeLevel = grade.level or grade.grade or rawJob.grade_level or rawJob.gradeLevel
    if type(rawJob.grade) == 'number' or type(rawJob.grade) == 'string' then
        gradeLevel = rawJob.grade
    end

    return {
        name = Utils.trim(rawJob.name or rawJob.id or rawJob.key),
        label = Utils.trim(rawJob.label or rawJob.name),
        grade_level = tonumber(gradeLevel) or 0,
        grade_name = Utils.trim(grade.name or grade.label),
        is_boss = Utils.parseBool(rawJob.isboss)
            or Utils.parseBool(rawJob.isBoss)
            or Utils.parseBool(rawJob.boss)
            or Utils.parseBool(grade.isboss)
            or Utils.parseBool(grade.isBoss)
            or Utils.parseBool(grade.boss),
        onduty = rawJob.onduty == nil and rawJob.onDuty or rawJob.onduty,
        raw = rawJob,
    }
end

function Permissions.getCitizenId(source)
    local record = VancePay.Server.getPlayerRecord(source)
    return record and record.citizenid or nil
end

function Permissions.getJob(source)
    local record = VancePay.Server.getPlayerRecord(source)
    return parseJobData(record and record.data and record.data.job)
end

function Permissions.isJobBoss(source, jobName)
    local job = Permissions.getJob(source)
    if not job or Utils.isBlank(job.name) then
        return false
    end

    if not Utils.isBlank(jobName) and tostring(job.name):lower() ~= tostring(jobName):lower() then
        return false
    end

    return job.is_boss == true
end

function Permissions.isAdmin(source)
    local adminGroups = Config.AdminGroups

    if type(adminGroups) == 'string' then
        adminGroups = { adminGroups }
    end

    if type(adminGroups) ~= 'table' then
        return false
    end

    for index = 1, #adminGroups do
        if hasQbxPermission(source, adminGroups[index]) then
            return true
        end
    end

    return false
end

function Permissions.getEmployee(storeId, citizenid)
    if not storeId or Utils.isBlank(citizenid) then
        return nil
    end

    local row = MySQL.single.await([[
        SELECT *
        FROM vancepay_employees
        WHERE store_id = ? AND citizenid = ?
        LIMIT 1
    ]], { tonumber(storeId), citizenid })

    return row and Utils.normalizeDbRow(row) or nil
end

function Permissions.getStoreAccess(source, storeId)
    storeId = tonumber(storeId)
    if not storeId then
        return nil
    end

    if Permissions.isAdmin(source) then
        return {
            source = source,
            citizenid = Permissions.getCitizenId(source),
            store_id = storeId,
            role = VancePay.EmployeeRoles.owner,
            is_admin = true,
            is_owner = true,
            can_collect = true,
            can_manage = true,
            can_refund = true,
            can_discount = true,
        }
    end

    local citizenid = Permissions.getCitizenId(source)
    local employee = Permissions.getEmployee(storeId, citizenid)
    if not employee then
        return nil
    end

    local isOwner = employee.role == VancePay.EmployeeRoles.owner
    local isManager = employee.role == VancePay.EmployeeRoles.manager

    return {
        source = source,
        citizenid = citizenid,
        store_id = storeId,
        role = employee.role,
        employee = employee,
        is_admin = false,
        is_owner = isOwner,
        can_collect = true,
        can_manage = isOwner or isManager,
        can_refund = isOwner or isManager or Utils.parseBool(employee.can_refund),
        can_discount = isOwner or isManager or Utils.parseBool(employee.can_discount),
    }
end

function Permissions.checkAccess(source, storeId, permission)
    local access = Permissions.getStoreAccess(source, storeId)
    if not access then
        return false, '你没有该店铺权限'
    end

    if permission == 'collect' and access.can_collect then
        return true, access
    end

    if permission == 'manage' and access.can_manage then
        return true, access
    end

    if permission == 'refund' and access.can_refund then
        return true, access
    end

    if permission == 'discount' and access.can_discount then
        return true, access
    end

    if permission == 'admin' and access.is_admin then
        return true, access
    end

    return false, '权限不足'
end
