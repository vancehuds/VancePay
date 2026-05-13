VancePay.Reports = VancePay.Reports or {}

local Reports = VancePay.Reports

local function parseDate(value)
    if type(value) ~= 'string' then
        return nil
    end

    local year, month, day = value:match('^(%d+)%-(%d+)%-(%d+)$')
    if not year then
        return nil
    end

    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 0,
        min = 0,
        sec = 0,
    })
end

local function formatDate(timestamp)
    return os.date('%Y-%m-%d', timestamp)
end

local function cleanString(value)
    value = Utils.trim(value)
    if Utils.isBlank(value) then
        return nil
    end

    return value
end

local function normalizeReportRange(filters)
    filters = filters or {}

    local today = os.time()
    local rangeDays = Utils.clamp(tonumber(filters.range_days or filters.days) or 7, 1, 90)
    local dateTo = cleanString(filters.date_to) or formatDate(today)
    local dateFrom = cleanString(filters.date_from)

    local dateToTs = parseDate(dateTo) or today
    local dateFromTs = parseDate(dateFrom)

    if not dateFromTs then
        dateFromTs = dateToTs - ((rangeDays - 1) * 86400)
        dateFrom = formatDate(dateFromTs)
    end

    if dateFromTs > dateToTs then
        dateFromTs, dateToTs = dateToTs, dateFromTs
        dateFrom, dateTo = dateTo, dateFrom
    end

    return {
        store_id = tonumber(filters.store_id),
        date_from = dateFrom,
        date_to = dateTo,
        date_from_ts = dateFromTs,
        date_to_ts = dateToTs,
        range_days = math.floor(((dateToTs - dateFromTs) / 86400) + 1),
    }
end

local function normalizeTransactionFilters(filters)
    filters = filters or {}

    return {
        store_id = tonumber(filters.store_id),
        date_from = cleanString(filters.date_from),
        date_to = cleanString(filters.date_to),
        method = cleanString(filters.method),
        type = cleanString(filters.type),
        status = cleanString(filters.status),
    }
end

