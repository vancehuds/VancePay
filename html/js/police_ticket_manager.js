(function () {
    const app = window.VancePayApp;
    const state = {
        payload: {},
        selectedTicketCode: null,
        activePanel: 'tickets',
        audit: null
    };

    const elements = {
        title: document.getElementById('ticket-manager-title'),
        subcopy: document.getElementById('ticket-manager-subcopy'),
        scopeBadge: document.getElementById('ticket-manager-scope-badge'),
        refreshButton: document.getElementById('ticket-manager-refresh-button'),
        panelButtons: document.querySelectorAll('[data-ticket-manager-panel]'),
        panels: document.querySelectorAll('[data-ticket-manager-view]'),
        auditButton: document.getElementById('ticket-manager-audit-tab'),
        agencyFilter: document.getElementById('ticket-manager-agency-filter'),
        statusFilter: document.getElementById('ticket-manager-status-filter'),
        searchFilter: document.getElementById('ticket-manager-search-filter'),
        dateFromFilter: document.getElementById('ticket-manager-date-from-filter'),
        dateToFilter: document.getElementById('ticket-manager-date-to-filter'),
        filterForm: document.getElementById('ticket-manager-filter-form'),
        summary: document.getElementById('ticket-manager-summary'),
        list: document.getElementById('ticket-manager-list'),
        detail: document.getElementById('ticket-manager-detail'),
        auditList: document.getElementById('ticket-manager-audit-list'),
        auditRefreshButton: document.getElementById('ticket-manager-audit-refresh-button')
    };

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatDateTime(value) {
        if (!value) return '--';
        return String(value).replace('T', ' ').replace(/\.\d+Z?$/, '').replace(/Z$/, '').slice(0, 19);
    }

    function formatStatus(status) {
        return {
            unpaid: '未缴纳',
            paid: '已缴纳',
            cancelled: '已取消'
        }[status] || status || '--';
    }

    function formatTicketType(value) {
        return {
            notice: '行政处罚告知单',
            traffic: '交通违法处罚单'
        }[value] || value || '--';
    }

    function formatTargetType(type) {
        return {
            police_ticket: '罚单',
            store: '店铺',
            terminal: '终端',
            employee: '员工',
            transaction: '交易',
            loan: '贷款',
            collection_task: '催收任务'
        }[type] || type || '--';
    }

    function formatAuditAction(action) {
        return {
            create_police_ticket: '开具罚单',
            pay_police_ticket: '缴纳罚单',
            cancel_police_ticket: '取消罚单',
            restore_police_ticket: '恢复罚单'
        }[action] || action || '--';
    }

    function formatAuditKey(key) {
        return {
            ticket_code: '罚单编号',
            ticket_agency: '执法机构',
            agency_label: '机构名称',
            target_citizenid: '被罚人',
            target_name: '被罚人姓名',
            officer_citizenid: '开单人',
            officer_name: '开单人姓名',
            amount: '金额',
            reason: '原因',
            note: '备注',
            previous_status: '原状态',
            new_status: '新状态',
            payment_account: '入账账户',
            metadata_written: '物品状态已写回',
            ctifo_credit_impact: '信誉影响',
            ctifo_credit_event_id: '信誉事件 ID',
            ticket_type: '票据类型',
            ticket_style: '票面样式'
        }[key] || String(key || '--').replace(/_/g, ' ');
    }

    function formatAuditValue(key, value) {
        if (value == null || value === '') return '--';
        if (/status$/.test(key)) return formatStatus(value);
        if (/(amount|balance)/.test(key) && typeof value === 'number') return app.formatCurrency(value);
        if (typeof value === 'boolean') return value ? '是' : '否';
        if (Array.isArray(value)) return value.length ? value.slice(0, 2).map((item) => formatAuditValue(key, item)).join(', ') : '--';
        if (typeof value === 'object') {
            return Object.entries(value)
                .filter(([, nestedValue]) => nestedValue != null && nestedValue !== '')
                .slice(0, 2)
                .map(([nestedKey, nestedValue]) => `${formatAuditKey(nestedKey)} ${formatAuditValue(nestedKey, nestedValue)}`)
                .join(' · ') || '--';
        }
        return String(value);
    }

    function buildAuditSummary(detail) {
        if (!detail || typeof detail !== 'object' || Array.isArray(detail)) return '';
        return Object.entries(detail)
            .filter(([, value]) => value != null && value !== '')
            .slice(0, 4)
            .map(([key, value]) => `${formatAuditKey(key)} ${formatAuditValue(key, value)}`)
            .join(' · ');
    }

    function getTickets() {
        return (state.payload.tickets && state.payload.tickets.items) || [];
    }

    function getSelectedTicket() {
        const code = String(state.selectedTicketCode || '').trim();
        if (!code) return getTickets()[0] || null;
        return getTickets().find((ticket) => ticket.ticket_code === code) || getTickets()[0] || null;
    }

    function collectFilters() {
        return {
            agency: elements.agencyFilter ? elements.agencyFilter.value : undefined,
            status: elements.statusFilter ? elements.statusFilter.value : 'all',
            search: elements.searchFilter ? elements.searchFilter.value.trim() : undefined,
            date_from: elements.dateFromFilter ? elements.dateFromFilter.value : undefined,
            date_to: elements.dateToFilter ? elements.dateToFilter.value : undefined,
            page: 1,
            per_page: state.payload.tickets && state.payload.tickets.per_page || 15
        };
    }

    function renderScope() {
        const scope = state.payload.scope || {};
        elements.title.textContent = scope.title || '罚单管理';
        elements.subcopy.textContent = scope.subtitle || '查看并处理罚单记录';
        elements.scopeBadge.textContent = scope.is_admin ? '管理员全局' : (scope.is_boss ? 'Boss 审计' : '职业管理');
        elements.scopeBadge.dataset.scope = scope.is_admin ? 'admin' : (scope.is_boss ? 'boss' : 'job');
        elements.auditButton.classList.toggle('hidden', !scope.can_audit);
        if (!scope.can_audit && state.activePanel === 'audit') {
            state.activePanel = 'tickets';
        }
    }

    function renderFilters() {
        const scope = state.payload.scope || {};
        const agencies = state.payload.agencies || [];
        const isAdmin = scope.is_admin === true;
        const currentAgency = (state.payload.filters && state.payload.filters.agency) || (isAdmin ? '' : scope.agency_key || '');

        if (elements.agencyFilter) {
            elements.agencyFilter.disabled = !isAdmin;
            elements.agencyFilter.innerHTML = isAdmin
                ? `<option value="">全部机构</option>${agencies.map((agency) => `
                    <option value="${escapeHtml(agency.key)}" ${agency.key === currentAgency ? 'selected' : ''}>${escapeHtml(agency.label || agency.key)}</option>
                `).join('')}`
                : agencies.map((agency) => `
                    <option value="${escapeHtml(agency.key)}" selected>${escapeHtml(agency.label || agency.key)}</option>
                `).join('');
        }

        const filters = state.payload.filters || {};
        if (elements.statusFilter) elements.statusFilter.value = filters.status || 'all';
        if (elements.searchFilter) elements.searchFilter.value = filters.search || '';
        if (elements.dateFromFilter) elements.dateFromFilter.value = filters.date_from || '';
        if (elements.dateToFilter) elements.dateToFilter.value = filters.date_to || '';
    }

    function renderSummary() {
        const summary = state.payload.summary || {};
        const items = [
            ['总罚单', String(summary.total_count || 0)],
            ['未缴金额', app.formatCurrency(summary.unpaid_amount || 0)],
            ['已缴金额', app.formatCurrency(summary.paid_amount || 0)],
            ['已取消', `${summary.cancelled_count || 0} 张`],
            ['未缴数量', String(summary.unpaid_count || 0)],
            ['累计金额', app.formatCurrency(summary.total_amount || 0)]
        ];

        elements.summary.innerHTML = items.map(([label, value]) => `
            <div class="overview-pill">
                <label>${escapeHtml(label)}</label>
                <strong>${escapeHtml(value)}</strong>
            </div>
        `).join('');
    }

    function buildTicketBadges(ticket) {
        const statusTone = ticket.status === 'paid' ? 'success' : (ticket.status === 'cancelled' ? 'danger' : 'warning');
        return `
            <span class="list-badge" data-tone="${statusTone}">${escapeHtml(formatStatus(ticket.status))}</span>
            <span class="list-badge" data-tone="target">${escapeHtml(ticket.agency_badge || ticket.ticket_agency || '--')}</span>
            <span class="list-badge" data-tone="type">${escapeHtml(ticket.ticket_type_label || formatTicketType(ticket.ticket_type))}</span>
        `;
    }

    function renderList() {
        const tickets = getTickets();
        if (!state.selectedTicketCode && tickets[0]) {
            state.selectedTicketCode = tickets[0].ticket_code;
        }

        elements.list.innerHTML = tickets.map((ticket) => `
            <button class="ticket-manager-row ${ticket.ticket_code === state.selectedTicketCode ? 'active' : ''}" type="button" data-ticket-code="${escapeHtml(ticket.ticket_code)}">
                <span class="ticket-manager-row-main">
                    <strong>${escapeHtml(ticket.ticket_code || '--')}</strong>
                    <em>${escapeHtml(ticket.target_name_snapshot || ticket.target_citizenid || '--')}</em>
                </span>
                <span class="ticket-manager-row-amount">${app.formatCurrency(ticket.amount || 0)}</span>
                <span class="list-badge-row">${buildTicketBadges(ticket)}</span>
                <span class="ticket-manager-row-meta">
                    ${escapeHtml(ticket.officer_name_snapshot || ticket.officer_citizenid || '--')} · ${escapeHtml(formatDateTime(ticket.created_at))}
                </span>
            </button>
        `).join('') || '<div class="ticket-manager-empty">暂无符合条件的罚单</div>';
    }

    function renderDetail() {
        const ticket = getSelectedTicket();
        if (!ticket) {
            elements.detail.innerHTML = '<div class="detail-placeholder">选择左侧罚单查看详情</div>';
            return;
        }

        const canCancel = ticket.status === 'unpaid';
        const canRestore = ticket.status === 'cancelled';
        elements.detail.innerHTML = `
            <div class="detail-head">
                <div>
                    <p class="detail-kicker">罚单详情</p>
                    <h3>${escapeHtml(ticket.ticket_code || '--')}</h3>
                </div>
                <span class="detail-badge" data-state="${escapeHtml(ticket.status || '')}">${escapeHtml(formatStatus(ticket.status))}</span>
            </div>
            <div class="ticket-manager-detail-grid">
                <div class="detail-field">
                    <label>被罚人</label>
                    <strong>${escapeHtml(ticket.target_name_snapshot || '--')}</strong>
                    <span>${escapeHtml(ticket.target_citizenid || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>开单人员</label>
                    <strong>${escapeHtml(ticket.officer_name_snapshot || '--')}</strong>
                    <span>${escapeHtml(ticket.officer_citizenid || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>执法机构</label>
                    <strong>${escapeHtml(ticket.agency_label || ticket.ticket_agency || '--')}</strong>
                    <span>${escapeHtml(ticket.agency_badge || ticket.ticket_agency || '--')}</span>
                </div>
                <div class="detail-field">
                    <label>罚款金额</label>
                    <strong>${app.formatCurrency(ticket.amount || 0)}</strong>
                    <span>${escapeHtml(ticket.ticket_type_label || formatTicketType(ticket.ticket_type))}</span>
                </div>
                <div class="detail-field wide">
                    <label>处罚原因</label>
                    <strong>${escapeHtml(ticket.reason || '--')}</strong>
                </div>
                <div class="detail-field">
                    <label>开具时间</label>
                    <span>${escapeHtml(formatDateTime(ticket.created_at))}</span>
                </div>
                <div class="detail-field">
                    <label>缴纳时间</label>
                    <span>${escapeHtml(formatDateTime(ticket.paid_at))}</span>
                </div>
                <div class="detail-field">
                    <label>信誉影响</label>
                    <span>${Number(ticket.ctifo_credit_impact || 0)}</span>
                </div>
                <div class="detail-field">
                    <label>票面</label>
                    <span>${escapeHtml(ticket.ticket_style_label || ticket.ticket_style || '--')}</span>
                </div>
            </div>
            <div class="ticket-manager-actions">
                <button class="action-button muted" type="button" data-ticket-manager-cancel ${canCancel ? '' : 'disabled'}>取消罚单</button>
                <button class="action-button accent" type="button" data-ticket-manager-restore ${canRestore ? '' : 'disabled'}>恢复未缴</button>
            </div>
            <p class="helper-copy">已缴纳罚单不会在平板内退款。需要退款时请由管理员按服务器流程线下处理资金和信用记录。</p>
        `;
    }

    function renderPanels() {
        elements.panelButtons.forEach((button) => {
            button.classList.toggle('active', button.dataset.ticketManagerPanel === state.activePanel);
        });
        elements.panels.forEach((panel) => {
            panel.classList.toggle('hidden', panel.dataset.ticketManagerView !== state.activePanel);
        });
    }

    function renderAudit() {
        const audit = state.audit || state.payload.audit || { items: [] };
        const items = audit.items || [];
        elements.auditList.innerHTML = items.map((entry) => `
            <div class="table-item audit-item">
                <div class="audit-item-head">
                    <div class="audit-item-copy">
                        <strong>${escapeHtml(formatAuditAction(entry.action))}</strong>
                        <span class="audit-item-target">${escapeHtml(formatTargetType(entry.target_type))} · ${escapeHtml(entry.target_id || '--')}</span>
                    </div>
                    <span class="audit-item-time">${escapeHtml(formatDateTime(entry.created_at))}</span>
                </div>
                <div class="list-badge-row">
                    <span class="list-badge" data-tone="audit">${escapeHtml(formatAuditAction(entry.action))}</span>
                    <span class="list-badge" data-tone="target">${escapeHtml(entry.actor_citizenid || '--')}</span>
                </div>
                ${buildAuditSummary(entry.detail) ? `<div class="audit-item-summary">${escapeHtml(buildAuditSummary(entry.detail))}</div>` : ''}
            </div>
        `).join('') || '<div class="ticket-manager-empty">暂无罚单审计日志</div>';
    }

    function render(payload) {
        state.payload = payload || {};
        state.audit = state.payload.audit || state.audit;
        const tickets = getTickets();
        if (state.selectedTicketCode && !tickets.find((ticket) => ticket.ticket_code === state.selectedTicketCode)) {
            state.selectedTicketCode = tickets[0] && tickets[0].ticket_code || null;
        }

        renderScope();
        renderFilters();
        renderSummary();
        renderList();
        renderDetail();
        renderAudit();
        renderPanels();
    }

    async function refresh() {
        const response = await app.post('refreshPoliceTicketManager', collectFilters());
        app.setRibbon(response.message || (response.ok ? '罚单列表已刷新' : '罚单刷新失败'), response.ok ? 'success' : 'error');
        if (response.ok) render(response.data);
    }

    async function refreshAudit() {
        const filters = collectFilters();
        const response = await app.post('getPoliceTicketManagerAudit', {
            agency: filters.agency,
            search: filters.search,
            page: 1,
            per_page: 20
        });

        app.setRibbon(response.message || (response.ok ? '罚单审计已刷新' : '审计刷新失败'), response.ok ? 'success' : 'error');
        if (response.ok) {
            state.audit = response.data;
            renderAudit();
        }
    }

    async function mutateTicket(endpoint, ticketCode) {
        const response = await app.post(endpoint, {
            ticket_code: ticketCode,
            note: ''
        });
        app.setRibbon(response.message || '操作完成', response.ok ? 'success' : 'error');
    }

    elements.refreshButton.addEventListener('click', refresh);
    elements.filterForm.addEventListener('submit', (event) => {
        event.preventDefault();
        refresh();
    });

    elements.panelButtons.forEach((button) => {
        button.addEventListener('click', () => {
            if (button.classList.contains('hidden')) return;
            state.activePanel = button.dataset.ticketManagerPanel || 'tickets';
            renderPanels();
            if (state.activePanel === 'audit' && !(state.audit && state.audit.items)) {
                refreshAudit();
            }
        });
    });

    elements.list.addEventListener('click', (event) => {
        const row = event.target.closest('[data-ticket-code]');
        if (!row) return;
        state.selectedTicketCode = row.dataset.ticketCode;
        renderList();
        renderDetail();
    });

    elements.detail.addEventListener('click', (event) => {
        const ticket = getSelectedTicket();
        if (!ticket) return;
        const cancelButton = event.target.closest('[data-ticket-manager-cancel]');
        const restoreButton = event.target.closest('[data-ticket-manager-restore]');
        if (cancelButton && !cancelButton.disabled) {
            mutateTicket('cancelManagedPoliceTicket', ticket.ticket_code);
        }
        if (restoreButton && !restoreButton.disabled) {
            mutateTicket('restoreManagedPoliceTicket', ticket.ticket_code);
        }
    });

    elements.auditRefreshButton.addEventListener('click', refreshAudit);

    window.VancePayPoliceTicketManager = {
        render
    };
})();
