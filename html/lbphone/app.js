const state = {
    balance: 0,
    bankBalance: 0,
    balanceSummary: {},
    balanceHistory: [],
    balanceHistoryPage: 1,
    balanceHistoryPerPage: 20,
    balanceHistoryTotal: 0,
    balanceHistoryTotalPages: 1,
    balanceHistoryHasMore: false,
    loans: {},
    selectedLoanId: null,
    currency: "$",
    intents: [],
    activity: [],
    activityPage: 1,
    activityPerPage: 12,
    activityTotal: 0,
    activityTotalPages: 1,
    activityHasMore: false,
    selectedIntentId: null,
    activeView: "requests",
    pendingAction: false,
    pendingWithdraw: false,
    pendingLoanRequest: false,
    pendingLoanRepay: false,
    pendingSync: false,
    renderedViews: {
        requests: false,
        balance: false,
        loans: false,
        activity: false,
    },
    dirtyViews: {
        requests: true,
        balance: true,
        loans: true,
        activity: true,
    },
};

let bridgeListenersBound = false;
let initialStateRequested = false;

const elements = {
    syncPill: document.getElementById("sync-pill"),
    balanceValue: document.getElementById("balance-value"),
    pendingBalance: document.getElementById("pending-balance"),
    bankBalance: document.getElementById("bank-balance"),
    pendingCount: document.getElementById("pending-count"),
    loanCreditLimit: document.getElementById("loan-credit-limit"),
    refreshButton: document.getElementById("refresh-button"),
    detailPanel: document.getElementById("detail-panel"),
    detailStore: document.getElementById("detail-store"),
    detailLine: document.getElementById("detail-line"),
    detailAmount: document.getElementById("detail-amount"),
    detailSummary: document.getElementById("detail-summary"),
    detailBreakdown: document.getElementById("detail-breakdown"),
    confirmButton: document.getElementById("confirm-button"),
    declineButton: document.getElementById("decline-button"),
    requestList: document.getElementById("request-list"),
    requestsEmpty: document.getElementById("requests-empty"),
    requestsCounter: document.getElementById("requests-counter"),
    balanceSummaryGrid: document.getElementById("balance-summary-grid"),
    balanceHistoryList: document.getElementById("balance-history-list"),
    balanceHistoryEmpty: document.getElementById("balance-history-empty"),
    balanceHistoryCounter: document.getElementById("balance-history-counter"),
    balanceHistorySubcopy: document.getElementById("balance-history-subcopy"),
    balanceHistoryPagination: document.getElementById("balance-history-pagination"),
    balanceHistoryPrevButton: document.getElementById("balance-history-prev-button"),
    balanceHistoryNextButton: document.getElementById("balance-history-next-button"),
    balanceHistoryPageStatus: document.getElementById("balance-history-page-status"),
    withdrawNote: document.getElementById("withdraw-note"),
    withdrawAmount: document.getElementById("withdraw-amount"),
    withdrawAllButton: document.getElementById("withdraw-all-button"),
    withdrawButton: document.getElementById("withdraw-button"),
    loanEligibility: document.getElementById("loan-eligibility"),
    loanTrustScore: document.getElementById("loan-trust-score"),
    loanTrustBand: document.getElementById("loan-trust-band"),
    loanAvailableLimit: document.getElementById("loan-available-limit"),
    loanRate: document.getElementById("loan-rate"),
    loanOutstanding: document.getElementById("loan-outstanding"),
    loanDueSummary: document.getElementById("loan-due-summary"),
    loanFactorList: document.getElementById("loan-factor-list"),
    loanApplyNote: document.getElementById("loan-apply-note"),
    loanAmount: document.getElementById("loan-amount"),
    loanTerm: document.getElementById("loan-term"),
    loanInterestPreview: document.getElementById("loan-interest-preview"),
    loanTotalPreview: document.getElementById("loan-total-preview"),
    loanRequestButton: document.getElementById("loan-request-button"),
    loanRepayTitle: document.getElementById("loan-repay-title"),
    loanRepayNote: document.getElementById("loan-repay-note"),
    loanRepayAmount: document.getElementById("loan-repay-amount"),
    loanRepayAllButton: document.getElementById("loan-repay-all-button"),
    loanRepayButton: document.getElementById("loan-repay-button"),
    loanEmpty: document.getElementById("loan-empty"),
    loanCounter: document.getElementById("loan-counter"),
    loanList: document.getElementById("loan-list"),
    activityList: document.getElementById("activity-list"),
    activityEmpty: document.getElementById("activity-empty"),
    activityCounter: document.getElementById("activity-counter"),
    activityPagination: document.getElementById("activity-pagination"),
    activityPrevButton: document.getElementById("activity-prev-button"),
    activityNextButton: document.getElementById("activity-next-button"),
    activityPageStatus: document.getElementById("activity-page-status"),
    toast: document.getElementById("toast"),
};

const tabButtons = Array.from(document.querySelectorAll(".nav-item, .tab-button"));
const viewPanels = Array.from(document.querySelectorAll("[data-view-panel]"));

const normalizeList = (value) => {
    if (Array.isArray(value)) {
        return value;
    }

    if (value && typeof value === "object") {
        return Object.values(value);
    }

    return [];
};

const normalizePagedResult = (value, fallbackPage = 1, fallbackPerPage = 10) => {
    const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
    const items = normalizeList(Array.isArray(value) ? value : (Object.prototype.hasOwnProperty.call(source, "items") ? source.items : value));
    const page = Math.max(1, Number(source.page || fallbackPage || 1));
    const perPage = Math.max(1, Number(source.per_page || fallbackPerPage || items.length || 1));
    const total = Math.max(0, Number(source.total != null ? source.total : items.length));
    const totalPages = Math.max(1, Number(source.total_pages || Math.ceil(total / perPage) || 1));

    return {
        items,
        page,
        perPage,
        total,
        totalPages,
        hasPrev: source.has_prev === true || page > 1,
        hasMore: source.has_more === true || page < totalPages,
    };
};

const currency = (value) => {
    const amount = Number(value || 0);
    const absolute = Math.abs(amount).toFixed(2);
    return `${state.currency}${absolute}`;
};

const signedCurrency = (value) => {
    const amount = Number(value || 0);
    return `${amount >= 0 ? "+" : "-"}${currency(amount)}`;
};