local function appendStoreCondition(filters, conditions, params)
    if filters.store_id then
        conditions[#conditions + 1] = 'store_id = ?'
        params[#params + 1] = filters.store_id
    end
end

local function assertManageScope(source, storeId)
    if VancePay.Permissions.isAdmin(source) then
        return true
    end

    if not storeId then
        return false, '缺少店铺范围'
    end

    local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
    if not allowed then
        return false, reason
    end

    return true
end

local function escapeCsv(value)
    if value == nil then
        return ''
    end

    if type(value) == 'table' then
        value = json.encode(value)
    end

    value = tostring(value)
    if value:find('"') then
        value = value:gsub('"', '""')
    end

    if value:find('[,\r\n"]') then
        return ('"%s"'):format(value)
    end

    return value
end

local function buildCsv(columns, rows)
    local lines = {}
    local header = {}

    for index = 1, #columns do
        header[index] = escapeCsv(columns[index].header)
    end

    lines[1] = '\239\187\191' .. table.concat(header, ',')

    for rowIndex = 1, #rows do
        local row = rows[rowIndex]
        local values = {}

        for columnIndex = 1, #columns do
            local column = columns[columnIndex]
            local value = row[column.key]

            if type(column.transform) == 'function' then
                value = column.transform(value, row)
            end

            values[columnIndex] = escapeCsv(value)
        end

        lines[#lines + 1] = table.concat(values, ',')
    end

    return table.concat(lines, '\r\n')
end

local function buildTransactionConditions(filters)
    local conditions = { '1=1' }
    local params = {}

    appendStoreCondition(filters, conditions, params)

    if filters.date_from then
        conditions[#conditions + 1] = 'DATE(created_at) >= DATE(?)'
        params[#params + 1] = filters.date_from
    end

    if filters.date_to then
        conditions[#conditions + 1] = 'DATE(created_at) <= DATE(?)'
        params[#params + 1] = filters.date_to
    end

    if filters.method and filters.method ~= 'all' then
        conditions[#conditions + 1] = 'method = ?'
        params[#params + 1] = filters.method
    end

    if filters.type and filters.type ~= 'all' then
        conditions[#conditions + 1] = 'type = ?'
        params[#params + 1] = filters.type
    end

    if filters.status and filters.status ~= 'all' then
        conditions[#conditions + 1] = 'status = ?'
        params[#params + 1] = filters.status
    end

    return conditions, params
end

function Reports.getStoreOverview(storeId)
    storeId = tonumber(storeId)
    if not storeId then
        return nil
    end

    local store = VancePay.Stores.fetchById(storeId)
    if not store then
        return nil
    end

    local metrics = MySQL.single.await([[
        SELECT
            COALESCE(SUM(CASE
                WHEN type = 'payment' AND DATE(created_at) = UTC_DATE() THEN 1
                ELSE 0
            END), 0) AS today_transaction_count,
            COALESCE(SUM(CASE
                WHEN type = 'payment' AND DATE(created_at) = UTC_DATE() THEN net_amount
                WHEN type = 'refund' AND DATE(created_at) = UTC_DATE() THEN -net_amount
                ELSE 0
            END), 0) AS today_net_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' AND DATE(created_at) = UTC_DATE() THEN final_amount
                ELSE 0
            END), 0) AS today_gross_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' AND DATE(created_at) = UTC_DATE() THEN commission_amount
                ELSE 0
            END), 0) AS today_commission_amount,
            COALESCE(SUM(CASE
                WHEN type = 'refund' AND DATE(created_at) = UTC_DATE() THEN commission_amount
                ELSE 0
            END), 0) AS today_refunded_commission_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' AND DATE(created_at) = UTC_DATE() THEN commission_amount
                WHEN type = 'refund' AND DATE(created_at) = UTC_DATE() THEN -commission_amount
                ELSE 0
            END), 0) AS today_net_commission_amount
        FROM vancepay_transactions
        WHERE store_id = ?
    ]], { storeId }) or {}

    local pending = MySQL.single.await([[
        SELECT COUNT(*) AS pending_count
        FROM vancepay_payment_intents
        WHERE store_id = ?
            AND status IN ('awaiting_customer', 'awaiting_swipe')
    ]], { storeId }) or {}

    return {
        store_id = store.id,
        balance = Utils.roundCurrency(store.available_balance or store.balance),
        balance_label = store.balance_label or '余额',
        status = store.status,
        name = store.name,
        settlement_mode = store.settlement_mode,
        settlement_mode_label = store.settlement_mode_label,
        settlement_target_label = store.settlement_target_label,
        commission_rate = Utils.roundCurrency(store.commission_rate or 0),
        commission_enabled = store.commission_enabled == true,
        default_tax_rate = Utils.roundCurrency(store.default_tax_rate or 0),
        tax_rate = Utils.roundCurrency(store.tax_rate or 0),
        custom_tax_rate = Utils.roundCurrency(store.custom_tax_rate or store.tax_rate or 0),
        tax_custom_rate_enabled = store.tax_custom_rate_enabled == true,
        tax_exempt = store.tax_exempt == true,
        effective_tax_rate = Utils.roundCurrency(store.effective_tax_rate or 0),
        tax_enabled = store.tax_enabled == true,
        tax_target_label = store.tax_target_label,
        tax_settlement_mode = store.tax_settlement_mode,
        tax_settlement_account_identifier = store.tax_settlement_account_identifier,
        payout_available_balance = Utils.roundCurrency(store.payout_available_balance or 0),
        terminal_count = tonumber(store.terminal_count) or 0,
        employee_count = tonumber(store.employee_count) or 0,
        today_transaction_count = tonumber(metrics.today_transaction_count) or 0,
        today_net_amount = Utils.roundCurrency(metrics.today_net_amount or 0),
        today_gross_amount = Utils.roundCurrency(metrics.today_gross_amount or 0),
        today_commission_amount = Utils.roundCurrency(metrics.today_commission_amount or 0),
        today_refunded_commission_amount = Utils.roundCurrency(metrics.today_refunded_commission_amount or 0),
        today_net_commission_amount = Utils.roundCurrency(metrics.today_net_commission_amount or 0),
        pending_count = tonumber(pending.pending_count) or 0,
    }
end

function Reports.buildAdvancedReportData(filters)
    filters = normalizeReportRange(filters)
    local conditions, params = buildTransactionConditions(filters)
    local whereClause = table.concat(conditions, ' AND ')

    local summary = MySQL.single.await(([[
        SELECT
            COALESCE(SUM(CASE WHEN type = 'payment' THEN final_amount ELSE 0 END), 0) AS gross_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN final_amount ELSE 0 END), 0) AS refunded_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN net_amount
                WHEN type = 'refund' THEN -net_amount
                ELSE 0
            END), 0) AS net_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN 1 ELSE 0 END), 0) AS payment_count,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN 1 ELSE 0 END), 0) AS refund_count,
            COALESCE(AVG(CASE WHEN type = 'payment' THEN final_amount ELSE NULL END), 0) AS avg_ticket
        FROM vancepay_transactions
        WHERE %s
    ]]):format(whereClause), params) or {}

    local dailyRows = MySQL.query.await(([[
        SELECT
            DATE(created_at) AS report_date,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN final_amount ELSE 0 END), 0) AS gross_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN final_amount ELSE 0 END), 0) AS refunded_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN net_amount
                WHEN type = 'refund' THEN -net_amount
                ELSE 0
            END), 0) AS net_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN 1 ELSE 0 END), 0) AS payment_count,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN 1 ELSE 0 END), 0) AS refund_count
        FROM vancepay_transactions
        WHERE %s
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at) ASC
    ]]):format(whereClause), params) or {}

    local dailyMap = {}
    for index = 1, #dailyRows do
        local row = Utils.normalizeDbRow(dailyRows[index])
        dailyMap[tostring(row.report_date)] = {
            date = tostring(row.report_date),
            gross_amount = Utils.roundCurrency(row.gross_amount or 0),
            refunded_amount = Utils.roundCurrency(row.refunded_amount or 0),
            net_amount = Utils.roundCurrency(row.net_amount or 0),
            payment_count = tonumber(row.payment_count) or 0,
            refund_count = tonumber(row.refund_count) or 0,
        }
    end

    local daily = {}
    local dayCursor = filters.date_from_ts
    while dayCursor <= filters.date_to_ts do
        local dateKey = formatDate(dayCursor)
        local entry = dailyMap[dateKey] or {
            date = dateKey,
            gross_amount = 0,
            refunded_amount = 0,
            net_amount = 0,
            payment_count = 0,
            refund_count = 0,
        }

        entry.label = dateKey:sub(6)
        daily[#daily + 1] = entry
        dayCursor = dayCursor + 86400
    end

    local methodRows = MySQL.query.await(([[
        SELECT
            method,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN final_amount ELSE 0 END), 0) AS payment_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN final_amount ELSE 0 END), 0) AS refund_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN net_amount
                WHEN type = 'refund' THEN -net_amount
                ELSE 0
            END), 0) AS net_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN 1 ELSE 0 END), 0) AS payment_count,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN 1 ELSE 0 END), 0) AS refund_count
        FROM vancepay_transactions
        WHERE %s
        GROUP BY method
        ORDER BY method ASC
    ]]):format(whereClause), params) or {}

    local methodMap = {}
    for index = 1, #methodRows do
        local row = Utils.normalizeDbRow(methodRows[index])
        methodMap[row.method] = row
    end

    local methods = {}
    local grossAmount = Utils.roundCurrency(summary.gross_amount or 0)
    local orderedMethods = { 'phone', 'card' }
    for index = 1, #orderedMethods do
        local method = orderedMethods[index]
        local row = methodMap[method] or {}
        local paymentAmount = Utils.roundCurrency(row.payment_amount or 0)

        methods[#methods + 1] = {
            method = method,
            payment_amount = paymentAmount,
            refund_amount = Utils.roundCurrency(row.refund_amount or 0),
            net_amount = Utils.roundCurrency(row.net_amount or 0),
            payment_count = tonumber(row.payment_count) or 0,
            refund_count = tonumber(row.refund_count) or 0,
            share = grossAmount > 0 and math.floor(((paymentAmount / grossAmount) * 1000) + 0.5) / 10 or 0,
        }
    end

    local topStores = {}
    if not filters.store_id then
        local topConditions = { 'DATE(created_at) >= DATE(?)', 'DATE(created_at) <= DATE(?)' }
        local topParams = { filters.date_from, filters.date_to }

        local rows = MySQL.query.await(([[ 
            SELECT
                store_id,
                MAX(store_name_snapshot) AS store_name,
                COALESCE(SUM(CASE WHEN type = 'payment' THEN final_amount ELSE 0 END), 0) AS gross_amount,
                COALESCE(SUM(CASE
                    WHEN type = 'payment' THEN net_amount
                    WHEN type = 'refund' THEN -net_amount
                    ELSE 0
                END), 0) AS net_amount,
                COALESCE(SUM(CASE WHEN type = 'payment' THEN 1 ELSE 0 END), 0) AS payment_count
            FROM vancepay_transactions
            WHERE %s
            GROUP BY store_id
            ORDER BY net_amount DESC
            LIMIT 5
        ]]):format(table.concat(topConditions, ' AND ')), topParams) or {}

        for index = 1, #rows do
            local row = Utils.normalizeDbRow(rows[index])
            topStores[#topStores + 1] = {
                store_id = tonumber(row.store_id),
                store_name = row.store_name,
                gross_amount = Utils.roundCurrency(row.gross_amount or 0),
                net_amount = Utils.roundCurrency(row.net_amount or 0),
                payment_count = tonumber(row.payment_count) or 0,
            }
        end
    end

    return {
        filters = {
            store_id = filters.store_id,
            date_from = filters.date_from,
            date_to = filters.date_to,
            range_days = filters.range_days,
        },
        summary = {
            gross_amount = Utils.roundCurrency(summary.gross_amount or 0),
            refunded_amount = Utils.roundCurrency(summary.refunded_amount or 0),
            net_amount = Utils.roundCurrency(summary.net_amount or 0),
            payment_count = tonumber(summary.payment_count) or 0,
            refund_count = tonumber(summary.refund_count) or 0,
            avg_ticket = Utils.roundCurrency(summary.avg_ticket or 0),
        },
        daily = daily,
        methods = methods,
        top_stores = topStores,
    }
