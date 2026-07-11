/**
 * Finance Panel — Monarch Money integration for ARES WebUI.
 *
 * Provides: connection management, account overview, transactions,
 * budgets with adjustment, cashflow, recurring bills, and refresh.
 */

let _financeState = {
  connected: false,
  accounts: [],
  transactions: [],
  budgets: [],
  cashflow: [],
  recurring: [],
  loading: false,
  error: null,
};

/* ── API helpers ──────────────────────────────────────────────── */

async function _financeApi(path, opts = {}) {
  try {
    const res = await fetch(path, {
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      ...opts,
    });
    return await res.json();
  } catch (e) {
    return { success: false, error: e.message };
  }
}

function _financeGet(path) {
  return _financeApi(path, { method: 'GET' });
}

function _financePost(path, body) {
  return _financeApi(path, { method: 'POST', body: JSON.stringify(body) });
}

/* ── Status ──────────────────────────────────────────────────── */

async function _checkFinanceStatus() {
  const result = await _financeGet('/api/monarch/status');
  _financeState.connected = result.connected || false;
  _financeState.error = result.last_error || null;
  _renderFinanceStatus();
  return result;
}

function _renderFinanceStatus() {
  const badge = document.getElementById('financeStatusBadge');
  if (!badge) return;
  if (_financeState.connected) {
    badge.className = 'finance-status-badge connected';
    badge.innerHTML = '<span class="dot"></span> Connected';
  } else {
    badge.className = 'finance-status-badge disconnected';
    badge.innerHTML = '<span class="dot"></span> Disconnected';
  }
  const btn = document.getElementById('financeConnectBtn');
  if (btn) {
    btn.textContent = _financeState.connected ? 'Disconnect' : 'Connect';
    btn.disabled = false;
  }
}

/* ── Connect / Disconnect ─────────────────────────────────────── */

function _showFinanceConnectModal() {
  const existing = document.querySelector('.finance-modal-overlay');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.className = 'finance-modal-overlay';
  overlay.innerHTML = `
    <div class="finance-modal">
      <h3>Connect to Monarch Money</h3>
      <p style="font-size:13px;color:var(--muted);margin-bottom:var(--space-4)">
        Leave fields empty to try saved session. Enter email/password for first-time setup.
      </p>
      <div class="form-group">
        <label>Email</label>
        <input type="email" id="financeEmail" placeholder="you@example.com">
      </div>
      <div class="form-group">
        <label>Password</label>
        <input type="password" id="financePassword" placeholder="••••••••">
      </div>
      <div class="form-group">
        <label>MFA Secret Key (optional)</label>
        <input type="text" id="financeMfaSecret" placeholder="Leave blank if not using MFA">
      </div>
      <div class="error-msg" id="financeConnectError" style="display:none"></div>
      <div class="modal-actions">
        <button class="secondary" onclick="this.closest('.finance-modal-overlay').remove()">Cancel</button>
        <button class="primary" id="financeConnectSubmit">Connect</button>
      </div>
    </div>
  `;
  document.body.appendChild(overlay);

  document.getElementById('financeConnectSubmit').onclick = async () => {
    const email = document.getElementById('financeEmail').value.trim() || undefined;
    const password = document.getElementById('financePassword').value || undefined;
    const mfa_secret = document.getElementById('financeMfaSecret').value.trim() || undefined;
    const errEl = document.getElementById('financeConnectError');
    const btn = document.getElementById('financeConnectSubmit');
    btn.disabled = true;
    btn.textContent = 'Connecting...';
    errEl.style.display = 'none';

    const result = await _financePost('/api/monarch/connect', { email, password, mfa_secret });
    if (result.success) {
      overlay.remove();
      await _checkFinanceStatus();
      _loadFinanceData();
    } else if (result.needs_mfa) {
      errEl.textContent = 'MFA required — add your MFA secret key and try again.';
      errEl.style.display = 'block';
      btn.disabled = false;
      btn.textContent = 'Connect';
    } else {
      errEl.textContent = result.error || 'Connection failed';
      errEl.style.display = 'block';
      btn.disabled = false;
      btn.textContent = 'Connect';
    }
  };
}

async function _financeToggleConnect() {
  if (_financeState.connected) {
    await _financePost('/api/monarch/disconnect', {});
    _financeState.connected = false;
    _renderFinanceStatus();
    _financeState.accounts = [];
    _financeState.transactions = [];
    _financeState.budgets = [];
    _financeState.cashflow = [];
    _renderFinancePanel();
  } else {
    _showFinanceConnectModal();
  }
}

/* ── Data Loading ────────────────────────────────────────────── */