const relativeTime = (value) => {
    const seconds = Math.max(0, Number(value || 0));
    if (seconds >= 86400) {
        return `${Math.floor(seconds / 86400)}d ${Math.floor((seconds % 86400) / 3600)}h`;
    }

    if (seconds >= 3600) {
        return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
    }

    if (seconds >= 60) {
        return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
    }

    return `${seconds}s`;
};

const formatQuantity = (value) => {
    const amount = Number(value || 0);
    if (Number.isInteger(amount)) {
        return String(amount);
    }

    return amount.toFixed(3).replace(/\.?0+$/, "");
};

const buildItemMeta = (itemDescription, itemLines) => {
    const description = String(itemDescription || "").trim();
    if (description) {
        return description;
    }

    if (!Array.isArray(itemLines) || !itemLines.length) {
        return "";
    }

    const parts = itemLines.slice(0, 2).map((line) => `${line.name || "商品"} x${formatQuantity(line.quantity)}`);
    if (itemLines.length > 2) {
        parts.push(`等 ${itemLines.length} 项`);
    }

    return parts.join(" · ");
};

const formatDateTime = (value) => {
    if (!value) {
        return "刚刚";
    }

    const normalized = String(value).replace(" ", "T");
    const date = new Date(normalized);
    if (Number.isNaN(date.getTime())) {
        return value;
    }

    return new Intl.DateTimeFormat("zh-CN", {
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
    }).format(date);
};

const formatStatus = (value) => {
    const normalized = String(value || "").toLowerCase();
    const labels = {
        completed: "已完成",
        refunded: "已退款",
        cancelled: "已取消",
        expired: "已过期",
        failed: "失败",
        pending: "处理中",
        partially_refunded: "部分退款",
    };

    return labels[normalized] || (value ? String(value) : "已完成");
};

const formatTrustBand = (value) => {
    const labels = {
        excellent: "卓越",
        stable: "稳定",
        watch: "观察",
        high_risk: "高风险",
    };

    return labels[String(value || "").toLowerCase()] || "未评估";
};

const formatLoanStatus = (loan) => {
    const status = String(loan?.status || "").toLowerCase();
    if (status === "active" && loan?.is_overdue) {
        return "已逾期";
    }

    const labels = {
        active: "还款中",
        paid: "已结清",
        defaulted: "已违约",
        cancelled: "已取消",
    };

    return labels[status] || "贷款记录";
};

const formatLoanDue = (loan) => {
    if (!loan || String(loan.status || "").toLowerCase() !== "active") {
        return loan?.repaid_at ? `结清 ${formatDateTime(loan.repaid_at)}` : formatDateTime(loan?.created_at);
    }

    if (loan.is_overdue) {
        return `逾期 · 到期 ${formatDateTime(loan.due_at)}`;
    }

    return `剩余 ${relativeTime(loan.due_in)} · 到期 ${formatDateTime(loan.due_at)}`;
};

const getInitials = (value) => {
    const text = String(value || "").trim();
    if (!text) {
        return "VP";
    }

    return Array.from(text).slice(0, 2).join("").toUpperCase();
};

const escapeHtml = (value) =>
    String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");

const showToast = (message) => {
    elements.toast.textContent = message;
    elements.toast.hidden = false;
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => {
        elements.toast.hidden = true;
    }, 2200);
};

const setSyncState = (label, status = "loading") => {
    elements.syncPill.textContent = label;
    elements.syncPill.dataset.state = status;
};

const getSelectedIntent = () =>
    state.intents.find((intent) => String(intent.intent_id) === String(state.selectedIntentId)) || null;

const ensureSelectedIntent = () => {
    if (!state.intents.length) {
        state.selectedIntentId = null;
        return;
    }

    if (!getSelectedIntent()) {
        state.selectedIntentId = state.intents[0].intent_id;
    }
};

const getLoanState = () => state.loans && typeof state.loans === "object" ? state.loans : {};

const getLoanItems = () => normalizeList(getLoanState().items);

const getActiveLoans = () =>
    getLoanItems().filter((loan) => String(loan.status || "").toLowerCase() === "active");

const getLoanRequestUnavailableReason = (offer) => {
    offer = offer || {};
    const availableAmount = Number(offer.available_amount || 0);
    const minAmount = Number(offer.min_amount || 0);

    if (!offer.eligible) {
        return offer.reason || "当前不可申请贷款";
    }

    if (!(availableAmount >= minAmount)) {
        return `当前可借额度低于最低贷款 ${currency(minAmount)}`;
    }

    return "";
};

const getSelectedLoan = () => {
    const activeLoans = getActiveLoans();
    if (!activeLoans.length) {
        return null;
    }

    return activeLoans.find((loan) => String(loan.id) === String(state.selectedLoanId)) || activeLoans[0];
};

const ensureSelectedLoan = () => {
    const activeLoans = getActiveLoans();
    if (!activeLoans.length) {
        state.selectedLoanId = null;
        return;
    }

    if (!activeLoans.some((loan) => String(loan.id) === String(state.selectedLoanId))) {
        state.selectedLoanId = activeLoans[0].id;
    }
};

const getEntryAvailabilityStatus = (entry, availableIn = entry?.available_in) => {
    if (!entry) {
        return "available";
    }

    const seconds = Math.max(0, Number(availableIn || 0));
    if (entry.entry_type === "withdrawal") {
        return "withdrawn";
    }

    if (seconds > 0) {
        return Number(entry.amount || 0) < 0 ? "pending_reversal" : "pending";
    }

    if (entry.entry_type === "commission_refund") {
        return "reversed";
    }

    return "available";
};

const formatBalanceEntryType = (entry) => {
    const labels = {
        commission: "收款提成",
        commission_refund: "提成冲回",
        withdrawal: "余额提现",
    };

    return labels[String(entry?.entry_type || "").toLowerCase()] || "余额流水";
};

const formatBalanceEntryStatus = (entry) => {
    const status = String(entry?.availability_status || getEntryAvailabilityStatus(entry)).toLowerCase();
    if (status === "pending") {
        return `待解锁 · ${relativeTime(entry.available_in)}`;
    }

    if (status === "pending_reversal") {
        return `待冲回 · ${relativeTime(entry.available_in)}`;
    }

    if (status === "withdrawn") {
        return "已提现";
    }

    if (status === "reversed") {
        return "已冲回";
    }

    return "可提现";
};

const getBalanceEntryTone = (entry) => {
    const amount = Number(entry?.amount || 0);
    if (amount > 0) {
        return "positive";
    }

    if (amount < 0) {
        return "negative";
    }

    return "neutral";
};