end

function Reports.buildTaxReportData(filters)
    filters = normalizeReportRange(filters)
    local conditions, params = buildTransactionConditions(filters)
    local whereClause = table.concat(conditions, ' AND ')

    local summary = MySQL.single.await(([[
        SELECT
            COALESCE(SUM(CASE WHEN type = 'payment' THEN tax_amount ELSE 0 END), 0) AS collected_tax_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN tax_amount ELSE 0 END), 0) AS refunded_tax_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN tax_amount
                WHEN type = 'refund' THEN -tax_amount
                ELSE 0
            END), 0) AS net_tax_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' AND tax_amount > 0 THEN 1 ELSE 0 END), 0) AS taxable_payment_count,
            COALESCE(SUM(CASE WHEN type = 'payment' AND tax_exempt = 1 THEN 1 ELSE 0 END), 0) AS exempt_payment_count,
            COALESCE(SUM(CASE WHEN type = 'refund' AND tax_amount > 0 THEN 1 ELSE 0 END), 0) AS tax_refund_count,
            COALESCE(AVG(CASE WHEN type = 'payment' AND tax_amount > 0 THEN tax_amount ELSE NULL END), 0) AS avg_tax_amount
        FROM vancepay_transactions
        WHERE %s
    ]]):format(whereClause), params) or {}

    local dailyRows = MySQL.query.await(([[
        SELECT
            DATE(created_at) AS report_date,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN tax_amount ELSE 0 END), 0) AS collected_tax_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN tax_amount ELSE 0 END), 0) AS refunded_tax_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN tax_amount
                WHEN type = 'refund' THEN -tax_amount
                ELSE 0
            END), 0) AS net_tax_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' AND tax_amount > 0 THEN 1 ELSE 0 END), 0) AS taxable_payment_count,
            COALESCE(SUM(CASE WHEN type = 'payment' AND tax_exempt = 1 THEN 1 ELSE 0 END), 0) AS exempt_payment_count
        FROM vancepay_transactions
        WHERE %s
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at) ASC
    ]]):format(whereClause), params) or {}

    local dailyMap = {}
    for index = 1, #dailyRows do
        local row = Utils.normalizeDbRow(dailyRows[index])
        dailyMap[tostring(row.report_date)] = {
            date = tostring(row.report_date),
            collected_tax_amount = Utils.roundCurrency(row.collected_tax_amount or 0),
            refunded_tax_amount = Utils.roundCurrency(row.refunded_tax_amount or 0),
            net_tax_amount = Utils.roundCurrency(row.net_tax_amount or 0),
            taxable_payment_count = tonumber(row.taxable_payment_count) or 0,
            exempt_payment_count = tonumber(row.exempt_payment_count) or 0,
        }
    end

    local daily = {}
    local dayCursor = filters.date_from_ts
    while dayCursor <= filters.date_to_ts do
        local dateKey = formatDate(dayCursor)
        local entry = dailyMap[dateKey] or {
            date = dateKey,
            collected_tax_amount = 0,
            refunded_tax_amount = 0,
            net_tax_amount = 0,
            taxable_payment_count = 0,
            exempt_payment_count = 0,
        }

        entry.label = dateKey:sub(6)
        daily[#daily + 1] = entry
        dayCursor = dayCursor + 86400
    end

    local methodRows = MySQL.query.await(([[
        SELECT
            method,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN tax_amount ELSE 0 END), 0) AS collected_tax_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN tax_amount ELSE 0 END), 0) AS refunded_tax_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN tax_amount
                WHEN type = 'refund' THEN -tax_amount
                ELSE 0
            END), 0) AS net_tax_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' AND tax_amount > 0 THEN 1 ELSE 0 END), 0) AS taxable_payment_count,
            COALESCE(SUM(CASE WHEN type = 'payment' AND tax_exempt = 1 THEN 1 ELSE 0 END), 0) AS exempt_payment_count
        FROM vancepay_transactions
        WHERE %s
        GROUP BY method
        ORDER BY method ASC
    ]]):format(whereClause), params) or {}

    local methodMap = {}
    for index = 1, #methodRows do
        local row = Utils.normalizeDbRow(methodRows[index])
        methodMap[row.method] = row
    end

    local methods = {}
    local totalCollectedTax = Utils.roundCurrency(summary.collected_tax_amount or 0)
    local orderedMethods = { 'phone', 'card' }
    for index = 1, #orderedMethods do
        local method = orderedMethods[index]
        local row = methodMap[method] or {}
        local collectedTaxAmount = Utils.roundCurrency(row.collected_tax_amount or 0)

        methods[#methods + 1] = {
            method = method,
            collected_tax_amount = collectedTaxAmount,
            refunded_tax_amount = Utils.roundCurrency(row.refunded_tax_amount or 0),
            net_tax_amount = Utils.roundCurrency(row.net_tax_amount or 0),
            taxable_payment_count = tonumber(row.taxable_payment_count) or 0,
            exempt_payment_count = tonumber(row.exempt_payment_count) or 0,
            share = totalCollectedTax > 0 and math.floor(((collectedTaxAmount / totalCollectedTax) * 1000) + 0.5) / 10 or 0,
        }
    end

    return {
        filters = {
            store_id = filters.store_id,
            date_from = filters.date_from,
            date_to = filters.date_to,
            range_days = filters.range_days,
        },
        summary = {
            collected_tax_amount = Utils.roundCurrency(summary.collected_tax_amount or 0),
            refunded_tax_amount = Utils.roundCurrency(summary.refunded_tax_amount or 0),
            net_tax_amount = Utils.roundCurrency(summary.net_tax_amount or 0),
            taxable_payment_count = tonumber(summary.taxable_payment_count) or 0,
            exempt_payment_count = tonumber(summary.exempt_payment_count) or 0,
            tax_refund_count = tonumber(summary.tax_refund_count) or 0,
            avg_tax_amount = Utils.roundCurrency(summary.avg_tax_amount or 0),
        },
        daily = daily,
        methods = methods,
    }
