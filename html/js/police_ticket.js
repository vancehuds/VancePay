(function () {
    const app = window.VancePayApp;
    const state = {
        payload: null,
        pendingPayment: false
    };

    const defaultAgency = {
        key: 'lspd',
        label: '洛圣都警察局',
        subtitle: 'LOS SANTOS POLICE DEPARTMENT',
        badge: 'LS',
        watermark: 'LSPD',
        code_prefix: 'LS',
        class_name: 'agency-lspd',
        theme: null
    };

    const themeVars = {
        paper: '--ticket-paper',
        paper_deep: '--ticket-paper-deep',
        edge: '--ticket-paper-edge',
        ink: '--ticket-ink',
        ink_soft: '--ticket-ink-soft',
        line: '--ticket-line',
        stamp: '--ticket-stamp'
    };
    const supportsOklch = !window.CSS || typeof window.CSS.supports !== 'function'
        ? true
        : window.CSS.supports('color', 'oklch(50% 0 0)');

    const elements = {
        document: document.getElementById('police-ticket-document'),
        agency: document.getElementById('police-ticket-agency'),
        agencyField: document.getElementById('police-ticket-agency-field'),
        badge: document.getElementById('police-ticket-badge'),
        title: document.getElementById('police-ticket-title'),
        subtitle: document.getElementById('police-ticket-subtitle'),
        code: document.getElementById('police-ticket-code'),
        issuedAt: document.getElementById('police-ticket-issued-at'),
        typeLabel: document.getElementById('police-ticket-type-label'),
        statusLabel: document.getElementById('police-ticket-status-label'),
        target: document.getElementById('police-ticket-target'),
        officer: document.getElementById('police-ticket-officer'),
        statusField: document.getElementById('police-ticket-status-field'),
        amount: document.getElementById('police-ticket-amount'),
        reason: document.getElementById('police-ticket-reason'),
        trafficCode: document.getElementById('police-ticket-traffic-code'),
        trafficReason: document.getElementById('police-ticket-traffic-reason'),
        trafficAmount: document.getElementById('police-ticket-traffic-amount'),
        createdAt: document.getElementById('police-ticket-created-at'),
        paidAt: document.getElementById('police-ticket-paid-at'),
        credit: document.getElementById('police-ticket-credit'),
        payArea: document.getElementById('police-ticket-pay-area'),
        payCopy: document.getElementById('police-ticket-pay-copy'),
        payAmount: document.getElementById('police-ticket-pay-amount'),
        signature: document.getElementById('police-ticket-signature'),
        signatureSeal: document.getElementById('police-ticket-signature-seal'),
        close: document.getElementById('police-ticket-close'),
        stamp: document.getElementById('police-ticket-stamp'),
        watermark: document.getElementById('police-ticket-watermark')
    };

    function valueOrDash(value) {
        const text = String(value == null ? '' : value).trim();
        return text || '--';
    }

    function normalizeChoice(value, fallback, allowed) {
        const normalized = String(value || '').trim();
        const normalizedLower = normalized.toLowerCase();
        for (let index = 0; index < allowed.length; index += 1) {
            const optionValue = String(allowed[index] || '').trim();
            if (optionValue.toLowerCase() === normalizedLower) {
                return optionValue;
            }
        }

        return fallback;
    }

    function getOptionValues(options, fallback) {
        if (!Array.isArray(options) || !options.length) {
            return fallback;
        }

        const values = options.map((option) => option && option.value).filter(Boolean);
        return values.length ? values : fallback;
    }

    function getTicketType(ticket, metadata) {
        const configured = getOptionValues(state.payload && state.payload.ticket_types, ['notice', 'traffic']);
        return normalizeChoice(ticket.ticket_type || metadata.ticket_type || metadata.ticketType, configured[0] || 'notice', configured);
    }

    function getTicketStyle(ticket, metadata) {
        const configured = getOptionValues(state.payload && state.payload.ticket_styles, ['aged', 'carbon']);
        return normalizeChoice(ticket.ticket_style || metadata.ticket_style || metadata.ticketStyle, configured[0] || 'aged', configured);
    }

    function normalizeKey(value) {
        return String(value || '').trim().toLowerCase();
    }

    function normalizeClassName(value, fallback) {
        const normalized = String(value || '').replace(/[^a-zA-Z0-9_\-\s]/g, '').trim();
        return normalized || fallback;
    }

    function normalizeAgency(rawAgency, fallbackKey) {
        rawAgency = rawAgency || {};
        const agencyKey = normalizeKey(rawAgency.key || fallbackKey || defaultAgency.key);
        return Object.assign({}, defaultAgency, rawAgency, {
            key: agencyKey || defaultAgency.key,
            label: rawAgency.label || rawAgency.name || defaultAgency.label,
            subtitle: rawAgency.subtitle || defaultAgency.subtitle,
            badge: rawAgency.badge || defaultAgency.badge,
            watermark: rawAgency.watermark || (agencyKey ? agencyKey.toUpperCase() : defaultAgency.watermark),
            code_prefix: rawAgency.code_prefix || rawAgency.codePrefix || rawAgency.badge || defaultAgency.code_prefix,
            class_name: rawAgency.class_name || rawAgency.className || (agencyKey ? `agency-${agencyKey}` : defaultAgency.class_name),
            theme: rawAgency.theme || null
        });
    }

    function pickAgency(payload, ticket, metadata) {
        const agencyKey = normalizeKey(ticket.ticket_agency || metadata.ticket_agency || metadata.ticketAgency || metadata.agency_key);
        const agencies = Array.isArray(payload.agencies) ? payload.agencies : [];
        for (let index = 0; index < agencies.length; index += 1) {
            const agency = agencies[index];
            if (agency && normalizeKey(agency.key) === agencyKey) {
                return normalizeAgency(agency, agencyKey);
            }
        }

        return normalizeAgency({
            key: agencyKey || defaultAgency.key,
            label: metadata.agency_label || metadata.agencyLabel,
            subtitle: metadata.agency_subtitle || metadata.agencySubtitle,
            badge: metadata.agency_badge || metadata.agencyBadge,
            watermark: metadata.agency_watermark || metadata.agencyWatermark,
            code_prefix: metadata.agency_code_prefix || metadata.agencyCodePrefix,
            class_name: metadata.agency_class_name || metadata.agencyClassName,
            theme: metadata.agency_theme || metadata.agencyTheme
        }, agencyKey);
    }

    function getStatusLabel(status) {
        return {
            paid: '已缴纳',
            cancelled: '已取消',
            unpaid: '未缴纳'
        }[status] || '未缴纳';
    }

    function getTypeLabel(type) {
        const types = Array.isArray(state.payload && state.payload.ticket_types) ? state.payload.ticket_types : [];
        for (let index = 0; index < types.length; index += 1) {
            const option = types[index];
            if (option && option.value === type && option.label) {
                return option.label;
            }
        }

        return type === 'traffic' ? '交通违法处罚单' : '行政处罚告知单';
    }

    function formatCreditImpact(value) {
        const impact = Number(value || 0);
        if (!impact) {
            return '无额外影响';
        }

        return impact > 0 ? `+${impact}` : String(impact);
    }

    function makeTrafficCode(ticket, agency) {
        const prefix = String(agency.code_prefix || agency.badge || 'LS').replace(/[^A-Z0-9]/gi, '').toUpperCase() || 'LS';
        const code = String(ticket.ticket_code || 'PF0000').replace(/[^A-Z0-9]/gi, '').slice(-4).toUpperCase();
        return `${prefix}-${code || '0000'}`;
    }

    function clearAgencyTheme() {
        Object.keys(themeVars).forEach((key) => {
            elements.document.style.removeProperty(themeVars[key]);
        });
    }

    function applyAgencyTheme(agency) {
        clearAgencyTheme();
        const theme = agency && agency.theme;
        if (!theme || typeof theme !== 'object') {
            return;
        }

        Object.keys(themeVars).forEach((key) => {
            const value = theme[key];
            if (typeof value === 'string' && value.trim() && !/[;{}]/.test(value)) {
                const normalized = value.trim();
                if (!supportsOklch && /\boklch\(/i.test(normalized)) {
                    return;
                }

                elements.document.style.setProperty(themeVars[key], normalized);
            }
        });
    }

    function setDocumentClass(type, style, status, agency) {
        const agencyClassName = normalizeClassName(agency && (agency.class_name || agency.className), `agency-${agency && agency.key || 'lspd'}`);
        elements.document.className = [
            'police-ticket',
            style === 'carbon' ? 'paper-carbon' : 'paper-aged',
            type === 'traffic' ? 'ticket-type-traffic' : 'ticket-type-notice',
            `ticket-status-${status || 'unpaid'}`,
            agencyClassName
        ].join(' ');
        applyAgencyTheme(agency);
    }

    function syncPayArea(ticket) {
        ticket = ticket || {};
        const isPayable = ticket.status === 'unpaid';
        elements.payArea.disabled = !isPayable || state.pendingPayment;
        elements.payArea.dataset.disabled = isPayable ? 'false' : 'true';
        elements.payCopy.textContent = state.pendingPayment
            ? '正在处理缴款'
            : (isPayable ? '点击二维码缴纳罚款' : '缴款回执已生成');
        elements.payAmount.textContent = isPayable ? app.formatCurrency(ticket.amount || 0) : getStatusLabel(ticket.status);
    }

    function render(payload) {
        payload = payload || {};
        state.payload = payload;
        state.pendingPayment = false;

        const ticket = payload.ticket || {};
        const metadata = payload.metadata || {};
        ticket.status = ticket.status || metadata.status || 'unpaid';
        const type = getTicketType(ticket, metadata);
        const style = getTicketStyle(ticket, metadata);
        const agency = pickAgency(payload, ticket, metadata);
        const status = ticket.status;
        const statusLabel = getStatusLabel(status);
        const typeLabel = getTypeLabel(type);
        const amount = app.formatCurrency(ticket.amount || metadata.amount || 0);
        const reason = valueOrDash(ticket.reason || metadata.reason);
        const officer = valueOrDash(ticket.officer_name_snapshot || metadata.officer_name || ticket.officer_citizenid || metadata.officer_citizenid);
        const target = valueOrDash(ticket.target_name_snapshot || metadata.target_name || ticket.target_citizenid || metadata.target_citizenid);
        const createdAt = app.formatDate(ticket.created_at || metadata.created_at);
        const paidAt = ticket.paid_at || metadata.paid_at ? app.formatDate(ticket.paid_at || metadata.paid_at) : '未缴纳';

        setDocumentClass(type, style, status, agency);

        elements.agency.textContent = agency.label || defaultAgency.label;
        elements.agencyField.textContent = agency.label || defaultAgency.label;
        elements.badge.textContent = agency.badge || defaultAgency.badge;
        elements.title.textContent = typeLabel;
        elements.subtitle.textContent = agency.subtitle || defaultAgency.subtitle;
        elements.watermark.textContent = agency.watermark || agency.key || defaultAgency.watermark;
        elements.code.textContent = valueOrDash(ticket.ticket_code || metadata.ticket_code);
        elements.issuedAt.textContent = createdAt;
        elements.typeLabel.textContent = `${typeLabel} · ${agency.badge || agency.key || 'LS'} · ${style === 'carbon' ? '碳复写联' : '纸质正本'}`;
        elements.statusLabel.textContent = statusLabel;
        elements.statusField.textContent = statusLabel;
        elements.target.textContent = target;
        elements.officer.textContent = officer;
        elements.amount.textContent = amount;
        elements.reason.textContent = reason;
        elements.trafficCode.textContent = makeTrafficCode(ticket, agency);
        elements.trafficReason.textContent = reason;
        elements.trafficAmount.textContent = amount;
        elements.createdAt.textContent = createdAt;
        elements.paidAt.textContent = paidAt;
        elements.credit.textContent = formatCreditImpact(ticket.ctifo_credit_impact || metadata.ctifo_credit_impact);
        elements.signature.textContent = officer;
        elements.signatureSeal.textContent = `${agency.label || defaultAgency.label} 公章`;
        elements.stamp.textContent = statusLabel;

        syncPayArea(ticket);
    }

    elements.payArea.addEventListener('click', async () => {
        if (!state.payload || state.pendingPayment || !state.payload.ticket || state.payload.ticket.status !== 'unpaid') {
            return;
        }

        state.pendingPayment = true;
        syncPayArea(state.payload.ticket);

        const response = await app.post('payPoliceTicket', {});
        if (response && response.ok && response.data) {
            render(response.data);
        } else {
            app.setRibbon(response && response.message || '罚单缴款失败', 'error');
            state.pendingPayment = false;
            syncPayArea(state.payload && state.payload.ticket);
        }
    });

    elements.close.addEventListener('click', () => app.close());

    window.VancePayPoliceTicket = {
        render
    };
})();