const formatNextUnlockNote = (summary) => {
    const pendingBalance = Number(summary?.pending_balance || 0);
    const nextUnlockIn = Math.max(0, Number(summary?.next_unlock_in || 0));
    if (!(pendingBalance > 0)) {
        return "当前没有待解锁提成。";
    }

    if (nextUnlockIn > 0) {
        return `下一笔余额约 ${relativeTime(nextUnlockIn)} 后解锁。`;
    }

    return "有提成即将解锁，刷新后可提现。";
};

const setPagerState = (pagination, prevButton, nextButton, statusLabel, page, totalPages, hasMore, pendingSync) => {
    if (!pagination || !prevButton || !nextButton || !statusLabel) {
        return;
    }

    const safePage = Math.max(1, Number(page || 1));
    const safeTotalPages = Math.max(1, Number(totalPages || 1));
    pagination.hidden = safeTotalPages <= 1;
    statusLabel.textContent = `第 ${safePage} / ${safeTotalPages} 页`;
    prevButton.disabled = pendingSync || safePage <= 1;
    nextButton.disabled = pendingSync || !hasMore;
};

const buildStateRequest = (overrides = {}) => ({
    activity_page: Math.max(1, Number(overrides.activity_page || state.activityPage || 1)),
    activity_per_page: Math.max(1, Number(overrides.activity_per_page || state.activityPerPage || 12)),
    balance_history_page: Math.max(1, Number(overrides.balance_history_page || state.balanceHistoryPage || 1)),
    balance_history_per_page: Math.max(1, Number(overrides.balance_history_per_page || state.balanceHistoryPerPage || 20)),
});

const renderSummary = () => {
    const summary = state.balanceSummary || {};
    const withdrawableBalance = Number(summary.withdrawable_balance || state.balance || 0);
    const pendingBalance = Number(summary.pending_balance || 0);

    elements.balanceValue.textContent = currency(withdrawableBalance);
    elements.pendingBalance.textContent = currency(pendingBalance);
    elements.bankBalance.textContent = currency(state.bankBalance);
    elements.pendingCount.textContent = String(state.intents.length);
    elements.loanCreditLimit.textContent = currency(getLoanState()?.offer?.available_amount || 0);
};

const renderDetail = () => {
    const selectedIntent = getSelectedIntent();
    if (!selectedIntent) {
        elements.detailPanel.hidden = true;
        elements.confirmButton.textContent = "支付 $0.00";
        return;
    }

    const description = buildItemMeta(selectedIntent.item_description, selectedIntent.item_lines);
    const expiresSoon = Number(selectedIntent.expires_in || 0) <= 90;
    const rows = [];
    const itemLines = Array.isArray(selectedIntent.item_lines) ? selectedIntent.item_lines : [];

    elements.detailPanel.hidden = false;
    elements.detailStore.textContent = selectedIntent.store_name || "VancePay";
    elements.detailLine.textContent = description || "确认后会从你的银行卡余额中扣款。";
    elements.detailAmount.textContent = currency(selectedIntent.final_amount);
    elements.detailSummary.innerHTML = [
        {
            label: `订单号 ${selectedIntent.intent_code || selectedIntent.intent_id}`,
            tone: "",
        },
        {
            label: "手机支付",
            tone: "",
        },
        {
            label: `银行卡余额 ${currency(selectedIntent.current_balance)}`,
            tone: "",
        },
        {
            label: `剩余 ${relativeTime(selectedIntent.expires_in)}`,
            tone: expiresSoon ? "alert" : "",
        },
    ]
        .map(
            (pill) => `
                <span class="summary-pill ${pill.tone ? `summary-pill-${pill.tone}` : ""}">
                    ${escapeHtml(pill.label)}
                </span>
            `
        )
        .join("");

    rows.push(["商品金额", currency(selectedIntent.subtotal_amount)]);

    itemLines.forEach((line, index) => {
        rows.push([
            `商品 ${index + 1}`,
            `${line.name || "商品"} x${formatQuantity(line.quantity)} · ${currency(line.line_total || (Number(line.quantity || 0) * Number(line.unit_price || 0)))}`,
        ]);
    });

    if (Number(selectedIntent.discount_amount || 0) > 0 || Number(selectedIntent.discount_rate || 0) > 0) {
        rows.push([
            "折扣",
            `${Number(selectedIntent.discount_rate || 0).toFixed(2)}% (-${currency(selectedIntent.discount_amount)})`,
        ]);
    }

    if (Number(selectedIntent.tip_amount || 0) > 0) {
        rows.push(["小费", currency(selectedIntent.tip_amount)]);
    }

    if (Number(selectedIntent.fee_amount || 0) > 0) {
        rows.push(["手续费", currency(selectedIntent.fee_amount)]);
    }

    if (Number(selectedIntent.tax_amount || 0) > 0) {
        rows.push(["税额", currency(selectedIntent.tax_amount)]);
    }

    rows.push(["付款后银行卡余额", currency(selectedIntent.balance_after_preview)]);

    elements.detailBreakdown.innerHTML = rows
        .map(
            ([label, value]) => `
                <div class="detail-row">
                    <span>${escapeHtml(label)}</span>
                    <strong>${escapeHtml(value)}</strong>
                </div>
            `
        )
        .join("");

    elements.confirmButton.disabled = state.pendingAction;
    elements.declineButton.disabled = state.pendingAction;
    elements.confirmButton.textContent = state.pendingAction
        ? "处理中..."
        : `支付 ${currency(selectedIntent.final_amount)}`;
};