end

function Reports.buildCommissionReportData(filters)
    filters = normalizeReportRange(filters)
    local conditions, params = buildTransactionConditions(filters)
    local whereClause = table.concat(conditions, ' AND ')

    local summary = MySQL.single.await(([[
        SELECT
            COALESCE(SUM(CASE WHEN type = 'payment' THEN commission_amount ELSE 0 END), 0) AS generated_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN commission_amount ELSE 0 END), 0) AS refunded_commission_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN commission_amount
                WHEN type = 'refund' THEN -commission_amount
                ELSE 0
            END), 0) AS net_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' AND commission_amount > 0 THEN 1 ELSE 0 END), 0) AS commission_payment_count,
            COALESCE(SUM(CASE WHEN type = 'refund' AND commission_amount > 0 THEN 1 ELSE 0 END), 0) AS commission_refund_count,
            COALESCE(COUNT(DISTINCT CASE
                WHEN type = 'payment' AND commission_amount > 0 THEN cashier_citizenid
                ELSE NULL
            END), 0) AS cashier_count,
            COALESCE(AVG(CASE WHEN type = 'payment' AND commission_amount > 0 THEN commission_amount ELSE NULL END), 0) AS avg_commission_amount
        FROM vancepay_transactions
        WHERE %s
    ]]):format(whereClause), params) or {}

    local dailyRows = MySQL.query.await(([[
        SELECT
            DATE(created_at) AS report_date,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN commission_amount ELSE 0 END), 0) AS generated_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN commission_amount ELSE 0 END), 0) AS refunded_commission_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN commission_amount
                WHEN type = 'refund' THEN -commission_amount
                ELSE 0
            END), 0) AS net_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' AND commission_amount > 0 THEN 1 ELSE 0 END), 0) AS commission_payment_count,
            COALESCE(SUM(CASE WHEN type = 'refund' AND commission_amount > 0 THEN 1 ELSE 0 END), 0) AS commission_refund_count
        FROM vancepay_transactions
        WHERE %s
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at) ASC
    ]]):format(whereClause), params) or {}

    local dailyMap = {}
    for index = 1, #dailyRows do
        local row = Utils.normalizeDbRow(dailyRows[index])
        dailyMap[tostring(row.report_date)] = {
            date = tostring(row.report_date),
            generated_commission_amount = Utils.roundCurrency(row.generated_commission_amount or 0),
            refunded_commission_amount = Utils.roundCurrency(row.refunded_commission_amount or 0),
            net_commission_amount = Utils.roundCurrency(row.net_commission_amount or 0),
            commission_payment_count = tonumber(row.commission_payment_count) or 0,
            commission_refund_count = tonumber(row.commission_refund_count) or 0,
        }
    end

    local daily = {}
    local dayCursor = filters.date_from_ts
    while dayCursor <= filters.date_to_ts do
        local dateKey = formatDate(dayCursor)
        local entry = dailyMap[dateKey] or {
            date = dateKey,
            generated_commission_amount = 0,
            refunded_commission_amount = 0,
            net_commission_amount = 0,
            commission_payment_count = 0,
            commission_refund_count = 0,
        }

        entry.label = dateKey:sub(6)
        daily[#daily + 1] = entry
        dayCursor = dayCursor + 86400
    end

    local methodRows = MySQL.query.await(([[
        SELECT
            method,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN commission_amount ELSE 0 END), 0) AS generated_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN commission_amount ELSE 0 END), 0) AS refunded_commission_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN commission_amount
                WHEN type = 'refund' THEN -commission_amount
                ELSE 0
            END), 0) AS net_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' AND commission_amount > 0 THEN 1 ELSE 0 END), 0) AS commission_payment_count,
            COALESCE(SUM(CASE WHEN type = 'refund' AND commission_amount > 0 THEN 1 ELSE 0 END), 0) AS commission_refund_count
        FROM vancepay_transactions
        WHERE %s
        GROUP BY method
        ORDER BY method ASC
    ]]):format(whereClause), params) or {}

    local methodMap = {}
    for index = 1, #methodRows do
        local row = Utils.normalizeDbRow(methodRows[index])
        methodMap[row.method] = row
    end

    local methods = {}
    local totalGeneratedCommission = Utils.roundCurrency(summary.generated_commission_amount or 0)
    local orderedMethods = { 'phone', 'card' }
    for index = 1, #orderedMethods do
        local method = orderedMethods[index]
        local row = methodMap[method] or {}
        local generatedCommissionAmount = Utils.roundCurrency(row.generated_commission_amount or 0)

        methods[#methods + 1] = {
            method = method,
            generated_commission_amount = generatedCommissionAmount,
            refunded_commission_amount = Utils.roundCurrency(row.refunded_commission_amount or 0),
            net_commission_amount = Utils.roundCurrency(row.net_commission_amount or 0),
            commission_payment_count = tonumber(row.commission_payment_count) or 0,
            commission_refund_count = tonumber(row.commission_refund_count) or 0,
            share = totalGeneratedCommission > 0 and math.floor(((generatedCommissionAmount / totalGeneratedCommission) * 1000) + 0.5) / 10 or 0,
        }
    end

    local topCashiers = {}
    local cashierRows = MySQL.query.await(([[
        SELECT
            cashier_citizenid,
            COALESCE(SUM(CASE WHEN type = 'payment' THEN commission_amount ELSE 0 END), 0) AS generated_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'refund' THEN commission_amount ELSE 0 END), 0) AS refunded_commission_amount,
            COALESCE(SUM(CASE
                WHEN type = 'payment' THEN commission_amount
                WHEN type = 'refund' THEN -commission_amount
                ELSE 0
            END), 0) AS net_commission_amount,
            COALESCE(SUM(CASE WHEN type = 'payment' AND commission_amount > 0 THEN 1 ELSE 0 END), 0) AS payment_count
        FROM vancepay_transactions
        WHERE %s
            AND cashier_citizenid IS NOT NULL
        GROUP BY cashier_citizenid
        ORDER BY net_commission_amount DESC, generated_commission_amount DESC, cashier_citizenid ASC
        LIMIT 5
    ]]):format(whereClause), params) or {}

    for index = 1, #cashierRows do
        local row = Utils.normalizeDbRow(cashierRows[index])
        topCashiers[#topCashiers + 1] = {
            cashier_citizenid = row.cashier_citizenid,
            generated_commission_amount = Utils.roundCurrency(row.generated_commission_amount or 0),
            refunded_commission_amount = Utils.roundCurrency(row.refunded_commission_amount or 0),
            net_commission_amount = Utils.roundCurrency(row.net_commission_amount or 0),
            payment_count = tonumber(row.payment_count) or 0,
        }
    end

    return {
        filters = {
            store_id = filters.store_id,
            date_from = filters.date_from,
            date_to = filters.date_to,
            range_days = filters.range_days,
        },
        summary = {
            generated_commission_amount = Utils.roundCurrency(summary.generated_commission_amount or 0),
            refunded_commission_amount = Utils.roundCurrency(summary.refunded_commission_amount or 0),
            net_commission_amount = Utils.roundCurrency(summary.net_commission_amount or 0),
            commission_payment_count = tonumber(summary.commission_payment_count) or 0,
            commission_refund_count = tonumber(summary.commission_refund_count) or 0,
            cashier_count = tonumber(summary.cashier_count) or 0,
            avg_commission_amount = Utils.roundCurrency(summary.avg_commission_amount or 0),
        },
        daily = daily,
        methods = methods,
        top_cashiers = topCashiers,
    }
