VancePay.PaymentFlow = VancePay.PaymentFlow or {}

local PaymentFlow = VancePay.PaymentFlow

PaymentFlow.session = PaymentFlow.session or nil

local function normalizeActiveIntent(intent)
    if not intent then
        return nil
    end

    return {
        id = intent.id or intent.intent_id,
        intent_code = intent.intent_code or intent.code,
        status = intent.status,
        method = intent.method,
        target_citizenid = intent.target_citizenid,
        item_description = intent.item_description,
        item_lines = intent.item_lines,
        final_amount = intent.final_amount,
        expires_at = intent.expires_at,
        message = intent.message,
    }
end

local function buildCashierPayload()
    if not PaymentFlow.session then
        return {}
    end

    local nearbyPlayers = VancePay.Client.getNearbyPlayers(Config.TargetingDistance)

    return {
        store = PaymentFlow.session.store,
        terminal = PaymentFlow.session.terminal,
        access = PaymentFlow.session.access,
        overview = PaymentFlow.session.overview,
        config = {
            enable_fee = Config.EnableFee,
            fee_rate = Config.FeeRate,
            fee_paid_by = Config.FeePaidBy,
            min_amount = Config.MinAmount,
            max_amount = Config.MaxAmount,
            max_discount = Config.MaxDiscount,
            max_tip = Config.MaxTip,
            max_item_lines = Config.MaxItemLines,
            tax_rate = (PaymentFlow.session.store and PaymentFlow.session.store.effective_tax_rate)
                or (PaymentFlow.session.overview and PaymentFlow.session.overview.effective_tax_rate)
                or 0,
            tax_exempt = (PaymentFlow.session.store and PaymentFlow.session.store.tax_exempt)
                or (PaymentFlow.session.overview and PaymentFlow.session.overview.tax_exempt)
                or false,
        },
        recent_transactions = PaymentFlow.session.recent_transactions or {},
        nearby_customers = nearbyPlayers,
        active_intent = PaymentFlow.session.active_intent,
    }
end

function PaymentFlow.refreshStoreData()
    if not PaymentFlow.session then
        return
    end

    local overviewResponse = lib.callback.await('vancepay:server:getStoreOverview', false, PaymentFlow.session.store.id)
    if overviewResponse and overviewResponse.ok then
        PaymentFlow.session.overview = overviewResponse.data
        PaymentFlow.session.store.tax_rate = overviewResponse.data.tax_rate
        PaymentFlow.session.store.tax_exempt = overviewResponse.data.tax_exempt
        PaymentFlow.session.store.effective_tax_rate = overviewResponse.data.effective_tax_rate
        PaymentFlow.session.store.tax_enabled = overviewResponse.data.tax_enabled
    end

    local txResponse = lib.callback.await('vancepay:server:getTransactions', false, {
        store_id = PaymentFlow.session.store.id,
        page = 1,
        per_page = 5,
    })

    if txResponse and txResponse.ok then
        PaymentFlow.session.recent_transactions = txResponse.data.items or {}
    end
end

function PaymentFlow.open(payload)
    payload = payload or {}

    if payload.launch == 'portable' then
        VancePay.Client.playDeviceAnimation('portable')
    end

    if payload.binding_required then
        local bindingData = VancePay.Client.redeemBindingCode({
            terminal_type = payload.terminal_type or VancePay.TerminalTypes.portable,
            item_name = payload.item_name or Config.PortablePOSItem,
            item = payload.item or {},
            prompt_message = payload.prompt_message,
        })

        if not bindingData then
            return
        end

        payload.binding_required = false
        payload.serial_number = bindingData.launch_serial_number
        payload.item = bindingData.metadata or payload.item
    end

    local response = lib.callback.await('vancepay:server:getPosBootstrap', false, payload or {})
    if not response or not response.ok then
        VancePay.Client.notify(response and response.message or 'POS 初始化失败', 'error')
        return
    end

    PaymentFlow.session = {
        launch = payload.launch,
        store = response.data.store,
        terminal = response.data.terminal,
        access = response.data.access,
        overview = response.data.overview,
        recent_transactions = response.data.recent_transactions or {},
        active_intent = normalizeActiveIntent(response.data.active_intent),
    }

    VancePay.Client.openView('cashier', buildCashierPayload())