const renderRequests = () => {
    ensureSelectedIntent();
    elements.requestsCounter.textContent = `${state.intents.length} 笔`;

    if (!state.intents.length) {
        elements.requestList.innerHTML = "";
        elements.requestsEmpty.hidden = false;
        renderDetail();
        return;
    }

    elements.requestsEmpty.hidden = true;
    elements.requestList.innerHTML = state.intents
        .map((intent) => {
            const isActive = String(intent.intent_id) === String(state.selectedIntentId);
            const expiresSoon = Number(intent.expires_in || 0) <= 90;
            const storeName = intent.store_name || "VancePay";
            const metaParts = [
                `订单号 ${intent.intent_code || intent.intent_id}`,
                buildItemMeta(intent.item_description, intent.item_lines),
            ].filter(Boolean);

            return `
                <article class="request-card ${isActive ? "active" : ""} ${expiresSoon ? "urgent" : ""}" data-intent-id="${escapeHtml(intent.intent_id)}">
                    <div class="request-avatar">${escapeHtml(getInitials(storeName))}</div>
                    <div class="request-body">
                        <div class="request-topline">
                            <div>
                                <div class="request-title">${escapeHtml(storeName)}</div>
                                <p class="request-meta">${escapeHtml(metaParts.join(" · ") || "等待你确认")}</p>
                            </div>
                            <div class="request-amount">${currency(intent.final_amount)}</div>
                        </div>

                        <div class="request-bottomline">
                            <span class="status-badge ${expiresSoon ? "urgent" : ""}">剩余 ${escapeHtml(relativeTime(intent.expires_in))}</span>
                            <span class="method-badge">手机支付</span>
                            <span class="meta-chip">扣款后 ${escapeHtml(currency(intent.balance_after_preview))}</span>
                        </div>
                    </div>
                </article>
            `;
        })
        .join("");

    renderDetail();
};

const renderBalance = () => {
    const summary = state.balanceSummary || {};
    const withdrawableBalance = Number(summary.withdrawable_balance || 0);
    const pendingBalance = Number(summary.pending_balance || 0);
    const totalBalance = Number(summary.total_balance || 0);
    const lifetimeCommissionAmount = Number(summary.lifetime_commission_amount || 0);
    const lifetimeReversedAmount = Number(summary.lifetime_reversed_amount || 0);
    const lifetimeWithdrawnAmount = Number(summary.lifetime_withdrawn_amount || 0);

    const summaryItems = [
        {
            label: "可提现",
            value: currency(withdrawableBalance),
            note: withdrawableBalance > 0 ? "现在可转入银行卡" : "暂无可提现金额",
        },
        {
            label: "待解锁",
            value: currency(pendingBalance),
            note: formatNextUnlockNote(summary),
        },
        {
            label: "账本总额",
            value: currency(totalBalance),
            note: "包含已解锁与锁定中的提成",
        },
        {
            label: "累计产生",
            value: currency(lifetimeCommissionAmount),
            note: "已写入 VancePay 余额的提成",
        },
        {
            label: "累计冲回",
            value: currency(lifetimeReversedAmount),
            note: "退款导致的提成冲回",
        },
        {
            label: "累计提现",
            value: currency(lifetimeWithdrawnAmount),
            note: "已转入银行卡的金额",
        },
    ];

    elements.balanceSummaryGrid.innerHTML = summaryItems
        .map(
            (item) => `
                <article class="balance-card">
                    <span class="card-label">${escapeHtml(item.label)}</span>
                    <strong>${escapeHtml(item.value)}</strong>
                    <p class="card-note">${escapeHtml(item.note)}</p>
                </article>
            `
        )
        .join("");

    elements.balanceHistoryCounter.textContent = `${Math.max(state.balanceHistoryTotal, state.balanceHistory.length)} 条`;
    elements.balanceHistorySubcopy.textContent = pendingBalance > 0
        ? formatNextUnlockNote(summary)
        : "等待新的提成入账";
    setPagerState(
        elements.balanceHistoryPagination,
        elements.balanceHistoryPrevButton,
        elements.balanceHistoryNextButton,
        elements.balanceHistoryPageStatus,
        state.balanceHistoryPage,
        state.balanceHistoryTotalPages,
        state.balanceHistoryHasMore,
        state.pendingSync
    );

    elements.withdrawNote.textContent = withdrawableBalance > 0
        ? `当前可提现 ${currency(withdrawableBalance)} 到你的银行卡。${pendingBalance > 0 ? ` 另有 ${currency(pendingBalance)} 正在锁定中。` : ""}`
        : pendingBalance > 0
            ? `当前没有可提现余额。已有 ${currency(pendingBalance)} 进入锁定，满 24 小时后可提现。`
            : "当前没有可提现余额。完成收款提成后会自动累计到这里。";

    elements.withdrawButton.disabled = state.pendingWithdraw || !(withdrawableBalance > 0);
    elements.withdrawAllButton.disabled = state.pendingWithdraw || !(withdrawableBalance > 0);
    elements.withdrawButton.textContent = state.pendingWithdraw ? "处理中..." : "提现";

    if (!state.balanceHistory.length) {
        elements.balanceHistoryList.innerHTML = "";
        elements.balanceHistoryEmpty.hidden = false;
        return;
    }

    elements.balanceHistoryEmpty.hidden = true;
    elements.balanceHistoryList.innerHTML = state.balanceHistory
        .map((entry) => {
            const tone = getBalanceEntryTone(entry);
            const title = entry.entry_type === "withdrawal"
                ? "提现到银行卡"
                : (entry.store_name_snapshot || formatBalanceEntryType(entry));
            const metaParts = [
                formatBalanceEntryType(entry),
                formatDateTime(entry.created_at),
                entry.reference_code ? `流水 ${entry.reference_code}` : "",
                entry.related_reference_code ? `关联 ${entry.related_reference_code}` : "",
            ].filter(Boolean);

            return `
                <article class="activity-card balance-entry-card ${tone}">
                    <div class="activity-avatar ${tone === "positive" ? "positive" : "negative"}">${escapeHtml(entry.entry_type === "withdrawal" ? "提" : (tone === "positive" ? "佣" : "退"))}</div>
                    <div class="activity-content">
                        <div class="activity-topline balance-entry-head">
                            <div>
                                <div class="activity-title">${escapeHtml(title)}</div>
                                <p class="activity-subline">${escapeHtml(metaParts.join(" · "))}</p>
                            </div>
                            <div class="activity-side">
                                <div class="activity-amount ${tone === "positive" ? "positive" : "negative"}">${escapeHtml(signedCurrency(entry.amount))}</div>
                                <div class="activity-status">${escapeHtml(formatBalanceEntryStatus(entry))}</div>
                            </div>
                        </div>

                        <div class="activity-meta">
                            ${entry.description ? `<span class="meta-chip">${escapeHtml(entry.description)}</span>` : ""}
                            ${entry.available_at ? `<span class="meta-chip">${escapeHtml(`解锁 ${formatDateTime(entry.available_at)}`)}</span>` : ""}
                        </div>
                    </div>
                </article>
            `;
        })
        .join("");
};

