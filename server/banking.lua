VancePay.Banking = VancePay.Banking or {}

local Banking = VancePay.Banking

local function getBankingConfig()
    return Config.Banking or {}
end

local function getAdapterName()
    local adapter = Utils.trim(getBankingConfig().adapter)
    if Utils.isBlank(adapter) then
        return 'qbx_core'
    end

    return string.lower(adapter)
end

local function getQbxResourceName()
    local resourceName = Utils.trim(getBankingConfig().qbxResource)
    if Utils.isBlank(resourceName) then
        resourceName = 'qbx_core'
    end

    return resourceName
end

local function getPBankingResourceName()
    local resourceName = Utils.trim(getBankingConfig().pBankingResource)
    if Utils.isBlank(resourceName) then
        resourceName = 'p_banking'
    end

    return resourceName
end

local function callExportMethod(resourceName, method, ...)
    if Utils.isBlank(resourceName) or Utils.isBlank(method) then
        return false, nil
    end

    if GetResourceState(resourceName) ~= 'started' then
        Utils.debug('Banking resource not started', resourceName, method)
        return false, nil
    end

    local api = exports[resourceName]
    if not api or type(api[method]) ~= 'function' then
        Utils.debug('Banking export missing', resourceName, method)
        return false, nil
    end

    local ok, result = pcall(api[method], api, ...)
    if not ok then
        Utils.debug('Banking export failed', resourceName, method, result)
        return false, nil
    end

    return true, result
end

local function normalizeIdentifier(identifier)
    if type(identifier) == 'table' then
        identifier = identifier.account_identifier
            or identifier.identifier
            or identifier.citizenid
            or identifier.job
            or identifier.name
            or identifier.source
    end

    if type(identifier) == 'string' then
        identifier = Utils.trim(identifier)
    end

    return identifier
end

function Banking.getAdapterName()
    return getAdapterName()
end

function Banking.supportsDirectAccountSettlement()
    return getAdapterName() == 'p_banking'
end

function Banking.getBalance(identifier)
    local normalized = normalizeIdentifier(identifier)
    if not normalized then
        return 0
    end

    local amount = 0
    local adapter = getAdapterName()

    if adapter == 'p_banking' then
        local ok, result = callExportMethod(getPBankingResourceName(), 'getAccountMoney', normalized)
        amount = ok and result or 0
    else
        local ok, result = callExportMethod(getQbxResourceName(), 'GetMoney', normalized, getBankingConfig().moneyType)
        amount = ok and result or 0
    end

    return tonumber(amount) or 0
end

function Banking.hasFunds(identifier, amount)
    return Banking.getBalance(identifier) >= Utils.roundCurrency(amount)
end

function Banking.withdraw(identifier, amount, reason)
    local normalized = normalizeIdentifier(identifier)
    if not normalized then
        return false
    end

    amount = Utils.roundCurrency(amount)

    if getAdapterName() == 'p_banking' then
        local ok, result = callExportMethod(getPBankingResourceName(), 'removeAccountMoney', normalized, amount)
        return ok and result == true
    end

    local ok, result = callExportMethod(
        getQbxResourceName(),
        'RemoveMoney',
        normalized,
        getBankingConfig().moneyType,
        amount,
        reason or 'vancepay:payment'
    )

    return ok and result == true
end

function Banking.deposit(identifier, amount, reason)
    local normalized = normalizeIdentifier(identifier)
    if not normalized then
        return false
    end

    amount = Utils.roundCurrency(amount)

    if getAdapterName() == 'p_banking' then
        local ok, result = callExportMethod(getPBankingResourceName(), 'addAccountMoney', normalized, amount)
        return ok and result == true
    end

    local ok, result = callExportMethod(
        getQbxResourceName(),
        'AddMoney',
        normalized,
        getBankingConfig().moneyType,
        amount,
        reason or 'vancepay:refund'
    )

    return ok and result == true
end

function Banking.hasCard(source)
    local count = exports.ox_inventory:Search(source, 'count', Config.BankCardItem)
    return (tonumber(count) or 0) > 0
end

function Banking.getCardSlots(source)
    return exports.ox_inventory:Search(source, 'slots', Config.BankCardItem) or {}
end
