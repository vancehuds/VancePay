(function () {
    const app = window.VancePayApp;
    const state = {
        payload: {},
        selectedTaskId: null,
        latestClues: {},
        pending: false
    };

    const elements = {
        subcopy: document.getElementById('collections-subcopy'),
        openCount: document.getElementById('collections-open-count'),
        myCount: document.getElementById('collections-my-count'),
        limitCount: document.getElementById('collections-limit-count'),
        poolStatus: document.getElementById('collections-pool-status'),
        availableList: document.getElementById('collection-available-list'),
        myList: document.getElementById('collection-my-list'),
        detail: document.getElementById('collection-detail'),
        detailCopy: document.getElementById('collection-detail-copy'),
        refreshButton: document.getElementById('collections-refresh-button'),
        clueRefreshButton: document.getElementById('collection-clue-refresh-button')
    };

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function taskId(task) {
        return String(task && task.id || '');
    }

    function availableTasks() {
        return Array.isArray(state.payload.available_tasks) ? state.payload.available_tasks : [];
    }

    function myTasks() {
        return Array.isArray(state.payload.my_tasks) ? state.payload.my_tasks : [];
    }

    function selectedTask() {
        return myTasks().find((task) => taskId(task) === String(state.selectedTaskId)) || myTasks()[0] || null;
    }

    function formatStatus(status) {
        return {
            open: '可领取',
            claimed: '已领取',
            completed: '已完成',
            cancelled: '已取消'
        }[status] || status || '--';
    }

    function formatDate(value) {
        return app.formatDate(value);
    }

    function formatMeters(value) {
        const meters = Number(value);
        if (!Number.isFinite(meters) || meters <= 0) return '--';
        return `${Math.round(meters)}m`;
    }

    function isCompletedTask(task) {
        return task && (task.status === 'completed' || task.loan_status === 'paid');
    }

    function taskRewardAmount(task) {
        return Number(task && task.reward_amount || 0);
    }

    function isRewardClaimed(task) {
        return Boolean(task && (task.reward_claimed || task.reward_claimed_at));
    }

    function canClaimReward(task) {
        return isCompletedTask(task) && taskRewardAmount(task) > 0 && !isRewardClaimed(task);
    }

    function taskTitle(task) {
        return task && task.loan_code ? `贷款 ${task.loan_code}` : `任务 #${task && task.id || '--'}`;
    }

    function taskMeta(task) {
        const completed = isCompletedTask(task);
        const parts = [
            {
                text: completed
                    ? `已还清 ${app.formatCurrency(task.loan_total_due || task.total_due || 0)}`
                    : `欠款 ${app.formatCurrency(task.outstanding_amount || 0)}`,
                tone: completed ? 'positive' : 'warning'
            },
            { text: `到期 ${formatDate(task.due_at)}` },
            { text: `CID ${task.debtor_citizenid || '--'}` }
        ];

        if (task.debtor_name_snapshot) {
            parts.splice(2, 0, { text: task.debtor_name_snapshot });
        }

        if (completed && task.completed_at) {
            parts.splice(2, 0, { text: `完成 ${formatDate(task.completed_at)}` });
        }

        if (completed && taskRewardAmount(task) > 0) {
            parts.splice(1, 0, {
                text: `${isRewardClaimed(task) ? '已领奖励' : '奖励'} ${app.formatCurrency(taskRewardAmount(task))}`,
                tone: isRewardClaimed(task) ? 'positive' : 'warning'
            });
        }

        return parts;
    }

    function renderEmpty(message) {
        return `<div class="collection-empty">${escapeHtml(message)}</div>`;
    }

    function renderTaskCard(task, options = {}) {
        const selected = options.selected === true;
        const action = options.action || '';
        const meta = taskMeta(task).map((item) => `
            <span class="collection-chip ${item.tone || ''}">${escapeHtml(item.text)}</span>
        `).join('');

        return `
            <article class="collection-task-card ${selected ? 'is-selected' : ''}" data-task-id="${escapeHtml(task.id)}">
                <div>
                    <h3>${escapeHtml(taskTitle(task))}</h3>
                    <p>${escapeHtml(formatStatus(task.status))} · ${escapeHtml(task.task_code || '--')}</p>
                </div>
                <div class="collection-task-meta">${meta}</div>
                ${action}
            </article>
        `;
    }

    function renderAvailable() {
        const tasks = availableTasks();
        elements.poolStatus.textContent = tasks.length ? '开放领取' : '暂无任务';

        if (!tasks.length) {
            elements.availableList.innerHTML = renderEmpty('暂无可领取逾期任务');
            return;
        }

        elements.availableList.innerHTML = tasks.map((task) => renderTaskCard(task, {
            action: `
                <div class="collection-task-actions">
                    <button class="mini-button" type="button" data-claim-task="${escapeHtml(task.id)}">领取</button>
                </div>
            `
        })).join('');
    }

    function renderMine() {
        const tasks = myTasks();

        if (!tasks.length) {
            elements.myList.innerHTML = renderEmpty('还没有已领取任务');
            return;
        }

        elements.myList.innerHTML = tasks.map((task) => {
            const completed = isCompletedTask(task);

            return renderTaskCard(task, {
                selected: taskId(task) === String(state.selectedTaskId),
                action: `
                <div class="collection-task-actions">
                    <button class="mini-button" type="button" data-select-task="${escapeHtml(task.id)}">查看</button>
                    ${canClaimReward(task) ? `<button class="mini-button" type="button" data-claim-reward="${escapeHtml(task.id)}">领取奖励</button>` : ''}
                    ${completed ? '' : `<button class="mini-button" type="button" data-refresh-task="${escapeHtml(task.id)}">线索</button>`}
                </div>
            `
            });
        }).join('');
    }

    function clueForTask(task) {
        if (!task) return null;
        return state.latestClues[taskId(task)] || task.clue_snapshot || null;
    }

    function renderDetail() {
        const task = selectedTask();
        state.selectedTaskId = task ? task.id : null;
        elements.clueRefreshButton.disabled = !task || state.pending || isCompletedTask(task);

        if (!task) {
            elements.detailCopy.textContent = '选择已领取任务查看线索。';
            elements.detail.innerHTML = '<div class="detail-placeholder">暂无已领取任务</div>';
            return;
        }

        const clue = clueForTask(task);
        elements.detailCopy.textContent = `${taskTitle(task)} · ${formatStatus(task.status)}`;

        if (isCompletedTask(task)) {
            const reward = taskRewardAmount(task);
            const rewardText = reward > 0
                ? (isRewardClaimed(task)
                    ? `奖励 ${app.formatCurrency(reward)} 已领取。`
                    : `可领取奖励 ${app.formatCurrency(reward)}。`)
                : '该任务没有可领取奖励。';

            elements.detail.innerHTML = `
                <div class="collection-clue-card">
                    ${renderTaskCard(task)}
                    ${canClaimReward(task) ? `
                        <div class="collection-task-actions">
                            <button class="mini-button" type="button" data-claim-reward="${escapeHtml(task.id)}">领取奖励</button>
                        </div>
                    ` : ''}
                    <p class="collection-clue-note">该贷款已结清，追债任务已完成。${escapeHtml(rewardText)}逾期信用记录会在 VanceCtifo 中保留为已还清状态。</p>
                </div>
            `;
            return;
        }

        if (!clue) {
            elements.detail.innerHTML = `
                <div class="collection-clue-card">
                    ${renderTaskCard(task)}
                    <p class="collection-clue-note">领取成功后刷新线索。</p>
                </div>
            `;
            return;
        }

        const debtor = clue.debtor || {};
        const loan = clue.loan || {};
        const location = clue.location || {};
        const distance = clue.distance || {};
        const online = clue.online === true;
        const searchArea = location.search_area || clue.search_area || {};
        const place = online
            ? `${location.zone || '未知区域'} · ${location.street || '未知街区'}${location.cross_street ? ` / ${location.cross_street}` : ''}`
            : (clue.notice || '当前离线');
        const searchAreaText = online && searchArea.radius
            ? `${formatMeters(searchArea.radius)} 搜索圈`
            : (online ? '未生成' : '--');
        const clueNote = online
            ? (searchArea.radius
                ? `已在地图标记约 ${formatMeters(searchArea.radius)} 的模糊搜索范围，刷新线索会更新范围。`
                : '线索为模糊位置，不提供精确坐标。')
            : '目标当前离线，只显示 VanceCtifo 档案信息。';

        elements.detail.innerHTML = `
            <div class="collection-clue-card">
                <div class="collection-clue-hero">
                    <span>${online ? '在线线索' : '离线档案'}</span>
                    <strong>${escapeHtml(debtor.name || task.debtor_name_snapshot || debtor.citizenid || '--')}</strong>
                </div>
                <div class="collection-clue-grid">
                    <div>
                        <span>CitizenID</span>
                        <strong>${escapeHtml(debtor.citizenid || task.debtor_citizenid || '--')}</strong>
                    </div>
                    <div>
                        <span>电话</span>
                        <strong>${escapeHtml(debtor.phone || task.debtor_phone_snapshot || '--')}</strong>
                    </div>
                    <div>
                        <span>欠款</span>
                        <strong>${escapeHtml(app.formatCurrency(loan.outstanding_amount || task.outstanding_amount || 0))}</strong>
                    </div>
                    <div>
                        <span>到期时间</span>
                        <strong>${escapeHtml(formatDate(loan.due_at || task.due_at))}</strong>
                    </div>
                    <div>
                        <span>区域</span>
                        <strong>${escapeHtml(place)}</strong>
                    </div>
                    <div>
                        <span>距离</span>
                        <strong>${escapeHtml(distance.band || '未知距离')}${distance.meters ? ` · ${escapeHtml(distance.meters)}m` : ''}</strong>
                    </div>
                    <div>
                        <span>地图范围</span>
                        <strong>${escapeHtml(searchAreaText)}</strong>
                    </div>
                </div>
                <p class="collection-clue-note">${escapeHtml(clueNote)}</p>
            </div>
        `;
    }

    function renderOverview() {
        const summary = state.payload.summary || {};
        const config = state.payload.config || {};
        elements.openCount.textContent = String(summary.available_count ?? availableTasks().length);
        elements.myCount.textContent = String(summary.my_active_count ?? myTasks().length);
        elements.limitCount.textContent = String(summary.claim_limit ?? config.claim_limit ?? 1);
        elements.subcopy.textContent = state.payload.player_citizenid
            ? `持有人 ${state.payload.player_citizenid}`
            : '公开逾期贷款任务池';
    }

    function render() {
        if (!selectedTask() && myTasks().length) {
            state.selectedTaskId = myTasks()[0].id;
        }

        renderOverview();
        renderAvailable();
        renderMine();
        renderDetail();
    }

    async function refresh() {
        if (state.pending) return;
        state.pending = true;
        elements.refreshButton.disabled = true;

        try {
            const response = await app.post('refreshCollections', {});
            if (response.ok) {
                if (response.data && response.data.available_tasks) {
                    state.payload = response.data;
                    render();
                }
                app.setRibbon(response.message || '追债任务已刷新', 'success');
            } else {
                app.setRibbon(response.message || '刷新失败', 'error');
            }
        } finally {
            state.pending = false;
            elements.refreshButton.disabled = false;
            renderDetail();
        }
    }

    async function claimTask(id) {
        if (!id || state.pending) return;

        state.pending = true;
        renderDetail();

        try {
            const response = await app.post('claimCollectionTask', { task_id: Number(id) });
            if (response.ok) {
                if (response.data && response.data.available_tasks) {
                    state.payload = response.data;
                }
                state.selectedTaskId = response.data && response.data.claimed_task
                    ? response.data.claimed_task.id
                    : id;
                if (response.data && response.data.claimed_clue) {
                    state.latestClues[String(state.selectedTaskId)] = response.data.claimed_clue;
                }
            }

            app.setRibbon(response.message || (response.ok ? '任务已领取' : '领取失败'), response.ok ? 'success' : 'error');
        } finally {
            state.pending = false;
        }
    }

    async function claimReward(id) {
        if (!id || state.pending) return;

        state.pending = true;
        renderDetail();

        try {
            const response = await app.post('claimCollectionReward', { task_id: Number(id) });
            if (response.ok && response.data && response.data.available_tasks) {
                state.payload = response.data;
            }

            app.setRibbon(response.message || (response.ok ? '奖励已领取' : '奖励领取失败'), response.ok ? 'success' : 'error');
        } finally {
            state.pending = false;
            render();
        }
    }

    async function refreshClue(id = state.selectedTaskId) {
        if (!id || state.pending) return;

        state.pending = true;
        renderDetail();

        try {
            const response = await app.post('getCollectionTaskClue', { task_id: Number(id) });
            if (response.ok && response.data && response.data.clue) {
                state.latestClues[String(id)] = response.data.clue;
            }

            app.setRibbon(response.message || (response.ok ? '线索已刷新' : '线索刷新失败'), response.ok ? 'success' : 'error');
        } finally {
            state.pending = false;
            renderDetail();
        }
    }

    elements.refreshButton.addEventListener('click', refresh);
    elements.clueRefreshButton.addEventListener('click', () => refreshClue());

    elements.availableList.addEventListener('click', (event) => {
        const button = event.target.closest('[data-claim-task]');
        if (button) {
            claimTask(button.dataset.claimTask);
        }
    });

    elements.myList.addEventListener('click', (event) => {
        const rewardButton = event.target.closest('[data-claim-reward]');
        const selectButton = event.target.closest('[data-select-task]');
        const refreshButton = event.target.closest('[data-refresh-task]');

        if (rewardButton) {
            state.selectedTaskId = rewardButton.dataset.claimReward;
            claimReward(state.selectedTaskId);
            return;
        }

        if (selectButton) {
            state.selectedTaskId = selectButton.dataset.selectTask;
            render();
            return;
        }

        if (refreshButton) {
            state.selectedTaskId = refreshButton.dataset.refreshTask;
            refreshClue(state.selectedTaskId);
        }
    });

    elements.detail.addEventListener('click', (event) => {
        const rewardButton = event.target.closest('[data-claim-reward]');
        if (rewardButton) {
            state.selectedTaskId = rewardButton.dataset.claimReward;
            claimReward(state.selectedTaskId);
        }
    });

    window.VancePayCollections = {
        render(payload) {
            state.payload = payload || {};
            if (state.payload.claimed_task) {
                state.selectedTaskId = state.payload.claimed_task.id;
            }
            if (state.payload.claimed_clue && state.selectedTaskId) {
                state.latestClues[String(state.selectedTaskId)] = state.payload.claimed_clue;
            }
            render();
        }
    };
})();