const renderLoanTermOptions = (terms) => {
    const currentValue = Number(elements.loanTerm.value || 0);
    const normalizedTerms = normalizeList(terms)
        .map((term) => Number(term || 0))
        .filter((term) => term > 0);

    elements.loanTerm.innerHTML = normalizedTerms.length
        ? normalizedTerms
            .map((term) => `<option value="${term}">${term} 天</option>`)
            .join("")
        : '<option value="">暂无期限</option>';

    if (normalizedTerms.includes(currentValue)) {
        elements.loanTerm.value = String(currentValue);
    }
};

const renderLoans = () => {
    const loanState = getLoanState();
    const trust = loanState.trust || {};
    const offer = loanState.offer || {};
    const summary = loanState.summary || {};
    const loanItems = getLoanItems();
    const selectedLoan = getSelectedLoan();
    const availableAmount = Number(offer.available_amount || 0);
    const minAmount = Number(offer.min_amount || 0);
    const interestRate = Number(offer.interest_rate || 0);
    const requestedAmount = Number(elements.loanAmount.value || 0);
    const previewBase = offer.eligible ? Math.max(0, Math.min(requestedAmount, availableAmount)) : 0;
    const previewInterest = Math.round((previewBase * interestRate + 0.0001)) / 100;
    const previewTotal = previewBase + previewInterest;

    ensureSelectedLoan();
    renderLoanTermOptions(offer.term_days || []);
    const requestUnavailableReason = getLoanRequestUnavailableReason(offer);

    elements.loanEligibility.textContent = offer.reason || (offer.eligible ? "可申请" : "不可申请");
    elements.loanTrustScore.textContent = trust.available ? String(Math.round(Number(trust.score || 0))) : "--";
    elements.loanTrustBand.textContent = trust.available
        ? `${formatTrustBand(trust.band)} · ${trust.outlook || "stable"}`
        : (trust.reason || "暂时无法读取信誉分");
    elements.loanAvailableLimit.textContent = currency(availableAmount);
    elements.loanRate.textContent = `${interestRate.toFixed(2).replace(/\.?0+$/, "")}%`;
    elements.loanOutstanding.textContent = currency(summary.outstanding_amount || 0);
    elements.loanDueSummary.textContent = Number(summary.outstanding_amount || 0) > 0
        ? (Number(summary.overdue_count || 0) > 0
            ? `${summary.overdue_count} 笔逾期`
            : `下一笔 ${relativeTime(summary.next_due_in)}`)
        : "暂无待还贷款";
    elements.loanApplyNote.textContent = offer.eligible
        ? `当前可借 ${currency(availableAmount)}，单笔最低 ${currency(minAmount)}。`
        : (offer.reason || "当前不可申请贷款。");
    elements.loanInterestPreview.textContent = currency(previewInterest);
    elements.loanTotalPreview.textContent = currency(previewTotal);

    elements.loanAmount.min = minAmount > 0 ? String(minAmount) : "1";
    elements.loanAmount.max = availableAmount > 0 ? String(availableAmount) : "";
    elements.loanTerm.disabled = Boolean(requestUnavailableReason) || state.pendingLoanRequest;
    elements.loanAmount.disabled = Boolean(requestUnavailableReason) || state.pendingLoanRequest;
    elements.loanRequestButton.disabled = state.pendingLoanRequest;
    elements.loanRequestButton.dataset.blockReason = requestUnavailableReason;
    elements.loanRequestButton.title = requestUnavailableReason;
    elements.loanRequestButton.setAttribute("aria-disabled", requestUnavailableReason ? "true" : "false");
    elements.loanRequestButton.textContent = state.pendingLoanRequest ? "处理中..." : "申请贷款";

    const factors = normalizeList(trust.factors).slice(0, 3);
    elements.loanFactorList.innerHTML = factors.length
        ? factors
            .map((factor) => {
                const impact = Number(factor.impact || 0);
                const tone = impact >= 0 ? "positive" : "negative";
                return `
                    <span class="loan-factor ${tone}">
                        ${escapeHtml(factor.label || "信誉因素")}
                        <strong>${impact >= 0 ? "+" : ""}${impact}</strong>
                    </span>
                `;
            })
            .join("")
        : `<span class="loan-factor neutral">${escapeHtml(trust.reason || "等待信誉分因素")}</span>`;

    elements.loanCounter.textContent = `${loanItems.length} 笔`;
    elements.loanEmpty.hidden = loanItems.length > 0;

    if (!loanItems.length) {
        elements.loanList.innerHTML = "";
    } else {
        elements.loanList.innerHTML = loanItems
            .map((loan) => {
                const isSelected = selectedLoan && String(selectedLoan.id) === String(loan.id);
                const isActive = String(loan.status || "").toLowerCase() === "active";
                const amountLabel = isActive ? currency(loan.outstanding_amount) : currency(loan.total_due);
                const metaParts = [
                    loan.loan_code ? `编号 ${loan.loan_code}` : "",
                    `本金 ${currency(loan.principal_amount)}`,
                    `利息 ${currency(loan.interest_amount)}`,
                    `${Number(loan.interest_rate || 0).toFixed(2).replace(/\.?0+$/, "")}%`,
                ].filter(Boolean);

                return `
                    <article class="activity-card loan-card ${isSelected ? "selected" : ""} ${loan.is_overdue ? "overdue" : ""}" data-loan-id="${escapeHtml(loan.id)}">
                        <div class="activity-avatar ${isActive ? "loan-active" : "positive"}">${isActive ? "贷" : "清"}</div>
                        <div class="activity-content">
                            <div class="activity-topline">
                                <div>
                                    <div class="activity-title">${escapeHtml(formatLoanStatus(loan))}</div>
                                    <p class="activity-subline">${escapeHtml(formatLoanDue(loan))}</p>
                                </div>
                                <div class="activity-side">
                                    <div class="activity-amount ${loan.is_overdue ? "negative" : ""}">${escapeHtml(amountLabel)}</div>
                                    <div class="activity-status">${escapeHtml(formatTrustBand(loan.trust_band))}</div>
                                </div>
                            </div>

                            <div class="activity-meta">
                                ${metaParts.map((part) => `<span class="meta-chip">${escapeHtml(part)}</span>`).join("")}
                            </div>
                        </div>
                    </article>
                `;
            })
            .join("");
    }

    const repayableAmount = Number(selectedLoan?.outstanding_amount || 0);
    elements.loanRepayTitle.textContent = selectedLoan
        ? `还款 ${selectedLoan.loan_code || selectedLoan.id}`
        : "选择待还贷款";
    elements.loanRepayNote.textContent = selectedLoan
        ? `待还 ${currency(repayableAmount)}，${formatLoanDue(selectedLoan)}。`
        : "当前没有待还贷款。";
    elements.loanRepayAmount.max = repayableAmount > 0 ? String(repayableAmount) : "";
    elements.loanRepayAmount.disabled = state.pendingLoanRepay || !selectedLoan;
    elements.loanRepayButton.disabled = state.pendingLoanRepay || !selectedLoan;
    elements.loanRepayAllButton.disabled = state.pendingLoanRepay || !selectedLoan;
    elements.loanRepayButton.textContent = state.pendingLoanRepay ? "处理中..." : "还款";
};