async function _loadFinanceData() {
  if (!_financeState.connected) return;
  _financeState.loading = true;
  _renderFinancePanel();

  const [accts, txns, budgets, cf, recurring] = await Promise.all([
    _financeGet('/api/monarch/accounts'),
    _financeGet('/api/monarch/transactions?limit=50'),
    _financeGet('/api/monarch/budgets'),
    _financeGet('/api/monarch/cashflow'),
    _financeGet('/api/monarch/recurring'),
  ]);

  _financeState.accounts = accts.success ? (accts.accounts || []) : [];
  _financeState.transactions = txns.success ? (txns.transactions || []) : [];
  _financeState.budgets = budgets.success ? (budgets.budgets || []) : [];
  _financeState.cashflow = cf.success ? (cf.cashflow || []) : [];
  _financeState.recurring = recurring.success ? (recurring.recurring || []) : [];
  _financeState.loading = false;
  _renderFinancePanel();
}

/* ── Rendering ────────────────────────────────────────────────── */

function _renderFinancePanel() {
  const content = document.getElementById('financeContent');
  if (!content) return;

  if (_financeState.loading) {
    content.innerHTML = '<div class="finance-loading"><div class="spinner"></div> Loading your finances...</div>';
    return;
  }

  if (!_financeState.connected) {
    content.innerHTML = `
      <div class="finance-empty">
        <p style="font-size:16px;margin-bottom:8px">Not connected to Monarch Money</p>
        <p style="font-size:13px;color:var(--muted)">Click Connect to link your account. Data is cached locally and never leaves your machine.</p>
      </div>
    `;
    return;
  }

  // Summary
  const totalBalance = _financeState.accounts.reduce((s, a) => s + (a.current_balance || 0), 0);
  const totalLiabilities = _financeState.accounts
    .filter(a => (a.subtype || '').toLowerCase().includes('credit') || (a.current_balance || 0) < 0)
    .reduce((s, a) => s + Math.abs(Math.min(a.current_balance || 0, 0)), 0);
  const monthlyIncome = _financeState.cashflow.reduce((s, c) => s + (c.income || 0), 0);
  const monthlyExpenses = _financeState.cashflow.reduce((s, c) => s + (c.expenses || 0), 0);
  const avgIncome = _financeState.cashflow.length > 0 ? (monthlyIncome / _financeState.cashflow.length) : 0;
  const avgExpenses = _financeState.cashflow.length > 0 ? (monthlyExpenses / _financeState.cashflow.length) : 0;
  const netMonthly = avgIncome - avgExpenses;

  // Accounts
  const accountsHtml = _financeState.accounts.map(a => {
    const bal = a.current_balance || 0;
    const cls = bal >= 0 ? 'positive' : 'negative';
    return `<tr>
      <td>${escHtml(a.display_name || a.name || 'Unknown')}</td>
      <td>${escHtml(a.subtype || '')}</td>
      <td>${escHtml(a.institution_name || '')}</td>
      <td class="amount ${cls}">${_fmtMoney(bal)}</td>
    </tr>`;
  }).join('');

  // Transactions
  const txnsHtml = _financeState.transactions.slice(0, 20).map(t => {
    const amt = t.amount || 0;
    const cls = amt >= 0 ? 'positive' : 'negative';
    return `<tr>
      <td>${escHtml(t.date || '')}</td>
      <td>${escHtml(t.merchant || t.description || '')}</td>
      <td>${escHtml(t.category_name || '')}</td>
      <td class="amount ${cls}">${_fmtMoney(amt)}</td>
    </tr>`;
  }).join('');

  // Budgets
  const budgetsHtml = _financeState.budgets.map(b => {
    const spent = b.spent || 0;
    const budget = b.amount || 0;
    const remaining = budget - spent;
    const pct = budget > 0 ? Math.min((spent / budget) * 100, 100) : 0;
    const barCls = remaining < 0 ? 'over' : (pct > 80 ? 'warning' : 'good');
    const remCls = remaining < 0 ? 'over' : 'under';
    return `<div class="finance-budget-item">
      <div class="category">${escHtml(b.category_name || 'Uncategorized')}</div>
      <div class="spend-row">
        <span class="spent">${_fmtMoney(spent)}</span>
        <span class="remaining ${remCls}">${remaining >= 0 ? _fmtMoney(remaining) + ' left' : _fmtMoney(Math.abs(remaining)) + ' over'}</span>
      </div>
      <div class="finance-budget-bar">
        <div class="finance-budget-bar-fill ${barCls}" style="width:${pct}%"></div>
      </div>
    </div>`;
  }).join('');

  // Cashflow chart (simple bar chart with divs)
  const maxCf = Math.max(..._financeState.cashflow.map(c => Math.max(c.income || 0, c.expenses || 0, 1)));
  const cfBars = _financeState.cashflow.slice().reverse().map(c => {
    const incPct = ((c.income || 0) / maxCf) * 100;
    const expPct = ((c.expenses || 0) / maxCf) * 100;
    return `<div style="display:flex;flex-direction:column;align-items:center;gap:2px;flex:1">
      <div style="width:100%;display:flex;flex-direction:column;align-items:center;height:120px;justify-content:flex-end">
        <div style="width:24px;background:var(--success);height:${incPct}%;border-radius:3px 3px 0 0;min-height:${c.income > 0 ? '4px' : '0'}"></div>
        <div style="width:24px;background:var(--error);height:${expPct}%;border-radius:3px 3px 0 0;min-height:${c.expenses > 0 ? '4px' : '0'}"></div>
      </div>
      <span style="font-size:10px;color:var(--muted)">${escHtml(c.month || '').slice(0, 7)}</span>
    </div>`;
  }).join('');

  // Recurring
  const recurringHtml = _financeState.recurring.slice(0, 10).map(r => {
    const amt = r.amount || 0;
    const cls = amt >= 0 ? 'positive' : 'negative';
    return `<tr>
      <td>${escHtml(r.merchant || r.description || '')}</td>
      <td>${escHtml(r.frequency || '')}</td>
      <td class="amount ${cls}">${_fmtMoney(amt)}</td>
    </tr>`;
  }).join('');

  content.innerHTML = `
    <div class="finance-summary-grid">
      <div class="finance-card">
        <div class="finance-card-label">Total Balance</div>
        <div class="finance-card-value ${totalBalance >= 0 ? 'positive' : 'negative'}">${_fmtMoney(totalBalance)}</div>
      </div>
      <div class="finance-card">
        <div class="finance-card-label">Monthly Net</div>
        <div class="finance-card-value ${netMonthly >= 0 ? 'positive' : 'negative'}">${_fmtMoney(netMonthly)}</div>
      </div>
      <div class="finance-card">
        <div class="finance-card-label">Avg Income</div>
        <div class="finance-card-value positive">${_fmtMoney(avgIncome)}</div>
      </div>
      <div class="finance-card">
        <div class="finance-card-label">Avg Expenses</div>
        <div class="finance-card-value negative">${_fmtMoney(avgExpenses)}</div>
      </div>
    </div>

    <div class="finance-section">
      <div class="finance-section-header">
        <span>Accounts (${_financeState.accounts.length})</span>
        <button class="action-btn" onclick="_financeRefresh()">Refresh</button>
      </div>
      <table class="finance-table">
        <thead><tr><th>Account</th><th>Type</th><th>Institution</th><th class="amount">Balance</th></tr></thead>
        <tbody>${accountsHtml || '<tr><td colspan="4" style="text-align:center;color:var(--muted)">No accounts</td></tr>'}</tbody>
      </table>
    </div>

    <div class="finance-section">
      <div class="finance-section-header">
        <span>Budgets (${_financeState.budgets.length})</span>
      </div>
      <div class="finance-budget-grid">
        ${budgetsHtml || '<div class="finance-empty">No budgets configured</div>'}
      </div>
    </div>

    <div class="finance-section">
      <div class="finance-section-header">
        <span>Cashflow</span>
      </div>
      <div class="finance-chart-area">
        ${cfBars ? `<div style="display:flex;width:100%;gap:4px;align-items:flex-end">${cfBars}</div>
        <div style="display:flex;gap:16px;font-size:11px;color:var(--muted);margin-top:8px">
          <span><span style="display:inline-block;width:10px;height:10px;background:var(--success);border-radius:2px;vertical-align:middle;margin-right:4px"></span>Income</span>
          <span><span style="display:inline-block;width:10px;height:10px;background:var(--error);border-radius:2px;vertical-align:middle;margin-right:4px"></span>Expenses</span>
        </div>` : '<span>No cashflow data</span>'}
      </div>
    </div>

    <div class="finance-section">
      <div class="finance-section-header">
        <span>Recent Transactions</span>
      </div>
      <table class="finance-table">
        <thead><tr><th>Date</th><th>Merchant</th><th>Category</th><th class="amount">Amount</th></tr></thead>
        <tbody>${txnsHtml || '<tr><td colspan="4" style="text-align:center;color:var(--muted)">No transactions</td></tr>'}</tbody>
      </table>
    </div>

    <div class="finance-section">
      <div class="finance-section-header">
        <span>Recurring Bills</span>
      </div>
      <table class="finance-table">
        <thead><tr><th>Merchant</th><th>Frequency</th><th class="amount">Amount</th></tr></thead>
        <tbody>${recurringHtml || '<tr><td colspan="3" style="text-align:center;color:var(--muted)">No recurring transactions</td></tr>'}</tbody>
      </table>
    </div>
  `;
}

async function _financeRefresh() {
  if (!_financeState.connected) return;
  await _financePost('/api/monarch/refresh', {});
  await _loadFinanceData();
}

/* ── Helpers ──────────────────────────────────────────────────── */

function _fmtMoney(n) {
  if (n == null || isNaN(n)) return '$0.00';
  const abs = Math.abs(n);
  const formatted = abs.toLocaleString('en-US', { style: 'currency', currency: 'USD' });
  return n < 0 ? '-' + formatted : formatted;
}

function escHtml(s) {
  if (!s) return '';
  const d = document.createElement('div');
  d.textContent = String(s);
  return d.innerHTML;
}

/* ── Panel Init ───────────────────────────────────────────────── */

function initFinancePanel() {
  _checkFinanceStatus();
}

// Called when the panel becomes active
function onFinancePanelActivate() {
  if (_financeState.connected) {
    _loadFinanceData();
  }
}