end

function Reports.getAdvancedReport(source, filters)
    filters = normalizeReportRange(filters)

    local allowed, reason = assertManageScope(source, filters.store_id)
    if not allowed then
        return VancePay.Server.fail(reason, 'forbidden')
    end

    return VancePay.Server.ok(Reports.buildAdvancedReportData(filters))
end

function Reports.getTaxReport(source, filters)
    filters = normalizeReportRange(filters)

    local allowed, reason = assertManageScope(source, filters.store_id)
    if not allowed then
        return VancePay.Server.fail(reason, 'forbidden')
    end

    return VancePay.Server.ok(Reports.buildTaxReportData(filters))
end

function Reports.getCommissionReport(source, filters)
    filters = normalizeReportRange(filters)

    local allowed, reason = assertManageScope(source, filters.store_id)
    if not allowed then
        return VancePay.Server.fail(reason, 'forbidden')
    end

    return VancePay.Server.ok(Reports.buildCommissionReportData(filters))
end

local function exportTransactions(source, payload)
    if VancePay.Transactions and VancePay.Transactions.ensureReady then
        VancePay.Transactions.ensureReady()
    end

    local filters = normalizeTransactionFilters(payload or {})
    local allowed, reason = assertManageScope(source, filters.store_id)
    if not allowed then
        return VancePay.Server.fail(reason, 'forbidden')
    end

    local conditions, params = buildTransactionConditions(filters)
    local query = ([[
        SELECT
            tx_code,
            type,
            method,
            status,
            store_id,
            store_name_snapshot,
            terminal_serial_snapshot,
            cashier_citizenid,
            customer_citizenid,
            processed_by_citizenid,
            subtotal_amount,
            discount_rate,
            discount_amount,
            tip_amount,
            fee_amount,
            tax_rate,
            tax_exempt,
            tax_amount,
            commission_rate,
            commission_amount,
            final_amount,
            net_amount,
            refunded_final_amount,
            refunded_net_amount,
            refunded_tax_amount,
            refunded_commission_amount,
            refund_reason,
            created_at
        FROM vancepay_transactions
        WHERE %s
        ORDER BY id DESC
    ]]):format(table.concat(conditions, ' AND '))

    local rows = MySQL.query.await(query, params) or {}
    for index = 1, #rows do
        rows[index] = Utils.normalizeDbRow(rows[index])
    end

    return VancePay.Server.ok({
        filename = ('vancepay-transactions-%s.csv'):format(os.date('%Y%m%d-%H%M%S')),
        mime = 'text/csv;charset=utf-8',
        content = buildCsv({
            { key = 'tx_code', header = '交易号' },
            { key = 'type', header = '类型' },
            { key = 'method', header = '方式' },
            { key = 'status', header = '状态' },
            { key = 'store_id', header = '店铺ID' },
            { key = 'store_name_snapshot', header = '店铺名称' },
            { key = 'terminal_serial_snapshot', header = '终端序列号' },
            { key = 'cashier_citizenid', header = '收银员' },
            { key = 'customer_citizenid', header = '顾客' },
            { key = 'processed_by_citizenid', header = '操作人' },
            { key = 'subtotal_amount', header = '原始金额' },
            { key = 'discount_rate', header = '折扣率' },
            { key = 'discount_amount', header = '折扣额' },
            { key = 'tip_amount', header = '小费' },
            { key = 'fee_amount', header = '手续费' },
            { key = 'tax_rate', header = '税率' },
            { key = 'tax_exempt', header = '免税' },
            { key = 'tax_amount', header = '税额' },
            { key = 'commission_rate', header = '提成比例' },
            { key = 'commission_amount', header = '提成金额' },
            { key = 'final_amount', header = '顾客实付' },
            { key = 'net_amount', header = '店铺入账' },
            { key = 'refunded_final_amount', header = '累计已退' },
            { key = 'refunded_net_amount', header = '累计已冲回' },
            { key = 'refunded_tax_amount', header = '累计已退税额' },
            { key = 'refunded_commission_amount', header = '累计已冲回提成' },
            { key = 'refund_reason', header = '退款原因' },
            { key = 'created_at', header = '创建时间' },
        }, rows)
    })
