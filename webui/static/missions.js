/**
 * Missions Panel — CEO multi-agent orchestration dashboard for ARES WebUI.
 *
 * Backend: webui/api/missions.py. Distinct from the single-session "/goal"
 * continuation feature (webui/api/goals.py, the "/goal" chat command) — a
 * Mission decomposes one prompt into sub-tasks dispatched across Hermes,
 * JROS, and direct Anthropic/OpenAI calls, tracked here as a list with a
 * sub-agent status breakdown per item. Live updates arrive via the
 * 'mission_update' SSE event on the existing per-session stream (wired in
 * messages.js's startSessionStream → _handleMissionUpdateEvent below).
 */

let _missionsState = {
  missions: [],
  currentId: null,
  loading: false,
  error: null,
};

/* ── API helpers ──────────────────────────────────────────────── */

async function _missionsApi(path, opts = {}) {
  try {
    const res = await fetch(path, {
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      ...opts,
    });
    return await res.json();
  } catch (e) {
    return { error: e.message };
  }
}

function _missionsSessionId() {
  return S.session && S.session.session_id;
}

function _missionsEscapeHtml(s) {
  const d = document.createElement('div');
  d.textContent = s == null ? '' : String(s);
  return d.innerHTML;
}

async function loadMissions() {
  const sid = _missionsSessionId();
  if (!sid) return;
  _missionsState.loading = true;
  const resp = await _missionsApi('api/missions?session_id=' + encodeURIComponent(sid));
  _missionsState.loading = false;
  if (resp && resp.missions) {
    _missionsState.missions = resp.missions;
    _missionsState.error = null;
    if (!_missionsState.currentId && resp.missions.length) {
      _missionsState.currentId = resp.missions[0].id;
    }
  } else {
    _missionsState.error = (resp && resp.error) || 'Failed to load missions';
  }
  renderMissionsList();
  renderMissionDetail();
}

async function createMission(prompt) {
  const sid = _missionsSessionId();
  const text = (prompt || '').trim();
  if (!sid) {
    if (typeof showToast === 'function') showToast('Open a conversation first', 2600, 'warning');
    return;
  }
  if (!text) return;
  const resp = await _missionsApi('api/missions', {
    method: 'POST',
    body: JSON.stringify({ session_id: sid, prompt: text }),
  });
  if (resp && resp.mission) {
    _missionsState.missions.unshift(resp.mission);
    _missionsState.currentId = resp.mission.id;
    renderMissionsList();
    renderMissionDetail();
  } else if (typeof showToast === 'function') {
    showToast((resp && resp.error) || 'Failed to start mission', 3200, 'error');
  }
}

async function cancelMission(missionId) {
  const sid = _missionsSessionId();
  if (!sid || !missionId) return;
  await _missionsApi('api/missions/' + encodeURIComponent(missionId), {
    method: 'DELETE',
    body: JSON.stringify({ session_id: sid }),
  });
}

function selectMission(id) {
  _missionsState.currentId = id;
  renderMissionsList();
  renderMissionDetail();
}

/* ── Live updates (mission_update SSE event, see messages.js) ───── */

function _handleMissionUpdateEvent(e, sid) {
  let mission;
  try {
    mission = JSON.parse(e.data || '{}');
  } catch (_) {
    return;
  }
  if (!mission || !mission.id) return;
  const idx = _missionsState.missions.findIndex(m => m.id === mission.id);
  if (idx >= 0) _missionsState.missions[idx] = mission;
  else _missionsState.missions.unshift(mission);
  renderMissionsList();
  if (_missionsState.currentId === mission.id) renderMissionDetail();
}

/* ── Rendering ────────────────────────────────────────────────── */

const _MISSION_STATUS_LABELS = {
  planning: 'Planning', running: 'Running', done: 'Done',
  failed: 'Failed', cancelling: 'Cancelling', cancelled: 'Cancelled',
  pending: 'Queued',
};

function _missionStatusLabel(status) {
  return _MISSION_STATUS_LABELS[status] || status || '';
}

