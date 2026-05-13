local osLib = os

local function safeUnixTime(timestampTable)
    if not osLib or type(osLib.time) ~= 'function' then
        return nil
    end

    local ok, value = pcall(osLib.time, timestampTable)
    if ok and type(value) == 'number' then
        return value
    end

    return nil
end

local function getSeed()
    local unixTime = safeUnixTime()
    if unixTime then
        return unixTime
    end

    local ok, gameTimer = pcall(GetGameTimer)
    if ok and type(gameTimer) == 'number' then
        return math.floor(gameTimer)
    end

    return 0
end

local seed = getSeed()
if not VancePay.__randomSeeded then
    math.randomseed(seed)
    VancePay.__randomSeeded = true
end

VancePay.Utils = VancePay.Utils or {}

local Utils = VancePay.Utils
_G.Utils = Utils

function Utils.debug(...)
    if not Config.Debug then
        return
    end

    local parts = { '[VancePay]' }
    for index = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(index, ...))
    end

    print(table.concat(parts, ' '))
end

function Utils.trim(value)
    if type(value) ~= 'string' then
        return value
    end

    return value:match('^%s*(.-)%s*$')
end

function Utils.isBlank(value)
    return value == nil or Utils.trim(value) == ''
end

function Utils.ensureNumber(value, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback or 0
    end

    return number
end

function Utils.roundCurrency(value)
    local number = Utils.ensureNumber(value, 0)
    return math.floor((number + 0.00001) * 100 + 0.5) / 100
end

function Utils.clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

function Utils.getPositiveLimit(value)
    local limit = tonumber(value)
    if not limit or limit <= 0 then
        return nil
    end

    return Utils.roundCurrency(limit)
end

function Utils.formatCurrency(value)
    return string.format('%s%.2f', Config.Currency or '$', Utils.roundCurrency(value))
end

function Utils.truncateUtf8(value, maxLength)
    if type(value) ~= 'string' or not maxLength or maxLength < 1 then
        return value
    end

    local ok, offset = pcall(utf8.offset, value, maxLength + 1)
    if not ok or not offset then
        return value
    end

    return value:sub(1, offset - 1)
end

function Utils.deepCopy(value)
    if type(value) ~= 'table' then
        return value
    end

    local copy = {}
    for key, innerValue in pairs(value) do
        copy[key] = Utils.deepCopy(innerValue)
    end

    return copy
end

function Utils.isInteractionOnlyTerminalModel(modelKey, modelName)
    modelKey = Utils.trim(modelKey)
    modelName = Utils.trim(modelName)

    local modelDefinition = modelKey and Config.POSModels and Config.POSModels[modelKey] or nil
    if type(modelDefinition) == 'table' and Utils.parseBool(modelDefinition.interaction_only) then
        return true
    end

    local interactionOnlyModelKey = Utils.trim(Config.InteractionOnlyTerminalModelKey or 'interaction_only')
    if not Utils.isBlank(interactionOnlyModelKey) and modelKey == interactionOnlyModelKey then
        return true
    end

    local interactionOnlyModelName = Utils.trim(Config.InteractionOnlyTerminalModelName or 'interaction_only')
    return not Utils.isBlank(interactionOnlyModelName) and modelName == interactionOnlyModelName
end

function Utils.getTerminalModelDisplayName(modelName, modelKey)
    if Utils.isInteractionOnlyTerminalModel(modelKey, modelName) then
        return '无实体模型'
    end

    return Utils.trim(modelName)
end

function Utils.tableContains(list, needle)
    if type(list) ~= 'table' then
        return false
    end

    for _, value in ipairs(list) do
        if value == needle then
            return true
        end
    end

    return false
end

function Utils.generateCode(prefix, length)
    local charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local chars = {}

    for index = 1, (length or 8) do
        local randomIndex = math.random(1, #charset)
        chars[index] = charset:sub(randomIndex, randomIndex)
    end

    if prefix and prefix ~= '' then
        return string.upper(prefix) .. table.concat(chars)
    end

    return table.concat(chars)
end

function Utils.parseBool(value)
    if value == true or value == 1 or value == '1' or value == 'true' then
        return true
    end

    return false
end

function Utils.decodeCoords(raw)
    if raw == nil then
        return nil
    end

    if type(raw) == 'table' then
        return {
            x = tonumber(raw.x) or 0.0,
            y = tonumber(raw.y) or 0.0,
            z = tonumber(raw.z) or 0.0
        }
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    return {
        x = tonumber(decoded.x) or 0.0,
        y = tonumber(decoded.y) or 0.0,
        z = tonumber(decoded.z) or 0.0
    }
end

function Utils.encodeCoords(coords)
    if type(coords) ~= 'table' then
        return nil
    end

    return json.encode({
        x = tonumber(coords.x) or 0.0,
        y = tonumber(coords.y) or 0.0,
        z = tonumber(coords.z) or 0.0
    })
end

function Utils.sanitizeAmountInput(payload)
    local subtotal = Utils.roundCurrency(Utils.ensureNumber(payload.subtotal_amount or payload.subtotal, 0))
    local discountRate = Utils.roundCurrency(Utils.ensureNumber(payload.discount_rate or payload.discountRate, 0))
    local tipAmount = Utils.roundCurrency(Utils.ensureNumber(payload.tip_amount or payload.tipAmount, 0))
    local minAmount = Utils.roundCurrency(Utils.ensureNumber(Config.MinAmount, 1))
    local maxAmount = Utils.getPositiveLimit(Config.MaxAmount)
    local maxDiscount = Utils.roundCurrency(Utils.ensureNumber(Config.MaxDiscount, 0))
    local maxTip = Utils.getPositiveLimit(Config.MaxTip)

    if subtotal < minAmount then
        return nil, nil, nil, ('订单金额至少为 %s'):format(Utils.formatCurrency(minAmount)), 'invalid_amount'
    end

    if maxAmount and subtotal > maxAmount then
        return nil, nil, nil, ('订单金额不能超过 %s'):format(Utils.formatCurrency(maxAmount)), 'amount_exceeded'
    end

    if discountRate < 0 or discountRate > maxDiscount then
        return nil, nil, nil, ('折扣必须在 0 到 %.2f%% 之间'):format(maxDiscount), 'invalid_discount'
    end

    if tipAmount < 0 then
        return nil, nil, nil, '小费不能为负数', 'invalid_tip'
    end

    if maxTip and tipAmount > maxTip then
        return nil, nil, nil, ('小费不能超过 %s'):format(Utils.formatCurrency(maxTip)), 'tip_exceeded'
    end

    return subtotal, discountRate, tipAmount
end

function Utils.sanitizeItemDescription(value)
    if value == nil then
        return nil
    end

    value = tostring(value)
    value = value:gsub('[\r\n]+', ' ')
    value = value:gsub('%s+', ' ')
    value = Utils.trim(value)

    if Utils.isBlank(value) then
        return nil
    end

    value = Utils.truncateUtf8(value, tonumber(Config.MaxItemDescriptionLength) or 120)
    value = Utils.trim(value)

    if Utils.isBlank(value) then
        return nil
    end

    return value
end

function Utils.formatQuantity(value)
    local number = tonumber(value) or 0
    local text = string.format('%.3f', number)
    text = text:gsub('%.?0+$', '')
    return text
end

function Utils.getUnixTime()
    return safeUnixTime()
end

function Utils.sanitizeItemLines(value)
    if type(value) ~= 'table' then
        return {}, 0
    end

    local maxLines = tonumber(Config.MaxItemLines) or 12
    local maxQuantity = tonumber(Config.MaxItemLineQuantity) or 9999
    local maxNameLength = tonumber(Config.MaxItemLineNameLength) or 80
    local maxAmount = Utils.getPositiveLimit(Config.MaxAmount)
    local lines = {}
    local subtotal = 0

    for index = 1, math.min(#value, maxLines) do
        local rawLine = value[index]
        if type(rawLine) == 'table' then
            local name = Utils.sanitizeItemDescription(rawLine.name or rawLine.label or rawLine.description)
            if name then
                name = Utils.truncateUtf8(name, maxNameLength)
                name = Utils.trim(name)
            end

            local quantityRaw = rawLine.quantity
            if quantityRaw == nil then
                quantityRaw = rawLine.qty
            end
            if quantityRaw == nil then
                quantityRaw = rawLine.count
            end

            local unitPriceRaw = rawLine.unit_price
            if unitPriceRaw == nil then
                unitPriceRaw = rawLine.unitPrice
            end
            if unitPriceRaw == nil then
                unitPriceRaw = rawLine.price
            end
            if unitPriceRaw == nil then
                unitPriceRaw = rawLine.amount
            end

            local quantity = Utils.ensureNumber(quantityRaw, 0)
            quantity = math.floor((quantity + 0.0000001) * 1000 + 0.5) / 1000
            if quantity > maxQuantity then
                return {}, 0, ('商品数量不能超过 %s'):format(Utils.formatQuantity(maxQuantity)), 'item_quantity_exceeded'
            end
            quantity = Utils.clamp(quantity, 0, maxQuantity)

            local unitPrice = Utils.roundCurrency(Utils.ensureNumber(unitPriceRaw, 0))
            if maxAmount and unitPrice > maxAmount then
                return {}, 0, ('商品单价不能超过 %s'):format(Utils.formatCurrency(maxAmount)), 'item_price_exceeded'
            end
            unitPrice = math.max(0, unitPrice)

            if not Utils.isBlank(name)
                and quantity > 0
                and quantityRaw ~= nil and not Utils.isBlank(quantityRaw)
                and unitPriceRaw ~= nil and not Utils.isBlank(unitPriceRaw) then
                local lineTotal = Utils.roundCurrency(quantity * unitPrice)
                lines[#lines + 1] = {
                    name = name,
                    quantity = quantity,
                    unit_price = unitPrice,
                    line_total = lineTotal,
                }
                subtotal = Utils.roundCurrency(subtotal + lineTotal)
            end
        end
    end

    return lines, subtotal
end

function Utils.buildItemSummary(itemDescription, itemLines)
    itemDescription = Utils.sanitizeItemDescription(itemDescription)
    if not Utils.isBlank(itemDescription) then
        return itemDescription
    end

    if type(itemLines) ~= 'table' or #itemLines == 0 then
        return nil
    end

    local parts = {}
    local limit = math.min(#itemLines, 2)

    for index = 1, limit do
        local line = itemLines[index]
        parts[#parts + 1] = ('%s x%s'):format(
            Utils.truncateUtf8(tostring(line.name or ''), 28),
            Utils.formatQuantity(line.quantity or 0)
        )
    end

    if #itemLines > limit then
        parts[#parts + 1] = ('等 %d 项'):format(#itemLines)
    end

    return Utils.sanitizeItemDescription(table.concat(parts, ' · '))
end

function Utils.computeAmounts(subtotal, discountRate, tipAmount, taxRate)
    subtotal = Utils.roundCurrency(subtotal)
    discountRate = Utils.roundCurrency(discountRate)
    tipAmount = Utils.roundCurrency(tipAmount)
    taxRate = Utils.roundCurrency(taxRate or 0)

    local discountAmount = Utils.roundCurrency(subtotal * (discountRate / 100))
    local taxableAmount = Utils.roundCurrency(math.max(0, subtotal - discountAmount))
    local taxAmount = Utils.roundCurrency(taxableAmount * (taxRate / 100))
    local baseAmount = Utils.roundCurrency(taxableAmount + tipAmount)
    local feeAmount = 0.0
    local finalAmount = Utils.roundCurrency(baseAmount + taxAmount)
    local netAmount = baseAmount

    if Config.EnableFee then
        if Config.FeePaidBy == 'store' then
            feeAmount = Utils.roundCurrency(baseAmount * Config.FeeRate)
            finalAmount = Utils.roundCurrency(baseAmount + taxAmount)
            netAmount = Utils.roundCurrency(baseAmount - feeAmount)
        else
            netAmount = baseAmount
            feeAmount = Utils.roundCurrency(netAmount * Config.FeeRate)
            finalAmount = Utils.roundCurrency(netAmount + taxAmount + feeAmount)
        end
    end

    return {
        subtotal_amount = subtotal,
        discount_rate = discountRate,
        discount_amount = discountAmount,
        tip_amount = tipAmount,
        tax_rate = taxRate,
        tax_amount = taxAmount,
        fee_amount = feeAmount,
        final_amount = finalAmount,
        net_amount = netAmount,
    }
end

function Utils.computeCommissionAmount(netAmount, commissionRate)
    netAmount = Utils.roundCurrency(netAmount or 0)
    commissionRate = Utils.roundCurrency(commissionRate or 0)

    if netAmount <= 0 or commissionRate <= 0 then
        return 0
    end

    return Utils.roundCurrency(math.min(netAmount, netAmount * (commissionRate / 100)))
end

function Utils.getPageOffset(page, perPage)
    local safePage = math.max(tonumber(page) or 1, 1)
    local safePerPage = math.max(tonumber(perPage) or Config.TransPerPage, 1)
    return safePage, safePerPage, (safePage - 1) * safePerPage
end

function Utils.parseSqlDateTime(value)
    if type(value) == 'number' then
        if value > 1000000000000 then
            return math.floor(value / 1000)
        end

        return math.floor(value)
    end

    if type(value) == 'table' then
        local year = tonumber(value.year)
        local month = tonumber(value.month)
        local day = tonumber(value.day)

        if not year or not month or not day then
            return nil
        end

        return safeUnixTime({
            year = year,
            month = month,
            day = day,
            hour = tonumber(value.hour) or 0,
            min = tonumber(value.min or value.minute) or 0,
            sec = tonumber(value.sec or value.second) or 0,
        })
    end

    if type(value) ~= 'string' then
        return nil
    end

    local numericValue = tonumber(value)
    if numericValue and value:match('^%s*%d+%s*$') then
        if numericValue > 1000000000000 then
            return math.floor(numericValue / 1000)
        end

        return math.floor(numericValue)
    end

    local year, month, day, hour, minute, second = value:match('^(%d+)%-(%d+)%-(%d+)[ T](%d+):(%d+):(%d+)')
    if not year then
        return nil
    end

    return safeUnixTime({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second),
    })
end

function Utils.normalizeDbRow(row)
    if type(row) ~= 'table' then
        return row
    end

    local normalized = Utils.deepCopy(row)

    if normalized.coords then
        normalized.coords = Utils.decodeCoords(normalized.coords)
    end

    if normalized.detail and type(normalized.detail) == 'string' then
        local ok, decoded = pcall(json.decode, normalized.detail)
        if ok then
            normalized.detail = decoded
        end
    end

    return normalized
end