const renderActivity = () => {
    elements.activityCounter.textContent = `${Math.max(state.activityTotal, state.activity.length)} 条`;
    setPagerState(
        elements.activityPagination,
        elements.activityPrevButton,
        elements.activityNextButton,
        elements.activityPageStatus,
        state.activityPage,
        state.activityTotalPages,
        state.activityHasMore,
        state.pendingSync
    );

    if (!state.activity.length) {
        elements.activityList.innerHTML = "";
        elements.activityEmpty.hidden = false;
        return;
    }

    elements.activityEmpty.hidden = true;
    elements.activityList.innerHTML = state.activity
        .map((entry) => {
            const amount = Number(entry.amount_delta || 0);
            const positive = amount >= 0;
            const typeLabel = entry.type === "refund" ? "退款" : "支付";
            const methodLabel = entry.method === "phone" ? "手机" : "刷卡";
            const itemMeta = buildItemMeta(entry.item_description, entry.item_lines);
            const statusLabel = formatStatus(entry.status);

            return `
                <article class="activity-card">
                    <div class="activity-avatar ${positive ? "positive" : "negative"}">${escapeHtml(entry.type === "refund" ? "退" : "付")}</div>
                    <div class="activity-content">
                        <div class="activity-topline">
                            <div>
                                <div class="activity-title">${escapeHtml(entry.store_name || "VancePay")}</div>
                                <p class="activity-subline">${escapeHtml(typeLabel)} · ${escapeHtml(methodLabel)} · ${escapeHtml(formatDateTime(entry.created_at))}${itemMeta ? ` · ${escapeHtml(itemMeta)}` : ""}</p>
                            </div>
                            <div class="activity-side">
                                <div class="activity-amount ${positive ? "positive" : "negative"}">${escapeHtml(signedCurrency(amount))}</div>
                                <div class="activity-status">${escapeHtml(statusLabel)}</div>
                            </div>
                        </div>

                        <div class="activity-meta">
                            <span class="meta-chip">流水 ${escapeHtml(entry.tx_code)}</span>
                            ${
                                entry.original_tx_code
                                    ? `<span class="meta-chip">原单 ${escapeHtml(entry.original_tx_code)}</span>`
                                    : ""
                            }
                        </div>
                    </div>
                </article>
            `;
        })
        .join("");
};

const markViewsDirty = (...views) => {
    const targetViews = views.length ? views : Object.keys(state.dirtyViews);
    targetViews.forEach((view) => {
        if (Object.prototype.hasOwnProperty.call(state.dirtyViews, view)) {
            state.dirtyViews[view] = true;
        }
    });
};

const renderActiveView = (force = false) => {
    const view = state.activeView;

    if (!force && state.renderedViews[view] && !state.dirtyViews[view]) {
        return;
    }

    if (view === "requests") {
        renderRequests();
    } else if (view === "balance") {
        renderBalance();
    } else if (view === "loans") {
        renderLoans();
    } else if (view === "activity") {
        renderActivity();
    }

    if (Object.prototype.hasOwnProperty.call(state.renderedViews, view)) {
        state.renderedViews[view] = true;
        state.dirtyViews[view] = false;
    }
};

const render = () => {
    renderSummary();
    markViewsDirty();
    switchView(state.activeView, true);
    renderActiveView(true);
};

const switchView = (view, skipRender = false) => {
    state.activeView = view;

    tabButtons.forEach((button) => {
        button.classList.toggle("active", button.dataset.view === view);
    });

    viewPanels.forEach((panel) => {
        panel.classList.toggle("active", panel.dataset.viewPanel === view);
    });

    if (!skipRender) {
        renderActiveView();
    }
};

const applyState = (payload) => {
    const data = payload?.data || payload || {};
    const activityPage = normalizePagedResult(data.activity, state.activityPage, state.activityPerPage);
    const balanceHistoryPage = normalizePagedResult(data.balance_history, state.balanceHistoryPage, state.balanceHistoryPerPage);

    state.balanceSummary = data.balance_summary && typeof data.balance_summary === "object" ? data.balance_summary : {};
    state.balance = Number(data.balance != null ? data.balance : state.balanceSummary.withdrawable_balance || 0);
    state.bankBalance = Number(data.bank_balance || 0);
    state.loans = data.loans && typeof data.loans === "object" ? data.loans : {};
    state.currency = data?.meta?.currency || data?.currency || "$";
    state.intents = normalizeList(data.intents);
    state.activity = activityPage.items;
    state.activityPage = activityPage.page;
    state.activityPerPage = activityPage.perPage;
    state.activityTotal = activityPage.total;
    state.activityTotalPages = activityPage.totalPages;
    state.activityHasMore = activityPage.hasMore;
    state.balanceHistory = balanceHistoryPage.items.map((entry) => ({
        ...entry,
        available_in: Math.max(0, Number(entry.available_in || 0)),
        availability_status: entry.availability_status || getEntryAvailabilityStatus(entry),
    }));
    state.balanceHistoryPage = balanceHistoryPage.page;
    state.balanceHistoryPerPage = balanceHistoryPage.perPage;
    state.balanceHistoryTotal = balanceHistoryPage.total;
    state.balanceHistoryTotalPages = balanceHistoryPage.totalPages;
    state.balanceHistoryHasMore = balanceHistoryPage.hasMore;
    state.pendingSync = false;
    ensureSelectedIntent();
    renderSummary();
    markViewsDirty();
    renderActiveView(true);
    setSyncState("已同步", "ready");
};

const connectBridge = () => {
    if (!bridgeListenersBound && typeof onNuiEvent === "function") {
        onNuiEvent("state", applyState);
        bridgeListenersBound = true;
    }

    if (initialStateRequested) {
        return;
    }

    if (typeof fetchNui !== "function") {
        setSyncState("等待连接", "loading");
        return;
    }

    initialStateRequested = true;
    fetchState();
};

