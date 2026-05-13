(function () {
    const app = window.VancePayApp;
    const state = {
        payload: {},
        selectedTransactionId: null,
        transactionDetail: null,
        itemLines: [],
        manualAmount: '',
        sessionKey: null,
        transactionsCollapsed: true
    };

    const elements = {
        layout: document.getElementById('cashier-layout'),
        ledgerCard: document.getElementById('cashier-ledger-card'),
        ledgerBody: document.getElementById('cashier-ledger-body'),
        toggleTransactionsButton: document.getElementById('toggle-transactions-button'),
        storeName: document.getElementById('cashier-store-name'),
        terminalMeta: document.getElementById('cashier-terminal-meta'),
        amount: document.getElementById('amount-input'),
        discount: document.getElementById('discount-input'),
        tip: document.getElementById('tip-input'),
        itemDescription: document.getElementById('item-description-input'),
        addItemLine: document.getElementById('add-item-line-button'),
        itemLines: document.getElementById('item-lines-list'),
        customerSelect: document.getElementById('customer-select'),
        customerList: document.getElementById('nearby-customer-list'),
        phonePayButton: document.getElementById('phone-pay-button'),
        cardPayButton: document.getElementById('card-pay-button'),
        statusPill: document.getElementById('cashier-status-pill'),
        finalAmount: document.getElementById('preview-final-amount'),
        netAmount: document.getElementById('preview-net-amount'),
        feeAmount: document.getElementById('preview-fee-amount'),
        taxAmount: document.getElementById('preview-tax-amount'),
        discountAmount: document.getElementById('preview-discount-amount'),
        overviewStrip: document.getElementById('cashier-overview-strip'),
        transactions: document.getElementById('cashier-transactions'),
        transactionDetail: document.getElementById('cashier-transaction-detail'),
        intentContent: document.getElementById('active-intent-content'),
        cancelIntent: document.getElementById('cancel-intent-button')
    };

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatMethod(method) {
        return method === 'card' ? '刷卡' : '手机';
    }

    function formatType(type) {
        return type === 'refund' ? '退款' : '支付';
    }

    function formatStatus(status) {
        return {
            awaiting_customer: '等待确认',
            awaiting_swipe: '等待刷卡',
            completed: '已完成',
            partially_refunded: '部分退款',
            cancelled: '已取消',
            expired: '已超时',
            failed: '失败',
            refunded: '已退款'
        }[status] || status || '--';
    }

    function roundCurrency(value) {
        return Math.round((Number(value || 0) + Number.EPSILON) * 100) / 100;
    }

    function formatQuantity(value) {
        const amount = Number(value || 0);
        if (Number.isInteger(amount)) {
            return String(amount);
        }

        return amount.toFixed(3).replace(/\.?0+$/, '');
    }

    function buildItemMeta(itemDescription, itemLines) {
        const description = String(itemDescription || '').trim();
        if (description) {
            return description;
        }

        if (!Array.isArray(itemLines) || !itemLines.length) {
            return '';
        }

        const parts = itemLines.slice(0, 2).map((line) => `${line.name || '商品'} x${formatQuantity(line.quantity)}`);
        if (itemLines.length > 2) {
            parts.push(`等 ${itemLines.length} 项`);
        }

        return parts.join(' · ');
    }

    function renderItemLinesDetail(itemLines) {
        if (!Array.isArray(itemLines) || !itemLines.length) {
            return '';
        }

        return `
            <div class="item-lines-detail">
                ${itemLines.map((line) => `
                    <div class="item-line-detail">
                        <div>
                            <strong>${escapeHtml(line.name || '商品')}</strong>
                            <span>${escapeHtml(formatQuantity(line.quantity || 0))} × ${app.formatCurrency(line.unit_price || 0)}</span>
                        </div>
                        <em>${app.formatCurrency(line.line_total || (Number(line.quantity || 0) * Number(line.unit_price || 0)))}</em>
                    </div>
                `).join('')}
            </div>
        `;
    }

    function createEmptyItemLine() {
        return {
            name: '',
            quantity: '1',
            unit_price: ''
        };
    }

    function computeItemLine(line) {
        const normalized = line || {};
        const name = String(normalized.name || '').trim();
        const rawQuantity = String(normalized.quantity == null ? '' : normalized.quantity).trim();
        const rawUnitPrice = String(normalized.unit_price == null ? '' : normalized.unit_price).trim();
        const quantity = Number(rawQuantity || 0);
        const parsedUnitPrice = rawUnitPrice === '' ? Number.NaN : Number(rawUnitPrice);
        const unitPrice = Number.isFinite(parsedUnitPrice) ? roundCurrency(parsedUnitPrice) : Number.NaN;
        const lineTotal = roundCurrency(Math.max(0, quantity) * Math.max(0, Number.isFinite(unitPrice) ? unitPrice : 0));
        const hasAnyValue = name !== '' || rawQuantity !== '' || rawUnitPrice !== '';
        const valid = name !== '' && rawQuantity !== '' && rawUnitPrice !== '' && quantity > 0 && Number.isFinite(unitPrice) && unitPrice >= 0;

        return {
            name,
            quantity,
            unit_price: unitPrice,
            line_total: lineTotal,
            hasAnyValue,
            valid
        };
    }

    function getComputedItemLines() {
        return state.itemLines.map(computeItemLine);
    }

    function getValidItemLines() {
        return getComputedItemLines()
            .filter((line) => line.valid)
            .map((line) => ({
                name: line.name,
                quantity: line.quantity,
                unit_price: line.unit_price,
                line_total: line.line_total
            }));
    }

    function getMaxItemLines() {
        const configured = Number(state.payload?.config?.max_item_lines || 0);
        return configured > 0 ? Math.floor(configured) : 12;
    }

    function getPositiveConfigLimit(key) {
        const configured = Number(state.payload?.config?.[key] || 0);
        return Number.isFinite(configured) && configured > 0 ? configured : 0;
    }

    function getPaymentValidation(preview) {
        const config = state.payload.config || {};
        const minAmount = Number(config.min_amount || 1);
        const maxAmount = getPositiveConfigLimit('max_amount');
        const maxDiscount = Number(config.max_discount || 0);
        const maxTip = getPositiveConfigLimit('max_tip');

        if (preview.subtotal < minAmount) {
            return `订单金额至少为 ${app.formatCurrency(minAmount)}`;
        }

        if (maxAmount > 0 && preview.subtotal > maxAmount) {
            return `订单金额不能超过 ${app.formatCurrency(maxAmount)}`;
        }

        if (preview.discountRate < 0 || preview.discountRate > maxDiscount) {
            return `折扣必须在 0 到 ${maxDiscount.toFixed(2)}% 之间`;
        }

        if (preview.tipAmount < 0) {
            return '小费不能为负数';
        }

        if (maxTip > 0 && preview.tipAmount > maxTip) {
            return `小费不能超过 ${app.formatCurrency(maxTip)}`;
        }

        if (!(preview.finalAmount > 0)) {
            return '请输入有效金额';
        }

        return '';
    }

    function syncPaymentInputLimits() {
        const config = state.payload.config || {};
        const maxAmount = getPositiveConfigLimit('max_amount');
        const maxTip = getPositiveConfigLimit('max_tip');
        const maxDiscount = Number(config.max_discount || 0);

        elements.amount.min = String(Number(config.min_amount || 1));
        elements.amount.max = maxAmount > 0 ? String(maxAmount) : '';
        elements.discount.min = '0';
        elements.discount.max = maxDiscount > 0 ? String(maxDiscount) : '';
        elements.tip.min = '0';
        elements.tip.max = maxTip > 0 ? String(maxTip) : '';
    }

    function syncAmountFromItemLines(computedLines = getComputedItemLines()) {
        const validLines = computedLines.filter((line) => line.valid);
        const hasValidLines = validLines.length > 0;

        if (hasValidLines) {
            if (!elements.amount.readOnly) {
                state.manualAmount = elements.amount.value;
            }

            const subtotal = roundCurrency(validLines.reduce((sum, line) => sum + Number(line.line_total || 0), 0));
            elements.amount.value = subtotal.toFixed(2);
        } else {
            if (elements.amount.readOnly) {
                elements.amount.value = state.manualAmount || '';
            }
        }

        elements.amount.readOnly = hasValidLines;
        elements.amount.classList.toggle('readonly-input', hasValidLines);
        computePreview();

        return validLines;
    }

    function refreshItemLineEditorState() {
        const computedLines = getComputedItemLines();
        elements.itemLines.querySelectorAll('[data-line-index]').forEach((row) => {
            const index = Number(row.dataset.lineIndex);
            const line = computedLines[index];
            const totalEl = row.querySelector('[data-line-total]');
            if (totalEl && line) {
                totalEl.textContent = app.formatCurrency(line.line_total || 0);
            }
        });

        syncAmountFromItemLines(computedLines);
    }

    function renderItemLineEditor() {
        const maxItemLines = getMaxItemLines();
        elements.addItemLine.disabled = state.itemLines.length >= maxItemLines;

        if (!state.itemLines.length) {
            elements.itemLines.innerHTML = '<div class="line-items-empty">未添加商品项。你可以直接手填金额，也可以添加商品后自动汇总。</div>';
            syncAmountFromItemLines([]);
            return;
        }

        elements.itemLines.innerHTML = state.itemLines.map((line, index) => `
            <div class="line-item-row" data-line-index="${index}">
                <div class="line-item-grid">
                    <input type="text" data-line-field="name" placeholder="商品名称" value="${escapeHtml(line.name || '')}">
                    <input type="number" data-line-field="quantity" min="0.001" step="0.001" placeholder="数量" value="${escapeHtml(line.quantity || '')}">
                    <input type="number" data-line-field="unit_price" min="0" max="${escapeHtml(getPositiveConfigLimit('max_amount') || '')}" step="0.01" placeholder="单价" value="${escapeHtml(line.unit_price || '')}">
                    <div class="line-item-total" data-line-total>$0.00</div>
                    <button class="line-item-remove" type="button" data-remove-line>移除</button>
                </div>
            </div>
        `).join('');

        refreshItemLineEditorState();
    }

    function resetComposer() {
        state.itemLines = [];
        state.manualAmount = '';
        elements.amount.value = '';
        elements.amount.readOnly = false;
        elements.amount.classList.remove('readonly-input');
        elements.discount.value = '';
        elements.tip.value = '';
        elements.itemDescription.value = '';
        renderItemLineEditor();
        computePreview();
    }

    function canRefundTransaction(transaction) {
        return Boolean(
            state.payload.access &&
            state.payload.access.can_refund &&
            transaction &&
            transaction.type === 'payment' &&
            (transaction.status === 'completed' || transaction.status === 'partially_refunded')
        );
    }

    function getRefundableAmount(transactionId) {
        const numericId = Number(transactionId);

        if (
            state.transactionDetail &&
            state.transactionDetail.transaction &&
            Number(state.transactionDetail.transaction.id) === numericId &&
            state.transactionDetail.refund_summary
        ) {
            return roundCurrency(state.transactionDetail.refund_summary.remaining_final_amount);
        }

        const transaction = (state.payload.recent_transactions || []).find((entry) => Number(entry.id) === numericId);
        if (!transaction) {
            return 0;
        }

        return roundCurrency(Number(transaction.final_amount || 0) - Number(transaction.refunded_final_amount || 0));
    }

    function findTransaction(transactionId) {
        const numericId = Number(transactionId);

        if (
            state.transactionDetail &&
            state.transactionDetail.transaction &&
            Number(state.transactionDetail.transaction.id) === numericId
        ) {
            return state.transactionDetail.transaction;
        }

        return (state.payload.recent_transactions || []).find((entry) => Number(entry.id) === numericId) || null;
    }

    function computePreview() {
        const config = state.payload.config || {};
        const subtotal = Number(elements.amount.value || 0);
        const discountRate = Number(elements.discount.value || 0);
        const tipAmount = Number(elements.tip.value || 0);
        const discountAmount = subtotal * (discountRate / 100);
        const taxableAmount = Math.max(0, subtotal - discountAmount);
        const baseAmount = taxableAmount + tipAmount;
        const taxAmount = taxableAmount * Number(config.tax_rate || 0) / 100;
        let finalAmount = baseAmount + taxAmount;
        let feeAmount = 0;
        let netAmount = baseAmount;

        if (config.enable_fee) {
            if (config.fee_paid_by === 'customer') {
                feeAmount = netAmount * Number(config.fee_rate || 0);
                finalAmount = netAmount + taxAmount + feeAmount;
            } else {
                feeAmount = baseAmount * Number(config.fee_rate || 0);
                finalAmount = baseAmount + taxAmount;
                netAmount = baseAmount - feeAmount;
            }
        }

        elements.finalAmount.textContent = app.formatCurrency(finalAmount);
        elements.netAmount.textContent = app.formatCurrency(netAmount);
        elements.feeAmount.textContent = app.formatCurrency(feeAmount);
        elements.taxAmount.textContent = app.formatCurrency(taxAmount);
        elements.discountAmount.textContent = app.formatCurrency(discountAmount);
        elements.phonePayButton.textContent = `手机收款 ${app.formatCurrency(finalAmount)}`;
        elements.cardPayButton.textContent = `刷卡收款 ${app.formatCurrency(finalAmount)}`;

        const preview = {
            subtotal,
            discountRate,
            tipAmount,
            discountAmount,
            feeAmount,
            taxAmount,
            netAmount,
            finalAmount,
            canCharge: finalAmount > 0
        };
        preview.validationError = getPaymentValidation(preview);
        preview.canCharge = !preview.validationError;
        elements.phonePayButton.disabled = !preview.canCharge;
        elements.cardPayButton.disabled = !preview.canCharge;

        return preview;
    }

    function renderNearbyCustomers() {
        const customers = state.payload.nearby_customers || [];
        elements.customerSelect.innerHTML = customers.length
            ? customers.map((customer) => `<option value="${customer.source}">${escapeHtml(customer.name)} · ${customer.distance.toFixed(1)}m</option>`).join('')
            : '<option value="">手机支付需先锁定附近顾客</option>';

        elements.customerList.innerHTML = customers.map((customer) => `
            <div class="customer-chip">
                <div class="item-headline">
                    <strong>${escapeHtml(customer.name)}</strong>
                    <span>${customer.distance.toFixed(1)}m</span>
                </div>
                <div class="item-subcopy">服务器 ID #${customer.source}</div>
            </div>
        `).join('') || '<div class="table-item">暂无附近顾客</div>';
    }

    function renderOverview() {
        const overview = state.payload.overview || {};
        const items = [
            [overview.balance_label || '余额', app.formatCurrency(overview.balance || 0)],
            ['今日交易', String(overview.today_transaction_count || 0)],
            ['今日营收', app.formatCurrency(overview.today_net_amount || 0)],
            ['待处理', String(overview.pending_count || 0)]
        ];

        elements.overviewStrip.innerHTML = items.map(([label, value]) => `
            <div class="overview-pill">
                <label>${label}</label>
                <strong>${value}</strong>
            </div>
        `).join('');
    }

    function renderIntent() {
        const intent = state.payload.active_intent;
        if (!intent) {
            elements.statusPill.textContent = '空闲';
            elements.statusPill.dataset.state = 'idle';
            elements.intentContent.textContent = '暂无待支付订单';
            elements.cancelIntent.classList.add('hidden');
            return;
        }

        const waitCopy = intent.message || (intent.method === 'card' ? '等待附近顾客靠近 POS 刷卡' : '等待顾客在手机端确认');
        const itemMeta = buildItemMeta(intent.item_description, intent.item_lines);
        elements.statusPill.textContent = formatStatus(intent.status);
        elements.statusPill.dataset.state = intent.status || 'idle';
        elements.intentContent.innerHTML = `
            <div class="item-headline">
                <strong>${escapeHtml(intent.intent_code || intent.code || '订单')}</strong>
                <span>${formatMethod(intent.method)}</span>
            </div>
            <div class="item-subcopy">${escapeHtml(waitCopy)}</div>
            ${itemMeta ? `<div class="item-subcopy">概览：${escapeHtml(itemMeta)}</div>` : ''}
            <div class="item-subcopy">实付 ${app.formatCurrency(intent.final_amount || 0)}</div>
        `;
        elements.cancelIntent.classList.remove('hidden');
    }

    function setTransactionsCollapsed(collapsed) {
        state.transactionsCollapsed = collapsed !== false;

        if (elements.layout) {
            elements.layout.classList.toggle('history-collapsed', state.transactionsCollapsed);
        }

        if (elements.ledgerCard) {
            elements.ledgerCard.classList.toggle('is-collapsed', state.transactionsCollapsed);
        }

        if (elements.ledgerBody) {
            elements.ledgerBody.classList.toggle('hidden', state.transactionsCollapsed);
        }

        if (elements.toggleTransactionsButton) {
            elements.toggleTransactionsButton.textContent = state.transactionsCollapsed ? '展开历史' : '收起历史';
            elements.toggleTransactionsButton.setAttribute('aria-expanded', state.transactionsCollapsed ? 'false' : 'true');
        }
    }

    function renderTransactions() {
        const transactions = state.payload.recent_transactions || [];
        elements.transactions.innerHTML = transactions.map((transaction) => `
            <div class="ledger-item clickable ${Number(state.selectedTransactionId) === Number(transaction.id) ? 'active' : ''}" data-cashier-transaction-id="${transaction.id}">
                <div class="item-headline">
                    <strong>${escapeHtml(transaction.tx_code)}</strong>
                    <span>${app.formatCurrency(transaction.final_amount)}</span>
                </div>
                <div class="item-subcopy">
                    ${formatType(transaction.type)} · ${formatMethod(transaction.method)} · ${formatStatus(transaction.status)} · ${app.formatDate(transaction.created_at)}${transaction.type === 'payment' && Number(transaction.refunded_final_amount || 0) > 0 ? ` · 已退 ${app.formatCurrency(transaction.refunded_final_amount)}` : ''}
                </div>
                ${buildItemMeta(transaction.item_description, transaction.item_lines) ? `<div class="item-subcopy">概览：${escapeHtml(buildItemMeta(transaction.item_description, transaction.item_lines))}</div>` : ''}
                ${canRefundTransaction(transaction) ? `
                    <div class="item-actions">
                        <button data-refund-id="${transaction.id}">退款</button>
                    </div>
                ` : ''}
            </div>
        `).join('') || '<div class="table-item">暂无交易记录</div>';
    }

    function renderTransactionDetail() {
        const detail = state.transactionDetail;
        const transaction = detail && detail.transaction;

        if (!transaction) {
            elements.transactionDetail.innerHTML = '<div class="detail-placeholder">点击交易查看详情</div>';
            return;
        }

        const relationLines = [];
        const refunds = detail.refunds || [];
        const refundSummary = detail.refund_summary || null;
        const itemLinesDetail = renderItemLinesDetail(transaction.item_lines);
        const commissionAmount = Number(transaction.commission_amount || 0);
        const netAmount = Number(transaction.net_amount || 0);
        const actualStoreSettlementAmount = Math.max(0, netAmount - commissionAmount);
        if (detail.intent) {
            relationLines.push(`
                <div class="detail-line">
                    <span>订单 Intent</span>
                    <strong>${escapeHtml(detail.intent.intent_code || '--')}</strong>
                    <em>${formatStatus(detail.intent.status)}</em>
                </div>
            `);
        }
        if (detail.original) {
            relationLines.push(`
                <div class="detail-line">
                    <span>原交易</span>
                    <strong>${escapeHtml(detail.original.tx_code || '--')}</strong>
                    <em>${app.formatDate(detail.original.created_at)}</em>
                </div>
            `);
        }
        if (detail.refund && refunds.length === 0) {
            relationLines.push(`
                <div class="detail-line">
                    <span>最近退款</span>
                    <strong>${escapeHtml(detail.refund.tx_code || '--')}</strong>
                    <em>${app.formatCurrency(detail.refund.final_amount)} · ${app.formatDate(detail.refund.created_at)}</em>
                </div>
            `);
        }
        refunds.forEach((refund, index) => {
            relationLines.push(`
                <div class="detail-line">
                    <span>退款 ${index + 1}</span>
                    <strong>${escapeHtml(refund.tx_code || '--')}</strong>
                    <em>${app.formatCurrency(refund.final_amount)} · ${app.formatDate(refund.created_at)}${refund.refund_reason ? ` · ${escapeHtml(refund.refund_reason)}` : ''}</em>
                </div>
            `);
        });

        elements.transactionDetail.innerHTML = `
            <div class="detail-head">
                <div>
                    <p class="detail-kicker">交易详情</p>
                    <h3>${escapeHtml(transaction.tx_code)}</h3>
                </div>
                <span class="detail-badge" data-state="${escapeHtml(transaction.status || "")}">${formatStatus(transaction.status)}</span>
            </div>
            <div class="detail-grid">
                <div class="detail-field">
                    <label>类型</label>
                    <strong>${formatType(transaction.type)}</strong>
                </div>
                <div class="detail-field">
                    <label>方式</label>
                    <strong>${formatMethod(transaction.method)}</strong>
                </div>
                <div class="detail-field">
                    <label>顾客实付</label>
                    <strong>${app.formatCurrency(transaction.final_amount)}</strong>
                </div>
                <div class="detail-field">
                    <label>净入账</label>
                    <strong>${app.formatCurrency(netAmount)}</strong>
                </div>
                <div class="detail-field">
                    <label>提成</label>
                    <strong>${app.formatCurrency(commissionAmount)}</strong>
                </div>
                <div class="detail-field">
                    <label>店铺实际到账</label>
                    <strong>${app.formatCurrency(actualStoreSettlementAmount)}</strong>
                </div>
                ${refundSummary ? `
                    <div class="detail-field">
                        <label>累计已退</label>
                        <span>${app.formatCurrency(refundSummary.refunded_final_amount || 0)} 顾客 / ${app.formatCurrency(refundSummary.refunded_net_amount || 0)} 入账</span>
                    </div>
                    <div class="detail-field">
                        <label>剩余可退</label>
                        <span>${app.formatCurrency(refundSummary.remaining_final_amount || 0)} 顾客 / ${app.formatCurrency(refundSummary.remaining_net_amount || 0)} 入账</span>
                    </div>
                ` : ''}
                <div class="detail-field">
                    <label>原始金额</label>
                    <strong>${app.formatCurrency(transaction.subtotal_amount)}</strong>
                </div>
                ${buildItemMeta(transaction.item_description, transaction.item_lines) ? `
                    <div class="detail-field">
                        <label>商品概览</label>
                        <span>${escapeHtml(buildItemMeta(transaction.item_description, transaction.item_lines))}</span>
                    </div>
                ` : ''}
                <div class="detail-field">
                    <label>折扣 / 小费 / 手续费 / 税额</label>
                    <span>${app.formatCurrency(transaction.discount_amount)} / ${app.formatCurrency(transaction.tip_amount)} / ${app.formatCurrency(transaction.fee_amount)} / ${app.formatCurrency(transaction.tax_amount || 0)}</span>
                </div>
                <div class="detail-field">
                    <label>店铺</label>
                    <span>${escapeHtml(transaction.store_name_snapshot || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>终端</label>
                    <span>${escapeHtml(transaction.terminal_serial_snapshot || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>收银员</label>
                    <span>${escapeHtml(transaction.cashier_citizenid || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>顾客</label>
                    <span>${escapeHtml(transaction.customer_citizenid || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>操作人</label>
                    <span>${escapeHtml(transaction.processed_by_citizenid || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>时间</label>
                    <span>${app.formatDate(transaction.created_at)}</span>
                </div>
            </div>
            ${relationLines.length ? `<div class="detail-links">${relationLines.join('')}</div>` : ''}
            ${itemLinesDetail}
            ${transaction.type === 'refund' && transaction.refund_reason ? `<div class="detail-note">退款原因：${escapeHtml(transaction.refund_reason)}</div>` : ''}
            ${canRefundTransaction(transaction) ? `
                <div class="detail-actions">
                    <button class="mini-button" data-refund-detail-id="${transaction.id}">退款</button>
                </div>
            ` : ''}
        `;
    }

    async function refreshCustomers() {
        const response = await app.post('getNearbyCustomers');
        if (response.ok) {
            state.payload.nearby_customers = response.data || [];
            renderNearbyCustomers();
            app.setRibbon('附近顾客列表已刷新', 'success');
        }
    }

    async function fetchTransactionDetail(transactionId, silent = false) {
        const response = await app.post('getCashierTransactionDetail', {
            transaction_id: Number(transactionId)
        });

        if (!response.ok) {
            if (!silent) app.setRibbon(response.message || '获取交易详情失败', 'error');
            return;
        }

        state.selectedTransactionId = Number(transactionId);
        state.transactionDetail = response.data || null;
        setTransactionsCollapsed(false);
        renderTransactions();
        renderTransactionDetail();

        if (!silent) {
            app.setRibbon('交易详情已加载', 'success');
        }
    }

    async function refreshTransactions() {
        const response = await app.post('getCashierTransactions', {
            page: 1,
            per_page: 5
        });

        if (!response.ok) {
            app.setRibbon(response.message || '获取交易失败', 'error');
            return;
        }

        state.payload.recent_transactions = response.data.items || [];
        renderTransactions();

        if (state.selectedTransactionId) {
            await fetchTransactionDetail(state.selectedTransactionId, true);
        } else {
            renderTransactionDetail();
        }
    }

    async function createIntent(method) {
        const target = elements.customerSelect.value;
        const preview = computePreview();

        if (!preview.canCharge) {
            app.setRibbon(preview.validationError || '请输入有效金额', 'error');
            return;
        }

        if (method === 'phone' && !target) {
            app.setRibbon('请先选择顾客', 'error');
            return;
        }

        const payload = {
            subtotal_amount: Number(elements.amount.value || 0),
            discount_rate: Number(elements.discount.value || 0),
            tip_amount: Number(elements.tip.value || 0),
            item_description: String(elements.itemDescription.value || '').trim(),
            item_lines: getValidItemLines(),
            method,
            idempotency_key: `${Date.now()}-${Math.random().toString(16).slice(2)}`
        };

        if (method === 'phone') {
            payload.target_source = Number(target);
        }

        const response = await app.post('createIntent', payload);

        if (response.ok) {
            state.payload.active_intent = response.data;
            renderIntent();
            app.setRibbon(response.message || '支付请求已发送', 'success');
        } else {
            app.setRibbon(response.message || '创建订单失败', 'error');
        }
    }

    async function refundTransaction(transactionId) {
        const maxAmount = getRefundableAmount(transactionId);
        if (!(maxAmount > 0)) {
            app.setRibbon('该交易没有可退款金额', 'error');
            return;
        }

        const transaction = findTransaction(transactionId);
        const refundRequest = await app.requestRefund({
            title: '收银退款',
            summary: transaction
                ? `${transaction.tx_code || '当前交易'} 最多可退 ${app.formatCurrency(maxAmount)}。`
                : `请输入退款金额，最多 ${app.formatCurrency(maxAmount)}。`,
            maxAmount,
            initialAmount: maxAmount
        });
        if (!refundRequest) return;

        const response = await app.post('refundFromCashier', {
            transaction_id: Number(transactionId),
            refund_amount: refundRequest.amount,
            reason: refundRequest.reason
        });

        app.setRibbon(response.message || '退款已提交', response.ok ? 'success' : 'error');

        if (response.ok) {
            state.selectedTransactionId = Number(transactionId);
            await refreshTransactions();
        }
    }

    document.getElementById('refresh-customers-button').addEventListener('click', refreshCustomers);
    document.getElementById('refresh-transactions-button').addEventListener('click', refreshTransactions);
    elements.toggleTransactionsButton.addEventListener('click', () => {
        setTransactionsCollapsed(!state.transactionsCollapsed);
    });
    document.getElementById('phone-pay-button').addEventListener('click', () => createIntent('phone'));
    document.getElementById('card-pay-button').addEventListener('click', () => createIntent('card'));
    elements.addItemLine.addEventListener('click', () => {
        const maxItemLines = getMaxItemLines();
        if (state.itemLines.length >= maxItemLines) {
            app.setRibbon(`最多添加 ${maxItemLines} 项商品`, 'error');
            renderItemLineEditor();
            return;
        }

        state.itemLines.push(createEmptyItemLine());
        renderItemLineEditor();
    });
    elements.cancelIntent.addEventListener('click', async () => {
        const response = await app.post('cancelIntent', {});
        app.setRibbon(response.message || '订单已取消', response.ok ? 'success' : 'error');
    });

    elements.amount.addEventListener('input', () => {
        if (!elements.amount.readOnly) {
            state.manualAmount = elements.amount.value;
        }

        computePreview();
    });
    [elements.discount, elements.tip].forEach((input) => {
        input.addEventListener('input', computePreview);
    });

    elements.itemLines.addEventListener('input', (event) => {
        const row = event.target.closest('[data-line-index]');
        const field = event.target.dataset.lineField;
        if (!row || !field) {
            return;
        }

        const index = Number(row.dataset.lineIndex);
        if (!state.itemLines[index]) {
            return;
        }

        state.itemLines[index][field] = event.target.value;
        refreshItemLineEditorState();
    });

    elements.itemLines.addEventListener('click', (event) => {
        const removeButton = event.target.closest('[data-remove-line]');
        if (!removeButton) {
            return;
        }

        const row = removeButton.closest('[data-line-index]');
        const index = row ? Number(row.dataset.lineIndex) : -1;
        if (index < 0) {
            return;
        }

        state.itemLines.splice(index, 1);
        renderItemLineEditor();
    });

    elements.transactions.addEventListener('click', (event) => {
        const refundButton = event.target.closest('[data-refund-id]');
        if (refundButton) {
            refundTransaction(refundButton.dataset.refundId);
            return;
        }

        const item = event.target.closest('[data-cashier-transaction-id]');
        if (item) {
            fetchTransactionDetail(item.dataset.cashierTransactionId);
        }
    });

    elements.transactionDetail.addEventListener('click', (event) => {
        const refundButton = event.target.closest('[data-refund-detail-id]');
        if (refundButton) {
            refundTransaction(refundButton.dataset.refundDetailId);
        }
    });

    window.VancePayCashier = {
        render(payload) {
            payload = payload || {};
            const nextSessionKey = `${payload.store && payload.store.id || 0}:${payload.terminal && payload.terminal.id || 0}`;
            if (nextSessionKey !== state.sessionKey) {
                state.sessionKey = nextSessionKey;
                state.selectedTransactionId = null;
                state.transactionDetail = null;
                resetComposer();
                setTransactionsCollapsed(true);
            }
            state.payload = payload;
            syncPaymentInputLimits();
            elements.storeName.textContent = payload.store ? payload.store.name : 'POS';
            elements.terminalMeta.textContent = payload.terminal
                ? `${payload.terminal.serial_number} · ${payload.terminal.type}`
                : '终端未绑定';
            renderNearbyCustomers();
            renderOverview();
            renderIntent();
            renderTransactions();
            renderTransactionDetail();
            renderItemLineEditor();
            computePreview();
            setTransactionsCollapsed(state.transactionsCollapsed);
        }
    };
})();