end

function PaymentFlow.handleIntentUpdate(payload)
    if not PaymentFlow.session or not payload or payload.store_id ~= PaymentFlow.session.store.id then
        return
    end

    local isCurrentIntent = PaymentFlow.session.active_intent and PaymentFlow.session.active_intent.id == payload.intent_id

    if isCurrentIntent or not PaymentFlow.session.active_intent then
        if payload.status == VancePay.IntentStatuses.completed
            or payload.status == VancePay.IntentStatuses.cancelled
            or payload.status == VancePay.IntentStatuses.expired
            or payload.status == VancePay.IntentStatuses.failed then
            PaymentFlow.session.active_intent = nil
            PaymentFlow.refreshStoreData()
        else
            PaymentFlow.session.active_intent = normalizeActiveIntent(payload)
        end

        VancePay.Client.updateView('cashier', buildCashierPayload())
    end
end

RegisterNUICallback('getNearbyCustomers', function(_, cb)
    cb({
        ok = true,
        data = VancePay.Client.getNearbyPlayers(Config.TargetingDistance),
    })
end)

RegisterNUICallback('createIntent', function(data, cb)
    if not PaymentFlow.session then
        cb({ ok = false, message = '未打开 POS 会话' })
        return
    end

    data = data or {}
    data.terminal_id = PaymentFlow.session.terminal.id

    local response = lib.callback.await('vancepay:server:createIntent', false, data)
    if response and response.ok then
        PaymentFlow.session.active_intent = normalizeActiveIntent(response.data)
        VancePay.Client.updateView('cashier', buildCashierPayload())
    else
        VancePay.Client.notify(response and response.message or '创建订单失败', 'error')
    end

    cb(response or { ok = false, message = '创建订单失败' })
end)

RegisterNUICallback('cancelIntent', function(data, cb)
    if not PaymentFlow.session then
        cb({ ok = false, message = '未打开 POS 会话' })
        return
    end

    data = data or {}
    data.intent_id = data.intent_id or (PaymentFlow.session.active_intent and PaymentFlow.session.active_intent.id)

    local response = lib.callback.await('vancepay:server:cancelIntent', false, data)
    if response and response.ok then
        PaymentFlow.session.active_intent = nil
        VancePay.Client.updateView('cashier', buildCashierPayload())
    else
        VancePay.Client.notify(response and response.message or '取消订单失败', 'error')
    end

    cb(response or { ok = false, message = '取消订单失败' })
end)

RegisterNUICallback('getCashierTransactions', function(data, cb)
    if not PaymentFlow.session then
        cb({ ok = false, message = '未打开 POS 会话' })
        return
    end

    data = data or {}
    data.store_id = PaymentFlow.session.store.id

    local response = lib.callback.await('vancepay:server:getTransactions', false, data)
    cb(response or { ok = false, message = '获取交易失败' })
end)

RegisterNUICallback('getCashierTransactionDetail', function(data, cb)
    if not PaymentFlow.session then
        cb({ ok = false, message = '未打开 POS 会话' })
        return
    end

    local transactionId = data and (data.transaction_id or data.id) or nil
    local response = lib.callback.await('vancepay:server:getTransactionDetail', false, transactionId)
    cb(response or { ok = false, message = '获取交易详情失败' })
end)

RegisterNUICallback('refundFromCashier', function(data, cb)
    local response = lib.callback.await('vancepay:server:refundTransaction', false, data or {})
    if response and response.ok then
        PaymentFlow.refreshStoreData()
        VancePay.Client.updateView('cashier', buildCashierPayload())
    else
        VancePay.Client.notify(response and response.message or '退款失败', 'error')
    end

    cb(response or { ok = false, message = '退款失败' })
end)
