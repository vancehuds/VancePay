(function () {
    const app = window.VancePayApp;
    const state = {
        intent: null,
        cardSwipeIntent: null,
        intervalId: null,
        cardSwipeIntervalId: null,
        pendingAction: false
    };

    const elements = {
        storeName: document.getElementById('customer-store-name'),
        statusCopy: document.getElementById('customer-status-copy'),
        subtotal: document.getElementById('customer-subtotal'),
        discount: document.getElementById('customer-discount'),
        tip: document.getElementById('customer-tip'),
        fee: document.getElementById('customer-fee'),
        tax: document.getElementById('customer-tax'),
        balanceAfter: document.getElementById('customer-balance-after'),
        total: document.getElementById('customer-total'),
        itemDescriptionNote: document.getElementById('customer-item-description-note'),
        itemLines: document.getElementById('customer-item-lines'),
        methodLabel: document.getElementById('customer-method-label'),
        countdown: document.getElementById('customer-countdown'),
        confirmButton: document.getElementById('confirm-payment-button'),
        declineButton: document.getElementById('decline-payment-button'),
        cardSwipeStoreName: document.getElementById('card-swipe-store-name'),
        cardSwipeSummary: document.getElementById('card-swipe-summary'),
        cardSwipeAmount: document.getElementById('card-swipe-amount'),
        cardSwipeTerminal: document.getElementById('card-swipe-terminal'),
        cardSwipeQueue: document.getElementById('card-swipe-queue'),
        cardSwipeHelper: document.getElementById('card-swipe-helper'),
        cardSwipeCountdown: document.getElementById('card-swipe-countdown')
    };

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatQuantity(value) {
        const amount = Number(value || 0);
        if (Number.isInteger(amount)) {
            return String(amount);
        }

        return amount.toFixed(3).replace(/\.?0+$/, '');
    }

    function renderItemLines(itemLines) {
        if (!Array.isArray(itemLines) || !itemLines.length) {
            elements.itemLines.classList.add('hidden');
            elements.itemLines.innerHTML = '';
            return;
        }

        elements.itemLines.classList.remove('hidden');
        elements.itemLines.innerHTML = `
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

    function formatStatus(status) {
        return {
            awaiting_customer: '等待确认',
            awaiting_swipe: '等待刷卡',
            completed: '已完成',
            cancelled: '已取消',
            expired: '已超时',
            failed: '失败'
        }[status] || status || '等待处理';
    }

    function formatRemaining(seconds) {
        const remaining = Math.max(0, Number(seconds || 0));
        if (remaining >= 3600) {
            return `${Math.floor(remaining / 3600)}h ${Math.floor((remaining % 3600) / 60)}m`;
        }

        if (remaining >= 60) {
            return `${Math.floor(remaining / 60)}m ${remaining % 60}s`;
        }

        return `${remaining}s`;
    }

    function parseExpiresAtMs(value) {
        if (!value) {
            return null;
        }

        if (typeof value === 'number') {
            return value > 1000000000000 ? value : value * 1000;
        }

        if (typeof value === 'string') {
            const numericValue = Number(value);
            if (Number.isFinite(numericValue) && value.trim() !== '') {
                return numericValue > 1000000000000 ? numericValue : numericValue * 1000;
            }

            const normalized = value.replace(' ', 'T');
            const parsed = Date.parse(normalized);
            return Number.isFinite(parsed) ? parsed : null;
        }

        if (typeof value === 'object') {
            const year = Number(value.year);
            const month = Number(value.month);
            const day = Number(value.day);
            const hour = Number(value.hour || 0);
            const minute = Number(value.min || value.minute || 0);
            const second = Number(value.sec || value.second || 0);

            if ([year, month, day, hour, minute, second].every(Number.isFinite)) {
                return new Date(year, month - 1, day, hour, minute, second).getTime();
            }
        }

        return null;
    }

    function getIntentKey(intent) {
        return intent ? String(intent.intent_id || intent.id || '') : '';
    }

    function normalizeExpiry(intent, previousIntent) {
        if (!intent) {
            return;
        }

        const expiresAtMs = parseExpiresAtMs(intent.expires_at);
        if (expiresAtMs) {
            intent._expiresAtMs = expiresAtMs;
            return;
        }

        const previousExpiresAtMs = previousIntent && previousIntent._expiresAtMs;
        if (previousExpiresAtMs && getIntentKey(intent) === getIntentKey(previousIntent)) {
            intent._expiresAtMs = previousExpiresAtMs;
            return;
        }

        const expiresIn = Number(intent.expires_in);
        if (Number.isFinite(expiresIn)) {
            intent._expiresAtMs = Date.now() + (Math.max(0, expiresIn) * 1000);
        }
    }

    function getRemainingSeconds(intent) {
        if (!intent) {
            return null;
        }

        const expiresAtMs = intent._expiresAtMs || parseExpiresAtMs(intent.expires_at);
        if (!expiresAtMs) {
            return null;
        }

        return Math.max(0, Math.floor((expiresAtMs - Date.now()) / 1000));
    }

    function updateCountdown() {
        const remaining = getRemainingSeconds(state.intent);
        if (remaining == null) {
            elements.countdown.textContent = '等待处理';
            return;
        }

        elements.countdown.textContent = remaining > 0 ? `剩余 ${formatRemaining(remaining)}` : '订单即将过期';
    }

    function updateCardSwipeCountdown() {
        const remaining = getRemainingSeconds(state.cardSwipeIntent);
        if (remaining == null) {
            elements.cardSwipeCountdown.textContent = '等待刷卡';
            return;
        }

        elements.cardSwipeCountdown.textContent = remaining > 0 ? `剩余 ${formatRemaining(remaining)}` : '订单即将过期';
    }

    function updateButtons() {
        const finalAmount = state.intent ? app.formatCurrency(state.intent.final_amount) : '$0.00';
        const isFinished = Boolean(state.intent && ['completed', 'cancelled', 'expired', 'failed'].includes(state.intent.status));

        elements.confirmButton.textContent = state.pendingAction
            ? '处理中...'
            : (state.intent && state.intent.method === 'card'
                ? `刷卡支付 ${finalAmount}`
                : `支付 ${finalAmount}`);
        elements.confirmButton.disabled = state.pendingAction || isFinished;
        elements.declineButton.disabled = state.pendingAction || isFinished;
    }

    async function submitDecision(endpoint) {
        if (!state.intent || state.pendingAction) return;

        state.pendingAction = true;
        updateButtons();

        try {
            const response = await app.post(endpoint, {});
            if (response.ok) {
                state.intent.status = endpoint === 'confirmPayment' ? 'completed' : 'cancelled';
                elements.statusCopy.textContent = endpoint === 'confirmPayment' ? '支付已确认' : '请求已拒绝';
            }

            app.setRibbon(response.message || '请求已提交', response.ok ? 'success' : 'error');
        } finally {
            state.pendingAction = false;
            updateButtons();
        }
    }

    elements.confirmButton.addEventListener('click', () => submitDecision('confirmPayment'));
    elements.declineButton.addEventListener('click', () => submitDecision('declinePayment'));

    window.VancePayCustomer = {
        render(payload) {
            const previousIntent = state.intent;
            state.intent = payload.intent || null;
            normalizeExpiry(state.intent, previousIntent);
            if (!state.intent) return;

            elements.storeName.textContent = state.intent.store_name || '待支付';
            elements.statusCopy.textContent = state.intent.message || formatStatus(state.intent.status);
            elements.subtotal.textContent = app.formatCurrency(state.intent.subtotal_amount);
            elements.discount.textContent = `- ${app.formatCurrency(state.intent.discount_amount)}`;
            elements.tip.textContent = `+ ${app.formatCurrency(state.intent.tip_amount)}`;
            elements.fee.textContent = `+ ${app.formatCurrency(state.intent.fee_amount)}`;
            elements.tax.textContent = `+ ${app.formatCurrency(state.intent.tax_amount || 0)}`;
            elements.balanceAfter.textContent = app.formatCurrency(state.intent.balance_after_preview);
            elements.total.textContent = app.formatCurrency(state.intent.final_amount);
            elements.itemDescriptionNote.textContent = state.intent.item_description ? `订单说明：${state.intent.item_description}` : '';
            elements.itemDescriptionNote.classList.toggle('hidden', !state.intent.item_description);
            renderItemLines(state.intent.item_lines);
            elements.methodLabel.textContent = state.intent.method === 'card' ? '刷卡支付' : '手机支付';
            state.pendingAction = false;
            updateButtons();

            clearInterval(state.intervalId);
            updateCountdown();
            state.intervalId = window.setInterval(updateCountdown, 1000);
        },
        renderCardSwipeOverlay(payload) {
            const previousIntent = state.cardSwipeIntent;
            state.cardSwipeIntent = payload || null;
            normalizeExpiry(state.cardSwipeIntent, previousIntent);
            if (!state.cardSwipeIntent) {
                return;
            }

            elements.cardSwipeStoreName.textContent = state.cardSwipeIntent.store_name || '现场刷卡';
            elements.cardSwipeSummary.textContent = state.cardSwipeIntent.summary || '附近任意持卡人都可以完成付款';
            elements.cardSwipeAmount.textContent = app.formatCurrency(state.cardSwipeIntent.final_amount || 0);
            elements.cardSwipeTerminal.textContent = state.cardSwipeIntent.terminal_serial_number || '当前 POS';
            elements.cardSwipeQueue.textContent = state.cardSwipeIntent.queue_text || '等待附近持卡人响应';
            elements.cardSwipeHelper.textContent = state.cardSwipeIntent.helper_text || '按 E 刷卡支付';

            clearInterval(state.cardSwipeIntervalId);
            updateCardSwipeCountdown();
            state.cardSwipeIntervalId = window.setInterval(updateCardSwipeCountdown, 1000);
        },
        hideCardSwipeOverlay() {
            state.cardSwipeIntent = null;
            clearInterval(state.cardSwipeIntervalId);
            state.cardSwipeIntervalId = null;
        }
    };
})();