end

local function exportAudit(source, payload)
    payload = payload or {}
    local storeId = tonumber(payload.store_id)
    local allowed, reason = assertManageScope(source, storeId)
    if not allowed then
        return VancePay.Server.fail(reason, 'forbidden')
    end

    local conditions = { '1=1' }
    local params = {}

    appendStoreCondition({ store_id = storeId }, conditions, params)

    local rows = MySQL.query.await(([[ 
        SELECT
            actor_citizenid,
            store_id,
            terminal_id,
            action,
            target_type,
            target_id,
            detail,
            created_at
        FROM vancepay_audit_logs
        WHERE %s
        ORDER BY id DESC
    ]]):format(table.concat(conditions, ' AND ')), params) or {}

    for index = 1, #rows do
        rows[index] = Utils.normalizeDbRow(rows[index])
    end

    return VancePay.Server.ok({
        filename = ('vancepay-audit-%s.csv'):format(os.date('%Y%m%d-%H%M%S')),
        mime = 'text/csv;charset=utf-8',
        content = buildCsv({
            { key = 'actor_citizenid', header = '操作者' },
            { key = 'store_id', header = '店铺ID' },
            { key = 'terminal_id', header = '终端ID' },
            { key = 'action', header = '动作' },
            { key = 'target_type', header = '目标类型' },
            { key = 'target_id', header = '目标ID' },
            { key = 'detail', header = '详情' },
            { key = 'created_at', header = '创建时间' },
        }, rows)
    })
