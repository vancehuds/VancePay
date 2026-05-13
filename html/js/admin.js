(function () {
    const app = window.VancePayApp;
    const state = {
        payload: {},
        activeTab: 'stores',
        storeCreateMode: false,
        selectedTransactionId: null,
        transactionDetail: null,
        selectedLoanId: null,
        generatedBindingCode: null
    };

    const elements = {
        title: document.getElementById('admin-title'),
        subcopy: document.getElementById('admin-subcopy'),
        storeSelect: document.getElementById('admin-store-select'),
        overviewStrip: document.getElementById('admin-overview-strip'),
        storeList: document.getElementById('store-list'),
        terminalList: document.getElementById('terminal-list'),
        employeeList: document.getElementById('employee-list'),
        employeeSyncButton: document.getElementById('sync-employees-button'),
        employeeSyncNote: document.getElementById('employee-sync-note'),
        transactionList: document.getElementById('admin-transaction-list'),
        transactionDetail: document.getElementById('admin-transaction-detail'),
        loanSummary: document.getElementById('loan-summary-grid'),
        loanList: document.getElementById('admin-loan-list'),
        loanDetail: document.getElementById('admin-loan-detail'),
        loanForm: document.getElementById('loan-form'),
        loanSearchFilter: document.getElementById('loan-search-filter'),
        loanStatusFilter: document.getElementById('loan-status-filter'),
        loanDueFilter: document.getElementById('loan-due-filter'),
        loanCollectionFilter: document.getElementById('loan-collection-filter'),
        loanIdInput: document.getElementById('loan-id-input'),
        loanCodeInput: document.getElementById('loan-code-input'),
        loanCitizenIdInput: document.getElementById('loan-citizenid-input'),
        loanPrincipalInput: document.getElementById('loan-principal-input'),
        loanInterestInput: document.getElementById('loan-interest-input'),
        loanTotalInput: document.getElementById('loan-total-input'),
        loanRepaidInput: document.getElementById('loan-repaid-input'),
        loanRateInput: document.getElementById('loan-rate-input'),
        loanTermInput: document.getElementById('loan-term-input'),
        loanStatusInput: document.getElementById('loan-status-input'),
        loanDueAtInput: document.getElementById('loan-due-at-input'),
        loanFormNote: document.getElementById('loan-form-note'),
        saveLoanButton: document.getElementById('save-loan-button'),
        createCollectionTaskButton: document.getElementById('create-collection-task-button'),
        cancelCollectionTaskButton: document.getElementById('cancel-collection-task-button'),
        auditList: document.getElementById('audit-list'),
        reportSummary: document.getElementById('report-summary-grid'),
        reportDailyChart: document.getElementById('report-daily-chart'),
        reportMethodSplit: document.getElementById('report-method-split'),
        reportTopStores: document.getElementById('report-top-stores'),
        taxDefaultForm: document.getElementById('tax-default-form'),
        taxDefaultRateInput: document.getElementById('tax-default-rate-input'),
        saveTaxDefaultButton: document.getElementById('save-tax-default-button'),
        commissionSettingsForm: document.getElementById('commission-settings-form'),
        commissionSettingsNote: document.getElementById('commission-settings-note'),
        commissionBalanceNote: document.getElementById('commission-balance-note'),
        commissionRateInput: document.getElementById('commission-rate-input'),
        saveCommissionSettingsButton: document.getElementById('save-commission-settings-button'),
        commissionRangeFilter: document.getElementById('commission-range-filter'),
        commissionDateFromFilter: document.getElementById('commission-date-from-filter'),
        commissionDateToFilter: document.getElementById('commission-date-to-filter'),
        commissionReportSummary: document.getElementById('commission-report-summary-grid'),
        commissionReportDailyChart: document.getElementById('commission-report-daily-chart'),
        commissionReportMethodSplit: document.getElementById('commission-report-method-split'),
        commissionReportTopCashiers: document.getElementById('commission-report-top-cashiers'),
        taxSettingsForm: document.getElementById('tax-settings-form'),
        taxSettingsNote: document.getElementById('tax-settings-note'),
        taxRateInput: document.getElementById('tax-rate-input'),
        taxCustomRateEnabledInput: document.getElementById('tax-custom-rate-enabled-input'),
        taxSettlementModeInput: document.getElementById('tax-settlement-mode-input'),
        taxSettlementAccountInput: document.getElementById('tax-settlement-account-input'),
        taxExemptInput: document.getElementById('tax-exempt-input'),
        saveTaxSettingsButton: document.getElementById('save-tax-settings-button'),
        taxRangeFilter: document.getElementById('tax-range-filter'),
        taxDateFromFilter: document.getElementById('tax-date-from-filter'),
        taxDateToFilter: document.getElementById('tax-date-to-filter'),
        taxReportSummary: document.getElementById('tax-report-summary-grid'),
        taxReportDailyChart: document.getElementById('tax-report-daily-chart'),
        taxReportMethodSplit: document.getElementById('tax-report-method-split'),
        modelList: document.getElementById('model-list'),
        resetStoreFormButton: document.getElementById('reset-store-form-button'),
        resetEmployeeFormButton: document.getElementById('reset-employee-form-button'),
        storeForm: document.getElementById('store-form'),
        storePayoutForm: document.getElementById('store-payout-form'),
        employeeForm: document.getElementById('employee-form'),
        terminalForm: document.getElementById('terminal-form'),
        ownerForm: document.getElementById('change-owner-form'),
        modelForm: document.getElementById('model-form'),
        storeEditorTitle: document.getElementById('store-editor-title'),
        storeEditorCopy: document.getElementById('store-editor-copy'),
        storeModeKicker: document.getElementById('store-mode-kicker'),
        storeModeTitle: document.getElementById('store-mode-title'),
        storeModeCopy: document.getElementById('store-mode-copy'),
        storeModeBadge: document.getElementById('store-mode-badge'),
        storeCreateModeButton: document.getElementById('store-create-mode-button'),
        storeIdInput: document.getElementById('store-id-input'),
        storeNameInput: document.getElementById('store-name-input'),
        storeOwnerInput: document.getElementById('store-owner-input'),
        storeSettlementModeInput: document.getElementById('store-settlement-mode-input'),
        storeSettlementAccountInput: document.getElementById('store-settlement-account-input'),
        saveStoreButton: document.getElementById('save-store-button'),
        storeArchiveButton: document.getElementById('archive-store-button'),
        storePayoutTargetNote: document.getElementById('store-payout-target-note'),
        storePayoutAmountInput: document.getElementById('store-payout-amount-input'),
        storePayoutReasonInput: document.getElementById('store-payout-reason-input'),
        storePayoutButton: document.getElementById('store-payout-button'),
        newOwnerInput: document.getElementById('new-owner-input'),
        employeeFormTitle: document.getElementById('employee-form-title'),
        employeeFormNote: document.getElementById('employee-form-note'),
        terminalIdInput: document.getElementById('terminal-id-input'),
        terminalSerialInput: document.getElementById('terminal-serial-input'),
        terminalTypeInput: document.getElementById('terminal-type-input'),
        terminalStatusInput: document.getElementById('terminal-status-input'),
        terminalModelInput: document.getElementById('terminal-model-input'),
        terminalPlacementHelper: document.getElementById('terminal-placement-helper'),
        terminalPlacementStatus: document.getElementById('terminal-placement-status'),
        saveTerminalButton: document.getElementById('save-terminal-button'),
        saveAndGiveTerminalButton: document.getElementById('save-and-give-terminal-button'),
        placeTerminalButton: document.getElementById('place-terminal-button'),
        bindingCodeTypeInput: document.getElementById('binding-code-type-input'),
        bindingCodeNote: document.getElementById('binding-code-note'),
        generateBindingCodeButton: document.getElementById('generate-binding-code-button'),
        employeeCitizenIdInput: document.getElementById('employee-citizenid-input'),
        employeeRoleInput: document.getElementById('employee-role-input'),
        employeeRefundInput: document.getElementById('employee-refund-input'),
        employeeDiscountInput: document.getElementById('employee-discount-input'),
        saveEmployeeButton: document.getElementById('save-employee-button'),
        removeEmployeeButton: document.getElementById('remove-employee-button'),
        transactionTypeFilter: document.getElementById('transaction-type-filter'),
        transactionMethodFilter: document.getElementById('transaction-method-filter'),
        transactionStatusFilter: document.getElementById('transaction-status-filter'),
        transactionDateFromFilter: document.getElementById('transaction-date-from-filter'),
        transactionDateToFilter: document.getElementById('transaction-date-to-filter'),
        reportRangeFilter: document.getElementById('report-range-filter'),
        reportDateFromFilter: document.getElementById('report-date-from-filter'),
        reportDateToFilter: document.getElementById('report-date-to-filter'),
        modelKeyInput: document.getElementById('model-key-input'),
        modelLabelInput: document.getElementById('model-label-input'),
        modelNameInput: document.getElementById('model-name-input'),
        modelStatusInput: document.getElementById('model-status-input')
    };

    const defaultCitizenLookupNote = '输入在线玩家服务器 ID，可自动查到 CitizenID 并填入上方字段。';
    const interactionOnlyModelKey = 'interaction_only';
    const interactionOnlyModelName = 'interaction_only';

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
            refunded: '已退款',
            cancelled: '已取消',
            expired: '已超时',
            failed: '失败',
            active: '启用',
            archived: '归档',
            disabled: '停用',
            paid: '已结清',
            defaulted: '违约',
            open: '待领取',
            claimed: '已领取'
        }[status] || status || '--';
    }

    function formatLoanStatus(status) {
        return {
            active: '活跃',
            paid: '已结清',
            defaulted: '违约',
            cancelled: '已取消'
        }[status] || formatStatus(status);
    }

    function formatCollectionStatus(status) {
        return {
            open: '待领取',
            claimed: '已领取',
            completed: '已完成',
            cancelled: '已取消'
        }[status] || status || '无任务';
    }

    function formatEmployeeRole(role) {
        return {
            owner: '店主',
            manager: '经理',
            cashier: '收银员'
        }[role] || role || '--';
    }

    function formatEmployeeSource(source) {
        return {
            manual: '手动维护',
            public_account_sync: '产业同步'
        }[source] || source || '手动维护';
    }

    function getEmployeeDisplayName(employee) {
        const name = String(employee && employee.name || '').trim();
        if (name) {
            return name;
        }

        const citizenid = String(employee && employee.citizenid || '').trim();
        return citizenid || '未命名员工';
    }

    function isInteractionOnlyModel(modelKey, modelName) {
        return String(modelKey || '').trim() === interactionOnlyModelKey
            || String(modelName || '').trim() === interactionOnlyModelName;
    }

    function formatTerminalModelName(modelName, modelKey) {
        if (isInteractionOnlyModel(modelKey, modelName)) {
            return '无实体模型';
        }

        return modelName || '--';
    }

    function roundCurrency(value) {
        return Math.round((Number(value || 0) + Number.EPSILON) * 100) / 100;
    }

    function formatDateTime(value) {
        if (!value) {
            return '--';
        }

        const text = String(value).replace('T', ' ').replace(/\.\d+Z?$/, '');
        return text.replace(/Z$/, '');
    }

    function toDateTimeLocalValue(value) {
        if (!value) {
            return '';
        }

        return formatDateTime(value).slice(0, 16).replace(' ', 'T');
    }

    function formatDueState(loan) {
        if (!loan || loan.status !== 'active') {
            return formatLoanStatus(loan && loan.status);
        }

        if (loan.is_overdue) {
            return '已逾期';
        }

        const dueIn = Number(loan.due_in || 0);
        if (dueIn > 0 && dueIn <= 259200) {
            return '3 天内到期';
        }

        return '未到期';
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

    function formatTargetType(type) {
        return {
            store: '店铺',
            terminal: '终端',
            employee: '员工',
            transaction: '交易',
            terminal_model: 'POS 型号',
            binding_code: '绑定码',
            loan: '贷款',
            collection_task: '催收任务'
        }[type] || type || '--'
    }

    function formatAuditAction(action) {
        return {
            create_store: '创建店铺',
            update_store: '更新店铺',
            archive_store: '归档店铺',
            restore_store: '取消归档店铺',
            change_owner: '更换店主',
            payout_store: '店铺出款',
            update_store_tax: '更新税务设置',
            update_store_commission: '更新提成设置',
            update_tax_defaults: '更新全局税务设置',
            withdraw_balance: 'VancePay 余额提现',
            save_employee: '保存员工',
            sync_store_employees: '同步产业人员',
            remove_employee: '移除员工',
            create_terminal: '创建终端',
            update_terminal: '更新终端',
            archive_terminal: '归档终端',
            create_terminal_model: '创建型号',
            update_terminal_model: '更新型号',
            archive_terminal_model: '归档型号',
            create_binding_code: '生成绑定码',
            consume_binding_code: '使用绑定码',
            grant_terminal_item: '发放终端物品',
            refund_transaction: '退款交易',
            force_refund: '强制退款',
            create_loan: '发放贷款',
            repay_loan: '贷款还款',
            update_loan: '调整贷款',
            loan_overdue: '贷款逾期',
            loan_overdue_credit_event_failed: '逾期信用事件失败',
            create_collection_task: '生成催收任务',
            cancel_collection_task: '取消催收任务',
            claim_collection_task: '领取催收任务',
            claim_collection_reward: '领取催收奖励'
        }[action] || action || '--'
    }

    function formatAuditKey(key) {
        return {
            name: '名称',
            old_name: '原名称',
            new_name: '新名称',
            owner_citizenid: '店主',
            old_owner_citizenid: '原店主',
            new_owner_citizenid: '新店主',
            settlement_mode: '入账方式',
            old_settlement_mode: '原入账方式',
            new_settlement_mode: '新入账方式',
            settlement_account_identifier: '公账标识',
            old_settlement_account_identifier: '原公账标识',
            new_settlement_account_identifier: '新公账标识',
            tax_rate: '税率',
            old_tax_rate: '原税率',
            new_tax_rate: '新税率',
            commission_rate: '提成比例',
            old_commission_rate: '原提成比例',
            new_commission_rate: '新提成比例',
            custom_tax_rate: '店铺自定义税率',
            default_tax_rate: '默认税率',
            old_default_tax_rate: '原默认税率',
            new_default_tax_rate: '新默认税率',
            tax_custom_rate_enabled: '启用店铺自定义税率',
            old_tax_custom_rate_enabled: '原自定义税率开关',
            new_tax_custom_rate_enabled: '新自定义税率开关',
            tax_exempt: '免税',
            old_tax_exempt: '原免税',
            new_tax_exempt: '新免税',
            tax_amount: '税额',
            commission_amount: '提成金额',
            refunded_tax_amount: '累计已退税额',
            refunded_commission_amount: '累计已冲回提成',
            remaining_tax_amount: '剩余可退税额',
            remaining_commission_amount: '剩余可冲回提成',
            tax_settlement_mode: '税收入账方式',
            old_tax_settlement_mode: '原税收入账方式',
            new_tax_settlement_mode: '新税收入账方式',
            tax_settlement_account_identifier: '税收公账标识',
            old_tax_settlement_account_identifier: '原税收公账标识',
            new_tax_settlement_account_identifier: '新税收公账标识',
            amount: '金额',
            reason: '原因',
            citizenid: 'CitizenID',
            role: '角色',
            can_refund: '退款权限',
            can_discount: '折扣权限',
            employee_source: '员工来源',
            employee_source_key: '来源标识',
            account_type: '账户类型',
            job_name: '岗位名',
            added_count: '新增人数',
            updated_count: '更新人数',
            removed_count: '移除人数',
            unchanged_count: '无变化人数',
            synced_members: '同步成员',
            removed_members: '移除成员',
            serial_number: '序列号',
            terminal_serial_number: '终端序列号',
            type: '类型',
            terminal_type: '终端类型',
            status: '状态',
            store_id: '店铺',
            terminal_id: '终端',
            model_key: '型号 Key',
            model_name: '模型名',
            label: '标签',
            is_system: '系统型号',
            source: '来源',
            binding_code_hint: '绑定码尾号',
            expires_at: '过期时间',
            granted_item: '发放物品',
            metadata_written: 'Metadata 已写回',
            original_tx_code: '原交易',
            reference_code: '流水号',
            refund_amount: '退款金额',
            refund_reason: '退款原因',
            remaining_final_amount: '剩余实付',
            remaining_net_amount: '剩余入账',
            loan_id: '贷款 ID',
            loan_code: '贷款号',
            old_principal_amount: '原本金',
            new_principal_amount: '新本金',
            principal_amount: '本金',
            old_interest_amount: '原利息',
            new_interest_amount: '新利息',
            interest_amount: '利息',
            old_total_due: '原应还总额',
            new_total_due: '新应还总额',
            total_due: '应还总额',
            old_repaid_amount: '原已还金额',
            new_repaid_amount: '新已还金额',
            repaid_amount: '已还金额',
            outstanding_amount: '未还金额',
            old_interest_rate: '原利率',
            new_interest_rate: '新利率',
            interest_rate: '利率',
            old_term_days: '原期限',
            new_term_days: '新期限',
            term_days: '期限天数',
            old_due_at: '原到期时间',
            new_due_at: '新到期时间',
            due_at: '到期时间',
            trust_score: '信誉分',
            trust_band: '信誉档位',
            task_id: '催收任务 ID',
            task_code: '催收任务号',
            debtor_citizenid: '债务人',
            previous_status: '原状态',
            reward_amount: '奖励金额',
            reward_rate: '奖励比例',
            coords: '坐标',
            heading: '朝向'
        }[key] || String(key || '--').replace(/_/g, ' ')
    }

    function formatAuditValue(key, value) {
        if (value == null || value === '') {
            return '--'
        }

        if (/settlement_mode/.test(key)) {
            return value === 'public_account' ? '绑定公账' : 'VancePay 店铺余额'
        }

        if (key === 'employee_source' || key === 'old_employee_source' || key === 'new_employee_source') {
            return value === 'public_account_sync' ? '产业同步' : '手动维护'
        }

        if (key === 'account_type') {
            return value === 'society' ? '产业账户' : String(value)
        }

        if (typeof value === 'number') {
            if (/_rate$/.test(key)) {
                return `${value.toFixed(2)}%`
            }

            if (/(amount|subtotal|discount|tip|fee|tax|net|gross|balance|principal|interest|due|repaid|outstanding|reward)/.test(key)) {
                return app.formatCurrency(value)
            }

            if (key === 'heading') {
                return value.toFixed(2)
            }

            return String(value)
        }

        if (key === 'model_name') {
            return formatTerminalModelName(value)
        }

        if (typeof value === 'boolean') {
            return value ? '是' : '否'
        }

        if (Array.isArray(value)) {
            return value.length
                ? value.slice(0, 2).map((item) => formatAuditValue(key, item)).join(', ')
                : '--'
        }

        if (typeof value === 'object') {
            if (value.x != null || value.y != null || value.z != null) {
                const coords = ['x', 'y', 'z']
                    .filter((axis) => value[axis] != null)
                    .map((axis) => `${axis.toUpperCase()} ${Number(value[axis]).toFixed(2)}`)

                return coords.join(' · ') || '--'
            }

            const nestedParts = Object.entries(value)
                .filter(([, nestedValue]) => nestedValue != null && nestedValue !== '')
                .slice(0, 2)
                .map(([nestedKey, nestedValue]) => `${formatAuditKey(nestedKey)} ${formatAuditValue(nestedKey, nestedValue)}`)

            return nestedParts.join(' · ') || '--'
        }

        return String(value)
    }

    function buildAuditSummary(detail) {
        if (!detail || typeof detail !== 'object' || Array.isArray(detail)) {
            return ''
        }

        const parts = Object.entries(detail)
            .filter(([, value]) => value != null && value !== '')
            .slice(0, 3)
            .map(([key, value]) => `${formatAuditKey(key)} ${formatAuditValue(key, value)}`)

        return parts.join(' · ')
    }

    function buildTransactionChips(transaction) {
        const chips = [
            { tone: 'type', label: formatType(transaction.type) },
            { tone: 'method', label: formatMethod(transaction.method) },
            { tone: 'status', label: formatStatus(transaction.status) }
        ]

        if (transaction.type === 'payment' && Number(transaction.refunded_final_amount || 0) > 0) {
            chips.push({
                tone: 'refund',
                label: `已退 ${app.formatCurrency(transaction.refunded_final_amount)}`
            })
        }

        return chips.map((chip) => `
            <span class="list-badge" data-tone="${chip.tone}">${escapeHtml(chip.label)}</span>
        `).join('')
    }

    function buildTransactionFacts(transaction) {
        const facts = [
            ['时间', app.formatDate(transaction.created_at)]
        ]

        if (transaction.type === 'refund' && transaction.original_tx_code) {
            facts.push(['关联原单', transaction.original_tx_code])
        }

        if (Number(transaction.commission_amount || 0) > 0) {
            facts.push(['提成', `${Number(transaction.commission_rate || 0).toFixed(2)}% · ${app.formatCurrency(transaction.commission_amount || 0)}`])
        }

        const itemMeta = buildItemMeta(transaction.item_description, transaction.item_lines)
        if (itemMeta) {
            facts.push(['商品概览', itemMeta])
        }

        return facts.map(([label, value]) => `
            <div class="meta-pair">
                <label>${escapeHtml(label)}</label>
                <span>${escapeHtml(value)}</span>
            </div>
        `).join('')
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

    function canRefundTransaction(transaction) {
        return Boolean(
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

        const transaction = ((state.payload.transactions && state.payload.transactions.items) || []).find((entry) => Number(entry.id) === numericId);
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

        return ((state.payload.transactions && state.payload.transactions.items) || []).find((entry) => Number(entry.id) === numericId) || null;
    }

    function downloadPayload(data) {
        if (!data || !data.content) {
            app.setRibbon('导出内容为空', 'error');
            return;
        }

        const blob = new Blob([data.content], { type: data.mime || 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = data.filename || 'vancepay-export.txt';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        setTimeout(() => URL.revokeObjectURL(url), 1000);
    }

    function collectTransactionFilters() {
        return {
            store_id: state.payload.selected_store_id,
            type: elements.transactionTypeFilter.value,
            method: elements.transactionMethodFilter.value,
            status: elements.transactionStatusFilter.value,
            date_from: elements.transactionDateFromFilter.value || undefined,
            date_to: elements.transactionDateToFilter.value || undefined
        };
    }

    function collectLoanFilters() {
        return {
            search: elements.loanSearchFilter ? elements.loanSearchFilter.value.trim() || undefined : undefined,
            status: elements.loanStatusFilter ? elements.loanStatusFilter.value : 'all',
            due_state: elements.loanDueFilter ? elements.loanDueFilter.value : 'all',
            collection_status: elements.loanCollectionFilter ? elements.loanCollectionFilter.value : 'all',
            page: 1,
            per_page: 25
        };
    }

    function collectReportFilters() {
        return {
            store_id: state.payload.selected_store_id,
            range_days: Number(elements.reportRangeFilter.value || 7),
            date_from: elements.reportDateFromFilter.value || undefined,
            date_to: elements.reportDateToFilter.value || undefined
        };
    }

    function collectTaxFilters() {
        return {
            store_id: state.payload.selected_store_id,
            range_days: Number(elements.taxRangeFilter.value || 7),
            date_from: elements.taxDateFromFilter.value || undefined,
            date_to: elements.taxDateToFilter.value || undefined
        };
    }

    function collectCommissionFilters() {
        return {
            store_id: state.payload.selected_store_id,
            range_days: Number(elements.commissionRangeFilter.value || 7),
            date_from: elements.commissionDateFromFilter.value || undefined,
            date_to: elements.commissionDateToFilter.value || undefined
        };
    }

    function renderOverview() {
        const overview = state.payload.overview || {};
        const items = [
            [overview.balance_label || '余额', app.formatCurrency(overview.balance || 0)],
            ['提成率', `${Number(overview.commission_rate || 0).toFixed(2)}%`],
            ['今日净提成', app.formatCurrency(overview.today_net_commission_amount || 0)],
            ['终端数', String(overview.terminal_count || 0)],
            ['员工数', String(overview.employee_count || 0)],
            ['今日交易', String(overview.today_transaction_count || 0)],
            ['待处理', String(overview.pending_count || 0)]
        ];

        elements.overviewStrip.innerHTML = items.map(([label, value]) => `
            <div class="overview-pill">
                <label>${label}</label>
                <strong>${value}</strong>
            </div>
        `).join('');
    }

    function renderStoreSelector() {
        const stores = state.payload.stores || [];
        elements.storeSelect.innerHTML = stores.map((store) => `
            <option value="${store.id}" ${store.id === state.payload.selected_store_id ? 'selected' : ''}>
                ${escapeHtml(store.name)} · ${escapeHtml(store.status)}
            </option>
        `).join('') || '<option value="">暂无店铺</option>';
    }

    function renderTerminalModelOptions(selectedKey) {
        const models = state.payload.active_terminal_models || [];
        elements.terminalModelInput.innerHTML = models.map((model) => `
            <option value="${escapeHtml(model.model_key)}" ${model.model_key === selectedKey ? 'selected' : ''}>
                ${escapeHtml(model.label)} · ${escapeHtml(formatTerminalModelName(model.model_name, model.model_key))}
            </option>
        `).join('') || '<option value="">暂无可用型号</option>';

        elements.terminalModelInput.disabled = elements.terminalTypeInput.value !== 'fixed';
    }

    function findStoreById(storeId) {
        const numericId = Number(storeId || 0);
        if (!numericId) {
            return null;
        }

        return (state.payload.stores || []).find((entry) => Number(entry.id) === numericId) || null;
    }

    function getSelectedStore() {
        return findStoreById(state.payload.selected_store_id);
    }

    function buildTaxDestinationLabel(settlementMode, settlementAccountIdentifier) {
        if (settlementMode === 'public_account') {
            return settlementAccountIdentifier
                ? `税收公账 ${settlementAccountIdentifier}`
                : '税收公账';
        }

        return '当前店铺 VancePay 余额';
    }

    function buildTaxTargetLabel(store, options = {}) {
        const taxDefaults = state.payload.tax_defaults || {};
        const taxExempt = options.taxExempt != null
            ? Boolean(options.taxExempt)
            : Boolean(store && store.tax_exempt);
        const effectiveTaxRate = Number(
            options.effectiveTaxRate != null
                ? options.effectiveTaxRate
                : ((store && store.effective_tax_rate) || 0)
        );
        const settlementMode = options.taxSettlementMode || taxDefaults.tax_settlement_mode || 'store_balance';
        const settlementAccountIdentifier = String(
            options.taxSettlementAccountIdentifier != null
                ? options.taxSettlementAccountIdentifier
                : (taxDefaults.tax_settlement_account_identifier || '')
        ).trim();

        if (taxExempt) {
            return '免税';
        }

        if (!(effectiveTaxRate > 0)) {
            return '未启用税收';
        }

        return buildTaxDestinationLabel(settlementMode, settlementAccountIdentifier);
    }

    function getTaxFormState(store) {
        const taxDefaults = state.payload.tax_defaults || {};
        const defaultTaxRate = Number(
            elements.taxDefaultRateInput && elements.taxDefaultRateInput.value !== ''
                ? elements.taxDefaultRateInput.value
                : (taxDefaults.default_tax_rate != null ? taxDefaults.default_tax_rate : store && store.default_tax_rate) || 0
        );
        const customRate = Number(
            elements.taxRateInput && elements.taxRateInput.value !== ''
                ? elements.taxRateInput.value
                : (store && store.custom_tax_rate != null ? store.custom_tax_rate : store && store.tax_rate) || 0
        );
        const customRateEnabled = Boolean(
            elements.taxCustomRateEnabledInput
                ? elements.taxCustomRateEnabledInput.checked
                : (store && store.tax_custom_rate_enabled)
        );
        const taxExempt = Boolean(
            elements.taxExemptInput
                ? elements.taxExemptInput.checked
                : (store && store.tax_exempt)
        );
        const taxSettlementMode = elements.taxSettlementModeInput
            ? elements.taxSettlementModeInput.value
            : (taxDefaults.tax_settlement_mode || 'store_balance');
        const taxSettlementAccountIdentifier = elements.taxSettlementAccountInput
            ? elements.taxSettlementAccountInput.value
            : (taxDefaults.tax_settlement_account_identifier || '');
        const effectiveTaxRate = taxExempt
            ? 0
            : (customRateEnabled ? customRate : defaultTaxRate);
        const taxDestinationLabel = buildTaxDestinationLabel(taxSettlementMode, taxSettlementAccountIdentifier);

        return {
            defaultTaxRate,
            customRate,
            customRateEnabled,
            taxExempt,
            taxSettlementMode,
            taxSettlementAccountIdentifier,
            effectiveTaxRate,
            taxDestinationLabel,
            taxTargetLabel: buildTaxTargetLabel(store, {
                taxExempt,
                effectiveTaxRate,
                taxSettlementMode,
                taxSettlementAccountIdentifier
            })
        };
    }

    function isStoreTabletMode() {
        return state.payload.mode === 'store';
    }

    function canCreateStore() {
        return !isStoreTabletMode();
    }

    function canManuallyManageEmployees() {
        return !isStoreTabletMode();
    }

    function findEmployeeByCitizenId(citizenid) {
        citizenid = String(citizenid || '').trim();
        if (!citizenid) {
            return null;
        }

        return (state.payload.employees || []).find((entry) => entry.citizenid === citizenid) || null;
    }

    function getEditingEmployee() {
        return findEmployeeByCitizenId(elements.employeeCitizenIdInput.value);
    }

    function getEditingStore() {
        const storeId = Number(elements.storeIdInput.value || 0);
        if (!storeId) {
            return null;
        }

        return findStoreById(storeId) || {
            id: storeId,
            name: elements.storeNameInput.value,
            owner_citizenid: elements.storeOwnerInput.value,
            settlement_mode: elements.storeSettlementModeInput ? elements.storeSettlementModeInput.value : 'store_balance',
            settlement_account_identifier: elements.storeSettlementAccountInput ? elements.storeSettlementAccountInput.value : '',
            status: 'active'
        };
    }

    function fillTaxForm(store) {
        store = store || {};
        const taxDefaults = state.payload.tax_defaults || {};

        if (elements.taxDefaultRateInput) {
            const defaultRate = taxDefaults.default_tax_rate != null ? taxDefaults.default_tax_rate : store.default_tax_rate;
            elements.taxDefaultRateInput.value = defaultRate != null ? Number(defaultRate).toFixed(2) : '0.00';
        }

        if (elements.taxRateInput) {
            const customRate = store.custom_tax_rate != null ? store.custom_tax_rate : store.tax_rate;
            elements.taxRateInput.value = customRate != null ? Number(customRate).toFixed(2) : '0.00';
        }

        if (elements.taxCustomRateEnabledInput) {
            elements.taxCustomRateEnabledInput.checked = Boolean(store.tax_custom_rate_enabled);
        }

        if (elements.taxSettlementModeInput) {
            elements.taxSettlementModeInput.value = taxDefaults.tax_settlement_mode || 'store_balance';
        }

        if (elements.taxSettlementAccountInput) {
            elements.taxSettlementAccountInput.value = taxDefaults.tax_settlement_account_identifier || '';
        }

        if (elements.taxExemptInput) {
            elements.taxExemptInput.checked = Boolean(store.tax_exempt);
        }
    }

    function fillCommissionForm(store) {
        store = store || {};

        if (elements.commissionRateInput) {
            elements.commissionRateInput.value = store.commission_rate != null
                ? Number(store.commission_rate).toFixed(2)
                : '0.00';
        }
    }

    function fillStoreForm(store) {
        store = store || {};
        state.storeCreateMode = !(store && store.id);
        elements.storeIdInput.value = store.id || '';
        elements.storeNameInput.value = store.name || '';
        elements.storeOwnerInput.value = store.owner_citizenid || '';

        if (elements.storeSettlementModeInput) {
            elements.storeSettlementModeInput.value = store.settlement_mode || 'store_balance';
        }

        if (elements.storeSettlementAccountInput) {
            elements.storeSettlementAccountInput.value = store.settlement_account_identifier || '';
        }
    }

    function resetStoreForm() {
        if (!canCreateStore()) {
            state.storeCreateMode = false;
            fillStoreForm(getSelectedStore());
            renderStoreFormState(getSelectedStore());
            resetCitizenLookup('store-owner-input', true);
            resetCitizenLookup('new-owner-input', true);
            return;
        }

        state.storeCreateMode = true;
        fillStoreForm(null);
        elements.newOwnerInput.value = '';
        renderStoreFormState();
        resetCitizenLookup('store-owner-input', true);
        resetCitizenLookup('new-owner-input', true);
    }

    function fillEmployeeForm(employee) {
        employee = employee || {};
        elements.employeeCitizenIdInput.value = employee.citizenid || '';
        elements.employeeRoleInput.value = employee.role === 'owner' ? 'manager' : (employee.role || 'cashier');
        elements.employeeRefundInput.checked = Number(employee.can_refund) === 1;
        elements.employeeDiscountInput.checked = Number(employee.can_discount) === 1;
    }

    function resetEmployeeForm() {
        fillEmployeeForm(null);
        resetCitizenLookup('employee-citizenid-input', true);
        renderEmployeeFormState();
    }

    function getSelectedTerminal() {
        const terminalId = Number(elements.terminalIdInput.value || 0);
        if (!terminalId) {
            return null;
        }

        return (state.payload.terminals || []).find((entry) => Number(entry.id) === terminalId) || null;
    }

    function canUseFixedTerminalType() {
        const terminal = getSelectedTerminal();
        return Boolean(state.payload.is_admin || (terminal && terminal.type === 'fixed'));
    }

    function syncTerminalTypeAccess() {
        const fixedOption = elements.terminalTypeInput.querySelector('option[value="fixed"]');
        const canUseFixedType = canUseFixedTerminalType();

        if (fixedOption) {
            fixedOption.hidden = !canUseFixedType;
            fixedOption.disabled = !canUseFixedType;
        }

        if (!canUseFixedType && elements.terminalTypeInput.value === 'fixed') {
            elements.terminalTypeInput.value = 'portable';
        }

        return canUseFixedType;
    }

    function formatTerminalCoords(coords) {
        if (!coords || typeof coords !== 'object') {
            return '--';
        }

        return [coords.x, coords.y, coords.z]
            .map((value) => Number(value || 0).toFixed(2))
            .join(', ');
    }

    function renderTerminalFormState() {
        const terminal = getSelectedTerminal();
        const canUseFixedType = syncTerminalTypeAccess();
        const terminalType = elements.terminalTypeInput.value;
        const isFixed = terminalType === 'fixed';
        const selectedModelKey = elements.terminalModelInput.value;
        const selectedModel = (state.payload.active_terminal_models || []).find((entry) => entry.model_key === selectedModelKey);
        const isInteractionOnlyFixed = isFixed && isInteractionOnlyModel(
            selectedModelKey,
            selectedModel && selectedModel.model_name
        );
        const canGrantItem = Boolean(state.payload.is_admin) && (terminalType === 'portable' || terminalType === 'tablet');
        const hasPlacement = Boolean(terminal && terminal.type === 'fixed' && terminal.coords);

        elements.terminalPlacementStatus.classList.toggle('hidden', !isFixed);
        elements.placeTerminalButton.classList.toggle('hidden', !isFixed || !hasPlacement);
        elements.saveAndGiveTerminalButton.classList.toggle('hidden', !canGrantItem);

        if (!isFixed) {
            elements.saveTerminalButton.textContent = '保存终端';
            elements.saveAndGiveTerminalButton.textContent = '保存并发给我';
            elements.terminalPlacementHelper.textContent = '便携 POS 和管理平板会直接保存，不需要摆放。';
            elements.terminalPlacementStatus.textContent = '';
            return;
        }

        if (!canUseFixedType) {
            elements.saveTerminalButton.textContent = '保存终端';
            elements.terminalPlacementHelper.textContent = '只有管理员可以新建固定 POS。';
            elements.terminalPlacementStatus.textContent = '';
            return;
        }

        if (hasPlacement) {
            elements.saveTerminalButton.textContent = '保存设置';
            elements.placeTerminalButton.textContent = '重新摆放并保存';
            elements.terminalPlacementHelper.textContent = isInteractionOnlyFixed
                ? '该固定 POS 不会生成实体模型，只会在当前位置创建交互点。需要移动位置时，使用“重新摆放并保存”。'
                : '修改固定 POS 的型号或状态时会保留原摆放点。需要移动机器时，使用“重新摆放并保存”。';
            elements.terminalPlacementStatus.textContent = `当前摆放：${formatTerminalCoords(terminal.coords)} · 朝向 ${Number(terminal.heading || 0).toFixed(1)}°`;
            return;
        }

        elements.saveTerminalButton.textContent = '进入摆放并保存';
        elements.terminalPlacementHelper.textContent = isInteractionOnlyFixed
            ? '该固定 POS 不会生成实体模型，只会在世界里创建交互点。进入摆放后会显示明显红色标记，方便贴到现有收银机模型上。'
            : '固定 POS 会进入世界预览。把准星对准台面后确认，终端才会真正保存。';
        elements.terminalPlacementStatus.textContent = isInteractionOnlyFixed
            ? '无模型交互点会从你当前准星命中的台面开始预览摆放。'
            : '新固定 POS 会从你当前准星命中的台面开始预览摆放。';
    }

    function renderBindingCodeState() {
        const bindingCode = state.generatedBindingCode;

        if (!bindingCode || Number(bindingCode.store_id || 0) !== Number(state.payload.selected_store_id || 0)) {
            elements.bindingCodeNote.classList.add('hidden');
            elements.bindingCodeNote.innerHTML = '';
            return;
        }

        elements.bindingCodeNote.classList.remove('hidden');
        elements.bindingCodeNote.innerHTML = `
            当前有效绑定码：<strong>${escapeHtml(bindingCode.code || '--')}</strong><br>
            设备 ${escapeHtml(bindingCode.terminal_type === 'tablet' ? '管理平板' : '便携 POS')}
            · 店铺 ${escapeHtml(bindingCode.store_name || '--')}
            · 截止 ${escapeHtml(formatDateTime(bindingCode.expires_at))}
        `;
    }

    function buildTerminalPayload(extra = {}) {
        return Object.assign({
            id: elements.terminalIdInput.value ? Number(elements.terminalIdInput.value) : undefined,
            store_id: state.payload.selected_store_id,
            serial_number: elements.terminalSerialInput.value,
            type: elements.terminalTypeInput.value,
            status: elements.terminalStatusInput.value,
            model_key: elements.terminalModelInput.value
        }, extra);
    }

    async function submitTerminalForm(extra = {}) {
        if (extra.grant_item && !state.payload.is_admin) {
            app.setRibbon('只有管理员可以直接发放终端物品', 'error');
            return;
        }

        if (!state.payload.is_admin && !elements.terminalIdInput.value && elements.terminalTypeInput.value === 'fixed') {
            renderTerminalFormState();
            app.setRibbon('只有管理员可以新建固定 POS', 'error');
            return;
        }

        const response = await app.post('saveTerminal', buildTerminalPayload(extra));
        const tone = !response.ok
            ? 'error'
            : ((response.message || '').includes('摆放模式') ? 'neutral' : 'success');
        app.setRibbon(response.message || '终端已保存', tone);
    }

    function renderStores() {
        const stores = state.payload.stores || [];
        elements.storeList.innerHTML = stores.map((store) => `
            <div class="table-item ${store.id === state.payload.selected_store_id ? 'active' : ''}" data-store-id="${store.id}">
                <div class="item-headline">
                    <strong>${escapeHtml(store.name)}</strong>
                    <span>${app.formatCurrency(store.available_balance != null ? store.available_balance : store.balance)}</span>
                </div>
                <div class="item-subcopy">
                    owner ${escapeHtml(store.owner_citizenid)} · 提成 ${Number(store.commission_rate || 0).toFixed(2)}% · ${escapeHtml(store.settlement_target_label || 'VancePay 店铺余额')} · ${escapeHtml(store.status)} · terminals ${store.terminal_count || 0}
                </div>
            </div>
        `).join('') || '<div class="table-item">暂无店铺</div>';
    }

    function isPublicAccountStore(store) {
        return store && store.settlement_mode === 'public_account';
    }

    function isPublicAccountMode(mode) {
        return mode === 'public_account';
    }

    function renderStoreSettlementFields() {
        const isAdmin = Boolean(state.payload.is_admin);
        const mode = elements.storeSettlementModeInput ? elements.storeSettlementModeInput.value : 'store_balance';
        const showPublicAccountField = isAdmin && mode === 'public_account';

        if (elements.storeSettlementModeInput) {
            elements.storeSettlementModeInput.disabled = !isAdmin;
        }

        if (elements.storeSettlementAccountInput) {
            const field = elements.storeSettlementAccountInput.closest('.field');
            if (field) {
                field.classList.toggle('hidden', !showPublicAccountField);
            }

            elements.storeSettlementAccountInput.disabled = !showPublicAccountField;
            if (!showPublicAccountField) {
                elements.storeSettlementAccountInput.value = '';
            }
        }
    }

    function renderTaxSettings() {
        const store = getSelectedStore();
        const isAdmin = Boolean(state.payload.is_admin);
        const readOnly = !store || !isAdmin;
        const taxFormState = getTaxFormState(store);
        const showPublicAccountField = isPublicAccountMode(taxFormState.taxSettlementMode);

        if (!store) {
            elements.taxSettingsNote.textContent = taxFormState.defaultTaxRate > 0
                ? `当前全局默认税率为 ${taxFormState.defaultTaxRate.toFixed(2)}%，税款统一进入 ${taxFormState.taxDestinationLabel}。选择店铺后可配置店铺自定义税率与免税状态。`
                : `当前全局默认税率为 0%，税收尚未启用；启用后税款将统一进入 ${taxFormState.taxDestinationLabel}。选择店铺后可配置店铺自定义税率与免税状态。`;
        } else if (taxFormState.taxExempt) {
            const preservedRate = taxFormState.customRateEnabled
                ? taxFormState.customRate
                : taxFormState.defaultTaxRate;
            elements.taxSettingsNote.textContent = `当前店铺已设为免税，恢复征税后将使用${taxFormState.customRateEnabled ? '店铺自定义' : '全局默认'}税率 ${Number(preservedRate || 0).toFixed(2)}%，税款统一进入 ${taxFormState.taxDestinationLabel}。`;
        } else if (taxFormState.effectiveTaxRate > 0) {
            elements.taxSettingsNote.textContent = taxFormState.customRateEnabled
                ? `当前店铺启用了自定义税率 ${taxFormState.effectiveTaxRate.toFixed(2)}%，全局默认税率为 ${taxFormState.defaultTaxRate.toFixed(2)}%，税款统一进入 ${taxFormState.taxDestinationLabel}。`
                : `当前店铺使用全局默认税率 ${taxFormState.effectiveTaxRate.toFixed(2)}%，税款统一进入 ${taxFormState.taxDestinationLabel}；如需特定店铺单独税率，请开启自定义税率。`;
        } else {
            elements.taxSettingsNote.textContent = taxFormState.customRateEnabled
                ? '当前店铺已启用自定义税率，但税率为 0%，目前不会产生税额。'
                : `当前全局默认税率为 0%，当前店铺未启用税收；一旦恢复征税，税款将统一进入 ${taxFormState.taxDestinationLabel}。`;
        }

        if (elements.taxDefaultRateInput) {
            elements.taxDefaultRateInput.disabled = !isAdmin;
        }

        if (elements.saveTaxDefaultButton) {
            elements.saveTaxDefaultButton.disabled = !isAdmin;
        }

        if (elements.taxSettlementModeInput) {
            elements.taxSettlementModeInput.disabled = !isAdmin;
        }

        if (elements.taxSettlementAccountInput) {
            const field = elements.taxSettlementAccountInput.closest('.field');
            if (field) {
                field.classList.toggle('hidden', !showPublicAccountField);
            }

            elements.taxSettlementAccountInput.disabled = !isAdmin || !showPublicAccountField;
            if (!showPublicAccountField) {
                elements.taxSettlementAccountInput.value = '';
            }
        }

        if (elements.taxRateInput) {
            elements.taxRateInput.disabled = readOnly || !taxFormState.customRateEnabled;
        }

        if (elements.taxCustomRateEnabledInput) {
            elements.taxCustomRateEnabledInput.disabled = readOnly;
        }

        if (elements.taxExemptInput) {
            elements.taxExemptInput.disabled = readOnly;
        }

        if (elements.saveTaxSettingsButton) {
            elements.saveTaxSettingsButton.disabled = readOnly;
        }
    }

    function renderCommissionSettings() {
        const store = getSelectedStore();
        const readOnly = !store;
        const commissionRate = Number(
            elements.commissionRateInput && elements.commissionRateInput.value !== ''
                ? elements.commissionRateInput.value
                : (store && store.commission_rate) || 0
        );

        if (!store) {
            elements.commissionSettingsNote.textContent = '选择店铺后可设置提成比例。提成按店铺净入账金额计算，不含税；生成后进入开单收银员的 VancePay 余额，24 小时后可提现。';
        } else if (commissionRate > 0) {
            elements.commissionSettingsNote.textContent = `当前店铺提成比例为 ${commissionRate.toFixed(2)}%。每笔交易会按净入账金额自动拆出提成，进入开单收银员的 VancePay 余额；若交易退款，系统会按比例自动冲回。`;
        } else {
            elements.commissionSettingsNote.textContent = '当前店铺未启用提成。设置为大于 0 的比例后，新开订单才会开始累计提成，历史订单不会回溯补算。';
        }

        if (elements.commissionBalanceNote) {
            const todayNetCommission = Number(store && store.today_net_commission_amount || 0);
            elements.commissionBalanceNote.textContent = store
                ? `店铺 ${store.name || '--'} 当前提成比例 ${commissionRate.toFixed(2)}%，今日净提成 ${app.formatCurrency(todayNetCommission)}。提成锁定 24 小时，到期后收银员可在手机的 VancePay 余额页提现。`
                : '每笔提成都先进入收银员的 VancePay 余额，锁定 24 小时后才可提现到银行；退款会自动生成提成冲回流水。';
        }

        if (elements.commissionRateInput) {
            elements.commissionRateInput.disabled = readOnly;
        }

        if (elements.saveCommissionSettingsButton) {
            elements.saveCommissionSettingsButton.disabled = readOnly;
        }
    }

    function renderStorePayout() {
        const store = getSelectedStore();
        const isDirectPublicAccount = isPublicAccountStore(store);
        const balance = roundCurrency(store && (store.payout_available_balance != null ? store.payout_available_balance : store.balance) || 0);
        const disabled = !store || !(balance > 0);

        if (!store) {
            elements.storePayoutTargetNote.textContent = '选择店铺后可将余额结算到当前店主银行账户。';
        } else if (isDirectPublicAccount) {
            elements.storePayoutTargetNote.textContent = `当前店铺为公账直入模式，交易会直接进入 ${store.settlement_target_label || '绑定公账'}，不会累计到 VancePay 店铺余额。`;
        } else if (!(balance > 0)) {
            elements.storePayoutTargetNote.textContent = `店主 ${store.owner_citizenid || '--'} 当前暂无可提现余额。`;
        } else {
            elements.storePayoutTargetNote.textContent = `当前最多可向店主 ${store.owner_citizenid || '--'} 结算 ${app.formatCurrency(balance)}，提现后会同步减少店铺可退款余额。`;
        }

        elements.storePayoutAmountInput.disabled = disabled || isDirectPublicAccount;
        elements.storePayoutReasonInput.disabled = disabled || isDirectPublicAccount;
        elements.storePayoutButton.disabled = disabled || isDirectPublicAccount;
        elements.storePayoutAmountInput.max = balance > 0 ? String(balance) : '';
        elements.storePayoutAmountInput.placeholder = store
            ? `最多 ${app.formatCurrency(balance)}`
            : '100.00';

        if (disabled || isDirectPublicAccount) {
            elements.storePayoutAmountInput.value = '';
            elements.storePayoutReasonInput.value = '';
            return;
        }

        const currentAmount = Number(elements.storePayoutAmountInput.value || 0);
        if (currentAmount > balance) {
            elements.storePayoutAmountInput.value = balance.toFixed(2);
        }
    }

    function renderStoreFormState(storeOverride = null) {
        const storeTabletMode = isStoreTabletMode();
        const storeId = Number(elements.storeIdInput.value || 0);
        const store = storeOverride || getEditingStore();
        const isEditing = storeId > 0;
        const isArchived = store && store.status === 'archived';
        const storeName = String(elements.storeNameInput.value || (store && store.name) || '').trim();
        const ownerCitizenId = String(elements.storeOwnerInput.value || (store && store.owner_citizenid) || '').trim();
        const displayName = storeName || (store && store.name) || (isEditing ? `店铺 #${storeId}` : '新店铺');

        if (elements.resetStoreFormButton) {
            elements.resetStoreFormButton.classList.toggle('hidden', storeTabletMode);
        }

        if (isEditing) {
            elements.storeEditorTitle.textContent = `编辑店铺 · ${displayName}`;
            elements.storeEditorCopy.textContent = storeTabletMode
                ? '当前表单已绑定现有店铺。店铺平板仅支持编辑已绑定店铺，不支持新建店铺。'
                : '当前表单已绑定现有店铺。修改后直接保存；需要创建新店铺时，点击右侧按钮切换回新建模式。';
            elements.storeModeKicker.textContent = '当前工作区';
            elements.storeModeTitle.textContent = displayName;
            elements.storeModeCopy.textContent = isArchived
                ? '该店铺当前处于归档状态。取消归档后，相关终端和管理流转才会恢复正常。'
                : `当前正在编辑店主 ${ownerCitizenId || '--'} 的店铺资料；左侧点击其他店铺可快速切换。`;
            elements.storeModeBadge.dataset.mode = 'edit';
            elements.storeModeBadge.textContent = '编辑模式';
            elements.storeCreateModeButton.classList.toggle('hidden', storeTabletMode);
        } else {
            elements.storeEditorTitle.textContent = storeTabletMode ? '当前店铺' : '新建店铺';
            elements.storeEditorCopy.textContent = storeTabletMode
                ? '当前平板未载入可编辑店铺，且不支持新建店铺。'
                : '填写基础信息后创建店铺；点击左侧店铺卡片可切换到编辑模式。';
            elements.storeModeKicker.textContent = '当前工作区';
            elements.storeModeTitle.textContent = storeTabletMode ? '仅可编辑已绑定店铺' : '新建模式';
            elements.storeModeCopy.textContent = storeTabletMode
                ? '请选择当前绑定店铺后再编辑资料；店铺平板不会提供新建入口。'
                : '保存成功后，这里会切换到该店铺的后续管理操作；更换店主和提现仅对已创建店铺开放。';
            elements.storeModeBadge.dataset.mode = storeTabletMode ? 'edit' : 'create';
            elements.storeModeBadge.textContent = storeTabletMode ? '平板模式' : '新建模式';
            elements.storeCreateModeButton.classList.add('hidden');
        }

        elements.saveStoreButton.textContent = isEditing ? '保存修改' : (storeTabletMode ? '店铺平板不可新建' : '创建店铺');
        elements.saveStoreButton.disabled = storeTabletMode && !isEditing;
        elements.storeArchiveButton.disabled = !store;
        elements.storeArchiveButton.textContent = !store
            ? '需先选择店铺'
            : (isArchived ? '取消归档' : '归档店铺');
        renderStoreSettlementFields();
    }

    function getCitizenLookupContainers(targetInputId) {
        return Array.from(document.querySelectorAll('[data-citizenid-lookup]')).filter((container) => {
            return !targetInputId || container.dataset.targetInput === targetInputId;
        });
    }

    function setCitizenLookupNote(container, message = defaultCitizenLookupNote, tone = '') {
        const note = container && container.querySelector('[data-lookup-note]');
        if (!note) {
            return;
        }

        note.textContent = message || defaultCitizenLookupNote;

        if (tone) {
            note.dataset.tone = tone;
        } else {
            delete note.dataset.tone;
        }
    }

    function resetCitizenLookup(targetInputId, clearPlayerId = false) {
        getCitizenLookupContainers(targetInputId).forEach((container) => {
            if (clearPlayerId) {
                const playerIdInput = container.querySelector('[data-player-id-input]');
                if (playerIdInput) {
                    playerIdInput.value = '';
                }
            }

            setCitizenLookupNote(container);
        });
    }

    function getCitizenLookupStoreId(container) {
        const context = container && container.dataset.storeContext;

        if (context === 'editing') {
            const editingStoreId = Number(elements.storeIdInput.value || 0);
            if (editingStoreId) {
                return editingStoreId;
            }
        }

        const selectedStoreId = Number(state.payload.selected_store_id || 0);
        return selectedStoreId || undefined;
    }

    async function fillCitizenIdFromPlayerId(container) {
        const playerIdInput = container && container.querySelector('[data-player-id-input]');
        const targetInput = container && document.getElementById(container.dataset.targetInput || '');

        if (!playerIdInput || !targetInput) {
            return;
        }

        const playerId = Number(playerIdInput.value || 0);
        if (!Number.isInteger(playerId) || playerId < 1) {
            const message = '请输入有效的在线玩家服务器 ID';
            setCitizenLookupNote(container, message, 'error');
            app.setRibbon(message, 'error');
            playerIdInput.focus();
            return;
        }

        const response = await app.post('resolveCitizenIdByPlayerId', {
            player_id: playerId,
            store_id: getCitizenLookupStoreId(container)
        });

        if (!response.ok) {
            const message = response.message || '查询 CitizenID 失败';
            setCitizenLookupNote(container, message, 'error');
            app.setRibbon(message, 'error');
            return;
        }

        const result = response.data || {};
        targetInput.value = result.citizenid || '';
        targetInput.dispatchEvent(new Event('input', { bubbles: true }));

        const message = result.citizenid
            ? `已填入 ${result.name || ('玩家 #' + String(result.source || playerId))} 的 CitizenID：${result.citizenid}`
            : '未找到可填入的 CitizenID';

        setCitizenLookupNote(container, message, 'success');
        app.setRibbon(response.message || 'CitizenID 已填入', 'success');
    }

    function renderTerminals() {
        const terminals = state.payload.terminals || [];
        elements.terminalList.innerHTML = terminals.map((terminal) => `
            <div class="table-item" data-terminal-id="${terminal.id}">
                <div class="item-headline">
                    <strong>${escapeHtml(terminal.serial_number)}</strong>
                    <span>${escapeHtml(terminal.type)}</span>
                </div>
                <div class="item-subcopy">
                    ${escapeHtml(formatStatus(terminal.status))}
                    · ${escapeHtml(terminal.store_name || '未绑定')}
                    ${terminal.model_label ? ` · ${escapeHtml(terminal.model_label)}` : ''}
                </div>
            </div>
        `).join('') || '<div class="table-item">暂无终端</div>';
    }

    function renderEmployees() {
        const employees = state.payload.employees || [];
        elements.employeeList.innerHTML = employees.map((employee) => {
            const citizenid = String(employee.citizenid || '').trim();
            const displayName = getEmployeeDisplayName(employee);
            const subcopy = [];

            if (citizenid && displayName !== citizenid) {
                subcopy.push(escapeHtml(citizenid));
            }

            subcopy.push(escapeHtml(formatEmployeeSource(employee.employee_source)));

            if (employee.employee_source_key) {
                subcopy.push(escapeHtml(employee.employee_source_key));
            }

            subcopy.push(`退款 ${Number(employee.can_refund) ? '开启' : '关闭'}`);
            subcopy.push(`折扣 ${Number(employee.can_discount) ? '开启' : '关闭'}`);

            return `
                <div class="table-item" data-employee-citizenid="${escapeHtml(citizenid)}">
                    <div class="item-headline">
                        <strong>${escapeHtml(displayName)}</strong>
                        <span>${escapeHtml(formatEmployeeRole(employee.role))}</span>
                    </div>
                    <div class="item-subcopy">${subcopy.join(' · ')}</div>
                </div>
            `;
        }).join('') || '<div class="table-item">暂无员工</div>';
    }

    function renderEmployeeSyncState() {
        const store = getSelectedStore();
        const storeTabletMode = isStoreTabletMode();
        const canSync = Boolean(
            store
            && store.settlement_mode === 'public_account'
            && store.settlement_account_identifier
        );

        if (elements.employeeSyncButton) {
            elements.employeeSyncButton.disabled = !canSync;
        }

        if (elements.employeeSyncNote) {
            if (storeTabletMode && canSync) {
                elements.employeeSyncNote.textContent = `当前已绑定产业账户 ${store.settlement_account_identifier}，员工只能通过同步加入或移除；点击左侧员工后可编辑其权限。`;
            } else if (storeTabletMode) {
                elements.employeeSyncNote.textContent = '当前平板不支持手动添加员工。请先绑定产业账户，再使用同步功能维护成员。';
            } else {
                elements.employeeSyncNote.textContent = canSync
                    ? `当前已绑定产业账户 ${store.settlement_account_identifier}，点击可一键同步该账户人员。`
                    : '仅已绑定产业账户的店铺支持一键同步人员。';
            }
        }
    }

    function renderEmployeeFormState() {
        const storeTabletMode = isStoreTabletMode();
        let employee = getEditingEmployee();

        if (storeTabletMode && !employee && String(elements.employeeCitizenIdInput.value || '').trim()) {
            fillEmployeeForm(null);
            employee = null;
        }

        const isOwner = employee && employee.role === 'owner';
        const hasEmployee = Boolean(employee);
        const canEditPermissions = canManuallyManageEmployees() || hasEmployee;
        const employeeLookupContainers = getCitizenLookupContainers('employee-citizenid-input');

        if (elements.resetEmployeeFormButton) {
            elements.resetEmployeeFormButton.classList.toggle('hidden', storeTabletMode);
        }

        if (elements.employeeFormTitle) {
            elements.employeeFormTitle.textContent = storeTabletMode ? '员工权限' : '员工表单';
        }

        if (elements.employeeFormNote) {
            if (isOwner) {
                elements.employeeFormNote.textContent = '店主权限请通过同步店主或更换店主流程维护，不能在这里直接修改。';
            } else if (storeTabletMode && hasEmployee) {
                elements.employeeFormNote.textContent = `当前正在编辑 ${employee.citizenid} 的权限；员工成员关系仍需通过同步功能维护。`;
            } else if (storeTabletMode) {
                elements.employeeFormNote.textContent = '店铺平板不支持手动添加员工。先从左侧选择已同步员工，再编辑其权限。';
            } else {
                elements.employeeFormNote.textContent = '可手动添加员工，或点击左侧员工继续编辑其权限。';
            }
        }

        elements.employeeCitizenIdInput.disabled = storeTabletMode;
        elements.employeeRoleInput.disabled = !canEditPermissions || isOwner;
        elements.employeeRefundInput.disabled = !canEditPermissions || isOwner;
        elements.employeeDiscountInput.disabled = !canEditPermissions || isOwner;

        if (elements.saveEmployeeButton) {
            elements.saveEmployeeButton.textContent = storeTabletMode ? '保存权限' : '保存员工';
            elements.saveEmployeeButton.disabled = !canEditPermissions || isOwner;
        }

        if (elements.removeEmployeeButton) {
            elements.removeEmployeeButton.classList.toggle('hidden', storeTabletMode);
            elements.removeEmployeeButton.disabled = storeTabletMode || !hasEmployee || isOwner;
        }

        employeeLookupContainers.forEach((container) => {
            container.classList.toggle('hidden', storeTabletMode);
            container.querySelectorAll('input, button').forEach((field) => {
                field.disabled = storeTabletMode;
            });
        });
    }

    function renderTransactions() {
        const transactions = (state.payload.transactions && state.payload.transactions.items) || [];
        elements.transactionList.innerHTML = transactions.map((transaction) => `
            <div class="table-item transaction-item clickable ${Number(state.selectedTransactionId) === Number(transaction.id) ? 'active' : ''}" data-admin-transaction-id="${transaction.id}">
                <div class="transaction-item-head">
                    <div class="transaction-item-copy">
                        <strong>${escapeHtml(transaction.tx_code)}</strong>
                        <span class="transaction-item-caption">
                            ${transaction.type === 'refund' && transaction.original_tx_code ? `退款单，关联 ${escapeHtml(transaction.original_tx_code)}` : '交易流水'}
                        </span>
                    </div>
                    <div class="transaction-item-amount">
                        ${app.formatCurrency(transaction.final_amount)}
                    </div>
                </div>
                <div class="list-badge-row">
                    ${buildTransactionChips(transaction)}
                </div>
                <div class="item-meta-grid">
                    ${buildTransactionFacts(transaction)}
                </div>
                ${canRefundTransaction(transaction) ? `
                    <div class="item-actions">
                        <button data-admin-refund-id="${transaction.id}">退款</button>
                    </div>
                ` : ''}
            </div>
        `).join('') || '<div class="table-item">暂无交易</div>';
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
                    <label>店铺入账</label>
                    <strong>${app.formatCurrency(transaction.net_amount)}</strong>
                </div>
                <div class="detail-field">
                    <label>${transaction.type === 'refund' ? '冲回提成' : '提成金额'}</label>
                    <strong>${app.formatCurrency(transaction.commission_amount || 0)}</strong>
                </div>
                <div class="detail-field">
                    <label>提成比例</label>
                    <span>${Number(transaction.commission_rate || 0).toFixed(2)}%</span>
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
                    <div class="detail-field">
                        <label>累计已冲回提成</label>
                        <span>${app.formatCurrency(refundSummary.refunded_commission_amount || 0)}</span>
                    </div>
                    <div class="detail-field">
                        <label>剩余可冲回提成</label>
                        <span>${app.formatCurrency(refundSummary.remaining_commission_amount || 0)}</span>
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
                    <label>折扣率</label>
                    <span>${Number(transaction.discount_rate || 0).toFixed(2)}%</span>
                </div>
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
                    <button class="mini-button" data-admin-refund-detail-id="${transaction.id}">退款</button>
                </div>
            ` : ''}
        `;
    }

    function getLoanData() {
        return state.payload.loans || {};
    }

    function getLoanItems() {
        const loanData = getLoanData();
        return Array.isArray(loanData.items) ? loanData.items : [];
    }

    function findLoan(loanId) {
        const numericId = Number(loanId || 0);
        if (!numericId) {
            return null;
        }

        return getLoanItems().find((loan) => Number(loan.id) === numericId) || null;
    }

    function getSelectedLoan() {
        return findLoan(state.selectedLoanId);
    }

    function buildLoanChips(loan) {
        const collectionTask = loan.collection_task || null;
        const chips = [
            { tone: loan.status === 'active' ? 'method' : 'status', label: formatLoanStatus(loan.status) },
            { tone: loan.is_overdue ? 'refund' : 'target', label: formatDueState(loan) }
        ];

        if (collectionTask) {
            chips.push({
                tone: collectionTask.status === 'claimed' ? 'audit' : 'target',
                label: `催收 ${formatCollectionStatus(collectionTask.status)}`
            });
        } else {
            chips.push({ tone: 'target', label: '无催收任务' });
        }

        return chips.map((chip) => `
            <span class="list-badge" data-tone="${chip.tone}">${escapeHtml(chip.label)}</span>
        `).join('');
    }

    function buildLoanFacts(loan) {
        const facts = [
            ['债务人', loan.citizenid || '--'],
            ['到期', formatDateTime(loan.due_at)],
            ['本金', app.formatCurrency(loan.principal_amount || 0)],
            ['已还 / 应还', `${app.formatCurrency(loan.repaid_amount || 0)} / ${app.formatCurrency(loan.total_due || 0)}`]
        ];

        if (loan.trust_score != null) {
            facts.push(['信誉', `${loan.trust_score}${loan.trust_band ? ` · ${loan.trust_band}` : ''}`]);
        }

        return facts.map(([label, value]) => `
            <div class="meta-pair">
                <label>${escapeHtml(label)}</label>
                <span>${escapeHtml(value)}</span>
            </div>
        `).join('');
    }

    function renderLoanSummary() {
        if (!elements.loanSummary) {
            return;
        }

        if (!state.payload.is_admin) {
            elements.loanSummary.innerHTML = '';
            return;
        }

        const loanData = getLoanData();
        if (loanData.schema_available === false) {
            elements.loanSummary.innerHTML = `
                <div class="overview-pill">
                    <label>贷款数据库</label>
                    <strong>未升级</strong>
                </div>
            `;
            return;
        }

        const summary = loanData.summary || {};
        const items = [
            ['活跃贷款', String(summary.active_count || 0)],
            ['逾期贷款', String(summary.overdue_count || 0)],
            ['未还金额', app.formatCurrency(summary.outstanding_amount || 0)],
            ['累计本金', app.formatCurrency(summary.principal_amount || 0)],
            ['催收待领取', String(summary.collection_open_count || 0)],
            ['待发催收奖励', app.formatCurrency(summary.pending_collection_rewards || 0)]
        ];

        if (loanData.collection_schema_available === false) {
            items.push(['催收结构', '需迁移']);
        }

        elements.loanSummary.innerHTML = items.map(([label, value]) => `
            <div class="overview-pill">
                <label>${escapeHtml(label)}</label>
                <strong>${escapeHtml(value)}</strong>
            </div>
        `).join('');
    }

    function renderLoans() {
        if (!elements.loanList) {
            return;
        }

        if (!state.payload.is_admin) {
            elements.loanList.innerHTML = '<div class="table-item">只有管理员可以查看贷款</div>';
            return;
        }

        const loanData = getLoanData();
        if (loanData.schema_available === false) {
            elements.loanList.innerHTML = `<div class="table-item">${escapeHtml(loanData.message || '贷款数据库未升级')}</div>`;
            return;
        }

        const loans = getLoanItems();
        elements.loanList.innerHTML = loans.map((loan) => `
            <div class="table-item loan-item clickable ${Number(state.selectedLoanId) === Number(loan.id) ? 'active' : ''}" data-loan-id="${loan.id}">
                <div class="transaction-item-head">
                    <div class="transaction-item-copy">
                        <strong>${escapeHtml(loan.loan_code || `#${loan.id}`)}</strong>
                        <span class="transaction-item-caption">${escapeHtml(loan.citizenid || '--')}</span>
                    </div>
                    <div class="transaction-item-amount">
                        ${app.formatCurrency(loan.outstanding_amount || 0)}
                    </div>
                </div>
                <div class="list-badge-row">
                    ${buildLoanChips(loan)}
                </div>
                <div class="item-meta-grid">
                    ${buildLoanFacts(loan)}
                </div>
            </div>
        `).join('') || '<div class="table-item">暂无贷款记录</div>';
    }

    function renderLoanDetail() {
        const loan = getSelectedLoan();

        if (!loan) {
            if (elements.loanDetail) {
                elements.loanDetail.innerHTML = '<div class="detail-placeholder">选择贷款后查看和调整数据</div>';
            }

            if (elements.loanForm) {
                elements.loanForm.classList.add('hidden');
            }
            return;
        }

        const collectionTask = loan.collection_task || null;
        const collectionLines = collectionTask ? `
            <div class="detail-links">
                <div class="detail-line">
                    <span>任务号</span>
                    <strong>${escapeHtml(collectionTask.task_code || '--')}</strong>
                    <em>${formatCollectionStatus(collectionTask.status)}</em>
                </div>
                <div class="detail-line">
                    <span>领取人</span>
                    <strong>${escapeHtml(collectionTask.claimed_by_citizenid || '--')}</strong>
                    <em>${escapeHtml(collectionTask.claimed_by_name_snapshot || '--')}</em>
                </div>
                <div class="detail-line">
                    <span>奖励</span>
                    <strong>${app.formatCurrency(collectionTask.reward_amount || 0)}</strong>
                    <em>${Number(collectionTask.reward_rate || 0).toFixed(2)}%${collectionTask.reward_claimed ? ' · 已领取' : ''}</em>
                </div>
            </div>
        ` : '<div class="detail-note">当前贷款还没有催收任务。逾期活跃贷款可以由管理员手动生成任务。</div>';

        elements.loanDetail.innerHTML = `
            <div class="detail-head">
                <div>
                    <p class="detail-kicker">贷款详情</p>
                    <h3>${escapeHtml(loan.loan_code || `#${loan.id}`)}</h3>
                </div>
                <span class="detail-badge" data-state="${escapeHtml(loan.status || '')}">${formatLoanStatus(loan.status)}</span>
            </div>
            <div class="detail-grid">
                <div class="detail-field">
                    <label>债务人</label>
                    <strong>${escapeHtml(loan.citizenid || '--')}</strong>
                </div>
                <div class="detail-field">
                    <label>到期情况</label>
                    <span>${escapeHtml(formatDueState(loan))}</span>
                </div>
                <div class="detail-field">
                    <label>本金 / 利息</label>
                    <strong>${app.formatCurrency(loan.principal_amount || 0)} / ${app.formatCurrency(loan.interest_amount || 0)}</strong>
                </div>
                <div class="detail-field">
                    <label>未还金额</label>
                    <strong>${app.formatCurrency(loan.outstanding_amount || 0)}</strong>
                </div>
                <div class="detail-field">
                    <label>已还 / 应还</label>
                    <span>${app.formatCurrency(loan.repaid_amount || 0)} / ${app.formatCurrency(loan.total_due || 0)}</span>
                </div>
                <div class="detail-field">
                    <label>利率 / 期限</label>
                    <span>${Number(loan.interest_rate || 0).toFixed(2)}% / ${Number(loan.term_days || 0)} 天</span>
                </div>
                <div class="detail-field">
                    <label>信誉快照</label>
                    <span>${loan.trust_score != null ? `${loan.trust_score}${loan.trust_band ? ` · ${escapeHtml(loan.trust_band)}` : ''}` : '--'}</span>
                </div>
                <div class="detail-field">
                    <label>到期时间</label>
                    <span>${escapeHtml(formatDateTime(loan.due_at))}</span>
                </div>
                <div class="detail-field">
                    <label>创建时间</label>
                    <span>${escapeHtml(formatDateTime(loan.created_at))}</span>
                </div>
                <div class="detail-field">
                    <label>结清时间</label>
                    <span>${escapeHtml(formatDateTime(loan.repaid_at))}</span>
                </div>
            </div>
            ${collectionLines}
        `;

        fillLoanForm(loan);
    }

    function fillLoanForm(loan) {
        if (!elements.loanForm || !loan) {
            return;
        }

        const collectionTask = loan.collection_task || null;
        const canCreateCollectionTask = Boolean(
            loan.status === 'active' &&
            loan.is_overdue &&
            Number(loan.outstanding_amount || 0) > 0 &&
            (!collectionTask || collectionTask.status === 'cancelled')
        );
        const canCancelCollectionTask = Boolean(
            collectionTask &&
            (collectionTask.status === 'open' || collectionTask.status === 'claimed')
        );

        elements.loanForm.classList.remove('hidden');
        elements.loanIdInput.value = loan.id || '';
        elements.loanCodeInput.value = loan.loan_code || '';
        elements.loanCitizenIdInput.value = loan.citizenid || '';
        elements.loanPrincipalInput.value = Number(loan.principal_amount || 0).toFixed(2);
        elements.loanInterestInput.value = Number(loan.interest_amount || 0).toFixed(2);
        elements.loanTotalInput.value = Number(loan.total_due || 0).toFixed(2);
        elements.loanRepaidInput.value = Number(loan.repaid_amount || 0).toFixed(2);
        elements.loanRateInput.value = Number(loan.interest_rate || 0).toFixed(2);
        elements.loanTermInput.value = Number(loan.term_days || 1);
        elements.loanStatusInput.value = loan.status || 'active';
        elements.loanDueAtInput.value = toDateTimeLocalValue(loan.due_at);
        elements.createCollectionTaskButton.disabled = !canCreateCollectionTask;
        elements.cancelCollectionTaskButton.classList.toggle('hidden', !canCancelCollectionTask);
        elements.loanFormNote.textContent = canCreateCollectionTask
            ? '该贷款已逾期且未结清，可以生成催收任务。'
            : '调整应还、已还、状态和到期时间后保存。标记已结清会同步关闭对应催收任务。';
    }

    function renderAudit() {
        const items = (state.payload.audit && state.payload.audit.items) || [];
        elements.auditList.innerHTML = items.map((entry) => `
            <div class="table-item audit-item">
                <div class="audit-item-head">
                    <div class="audit-item-copy">
                        <strong>${escapeHtml(formatAuditAction(entry.action))}</strong>
                        <span class="audit-item-target">
                            ${escapeHtml(formatTargetType(entry.target_type))} · ${escapeHtml(entry.target_id || '--')}
                        </span>
                    </div>
                    <span class="audit-item-time">${app.formatDate(entry.created_at)}</span>
                </div>
                <div class="list-badge-row">
                    <span class="list-badge" data-tone="audit">${escapeHtml(formatAuditAction(entry.action))}</span>
                    <span class="list-badge" data-tone="target">${escapeHtml(formatTargetType(entry.target_type))}</span>
                </div>
                <div class="item-meta-grid">
                    <div class="meta-pair">
                        <label>操作人</label>
                        <span>${escapeHtml(entry.actor_citizenid || '--')}</span>
                    </div>
                    <div class="meta-pair">
                        <label>目标</label>
                        <span>${escapeHtml(`${formatTargetType(entry.target_type)} ${entry.target_id || '--'}`)}</span>
                    </div>
                    ${entry.store_id ? `
                        <div class="meta-pair">
                            <label>店铺</label>
                            <span>#${escapeHtml(entry.store_id)}</span>
                        </div>
                    ` : ''}
                    ${entry.terminal_id ? `
                        <div class="meta-pair">
                            <label>终端</label>
                            <span>#${escapeHtml(entry.terminal_id)}</span>
                        </div>
                    ` : ''}
                </div>
                ${buildAuditSummary(entry.detail) ? `
                    <div class="audit-item-summary">${escapeHtml(buildAuditSummary(entry.detail))}</div>
                ` : ''}
            </div>
        `).join('') || '<div class="table-item">暂无审计记录</div>';
    }

    function renderReports() {
        const reports = state.payload.reports || {};
        const summary = reports.summary || {};
        const daily = reports.daily || [];
        const methods = reports.methods || [];
        const topStores = reports.top_stores || [];
        const filters = reports.filters || {};

        elements.reportRangeFilter.value = String(filters.range_days || 7);
        elements.reportDateFromFilter.value = filters.date_from || '';
        elements.reportDateToFilter.value = filters.date_to || '';

        const summaryItems = [
            ['支付总额', app.formatCurrency(summary.gross_amount || 0)],
            ['退款总额', app.formatCurrency(summary.refunded_amount || 0)],
            ['净入账', app.formatCurrency(summary.net_amount || 0)],
            ['支付笔数', String(summary.payment_count || 0)],
            ['退款笔数', String(summary.refund_count || 0)],
            ['平均客单', app.formatCurrency(summary.avg_ticket || 0)]
        ];

        elements.reportSummary.innerHTML = summaryItems.map(([label, value]) => `
            <div class="overview-pill">
                <label>${label}</label>
                <strong>${value}</strong>
            </div>
        `).join('');

        const chartValues = [];
        daily.forEach((item) => {
            chartValues.push(Number(item.gross_amount || 0));
            chartValues.push(Number(item.refunded_amount || 0));
            chartValues.push(Math.abs(Number(item.net_amount || 0)));
        });
        const maxValue = Math.max(1, ...chartValues);

        elements.reportDailyChart.innerHTML = daily.map((item) => {
            const grossHeight = Math.max(4, Math.round((Number(item.gross_amount || 0) / maxValue) * 100));
            const netHeight = Math.max(4, Math.round((Math.abs(Number(item.net_amount || 0)) / maxValue) * 100));
            const refundHeight = Math.max(4, Math.round((Number(item.refunded_amount || 0) / maxValue) * 100));

            return `
                <div class="chart-column">
                    <div class="chart-track">
                        <span class="chart-bar gross" style="height:${grossHeight}%"></span>
                        <span class="chart-bar net ${Number(item.net_amount || 0) < 0 ? 'negative' : ''}" style="height:${netHeight}%"></span>
                        <span class="chart-bar refund" style="height:${refundHeight}%"></span>
                    </div>
                    <div class="chart-meta">
                        <strong>${escapeHtml(item.label || item.date || '--')}</strong>
                        <span>${app.formatCurrency(item.net_amount || 0)}</span>
                    </div>
                </div>
            `;
        }).join('') || '<div class="detail-placeholder">暂无报表数据</div>';

        elements.reportMethodSplit.innerHTML = methods.map((item) => `
            <div class="report-row">
                <div class="report-row-head">
                    <strong>${formatMethod(item.method)}</strong>
                    <span>${app.formatCurrency(item.payment_amount || 0)} · ${item.share || 0}%</span>
                </div>
                <div class="report-progress">
                    <span style="width:${Math.min(100, Number(item.share || 0))}%"></span>
                </div>
                <div class="item-subcopy">
                    支付 ${item.payment_count || 0} 笔 · 退款 ${item.refund_count || 0} 笔 · 净额 ${app.formatCurrency(item.net_amount || 0)}
                </div>
            </div>
        `).join('') || '<div class="detail-placeholder">暂无支付方式数据</div>';

        elements.reportTopStores.innerHTML = topStores.length
            ? topStores.map((item) => `
                <div class="report-row">
                    <div class="report-row-head">
                        <strong>${escapeHtml(item.store_name || `店铺 #${item.store_id}`)}</strong>
                        <span>${app.formatCurrency(item.net_amount || 0)}</span>
                    </div>
                    <div class="item-subcopy">
                        支付总额 ${app.formatCurrency(item.gross_amount || 0)} · 支付 ${item.payment_count || 0} 笔
                    </div>
                </div>
            `).join('')
            : '<div class="detail-placeholder">当前为单店报表，暂无跨店排名</div>';
    }

    function renderTaxReport() {
        const report = state.payload.tax_report || {};
        const summary = report.summary || {};
        const daily = report.daily || [];
        const methods = report.methods || [];
        const filters = report.filters || {};

        elements.taxRangeFilter.value = String(filters.range_days || 7);
        elements.taxDateFromFilter.value = filters.date_from || '';
        elements.taxDateToFilter.value = filters.date_to || '';

        const summaryItems = [
            ['应收税额', app.formatCurrency(summary.collected_tax_amount || 0)],
            ['已退税额', app.formatCurrency(summary.refunded_tax_amount || 0)],
            ['净税额', app.formatCurrency(summary.net_tax_amount || 0)],
            ['含税支付', String(summary.taxable_payment_count || 0)],
            ['免税支付', String(summary.exempt_payment_count || 0)],
            ['平均税额', app.formatCurrency(summary.avg_tax_amount || 0)]
        ];

        elements.taxReportSummary.innerHTML = summaryItems.map(([label, value]) => `
            <div class="overview-pill">
                <label>${label}</label>
                <strong>${value}</strong>
            </div>
        `).join('');

        const chartValues = [];
        daily.forEach((item) => {
            chartValues.push(Number(item.collected_tax_amount || 0));
            chartValues.push(Number(item.refunded_tax_amount || 0));
            chartValues.push(Math.abs(Number(item.net_tax_amount || 0)));
        });
        const maxValue = Math.max(1, ...chartValues);

        elements.taxReportDailyChart.innerHTML = daily.map((item) => {
            const collectedHeight = Math.max(4, Math.round((Number(item.collected_tax_amount || 0) / maxValue) * 100));
            const netHeight = Math.max(4, Math.round((Math.abs(Number(item.net_tax_amount || 0)) / maxValue) * 100));
            const refundHeight = Math.max(4, Math.round((Number(item.refunded_tax_amount || 0) / maxValue) * 100));

            return `
                <div class="chart-column">
                    <div class="chart-track">
                        <span class="chart-bar gross" style="height:${collectedHeight}%"></span>
                        <span class="chart-bar net ${Number(item.net_tax_amount || 0) < 0 ? 'negative' : ''}" style="height:${netHeight}%"></span>
                        <span class="chart-bar refund" style="height:${refundHeight}%"></span>
                    </div>
                    <div class="chart-meta">
                        <strong>${escapeHtml(item.label || item.date || '--')}</strong>
                        <span>${app.formatCurrency(item.net_tax_amount || 0)}</span>
                    </div>
                </div>
            `;
        }).join('') || '<div class="detail-placeholder">暂无税务统计</div>';

        elements.taxReportMethodSplit.innerHTML = methods.map((item) => `
            <div class="report-row">
                <div class="report-row-head">
                    <strong>${formatMethod(item.method)}</strong>
                    <span>${app.formatCurrency(item.collected_tax_amount || 0)} · ${item.share || 0}%</span>
                </div>
                <div class="report-progress">
                    <span style="width:${Math.min(100, Number(item.share || 0))}%"></span>
                </div>
                <div class="item-subcopy">
                    含税 ${item.taxable_payment_count || 0} 笔 · 免税 ${item.exempt_payment_count || 0} 笔 · 净税额 ${app.formatCurrency(item.net_tax_amount || 0)}
                </div>
            </div>
        `).join('') || '<div class="detail-placeholder">暂无税务方式数据</div>';
    }

    function renderCommissionReport() {
        const report = state.payload.commission_report || {};
        const summary = report.summary || {};
        const daily = report.daily || [];
        const methods = report.methods || [];
        const topCashiers = report.top_cashiers || [];
        const filters = report.filters || {};

        elements.commissionRangeFilter.value = String(filters.range_days || 7);
        elements.commissionDateFromFilter.value = filters.date_from || '';
        elements.commissionDateToFilter.value = filters.date_to || '';

        const summaryItems = [
            ['产生提成', app.formatCurrency(summary.generated_commission_amount || 0)],
            ['冲回提成', app.formatCurrency(summary.refunded_commission_amount || 0)],
            ['净提成', app.formatCurrency(summary.net_commission_amount || 0)],
            ['提成支付', String(summary.commission_payment_count || 0)],
            ['提成退款', String(summary.commission_refund_count || 0)],
            ['收银员数', String(summary.cashier_count || 0)],
            ['平均提成', app.formatCurrency(summary.avg_commission_amount || 0)]
        ];

        elements.commissionReportSummary.innerHTML = summaryItems.map(([label, value]) => `
            <div class="overview-pill">
                <label>${label}</label>
                <strong>${value}</strong>
            </div>
        `).join('');

        const chartValues = [];
        daily.forEach((item) => {
            chartValues.push(Number(item.generated_commission_amount || 0));
            chartValues.push(Number(item.refunded_commission_amount || 0));
            chartValues.push(Math.abs(Number(item.net_commission_amount || 0)));
        });
        const maxValue = Math.max(1, ...chartValues);

        elements.commissionReportDailyChart.innerHTML = daily.map((item) => {
            const generatedHeight = Math.max(4, Math.round((Number(item.generated_commission_amount || 0) / maxValue) * 100));
            const netHeight = Math.max(4, Math.round((Math.abs(Number(item.net_commission_amount || 0)) / maxValue) * 100));
            const refundHeight = Math.max(4, Math.round((Number(item.refunded_commission_amount || 0) / maxValue) * 100));

            return `
                <div class="chart-column">
                    <div class="chart-track">
                        <span class="chart-bar gross" style="height:${generatedHeight}%"></span>
                        <span class="chart-bar net ${Number(item.net_commission_amount || 0) < 0 ? 'negative' : ''}" style="height:${netHeight}%"></span>
                        <span class="chart-bar refund" style="height:${refundHeight}%"></span>
                    </div>
                    <div class="chart-meta">
                        <strong>${escapeHtml(item.label || item.date || '--')}</strong>
                        <span>${app.formatCurrency(item.net_commission_amount || 0)}</span>
                    </div>
                </div>
            `;
        }).join('') || '<div class="detail-placeholder">暂无提成统计</div>';

        elements.commissionReportMethodSplit.innerHTML = methods.map((item) => `
            <div class="report-row">
                <div class="report-row-head">
                    <strong>${formatMethod(item.method)}</strong>
                    <span>${app.formatCurrency(item.generated_commission_amount || 0)} · ${item.share || 0}%</span>
                </div>
                <div class="report-progress">
                    <span style="width:${Math.min(100, Number(item.share || 0))}%"></span>
                </div>
                <div class="item-subcopy">
                    提成支付 ${item.commission_payment_count || 0} 笔 · 提成退款 ${item.commission_refund_count || 0} 笔 · 净提成 ${app.formatCurrency(item.net_commission_amount || 0)}
                </div>
            </div>
        `).join('') || '<div class="detail-placeholder">暂无提成方式数据</div>';

        elements.commissionReportTopCashiers.innerHTML = topCashiers.length
            ? topCashiers.map((item) => `
                <div class="report-row">
                    <div class="report-row-head">
                        <strong>${escapeHtml(item.cashier_citizenid || '--')}</strong>
                        <span>${app.formatCurrency(item.net_commission_amount || 0)}</span>
                    </div>
                    <div class="item-subcopy">
                        产生 ${app.formatCurrency(item.generated_commission_amount || 0)} · 冲回 ${app.formatCurrency(item.refunded_commission_amount || 0)} · 相关支付 ${item.payment_count || 0} 笔
                    </div>
                </div>
            `).join('')
            : '<div class="detail-placeholder">暂无收银员提成排行</div>';
    }

    function renderModels() {
        const models = state.payload.terminal_models || [];
        elements.modelList.innerHTML = models.map((model) => `
            <div class="table-item ${elements.modelKeyInput.value === model.model_key ? 'active' : ''}" data-model-key="${escapeHtml(model.model_key)}">
                <div class="item-headline">
                    <strong>${escapeHtml(model.label)}</strong>
                    <span>${formatStatus(model.status)}</span>
                </div>
                <div class="item-subcopy">
                    ${escapeHtml(model.model_key)} · ${escapeHtml(formatTerminalModelName(model.model_name, model.model_key))}${Number(model.is_system) ? ' · 系统内置' : ''}
                </div>
            </div>
        `).join('') || '<div class="table-item">暂无型号</div>';
    }

    function renderAdminOnlySections() {
        const isAdmin = Boolean(state.payload.is_admin);
        document.querySelectorAll('[data-admin-only="true"]').forEach((element) => {
            element.classList.toggle('hidden', !isAdmin);
        });

        const modelPanel = document.querySelector('[data-panel="models"]');
        if (modelPanel) {
            modelPanel.classList.toggle('hidden', !isAdmin || state.activeTab !== 'models');
        }

        const loanPanel = document.querySelector('[data-panel="loans"]');
        if (loanPanel) {
            loanPanel.classList.toggle('hidden', !isAdmin || state.activeTab !== 'loans');
        }

        if (!isAdmin && (state.activeTab === 'models' || state.activeTab === 'loans')) {
            switchTab('stores');
        }
    }

    function switchTab(tab) {
        state.activeTab = tab;
        document.querySelectorAll('.tab-button').forEach((button) => {
            button.classList.toggle('active', button.dataset.tab === tab);
        });
        document.querySelectorAll('[data-panel]').forEach((panel) => {
            panel.classList.toggle('hidden', panel.dataset.panel !== tab);
        });
        renderAdminOnlySections();
    }

    async function refresh(payload = {}) {
        const response = await app.post('refreshAdmin', payload);
        if (response.ok) {
            render(response.data);
        } else {
            app.setRibbon(response.message || '刷新失败', 'error');
        }
    }

    async function refreshTransactions() {
        const response = await app.post('getAdminTransactions', collectTransactionFilters());
        if (!response.ok) {
            app.setRibbon(response.message || '获取交易失败', 'error');
            return;
        }

        state.payload.transactions = response.data;
        renderTransactions();

        if (state.selectedTransactionId) {
            await fetchTransactionDetail(state.selectedTransactionId, true);
        } else {
            renderTransactionDetail();
        }
    }

    async function fetchTransactionDetail(transactionId, silent = false) {
        const response = await app.post('getAdminTransactionDetail', {
            transaction_id: Number(transactionId)
        });

        if (!response.ok) {
            if (!silent) app.setRibbon(response.message || '获取交易详情失败', 'error');
            return;
        }

        state.selectedTransactionId = Number(transactionId);
        state.transactionDetail = response.data || null;
        renderTransactions();
        renderTransactionDetail();

        if (!silent) {
            app.setRibbon('交易详情已加载', 'success');
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
            title: '管理端退款',
            summary: transaction
                ? `${transaction.tx_code || '当前交易'} 最多可退 ${app.formatCurrency(maxAmount)}。`
                : `请输入退款金额，最多 ${app.formatCurrency(maxAmount)}。`,
            maxAmount,
            initialAmount: maxAmount
        });
        if (!refundRequest) return;

        const response = await app.post('refundFromAdmin', {
            transaction_id: Number(transactionId),
            refund_amount: refundRequest.amount,
            reason: refundRequest.reason
        });
        app.setRibbon(response.message || '退款处理完成', response.ok ? 'success' : 'error');

        if (response.ok) {
            state.selectedTransactionId = Number(transactionId);
            await refreshTransactions();
        }
    }

    async function refreshLoans() {
        if (!state.payload.is_admin) {
            return;
        }

        const response = await app.post('getAdminLoans', collectLoanFilters());
        if (!response.ok) {
            app.setRibbon(response.message || '获取贷款失败', 'error');
            return;
        }

        state.payload.loans = response.data;
        if (state.selectedLoanId && !findLoan(state.selectedLoanId)) {
            state.selectedLoanId = null;
        }
        renderLoanSummary();
        renderLoans();
        renderLoanDetail();
        app.setRibbon('贷款列表已刷新', 'success');
    }

    async function refreshReports() {
        const response = await app.post('getAdvancedReport', collectReportFilters());
        if (!response.ok) {
            app.setRibbon(response.message || '获取报表失败', 'error');
            return;
        }

        state.payload.reports = response.data;
        renderReports();
        app.setRibbon('报表已刷新', 'success');
    }

    async function refreshTaxReport() {
        const response = await app.post('getTaxReport', collectTaxFilters());
        if (!response.ok) {
            app.setRibbon(response.message || '获取税务统计失败', 'error');
            return;
        }

        state.payload.tax_report = response.data;
        renderTaxReport();
        app.setRibbon('税务统计已刷新', 'success');
    }

    async function refreshCommissionReport() {
        const response = await app.post('getCommissionReport', collectCommissionFilters());
        if (!response.ok) {
            app.setRibbon(response.message || '获取提成统计失败', 'error');
            return;
        }

        state.payload.commission_report = response.data;
        renderCommissionReport();
        app.setRibbon('提成统计已刷新', 'success');
    }

    async function exportData(exportType, extra = {}) {
        const response = await app.post('exportAdminData', Object.assign({
            export_type: exportType
        }, extra));

        if (!response.ok) {
            app.setRibbon(response.message || '导出失败', 'error');
            return;
        }

        downloadPayload(response.data);
        app.setRibbon('导出文件已生成', 'success');
    }

    function resetModelForm() {
        elements.modelKeyInput.value = '';
        elements.modelLabelInput.value = '';
        elements.modelNameInput.value = '';
        elements.modelStatusInput.value = 'active';
    }

    function render(payload) {
        payload = payload || {};
        const previousStoreId = state.payload && state.payload.selected_store_id;
        state.payload = payload;
        if (isStoreTabletMode()) {
            state.storeCreateMode = false;
        }
        const selectedTerminal = getSelectedTerminal();
        const selectedStore = getSelectedStore();
        const editingStoreId = Number(elements.storeIdInput.value || 0);

        if (previousStoreId !== state.payload.selected_store_id) {
            state.selectedTransactionId = null;
            state.transactionDetail = null;
            state.selectedLoanId = null;
            state.generatedBindingCode = null;
            elements.storePayoutAmountInput.value = '';
            elements.storePayoutReasonInput.value = '';
        }

        if (
            !state.storeCreateMode &&
            selectedStore &&
            (!editingStoreId || previousStoreId !== state.payload.selected_store_id)
        ) {
            fillStoreForm(selectedStore);
        }

        fillTaxForm(selectedStore);
        fillCommissionForm(selectedStore);

        elements.title.textContent = payload.mode === 'admin' ? '全局管理面板' : `${payload.overview ? payload.overview.name : '店铺'} 面板`;
        elements.subcopy.textContent = payload.mode === 'admin' ? '管理员全局视图' : '店长 / 经理视图';

        renderOverview();
        renderStoreSelector();
        renderStores();
        renderStoreFormState();
        renderStorePayout();
        renderTerminalModelOptions(
            elements.terminalModelInput.value || (selectedTerminal && selectedTerminal.model_key) || undefined
        );
        renderTerminals();
        renderEmployees();
        renderEmployeeSyncState();
        renderEmployeeFormState();
        renderTransactions();
        renderTransactionDetail();
        renderLoanSummary();
        renderLoans();
        renderLoanDetail();
        renderAudit();
        renderReports();
        renderTaxSettings();
        renderTaxReport();
        renderCommissionSettings();
        renderCommissionReport();
        renderModels();
        renderAdminOnlySections();
        renderTerminalFormState();
        renderBindingCodeState();
        renderStoreSettlementFields();
        switchTab(state.activeTab);
    }

    renderStoreFormState();
    renderEmployeeFormState();

    getCitizenLookupContainers().forEach((container) => {
        const button = container.querySelector('[data-fill-citizenid]');
        const playerIdInput = container.querySelector('[data-player-id-input]');

        setCitizenLookupNote(container);

        if (button) {
            button.addEventListener('click', () => {
                fillCitizenIdFromPlayerId(container);
            });
        }

        if (playerIdInput) {
            playerIdInput.addEventListener('keydown', (event) => {
                if (event.key !== 'Enter') {
                    return;
                }

                event.preventDefault();
                fillCitizenIdFromPlayerId(container);
            });
        }
    });

    document.querySelectorAll('.tab-button').forEach((button) => {
        button.addEventListener('click', () => {
            if (button.dataset.adminOnly === 'true' && !state.payload.is_admin) return;
            switchTab(button.dataset.tab);
        });
    });

    document.getElementById('admin-refresh-button').addEventListener('click', () => {
        refresh({ store_id: Number(elements.storeSelect.value) || undefined });
    });

    elements.storeSelect.addEventListener('change', () => {
        state.storeCreateMode = false;
        state.selectedTransactionId = null;
        state.transactionDetail = null;
        state.selectedLoanId = null;
        resetCitizenLookup('store-owner-input', true);
        resetCitizenLookup('new-owner-input', true);
        resetEmployeeForm();
        refresh({ store_id: Number(elements.storeSelect.value) || undefined });
    });

    elements.resetStoreFormButton.addEventListener('click', resetStoreForm);
    elements.storeCreateModeButton.addEventListener('click', resetStoreForm);

    if (elements.storeSettlementModeInput) {
        elements.storeSettlementModeInput.addEventListener('change', () => {
            renderStoreSettlementFields();
        });
    }

    if (elements.taxSettlementModeInput) {
        elements.taxSettlementModeInput.addEventListener('change', () => {
            renderTaxSettings();
        });
    }

    if (elements.taxCustomRateEnabledInput) {
        elements.taxCustomRateEnabledInput.addEventListener('change', () => {
            renderTaxSettings();
        });
    }

    if (elements.commissionRateInput) {
        elements.commissionRateInput.addEventListener('input', () => {
            renderCommissionSettings();
        });
    }

    document.getElementById('reset-terminal-form-button').addEventListener('click', () => {
        elements.terminalIdInput.value = '';
        elements.terminalSerialInput.value = '';
        elements.terminalTypeInput.value = 'portable';
        elements.terminalStatusInput.value = 'active';
        elements.bindingCodeTypeInput.value = 'portable';
        renderTerminalModelOptions();
        renderTerminalFormState();
    });

    elements.terminalTypeInput.addEventListener('change', () => {
        if (elements.terminalTypeInput.value === 'portable' || elements.terminalTypeInput.value === 'tablet') {
            elements.bindingCodeTypeInput.value = elements.terminalTypeInput.value;
        }

        renderTerminalModelOptions(elements.terminalModelInput.value || undefined);
        renderTerminalFormState();
    });

    elements.resetEmployeeFormButton.addEventListener('click', resetEmployeeForm);

    if (elements.employeeSyncButton) {
        elements.employeeSyncButton.addEventListener('click', async () => {
            const store = getSelectedStore();
            if (!store || store.settlement_mode !== 'public_account' || !store.settlement_account_identifier) {
                app.setRibbon('当前店铺未绑定产业账户，无法同步人员', 'error');
                return;
            }

            const response = await app.post('syncStoreEmployees', {
                store_id: state.payload.selected_store_id
            });
            app.setRibbon(response.message || '产业账户人员已同步', response.ok ? 'success' : 'error');
        });
    }

    document.getElementById('reset-model-form-button').addEventListener('click', resetModelForm);

    elements.storeList.addEventListener('click', (event) => {
        const item = event.target.closest('[data-store-id]');
        if (!item) return;
        const store = (state.payload.stores || []).find((entry) => String(entry.id) === item.dataset.storeId);
        if (!store) return;
        fillStoreForm(store);
        elements.newOwnerInput.value = '';
        resetCitizenLookup('store-owner-input', true);
        resetCitizenLookup('new-owner-input', true);
        resetEmployeeForm();
        renderStoreFormState(store);
        state.selectedTransactionId = null;
        state.transactionDetail = null;
        state.selectedLoanId = null;
        refresh({ store_id: store.id });
    });

    elements.terminalList.addEventListener('click', (event) => {
        const item = event.target.closest('[data-terminal-id]');
        if (!item) return;
        const terminal = (state.payload.terminals || []).find((entry) => String(entry.id) === item.dataset.terminalId);
        if (!terminal) return;
        elements.terminalIdInput.value = terminal.id;
        elements.terminalSerialInput.value = terminal.serial_number;
        elements.terminalTypeInput.value = terminal.type;
        elements.terminalStatusInput.value = terminal.status === 'archived' ? 'disabled' : terminal.status;
        if (terminal.type === 'portable' || terminal.type === 'tablet') {
            elements.bindingCodeTypeInput.value = terminal.type;
        }
        renderTerminalModelOptions(terminal.model_key || undefined);
        renderTerminalFormState();
    });

    elements.employeeList.addEventListener('click', (event) => {
        const item = event.target.closest('[data-employee-citizenid]');
        if (!item) return;
        const employee = (state.payload.employees || []).find((entry) => entry.citizenid === item.dataset.employeeCitizenid);
        if (!employee) return;
        fillEmployeeForm(employee);
        resetCitizenLookup('employee-citizenid-input', true);
        renderEmployeeFormState();
    });

    elements.transactionList.addEventListener('click', (event) => {
        const refundButton = event.target.closest('[data-admin-refund-id]');
        if (refundButton) {
            refundTransaction(refundButton.dataset.adminRefundId);
            return;
        }

        const item = event.target.closest('[data-admin-transaction-id]');
        if (item) {
            fetchTransactionDetail(item.dataset.adminTransactionId);
        }
    });

    elements.transactionDetail.addEventListener('click', (event) => {
        const refundButton = event.target.closest('[data-admin-refund-detail-id]');
        if (refundButton) {
            refundTransaction(refundButton.dataset.adminRefundDetailId);
        }
    });

    if (elements.loanList) {
        elements.loanList.addEventListener('click', (event) => {
            const item = event.target.closest('[data-loan-id]');
            if (!item) return;
            state.selectedLoanId = Number(item.dataset.loanId);
            renderLoans();
            renderLoanDetail();
        });
    }

    elements.modelList.addEventListener('click', (event) => {
        const item = event.target.closest('[data-model-key]');
        if (!item) return;
        const model = (state.payload.terminal_models || []).find((entry) => entry.model_key === item.dataset.modelKey);
        if (!model) return;
        elements.modelKeyInput.value = model.model_key;
        elements.modelLabelInput.value = model.label;
        elements.modelNameInput.value = model.model_name;
        elements.modelStatusInput.value = model.status || 'active';
        renderModels();
    });

    document.getElementById('refresh-admin-transactions-button').addEventListener('click', refreshTransactions);
    document.getElementById('export-transactions-button').addEventListener('click', () => {
        exportData('transactions', collectTransactionFilters());
    });

    document.getElementById('refresh-admin-loans-button').addEventListener('click', refreshLoans);

    if (elements.loanSearchFilter) {
        elements.loanSearchFilter.addEventListener('keydown', (event) => {
            if (event.key !== 'Enter') {
                return;
            }

            event.preventDefault();
            refreshLoans();
        });
    }

    [elements.loanStatusFilter, elements.loanDueFilter, elements.loanCollectionFilter].forEach((input) => {
        if (!input) {
            return;
        }

        input.addEventListener('change', refreshLoans);
    });

    document.getElementById('refresh-report-button').addEventListener('click', refreshReports);
    document.getElementById('export-report-button').addEventListener('click', () => {
        exportData('report', collectReportFilters());
    });

    elements.reportRangeFilter.addEventListener('change', () => {
        elements.reportDateFromFilter.value = '';
        elements.reportDateToFilter.value = '';
    });

    document.getElementById('refresh-tax-report-button').addEventListener('click', refreshTaxReport);

    elements.taxRangeFilter.addEventListener('change', () => {
        elements.taxDateFromFilter.value = '';
        elements.taxDateToFilter.value = '';
    });

    document.getElementById('refresh-commission-report-button').addEventListener('click', refreshCommissionReport);

    elements.commissionRangeFilter.addEventListener('change', () => {
        elements.commissionDateFromFilter.value = '';
        elements.commissionDateToFilter.value = '';
    });

    document.getElementById('refresh-audit-button').addEventListener('click', async () => {
        const response = await app.post('getAuditLogs', {
            store_id: state.payload.selected_store_id
        });

        if (response.ok) {
            state.payload.audit = response.data;
            renderAudit();
            app.setRibbon('审计已刷新', 'success');
        }
    });

    document.getElementById('export-audit-button').addEventListener('click', () => {
        exportData('audit', {
            store_id: state.payload.selected_store_id
        });
    });

    elements.storeForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (!canCreateStore() && !elements.storeIdInput.value) {
            app.setRibbon('店铺平板不支持新建店铺', 'error');
            return;
        }

        const response = await app.post('saveStore', {
            id: elements.storeIdInput.value ? Number(elements.storeIdInput.value) : undefined,
            name: elements.storeNameInput.value,
            owner_citizenid: elements.storeOwnerInput.value,
            settlement_mode: elements.storeSettlementModeInput ? elements.storeSettlementModeInput.value : 'store_balance',
            settlement_account_identifier: elements.storeSettlementAccountInput ? elements.storeSettlementAccountInput.value : ''
        });
        app.setRibbon(response.message || '店铺已保存', response.ok ? 'success' : 'error');

        if (response.ok && response.data && response.data.id) {
            fillStoreForm(response.data);
            renderStoreFormState(response.data);
        }
    });

    elements.taxDefaultForm.addEventListener('submit', async (event) => {
        event.preventDefault();

        const response = await app.post('saveTaxDefaults', {
            default_tax_rate: roundCurrency(elements.taxDefaultRateInput.value),
            tax_settlement_mode: elements.taxSettlementModeInput ? elements.taxSettlementModeInput.value : 'store_balance',
            tax_settlement_account_identifier: elements.taxSettlementAccountInput ? elements.taxSettlementAccountInput.value : ''
        });
        app.setRibbon(response.message || '全局税务设置已保存', response.ok ? 'success' : 'error');

        if (response.ok && response.data) {
            state.payload.tax_defaults = Object.assign({}, state.payload.tax_defaults, response.data);
            fillTaxForm(getSelectedStore());
            renderTaxSettings();
        }
    });

    elements.taxSettingsForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const store = getSelectedStore();
        if (!store) {
            app.setRibbon('请先选择店铺', 'error');
            return;
        }

        const response = await app.post('saveStoreTaxSettings', {
            store_id: state.payload.selected_store_id,
            tax_rate: roundCurrency(elements.taxRateInput.value),
            tax_custom_rate_enabled: Boolean(elements.taxCustomRateEnabledInput && elements.taxCustomRateEnabledInput.checked),
            tax_exempt: Boolean(elements.taxExemptInput && elements.taxExemptInput.checked)
        });
        app.setRibbon(response.message || '税务设置已保存', response.ok ? 'success' : 'error');

        if (response.ok && response.data) {
            fillTaxForm(response.data);
            renderTaxSettings();
        }
    });

    elements.commissionSettingsForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const store = getSelectedStore();
        if (!store) {
            app.setRibbon('请先选择店铺', 'error');
            return;
        }

        const response = await app.post('saveStoreCommissionSettings', {
            store_id: state.payload.selected_store_id,
            commission_rate: roundCurrency(elements.commissionRateInput.value)
        });
        app.setRibbon(response.message || '提成设置已保存', response.ok ? 'success' : 'error');

        if (response.ok && response.data) {
            fillCommissionForm(response.data);
            renderCommissionSettings();
        }
    });

    elements.ownerForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (!elements.storeIdInput.value) return;
        const response = await app.post('changeStoreOwner', {
            store_id: Number(elements.storeIdInput.value),
            owner_citizenid: elements.newOwnerInput.value
        });
        app.setRibbon(response.message || '店主已更新', response.ok ? 'success' : 'error');
    });

    elements.storePayoutForm.addEventListener('submit', async (event) => {
        event.preventDefault();

        const store = getSelectedStore();
        if (!store) {
            app.setRibbon('请先选择店铺', 'error');
            return;
        }

        const amount = roundCurrency(elements.storePayoutAmountInput.value);
        if (!(amount > 0)) {
            app.setRibbon('请输入有效的提现金额', 'error');
            return;
        }

        const response = await app.post('storePayout', {
            store_id: state.payload.selected_store_id,
            amount,
            reason: elements.storePayoutReasonInput.value
        });
        app.setRibbon(response.message || '提现已处理', response.ok ? 'success' : 'error');

        if (response.ok) {
            elements.storePayoutAmountInput.value = '';
            elements.storePayoutReasonInput.value = '';
        }
    });

    elements.storeArchiveButton.addEventListener('click', async () => {
        const store = getEditingStore();
        if (!store) return;

        const isArchived = store.status === 'archived';
        const response = await app.post(isArchived ? 'restoreStore' : 'archiveStore', {
            store_id: Number(store.id)
        });
        app.setRibbon(
            response.message || (isArchived ? '店铺已取消归档' : '店铺已归档'),
            response.ok ? 'success' : 'error'
        );
    });

    elements.loanForm.addEventListener('submit', async (event) => {
        event.preventDefault();

        if (!elements.loanIdInput.value) {
            app.setRibbon('请先选择贷款', 'error');
            return;
        }

        const response = await app.post('saveAdminLoan', {
            loan_id: Number(elements.loanIdInput.value),
            principal_amount: roundCurrency(elements.loanPrincipalInput.value),
            interest_amount: roundCurrency(elements.loanInterestInput.value),
            total_due: roundCurrency(elements.loanTotalInput.value),
            repaid_amount: roundCurrency(elements.loanRepaidInput.value),
            interest_rate: roundCurrency(elements.loanRateInput.value),
            term_days: Number(elements.loanTermInput.value || 1),
            status: elements.loanStatusInput.value,
            due_at: elements.loanDueAtInput.value
        });

        app.setRibbon(response.message || '贷款已更新', response.ok ? 'success' : 'error');

        if (response.ok) {
            state.selectedLoanId = Number(elements.loanIdInput.value);
            await refreshLoans();
        }
    });

    elements.createCollectionTaskButton.addEventListener('click', async () => {
        if (!elements.loanIdInput.value) {
            app.setRibbon('请先选择贷款', 'error');
            return;
        }

        const response = await app.post('createAdminCollectionTask', {
            loan_id: Number(elements.loanIdInput.value)
        });
        app.setRibbon(response.message || '催收任务已生成', response.ok ? 'success' : 'error');

        if (response.ok) {
            state.selectedLoanId = Number(elements.loanIdInput.value);
            await refreshLoans();
        }
    });

    elements.cancelCollectionTaskButton.addEventListener('click', async () => {
        const loan = getSelectedLoan();
        if (!loan || !loan.collection_task) {
            app.setRibbon('当前贷款没有可取消的催收任务', 'error');
            return;
        }

        const response = await app.post('cancelAdminCollectionTask', {
            loan_id: loan.id,
            task_id: loan.collection_task.id
        });
        app.setRibbon(response.message || '催收任务已取消', response.ok ? 'success' : 'error');

        if (response.ok) {
            state.selectedLoanId = Number(loan.id);
            await refreshLoans();
        }
    });

    elements.employeeForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (isStoreTabletMode() && !getEditingEmployee()) {
            app.setRibbon('店铺平板不支持手动添加员工，请先同步后再编辑权限', 'error');
            return;
        }

        const response = await app.post('saveEmployee', {
            store_id: state.payload.selected_store_id,
            citizenid: elements.employeeCitizenIdInput.value,
            role: elements.employeeRoleInput.value,
            can_refund: elements.employeeRefundInput.checked,
            can_discount: elements.employeeDiscountInput.checked
        });
        app.setRibbon(response.message || '员工已保存', response.ok ? 'success' : 'error');
    });

    elements.removeEmployeeButton.addEventListener('click', async () => {
        if (isStoreTabletMode()) {
            app.setRibbon('店铺平板不支持手动移除员工，请使用同步功能维护成员', 'error');
            return;
        }

        if (!elements.employeeCitizenIdInput.value) return;
        const response = await app.post('removeEmployee', {
            store_id: state.payload.selected_store_id,
            citizenid: elements.employeeCitizenIdInput.value
        });
        app.setRibbon(response.message || '员工已移除', response.ok ? 'success' : 'error');
    });

    elements.terminalForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        await submitTerminalForm();
    });

    elements.saveAndGiveTerminalButton.addEventListener('click', async () => {
        await submitTerminalForm({
            grant_item: true
        });
    });

    elements.placeTerminalButton.addEventListener('click', async () => {
        await submitTerminalForm({
            place_terminal: true
        });
    });

    elements.generateBindingCodeButton.addEventListener('click', async () => {
        if (!state.payload.selected_store_id) {
            app.setRibbon('请先选择店铺后再生成绑定码', 'error');
            return;
        }

        const response = await app.post('generateBindingCode', {
            store_id: state.payload.selected_store_id,
            terminal_type: elements.bindingCodeTypeInput.value
        });

        if (response.ok) {
            state.generatedBindingCode = response.data || null;
            renderBindingCodeState();
            app.setRibbon(
                response.message || `绑定码 ${response.data && response.data.code || '--'} 已生成`,
                'success'
            );
            return;
        }

        app.setRibbon(response.message || '绑定码生成失败', 'error');
    });

    document.getElementById('archive-terminal-button').addEventListener('click', async () => {
        if (!elements.terminalIdInput.value) return;
        const response = await app.post('archiveTerminal', {
            terminal_id: Number(elements.terminalIdInput.value)
        });
        app.setRibbon(response.message || '终端已归档', response.ok ? 'success' : 'error');
    });

    elements.modelForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const response = await app.post('saveTerminalModel', {
            model_key: elements.modelKeyInput.value,
            label: elements.modelLabelInput.value,
            model_name: elements.modelNameInput.value,
            status: elements.modelStatusInput.value
        });
        app.setRibbon(response.message || 'POS 型号已保存', response.ok ? 'success' : 'error');
    });

    document.getElementById('archive-model-button').addEventListener('click', async () => {
        if (!elements.modelKeyInput.value) return;
        const response = await app.post('archiveTerminalModel', {
            model_key: elements.modelKeyInput.value
        });
        app.setRibbon(response.message || 'POS 型号已归档', response.ok ? 'success' : 'error');
    });

    window.VancePayAdmin = {
        render
    };
})();
