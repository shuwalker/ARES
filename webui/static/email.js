(function(){
  const state = {
    loaded: false,
    loading: false,
    messages: [],
    selectedId: null,
    mode: 'unread', // 'unread' | 'all'
    query: '',
    cleanResult: null,
    cleanRunning: false,
  };

  function $(id){ return document.getElementById(id); }

  function esc(value){
    return String(value == null ? '' : value)
      .replace(/&/g,'&amp;')
      .replace(/</g,'&lt;')
      .replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;')
      .replace(/'/g,'&#39;');
  }

  function jsArg(value){
    return esc(String(value == null ? '' : value)
      .replace(/\\/g,'\\\\')
      .replace(/'/g,"\\'")
      .replace(/[\r\n]+/g,' '));
  }

  function msgId(message){
    return String(message && (message.id || message.message_id || message.messageId || '') || '');
  }

  function msgBody(message){
    return String(message && (message.body_plain || message.body || message.text || message.preview || '') || '');
  }

  function classificationBadge(cls){
    const colors = {
      keep:        '#22c55e',
      junk:        '#ef4444',
      newsletter:  '#f59e0b',
      archive:     '#3b82f6',
    };
    const labels = {
      keep: 'KEEP',
      junk: 'JUNK',
      newsletter: 'PROMO',
      archive: 'ARCHIVE',
    };
    const color = colors[cls] || '#888';
    const label = labels[cls] || (cls || '???').toUpperCase();
    return `<span style="display:inline-block;padding:2px 7px;border-radius:6px;font-size:10px;font-weight:700;letter-spacing:.04em;color:#fff;background:${color};">${label}</span>`;
  }

  function setStatus(text, kind){
    const el = $('emailStatus');
    if(!el) return;
    if(!text){
      el.style.display='none';
      el.textContent='';
      el.classList.remove('error','warn','success');
      return;
    }
    el.textContent = text;
    el.style.display = '';
    el.classList.toggle('error', kind === 'error');
    el.classList.toggle('warn', kind === 'warn');
    el.classList.toggle('success', kind === 'success');
  }

  function renderList(){
    const list = $('emailList');
    const stats = $('emailStats');
    if(!list) return;
    if(state.loading){
      list.innerHTML = '<div class="email-empty">Loading messages from Mail.app…</div>';
      if(stats) stats.innerHTML = '';
      return;
    }
    if(!state.messages.length){
      list.innerHTML = '<div class="email-empty">No messages found.</div>';
      if(stats) stats.innerHTML = '';
      return;
    }
    // Stats bar
    if(stats){
      const unread = state.messages.filter(m => !m.is_read).length;
      const read = state.messages.filter(m => m.is_read).length;
      stats.innerHTML = `<span>${state.messages.length} msgs</span><span>${unread} unread</span><span>${read} read</span>`;
    }
    // Filter by search query
    let msgs = state.messages;
    if(state.query){
      const q = state.query.toLowerCase();
      msgs = msgs.filter(m =>
        (m.subject||'').toLowerCase().includes(q) ||
        (m.sender||'').toLowerCase().includes(q) ||
        (msgBody(m)).toLowerCase().includes(q)
      );
    }
    list.innerHTML = msgs.map(message => {
      const id = msgId(message);
      const active = id && id === state.selectedId;
      const subject = message.subject || '(No subject)';
      const sender = message.sender || 'Unknown';
      const date = message.date_received || message.date || '';
      const read = message.is_read;
      const cls = message._classification;
      const preview = msgBody(message).replace(/\s+/g,' ').trim().slice(0,80);
      return `<button type="button" class="email-item${active?' active':''}${read?' is-read':''}" onclick="AresEmail.select('${jsArg(id)}')">
        <span class="email-item-row">${cls ? classificationBadge(cls) : ''}${!read ? '<span class="email-read-badge" style="background:var(--accent);color:#fff;">NEW</span>' : ''}<span class="email-item-subject">${esc(subject)}</span></span>
        <span class="email-item-sender">${esc(sender)}${date ? ` · <span class="email-item-date">${esc(date)}</span>` : ''}</span>
        ${preview ? `<span class="email-item-preview">${esc(preview)}</span>` : ''}
      </button>`;
    }).join('');
  }

  function renderDetail(message, options){
    const detail = $('emailDetail');
    if(!detail) return;
    if(!message){
      detail.hidden = false;
      detail.innerHTML = '<div class="email-detail-empty">Select an email to preview it.</div>';
      return;
    }
    detail.hidden = false;
    const id = msgId(message);
    const body = msgBody(message) || '(No plain-text body returned.)';
    const draft = options && options.draft;
    const cls = message._classification;
    const clsMethod = message._classificationMethod;
    detail.innerHTML = `
      <div class="email-detail-card">
        <div class="email-detail-meta">
          <div class="email-detail-subject">${cls ? classificationBadge(cls) + ' ' : ''}${esc(message.subject || '(No subject)')}</div>
          <div class="email-detail-sender">${esc(message.sender || 'Unknown sender')}</div>
          ${message.date_received || message.date ? `<div class="email-detail-date">${esc(message.date_received || message.date)}</div>` : ''}
          ${cls ? `<div class="email-detail-classification">Classified as <strong>${esc(cls)}</strong> via ${esc(clsMethod || 'heuristic')}</div>` : ''}
        </div>
        <div class="email-detail-body">${esc(body)}</div>
        <div class="email-actions">
          <button class="btn secondary" type="button" onclick="AresEmail.draft('${jsArg(id)}')">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
            Draft reply
          </button>
          <button class="btn secondary" type="button" onclick="AresEmail.classify('${jsArg(id)}')">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>
            Classify
          </button>
          <button class="btn secondary" type="button" onclick="AresEmail.markRead('${jsArg(id)}')" title="Mark as read"${read ? ' disabled' : ''}>
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
            Mark read
          </button>
          <button class="btn secondary" type="button" onclick="AresEmail.showThread('${jsArg(id)}')" title="View thread">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
            Thread
          </button>
          <button class="btn email-action-junk" type="button" onclick="AresEmail.move('${jsArg(id)}','junk')">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            Junk
          </button>
          <button class="btn secondary" type="button" onclick="AresEmail.move('${jsArg(id)}','archive')">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 8v13H3V8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></svg>
            Archive
          </button>
          <button class="btn secondary" type="button" onclick="AresEmail.saveNas('${jsArg(id)}')" title="Save to NAS archive">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>
            Save NAS
          </button>
        </div>
        </div>
        ${draft ? `<div class="email-draft-block"><div class="email-draft-title">Draft reply</div><textarea class="email-draft-text" id="emailDraftText" spellcheck="true">${esc(draft)}</textarea><div class="email-draft-actions"><button class="btn secondary" type="button" onclick="AresEmail.copyDraft()">Copy draft</button><div class="email-draft-note">Edit above, then copy to paste into Mail.app or your preferred client.</div></div></div>` : ''}
      </div>`;
  }

  async function load(force){
    if(state.loading) return;
    if(state.loaded && !force){
      renderList();
      return;
    }
    state.loading = true;
    setStatus('Loading...', '');
    renderList();
    try{
      const endpoint = state.mode === 'all' ? '/api/email/all?limit=200' : '/api/email/unread?limit=20';
      const result = await api(endpoint, { timeoutMs: 120000, retryTimeouts: false, retries: 0 });
      const messages = Array.isArray(result) ? result : (result.messages || result.emails || []);
      // Preserve any previously attached classifications
      const oldMap = {};
      state.messages.forEach(m => { const mid = msgId(m); if(mid && m._classification) oldMap[mid] = m._classification; });
      state.messages = messages.map(m => {
        const mid = msgId(m);
        if(oldMap[mid]) m._classification = oldMap[mid];
        return m;
      });
      state.loaded = true;
      if(state.selectedId && !messages.some(m => msgId(m) === state.selectedId)) state.selectedId = null;
      const unread = result.unread != null ? result.unread : messages.filter(m => !m.is_read).length;
      const total = result.total || messages.length;
      const read = result.read != null ? result.read : messages.filter(m => m.is_read).length;
      if(state.mode === 'all'){
        setStatus(`Loaded ${total} messages (${unread} unread, ${read} read).`, messages.length ? 'success' : '');
      } else {
        setStatus(messages.length ? `Loaded ${messages.length} unread messages.` : 'Inbox has no unread messages.', messages.length ? 'success' : '');
      }
    }catch(err){
      console.error('Email load failed', err);
      state.messages = [];
      setStatus(err && err.message ? err.message : 'Failed to load email.', 'error');
    }finally{
      state.loading = false;
      renderList();
    }
  }

  async function select(id){
    if(!id) return;
    state.selectedId = id;
    renderList();
    renderDetail(null);
    setStatus('', '');
    try{
      const result = await api('/api/email/message?id=' + encodeURIComponent(id), { timeoutMs: 60000, retryTimeouts: false, retries: 0 });
      const message = result.message || result.email || result;
      // Preserve classification if we had one
      const existing = state.messages.find(m => msgId(m) === id);
      if(existing && existing._classification){
        message._classification = existing._classification;
        message._classificationMethod = existing._classificationMethod;
      }
      const idx = state.messages.findIndex(m => msgId(m) === id);
      if(idx >= 0) state.messages[idx] = { ...state.messages[idx], ...message };
      renderList();
      renderDetail(message);
    }catch(err){
      console.error('Email read failed', err);
      setStatus(err && err.message ? err.message : 'Failed to read email.', 'error');
    }
  }

  async function draft(id){
    if(!id) id = state.selectedId;
    if(!id) return;
    setStatus('Generating draft reply...', '');
    try{
      const result = await api('/api/email/draft', {
        method: 'POST',
        body: JSON.stringify({ id }),
        timeoutMs: 90000,
        retryTimeouts: false,
        retries: 0,
      });
      const draftText = result.draft || result.reply || result.text || '';
      const message = state.messages.find(m => msgId(m) === id) || { id };
      renderDetail(message, { draft: draftText });
      setStatus('Draft generated. Review before sending.', 'success');
    }catch(err){
      console.error('Email draft failed', err);
      setStatus(err && err.message ? err.message : 'Failed to generate draft.', 'error');
    }
  }

  async function classify(id){
    if(!id) id = state.selectedId;
    if(!id) return;
    setStatus('Classifying...', '');
    try{
      const result = await api('/api/email/classify?id=' + encodeURIComponent(id), { timeoutMs: 60000, retryTimeouts: false, retries: 0 });
      const cls = result.classification || 'keep';
      const method = result.method || 'unknown';
      // Update the message in our local state
      const idx = state.messages.findIndex(m => msgId(m) === id);
      if(idx >= 0){
        state.messages[idx]._classification = cls;
        state.messages[idx]._classificationMethod = method;
      }
      // Re-render detail if this is the selected message
      const message = state.messages.find(m => msgId(m) === id) || { id };
      message._classification = cls;
      message._classificationMethod = method;
      if(id === state.selectedId) renderDetail(message);
      renderList();
      setStatus(`Classified as ${cls} (${method}).`, 'success');
    }catch(err){
      console.error('Email classify failed', err);
      setStatus(err && err.message ? err.message : 'Failed to classify.', 'error');
    }
  }

  async function move(id, action){
    if(!id) return;
    const label = action === 'junk' ? 'Junk' : 'Archive';
    setStatus(`Moving to ${label}...`, '');
    try{
      const message = state.messages.find(m => msgId(m) === id);
      const result = await api('/api/email/move', {
        method: 'POST',
        body: JSON.stringify({
          id,
          action,
          sender: message ? message.sender : '',
          subject: message ? message.subject : '',
        }),
        timeoutMs: 30000,
        retryTimeouts: false,
        retries: 0,
      });
      if(result.moved_to === 'failed'){
        setStatus(`Failed to move to ${label}.`, 'error');
        return;
      }
      setStatus(`Moved to ${label}.`, 'success');
      // Remove from local list and reload
      state.messages = state.messages.filter(m => msgId(m) !== id);
      if(state.selectedId === id) state.selectedId = null;
      renderList();
      if(state.selectedId){
        const msg = state.messages.find(m => msgId(m) === state.selectedId);
        renderDetail(msg || null);
      } else {
        renderDetail(null);
      }
    }catch(err){
      console.error('Email move failed', err);
      setStatus(err && err.message ? err.message : `Failed to move to ${label}.`, 'error');
    }
  }

  async function cleanInbox(dryRun){
    if(state.cleanRunning) return;
    state.cleanRunning = true;
    const label = dryRun ? 'Previewing' : 'Cleaning';
    setStatus(`${label} inbox...`, 'warn');
    const resultEl = $('emailCleanResult');
    if(resultEl) resultEl.innerHTML = '';
    try{
      const result = await api('/api/email/clean', {
        method: 'POST',
        body: JSON.stringify({ dry_run: dryRun, limit: 200 }),
        timeoutMs: 300000, // 5 min — LLM can be slow
        retryTimeouts: false,
        retries: 0,
      });
      state.cleanResult = result.result || result;
      const r = state.cleanResult;
      const lines = [
        `<strong>Scanned:</strong> ${r.total_scanned} messages`,
        `<span style="color:#ef4444"><strong>Junk:</strong> ${r.junk}</span>`,
        `<span style="color:#f59e0b"><strong>Promo:</strong> ${r.newsletter}</span>`,
        `<span style="color:#3b82f6"><strong>Archive:</strong> ${r.archive}</span>`,
        `<span style="color:#22c55e"><strong>Keep:</strong> ${r.keep}</span>`,
        `<em>(heuristic: ${r.heuristic_hits}, LLM: ${r.llm_calls})</em>`,
      ];
      if(!dryRun){
        lines.push(`<br><strong>Moved to Junk:</strong> ${r.moved_junk}`);
        lines.push(`<strong>Archived:</strong> ${r.moved_archive}`);
        lines.push(`<strong>NAS saved:</strong> ${r.nas_saved}`);
      }
      if(resultEl){
        resultEl.innerHTML = lines.join('<br>');
        resultEl.style.display = '';
      }
      setStatus(dryRun ? 'Preview complete. Review above.' : 'Clean complete.', dryRun ? 'warn' : 'success');
      // Refresh the message list after a real clean
      if(!dryRun){
        state.loaded = false;
        await load(true);
      }
    }catch(err){
      console.error('Email clean failed', err);
      setStatus(err && err.message ? err.message : 'Failed to clean inbox.', 'error');
    }finally{
      state.cleanRunning = false;
    }
  }

  function setMode(mode){
    state.mode = mode;
    state.loaded = false;
    state.messages = [];
    state.selectedId = null;
    const btnUnread = $('emailModeUnread');
    const btnAll = $('emailModeAll');
    if(btnUnread) btnUnread.classList.toggle('active', mode === 'unread');
    if(btnAll) btnAll.classList.toggle('active', mode === 'all');
    load(true);
  }

  function setQuery(value){
    state.query = (value || '').trim();
    renderList();
  }

  async function markRead(id){
    if(!id) id = state.selectedId;
    if(!id) return;
    setStatus('Marking as read...', '');
    try{
      await api('/api/email/mark_read', {
        method: 'POST',
        body: JSON.stringify({ id }),
        timeoutMs: 15000,
        retryTimeouts: false,
        retries: 0,
      });
      setStatus('Marked as read.', 'success');
      // Update local state
      const idx = state.messages.findIndex(m => msgId(m) === id);
      if(idx >= 0) state.messages[idx].is_read = true;
      renderList();
      if(id === state.selectedId){
        const message = state.messages.find(m => msgId(m) === id);
        if(message) renderDetail(message);
      }
    }catch(err){
      console.error('Email mark_read failed', err);
      setStatus(err && err.message ? err.message : 'Failed to mark as read.', 'error');
    }
  }

  async function showThread(id){
    if(!id) id = state.selectedId;
    if(!id) return;
    setStatus('Loading thread...', '');
    try{
      const result = await api('/api/email/thread?id=' + encodeURIComponent(id), { timeoutMs: 30000, retryTimeouts: false, retries: 0 });
      const nodes = result.thread || [];
      const detail = $('emailDetail');
      if(!detail) return;
      const message = state.messages.find(m => msgId(m) === id) || { id };
      const subject = message.subject || '(No subject)';
      const sender = message.sender || '';
      const date = message.date_received || message.date || '';
      let threadHtml = nodes.map(n => {
        const level = n.level || 0;
        const indent = level * 24;
        const meta = n.meta ? `<div class="email-thread-meta">${esc(n.meta)}</div>` : '';
        const body = n.body ? esc(n.body.slice(0, 2000)) : '(empty)';
        return `<div class="email-thread-node" style="margin-left:${indent}px">${meta}<div class="email-thread-body">${body}</div></div>`;
      }).join('');
      if(!threadHtml) threadHtml = '<div class="email-empty">No thread structure found.</div>';
      detail.innerHTML = `
        <div class="email-detail-card">
          <div class="email-detail-meta">
            <div class="email-detail-subject">Thread: ${esc(subject)}</div>
            ${sender ? `<div class="email-detail-sender">${esc(sender)}</div>` : ''}
            ${date ? `<div class="email-detail-date">${esc(date)}</div>` : ''}
          </div>
          <div class="email-thread-view">${threadHtml}</div>
          <button class="btn secondary" type="button" onclick="AresEmail.select('${jsArg(id)}')" style="margin-top:8px">← Back to message</button>
        </div>`;
      detail.hidden = false;
      setStatus(nodes.length ? `Thread: ${nodes.length} message(s)` : 'No thread data.', nodes.length ? 'success' : 'warn');
    }catch(err){
      console.error('Email thread failed', err);
      setStatus(err && err.message ? err.message : 'Failed to load thread.', 'error');
    }
  }

  async function saveNas(id){
    if(!id) id = state.selectedId;
    if(!id) return;
    const message = state.messages.find(m => msgId(m) === id);
    setStatus('Saving to NAS...', 'warn');
    try{
      const result = await api('/api/email/save_nas', {
        method: 'POST',
        body: JSON.stringify({
          id,
          sender: message ? message.sender : '',
          subject: message ? message.subject : '',
        }),
        timeoutMs: 30000,
        retryTimeouts: false,
        retries: 0,
      });
      if(result.saved){
        setStatus(`Saved to NAS (${result.subfolder || 'archive'}).`, 'success');
      } else {
        setStatus('NAS archive not available (drive not mounted?).', 'error');
      }
    }catch(err){
      console.error('Email save_nas failed', err);
      setStatus(err && err.message ? err.message : 'Failed to save to NAS.', 'error');
    }
  }

  function copyDraft(){
    const textarea = $('emailDraftText');
    if(!textarea) return;
    const text = textarea.value || textarea.textContent || '';
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(text).then(() => {
        setStatus('Draft copied to clipboard.', 'success');
      }).catch(() => {
        textarea.select();
        document.execCommand('copy');
        setStatus('Draft copied to clipboard.', 'success');
      });
    } else {
      textarea.select();
      document.execCommand('copy');
      setStatus('Draft copied to clipboard.', 'success');
    }
  }

  window.AresEmail = { load, select, draft, classify, move, cleanInbox, setMode, setQuery, markRead, showThread, saveNas, copyDraft };
})();