const fetchState = async (overrides = {}) => {
    if (typeof fetchNui !== "function") {
        setSyncState("等待连接", "loading");
        return;
    }

    state.pendingSync = true;
    markViewsDirty("balance", "loans", "activity");
    renderActiveView(true);
    setSyncState("同步中", "loading");

    try {
        const response = await fetchNui("lbphoneGetState", buildStateRequest(overrides));
        if (response?.ok) {
            applyState(response.data || response);
            return;
        }

        showToast(response?.message || "同步失败");
        setSyncState("同步失败", "error");
    } catch (error) {
        showToast("同步失败");
        setSyncState("同步失败", "error");
    } finally {
        state.pendingSync = false;
        markViewsDirty("balance", "loans", "activity");
        renderActiveView(true);
    }
};

const changeBalanceHistoryPage = (nextPage) => {
    const targetPage = Math.min(
        Math.max(1, Number(nextPage || 1)),
        Math.max(1, Number(state.balanceHistoryTotalPages || 1))
    );

    if (state.pendingSync || targetPage === state.balanceHistoryPage) {
        return;
    }

    fetchState({
        balance_history_page: targetPage,
    });
};

const changeActivityPage = (nextPage) => {
    const targetPage = Math.min(
        Math.max(1, Number(nextPage || 1)),
        Math.max(1, Number(state.activityTotalPages || 1))
    );

    if (state.pendingSync || targetPage === state.activityPage) {
        return;
    }

    fetchState({
        activity_page: targetPage,
    });
};

const submitIntentAction = async (action) => {
    const selectedIntent = getSelectedIntent();
    if (!selectedIntent || state.pendingAction || typeof fetchNui !== "function") {
        return;
    }

    state.pendingAction = true;
    renderDetail();

    try {
        const eventName = action === "confirm" ? "lbphoneConfirmIntent" : "lbphoneDeclineIntent";
        const response = await fetchNui(eventName, {
            intent_id: selectedIntent.intent_id,
        });

        if (!response?.ok) {
            showToast(response?.message || "操作失败");
            return;
        }

        showToast(action === "confirm" ? "支付成功" : "已拒绝请求");
        await fetchState();
    } catch (error) {
        showToast("操作失败");
    } finally {
        state.pendingAction = false;
        renderDetail();
    }
};

const submitWithdrawal = async (amountOverride) => {
    if (state.pendingWithdraw || typeof fetchNui !== "function") {
        return;
    }

    const withdrawableBalance = Number(state.balanceSummary?.withdrawable_balance || 0);
    const requestedAmount = Number(amountOverride != null ? amountOverride : elements.withdrawAmount.value || 0);

    if (!(requestedAmount > 0)) {
        showToast("请输入有效提现金额");
        return;
    }

    if (requestedAmount > withdrawableBalance) {
        showToast(`最多可提现 ${currency(withdrawableBalance)}`);
        return;
    }

    state.pendingWithdraw = true;
    markViewsDirty("balance");
    renderActiveView(true);

    try {
        const response = await fetchNui("lbphoneWithdrawBalance", {
            amount: requestedAmount,
        });

        if (!response?.ok) {
            showToast(response?.message || "提现失败");
            return;
        }

        elements.withdrawAmount.value = "";
        showToast(response?.message || "提现成功");
        await fetchState();
    } catch (error) {
        showToast("提现失败");
    } finally {
        state.pendingWithdraw = false;
        markViewsDirty("balance");
        renderActiveView(true);
    }
};

const submitLoanRequest = async () => {
    if (state.pendingLoanRequest || typeof fetchNui !== "function") {
        return;
    }

    const offer = getLoanState().offer || {};
    const unavailableReason = getLoanRequestUnavailableReason(offer);
    const amount = Number(elements.loanAmount.value || 0);
    const termDays = Number(elements.loanTerm.value || 0);

    if (unavailableReason) {
        showToast(unavailableReason);
        return;
    }

    if (!(amount > 0)) {
        showToast("请输入有效贷款金额");
        return;
    }

    if (amount < Number(offer.min_amount || 0)) {
        showToast(`最低贷款 ${currency(offer.min_amount)}`);
        return;
    }

    if (amount > Number(offer.available_amount || 0)) {
        showToast(`最多可借 ${currency(offer.available_amount)}`);
        return;
    }

    if (!(termDays > 0)) {
        showToast("请选择贷款期限");
        return;
    }

    state.pendingLoanRequest = true;
    markViewsDirty("loans");
    renderActiveView(true);

    try {
        const response = await fetchNui("lbphoneCreateLoan", {
            amount,
            term_days: termDays,
        });

        if (!response?.ok) {
            showToast(response?.message || "贷款申请失败");
            return;
        }

        elements.loanAmount.value = "";
        showToast(response?.message || "贷款已发放");
        await fetchState();
    } catch (error) {
        showToast("贷款申请失败");
    } finally {
        state.pendingLoanRequest = false;
        markViewsDirty("loans");
        renderActiveView(true);
    }
};

const submitLoanRepayment = async (repayAll = false) => {
    if (state.pendingLoanRepay || typeof fetchNui !== "function") {
        return;
    }

    const selectedLoan = getSelectedLoan();
    if (!selectedLoan) {
        showToast("当前没有待还贷款");
        return;
    }

    const outstandingAmount = Number(selectedLoan.outstanding_amount || 0);
    const amount = repayAll ? outstandingAmount : Number(elements.loanRepayAmount.value || 0);

    if (!(amount > 0)) {
        showToast("请输入有效还款金额");
        return;
    }

    if (amount > outstandingAmount) {
        showToast(`最多还款 ${currency(outstandingAmount)}`);
        return;
    }

    state.pendingLoanRepay = true;
    markViewsDirty("loans");
    renderActiveView(true);

    try {
        const response = await fetchNui("lbphoneRepayLoan", {
            loan_id: selectedLoan.id,
            amount,
            repay_all: repayAll,
        });

        if (!response?.ok) {
            showToast(response?.message || "还款失败");
            return;
        }

        elements.loanRepayAmount.value = "";
        showToast(response?.message || "还款成功");
        await fetchState();
    } catch (error) {
        showToast("还款失败");
    } finally {
        state.pendingLoanRepay = false;
        markViewsDirty("loans");
        renderActiveView(true);
    }
};