function renderMissionsList() {
  const list = $('missionsList');
  if (!list) return;
  const missions = _missionsState.missions;
  if (_missionsState.loading && !missions.length) {
    list.innerHTML = '<div style="padding:12px;color:var(--muted);font-size:12px">Loading…</div>';
    return;
  }
  if (!missions.length) {
    list.innerHTML = '<div style="padding:12px;color:var(--muted);font-size:12px">No missions yet. Describe a goal below to put the team to work.</div>';
    return;
  }
  list.innerHTML = missions.map(m => {
    const active = m.id === _missionsState.currentId ? ' active' : '';
    const subtasks = m.subtasks || [];
    const done = subtasks.filter(s => s.status === 'done').length;
    return `<div class="mission-list-item${active}" onclick="selectMission('${m.id}')">
      <div class="mission-list-item-title">${_missionsEscapeHtml((m.prompt || '').slice(0, 80))}</div>
      <div class="mission-list-item-meta">
        <span class="mission-status-pill mission-status-${m.status}">${_missionStatusLabel(m.status)}</span>
        <span>${done}/${subtasks.length} sub-agents</span>
      </div>
    </div>`;
  }).join('');
}

function renderMissionDetail() {
  const body = $('missionDetailBody');
  const empty = $('missionDetailEmpty');
  const title = $('missionDetailTitle');
  if (!body || !empty) return;
  const mission = _missionsState.missions.find(m => m.id === _missionsState.currentId);
  if (!mission) {
    body.style.display = 'none';
    empty.style.display = 'flex';
    if (title) title.textContent = '';
    return;
  }
  empty.style.display = 'none';
  body.style.display = 'flex';
  if (title) title.textContent = (mission.prompt || '').slice(0, 80);

  const subtaskRows = (mission.subtasks || []).map(st => `
    <div class="mission-subtask-row mission-subtask-${st.status}">
      <div class="mission-subtask-head">
        <span class="mission-subtask-label">${_missionsEscapeHtml(st.label || st.backend)}</span>
        <span class="mission-status-pill mission-status-${st.status}">${_missionStatusLabel(st.status)}</span>
      </div>
      <div class="mission-subtask-desc">${_missionsEscapeHtml(st.description)}</div>
      ${st.result ? `<div class="mission-subtask-result">${_missionsEscapeHtml(String(st.result).slice(0, 4000))}</div>` : ''}
      ${st.error ? `<div class="mission-subtask-error">${_missionsEscapeHtml(st.error)}</div>` : ''}
    </div>
  `).join('');

  const canCancel = mission.status === 'running' || mission.status === 'planning';
  body.innerHTML = `
    <div class="mission-detail-header">
      <div class="mission-detail-prompt">${_missionsEscapeHtml(mission.prompt)}</div>
      <div class="mission-detail-header-actions">
        <span class="mission-status-pill mission-status-${mission.status}">${_missionStatusLabel(mission.status)}</span>
        ${canCancel ? `<button class="panel-head-btn" onclick="cancelMission('${mission.id}')">Cancel</button>` : ''}
      </div>
    </div>
    ${mission.error ? `<div class="mission-detail-error">${_missionsEscapeHtml(mission.error)}</div>` : ''}
    <div class="mission-subtask-list">${subtaskRows || '<div style="color:var(--muted);font-size:12px;padding:8px 0">Planning sub-agents…</div>'}</div>
  `;
}

/* ── Panel lifecycle ──────────────────────────────────────────── */

function initMissionsPanel() {
  const input = $('missionPromptInput');
  const btn = $('missionStartBtn');
  if (btn && !btn._missionsWired) {
    btn._missionsWired = true;
    btn.addEventListener('click', () => {
      if (!input) return;
      createMission(input.value);
      input.value = '';
    });
  }
  if (input && !input._missionsWired) {
    input._missionsWired = true;
    input.addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        if (btn) btn.click();
      }
    });
  }
  loadMissions();
}