end

local function exportReport(source, payload)
    local response = Reports.getAdvancedReport(source, payload)
    if not response.ok then
        return response
    end

    local report = response.data
    local rows = {}

    for index = 1, #report.daily do
        local item = report.daily[index]
        rows[#rows + 1] = {
            date = item.date,
            gross_amount = item.gross_amount,
            refunded_amount = item.refunded_amount,
            net_amount = item.net_amount,
            payment_count = item.payment_count,
            refund_count = item.refund_count,
        }
    end

    rows[#rows + 1] = {
        date = 'SUMMARY',
        gross_amount = report.summary.gross_amount,
        refunded_amount = report.summary.refunded_amount,
        net_amount = report.summary.net_amount,
        payment_count = report.summary.payment_count,
        refund_count = report.summary.refund_count,
    }

    return VancePay.Server.ok({
        filename = ('vancepay-report-%s.csv'):format(os.date('%Y%m%d-%H%M%S')),
        mime = 'text/csv;charset=utf-8',
        content = buildCsv({
            { key = 'date', header = '日期' },
            { key = 'gross_amount', header = '支付总额' },
            { key = 'refunded_amount', header = '退款总额' },
            { key = 'net_amount', header = '净入账' },
            { key = 'payment_count', header = '支付笔数' },
            { key = 'refund_count', header = '退款笔数' },
        }, rows)
    })
end