tabButtons.forEach((button) => {
    button.addEventListener("click", () => {
        switchView(button.dataset.view);
    });
});

elements.refreshButton.addEventListener("click", () => {
    fetchState();
});

elements.balanceHistoryPrevButton.addEventListener("click", () => {
    changeBalanceHistoryPage(state.balanceHistoryPage - 1);
});

elements.balanceHistoryNextButton.addEventListener("click", () => {
    changeBalanceHistoryPage(state.balanceHistoryPage + 1);
});

elements.activityPrevButton.addEventListener("click", () => {
    changeActivityPage(state.activityPage - 1);
});

elements.activityNextButton.addEventListener("click", () => {
    changeActivityPage(state.activityPage + 1);
});

elements.requestList.addEventListener("click", (event) => {
    const card = event.target.closest("[data-intent-id]");
    if (!card) {
        return;
    }

    state.selectedIntentId = card.dataset.intentId;
    markViewsDirty("requests");
    renderActiveView(true);
});

elements.confirmButton.addEventListener("click", () => {
    submitIntentAction("confirm");
});

elements.declineButton.addEventListener("click", () => {
    submitIntentAction("decline");
});

elements.withdrawButton.addEventListener("click", () => {
    submitWithdrawal();
});

elements.withdrawAllButton.addEventListener("click", () => {
    const withdrawableBalance = Number(state.balanceSummary?.withdrawable_balance || 0);
    if (!(withdrawableBalance > 0)) {
        showToast("当前没有可提现余额");
        return;
    }

    elements.withdrawAmount.value = withdrawableBalance.toFixed(2);
    submitWithdrawal(withdrawableBalance);
});

elements.withdrawAmount.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
        event.preventDefault();
        submitWithdrawal();
    }
});

elements.loanRequestButton.addEventListener("click", () => {
    submitLoanRequest();
});

elements.loanAmount.addEventListener("input", () => {
    markViewsDirty("loans");
    renderActiveView(true);
});

elements.loanTerm.addEventListener("change", () => {
    markViewsDirty("loans");
    renderActiveView(true);
});

elements.loanRepayButton.addEventListener("click", () => {
    submitLoanRepayment(false);
});

elements.loanRepayAllButton.addEventListener("click", () => {
    const selectedLoan = getSelectedLoan();
    if (!selectedLoan) {
        showToast("当前没有待还贷款");
        return;
    }

    elements.loanRepayAmount.value = Number(selectedLoan.outstanding_amount || 0).toFixed(2);
    submitLoanRepayment(true);
});

elements.loanRepayAmount.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
        event.preventDefault();
        submitLoanRepayment(false);
    }
});

elements.loanList.addEventListener("click", (event) => {
    const card = event.target.closest("[data-loan-id]");
    if (!card) {
        return;
    }

    state.selectedLoanId = card.dataset.loanId;
    markViewsDirty("loans");
    renderActiveView(true);
});

window.addEventListener("message", (event) => {
    const payload = event?.data;
    if (!payload) {
        return;
    }

    if (payload === "componentsLoaded") {
        connectBridge();
        return;
    }

    if (payload.type === "state" || payload.action === "state") {
        applyState(payload.data || payload);
    }
});

window.setInterval(() => {
    let shouldRefresh = false;
    let requestsChanged = false;
    let balanceChanged = false;
    let loansChanged = false;

    if (state.intents.length) {
        state.intents = state.intents.map((intent) => {
            const current = Math.max(0, Number(intent.expires_in || 0));
            const next = Math.max(0, current - 1);
            if (next !== current) {
                requestsChanged = true;
            }
            if (current > 0 && next === 0) {
                shouldRefresh = true;
            }

            return {
                ...intent,
                expires_in: next,
            };
        });
    }

    if (state.balanceHistory.length) {
        state.balanceHistory = state.balanceHistory.map((entry) => {
            const current = Math.max(0, Number(entry.available_in || 0));
            const next = Math.max(0, current - 1);
            if (next !== current) {
                balanceChanged = true;
            }
            if (current > 0 && next === 0) {
                shouldRefresh = true;
            }

            return {
                ...entry,
                available_in: next,
                availability_status: getEntryAvailabilityStatus(entry, next),
            };
        });
    }

    const nextUnlockIn = Math.max(0, Number(state.balanceSummary?.next_unlock_in || 0));
    if (nextUnlockIn > 0) {
        const updatedNextUnlockIn = Math.max(0, nextUnlockIn - 1);
        balanceChanged = true;
        if (updatedNextUnlockIn === 0) {
            shouldRefresh = true;
        }

        state.balanceSummary = {
            ...state.balanceSummary,
            next_unlock_in: updatedNextUnlockIn,
        };
    }

    if (state.loans && typeof state.loans === "object") {
        const loanState = getLoanState();
        const loanItems = getLoanItems();
        if (loanItems.length) {
            const items = loanItems.map((loan) => {
                if (String(loan.status || "").toLowerCase() !== "active") {
                    return loan;
                }

                const rawDueIn = Number(loan.due_in);
                const hasCountdown = Number.isFinite(rawDueIn);
                const current = hasCountdown ? Math.max(0, rawDueIn) : 0;
                const next = hasCountdown ? Math.max(0, current - 1) : 0;
                if (next !== current) {
                    loansChanged = true;
                }
                if (current > 0 && next === 0) {
                    shouldRefresh = true;
                }

                return {
                    ...loan,
                    due_in: next,
                    is_overdue: Boolean(loan.is_overdue) || (hasCountdown && next === 0),
                };
            });

            const summaryNextDue = Math.max(0, Number(loanState.summary?.next_due_in || 0));
            const updatedSummaryNextDue = summaryNextDue > 0 ? Math.max(0, summaryNextDue - 1) : summaryNextDue;
            if (updatedSummaryNextDue !== summaryNextDue) {
                loansChanged = true;
            }

            state.loans = {
                ...loanState,
                items,
                summary: {
                    ...(loanState.summary || {}),
                    next_due_in: updatedSummaryNextDue,
                },
            };
        }
    }

    if (requestsChanged) markViewsDirty("requests");
    if (balanceChanged) markViewsDirty("balance");
    if (loansChanged) markViewsDirty("loans");
    if (requestsChanged || balanceChanged || loansChanged) {
        renderSummary();
        renderActiveView();
    }

    if (shouldRefresh) {
        fetchState();
    }
}, 1000);

render();