function Reports.exportData(source, payload)
    payload = payload or {}
    local exportType = Utils.trim(payload.export_type or payload.type)

    if exportType == 'transactions' then
        return exportTransactions(source, payload)
    end

    if exportType == 'audit' then
        return exportAudit(source, payload)
    end

    if exportType == 'report' then
        return exportReport(source, payload)
    end

    return VancePay.Server.fail('不支持的导出类型', 'invalid_export_type')
end

function Reports.getAdminBootstrap(source, payload)
    payload = payload or {}
    local terminalBootstrap = VancePay.Terminals.getTabletBootstrap(source, payload)
    if not terminalBootstrap.ok then
        return terminalBootstrap
    end

    local context = terminalBootstrap.data
    local isAdmin = context.is_admin == true
    local stores = VancePay.Stores.listForSource(source, context.mode == 'store' and {
        store_id = context.store and context.store.id or nil
    } or {})

    local selectedStoreId = context.store and context.store.id or tonumber(payload.store_id)
    if not selectedStoreId and #stores > 0 then
        selectedStoreId = stores[1].id
    end

    local terminals = VancePay.Terminals.listForSource(source, selectedStoreId and {
        store_id = selectedStoreId
    } or {})

    local employees = {}
    local overview = selectedStoreId and Reports.getStoreOverview(selectedStoreId) or nil
    local transactions = VancePay.Transactions.listInternal({
        store_id = selectedStoreId,
        page = 1,
        per_page = Config.TransPerPage,
    })
    local audit = selectedStoreId and VancePay.Audit.list({
        store_id = selectedStoreId,
        page = 1,
        per_page = Config.TransPerPage,
    }) or (isAdmin and VancePay.Audit.list({
        page = 1,
        per_page = Config.TransPerPage,
    }) or { items = {}, page = 1, per_page = Config.TransPerPage })
    local reports = Reports.buildAdvancedReportData({
        store_id = selectedStoreId,
        range_days = 7,
    })
    local taxReport = Reports.buildTaxReportData({
        store_id = selectedStoreId,
        range_days = 7,
    })
    local commissionReport = Reports.buildCommissionReportData({
        store_id = selectedStoreId,
        range_days = 7,
    })
    local loans = isAdmin and (VancePay.Loans and VancePay.Loans.getAdminData and VancePay.Loans.getAdminData({
        page = 1,
        per_page = Config.TransPerPage,
    }) or nil) or nil
    local taxDefaults = VancePay.Stores and VancePay.Stores.getTaxDefaults and VancePay.Stores.getTaxDefaults() or {
        default_tax_rate = Utils.roundCurrency(Config.DefaultTaxRate or 0),
        tax_settlement_mode = VancePay.StoreSettlementModes and VancePay.StoreSettlementModes.storeBalance or 'store_balance',
        tax_settlement_account_identifier = nil,
        tax_target_label = '当前店铺 VancePay 余额',
    }

    if selectedStoreId then
        local employeeResponse = VancePay.Stores.listEmployees(source, selectedStoreId)
        if employeeResponse.ok then
            employees = employeeResponse.data
        end
    end

    return VancePay.Server.ok({
        mode = context.mode,
        is_admin = isAdmin,
        terminal = context.terminal,
        selected_store_id = selectedStoreId,
        stores = stores,
        terminals = terminals,
        terminal_models = isAdmin and (VancePay.Models and VancePay.Models.list({ status = 'all' }) or {}) or {},
        active_terminal_models = VancePay.Models and VancePay.Models.list({ status = 'active' }) or {},
        employees = employees,
        overview = overview,
        transactions = transactions,
        audit = audit,
        reports = reports,
        tax_report = taxReport,
        commission_report = commissionReport,
        loans = loans,
        tax_defaults = taxDefaults,
    })
end

lib.callback.register('vancepay:server:getStoreOverview', function(source, storeId)
    storeId = tonumber(storeId)
    if not storeId then
        return VancePay.Server.fail('缺少店铺 ID', 'missing_store_id')
    end

    if not VancePay.Permissions.isAdmin(source) then
        local allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'manage')
        if not allowed then
            allowed, reason = VancePay.Permissions.checkAccess(source, storeId, 'collect')
        end

        if not allowed then
            return VancePay.Server.fail(reason, 'forbidden')
        end
    end

    return VancePay.Server.ok(Reports.getStoreOverview(storeId))
end)

lib.callback.register('vancepay:server:getAdvancedReport', function(source, filters)
    return Reports.getAdvancedReport(source, filters or {})
end)

lib.callback.register('vancepay:server:getTaxReport', function(source, filters)
    return Reports.getTaxReport(source, filters or {})
end)

lib.callback.register('vancepay:server:getCommissionReport', function(source, filters)
    return Reports.getCommissionReport(source, filters or {})
end)

lib.callback.register('vancepay:server:exportAdminData', function(source, payload)
    return Reports.exportData(source, payload or {})
end)

lib.callback.register('vancepay:server:getAdminBootstrap', function(source, payload)
    return Reports.getAdminBootstrap(source, payload or {})
end)
