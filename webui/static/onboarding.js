const ONBOARDING={status:null,step:0,steps:['system','agentPrompt','iphone','connect','mcp','setup','workspace','password','finish'],form:{provider:'openrouter',workspace:'',model:'',password:'',apiKey:'',baseUrl:''},active:false,probe:{status:'idle',error:null,detail:'',models:null,probedKey:''}};

// ── Onboarding base-URL probe (#1499) ───────────────────────────────────────
// Probes <base_url>/models so the wizard can validate the configured endpoint
// before persisting AND populate the model dropdown from the live catalog.
// Probe state lives on ONBOARDING.probe; the dropdown render and the
// nextOnboardingStep gate both consult it.

let _onboardingProbeTimer=null;

function _onboardingProbeKey(provider,baseUrl,apiKey){
  return `${provider||''}|${(baseUrl||'').trim().replace(/\/+$/,'')}|${apiKey||''}`;
}

function _setOnboardingProbeState(patch){
  ONBOARDING.probe={...ONBOARDING.probe,...patch};
  // Re-render body so probe status / model dropdown reflect new state.
  _renderOnboardingBody();
}

async function _runOnboardingProbe({force=false}={}){
  const provider=ONBOARDING.form.provider;
  const cat=_getOnboardingSetupProvider(provider);
  if(!cat||!cat.requires_base_url){
    _setOnboardingProbeState({status:'idle',error:null,detail:'',models:null,probedKey:''});
    return ONBOARDING.probe;
  }
  const baseUrl=(ONBOARDING.form.baseUrl||'').trim();
  if(!baseUrl){
    _setOnboardingProbeState({status:'idle',error:null,detail:'',models:null,probedKey:''});
    return ONBOARDING.probe;
  }
  const apiKey=(ONBOARDING.form.apiKey||'').trim();
  const key=_onboardingProbeKey(provider,baseUrl,apiKey);
  if(!force&&ONBOARDING.probe.probedKey===key&&ONBOARDING.probe.status!=='probing'){
    return ONBOARDING.probe;
  }
  _setOnboardingProbeState({status:'probing',error:null,detail:'',probedKey:key});
  try{
    const res=await api('/api/onboarding/probe',{method:'POST',body:JSON.stringify({provider,base_url:baseUrl,api_key:apiKey||undefined})});
    if(res&&res.ok){
      _setOnboardingProbeState({status:'ok',error:null,detail:'',models:Array.isArray(res.models)?res.models:[],probedKey:key});
      // If the user hasn't picked a model yet (or their pick is no longer in
      // the list), default to the first probed model so Continue isn't blocked
      // on an empty selection.
      const stillPresent=ONBOARDING.form.model&&(res.models||[]).some(m=>m.id===ONBOARDING.form.model);
      if(!stillPresent&&(res.models||[]).length>0){
        ONBOARDING.form.model=res.models[0].id;
        _renderOnboardingBody();
      }
    }else{
      const err=(res&&res.error)||'unreachable';
      const detail=(res&&res.detail)||'';
      _setOnboardingProbeState({status:'error',error:err,detail,models:null,probedKey:key});
    }
  }catch(e){
    _setOnboardingProbeState({status:'error',error:'unreachable',detail:(e&&e.message)||String(e),models:null,probedKey:key});
  }
  return ONBOARDING.probe;
}

function _scheduleOnboardingProbe(){
  if(_onboardingProbeTimer)clearTimeout(_onboardingProbeTimer);
  _onboardingProbeTimer=setTimeout(()=>{_runOnboardingProbe();},400);
}

function _onboardingProbeMessage(probe){
  if(!probe||probe.status==='idle')return '';
  if(probe.status==='probing')return t('onboarding_probe_probing')||'Testing connection…';
  if(probe.status==='ok'){
    const n=(probe.models||[]).length;
    const tmpl=t('onboarding_probe_ok')||'Connected. {n} model(s) available.';
    return tmpl.replace('{n}',String(n));
  }
  // status === 'error'
  const errKey='onboarding_probe_error_'+probe.error;
  const localized=t(errKey);
  // i18n.js's `t()` returns the key itself when missing — fall back to a generic message.
  const heading=(localized&&localized!==errKey)?localized:(t('onboarding_probe_error_generic')||'Could not reach the configured base URL.');
  const detail=probe.detail?` (${probe.detail})`:'';
  return heading+detail;
}

function _getOnboardingSetupProviders(){
  return (((ONBOARDING.status||{}).setup||{}).providers)||[];
}

function _getOnboardingSetupProvider(id){
  return _getOnboardingSetupProviders().find(p=>p.id===id)||null;
}

function _getOnboardingSetupCategories(){
  return (((ONBOARDING.status||{}).setup||{}).categories)||[];
}

/** Render the provider <select> with <optgroup> per category. */
function _renderProviderSelectOptions(selectedId){
  const providers=_getOnboardingSetupProviders();
  const categories=_getOnboardingSetupCategories();
  const provMap={};
  providers.forEach(p=>{provMap[p.id]=p;});
  if(!categories.length){
    // Fallback: flat list when no categories are available.
    return providers.map(p=>`<option value="${esc(p.id)}">${esc(p.label)}${p.quick?' — '+esc(t('onboarding_quick_setup_badge')):''}</option>`).join('');
  }
  return categories.map(cat=>{
    const opts=cat.providers.map(pid=>{
      const p=provMap[pid];
      if(!p)return '';
      return `<option value="${esc(p.id)}"${p.id===selectedId?' selected':''}>${esc(p.label)}${p.quick?' — '+esc(t('onboarding_quick_setup_badge')):''}</option>`;
    }).join('');
    return `<optgroup label="${esc(t('provider_category_'+cat.id)||cat.label)}">${opts}</optgroup>`;
  }).join('');
}

function _getOnboardingCurrentSetup(){
  return (((ONBOARDING.status||{}).setup||{}).current)||{};
}

const ARES_PROVIDER_SYNC_IDS={
  gemini:'gemini',
  openai:'openai',
  anthropic:'anthropic',
  ollama:'ollama',
  lmstudio:'lmstudio',
};

function _onboardingStepMeta(key){
  return ({
    system:{title:t('onboarding_step_system_title')||'System check',desc:t('onboarding_step_system_desc')||'Verify the ARES agent backend and config visibility.'},
    agentPrompt:{title:t('onboarding_step_agent_prompt_title')||'Agent prompt',desc:t('onboarding_step_agent_prompt_desc')||'Copy the setup request for a local or remote agent.'},
    iphone:{title:t('onboarding_step_iphone_title')||'iPhone access',desc:t('onboarding_step_iphone_desc')||'Install Tailscale and join the same private network.'},
    connect:{title:t('onboarding_step_connect_title')||'Connect',desc:t('onboarding_step_connect_desc')||'Test the URL and password you will use from mobile.'},
    mcp:{title:t('onboarding_step_mcp_title')||'MCP servers',desc:t('onboarding_step_mcp_desc')||'Choose local-only vs remote/server automation.'},
    setup:{title:t('onboarding_step_setup_title')||'Provider setup',desc:t('onboarding_step_setup_desc')||'Save the minimum ARES provider config.'},
    workspace:{title:t('onboarding_step_workspace_title')||'Workspace + model',desc:t('onboarding_step_workspace_desc')||'Pick defaults for new sessions and chat.'},
    password:{title:t('onboarding_step_password_title')||'Optional password',desc:t('onboarding_step_password_desc')||'Protect the Web UI before sharing it.'},
    finish:{title:t('onboarding_step_finish_title')||'Finish',desc:t('onboarding_step_finish_desc')||'Review and enter the app.'}
  })[key];
}

function _renderOnboardingSteps(){
  const wrap=$('onboardingSteps');
  if(!wrap)return;
  wrap.innerHTML='';
  ONBOARDING.steps.forEach((key,idx)=>{
    const meta=_onboardingStepMeta(key);
    const item=document.createElement('div');
    item.className='onboarding-step'+(idx===ONBOARDING.step?' active':idx<ONBOARDING.step?' done':'');
    item.innerHTML=`<div class="onboarding-step-index">${idx+1}</div><div><div class="onboarding-step-title">${meta.title}</div><div class="onboarding-step-desc">${meta.desc}</div></div>`;
    wrap.appendChild(item);
  });
}

function _setOnboardingNotice(msg,kind='info'){
  const el=$('onboardingNotice');
  if(!el)return;
  if(!msg){el.style.display='none';el.textContent='';el.className='onboarding-status';return;}
  el.style.display='block';
  el.className='onboarding-status '+kind;
  el.textContent=msg;
}

function _getOnboardingWorkspaceChoices(){
  const items=((ONBOARDING.status||{}).workspaces||{}).items||[];
  return items.length?items:[{name:'Home',path:ONBOARDING.form.workspace||''}];
}

function _getOnboardingProviderModelChoices(){
  const provider=_getOnboardingSetupProvider(ONBOARDING.form.provider);
  // Probe-discovered models (#1499) take precedence over the static catalog
  // for providers with requires_base_url=True.  The catalog ships an empty
  // list for self-hosted providers (lmstudio, ollama, custom) — without the
  // probe the user had nothing to pick from.
  if(provider&&provider.requires_base_url&&ONBOARDING.probe&&ONBOARDING.probe.status==='ok'&&Array.isArray(ONBOARDING.probe.models)&&ONBOARDING.probe.models.length){
    return ONBOARDING.probe.models;
  }
  return provider?(provider.models||[]):[];
}

function _renderOnboardingBaseUrlField(showBaseUrl){
  // Renders the base_url input PLUS the probe status banner / Test button
  // when the active provider has requires_base_url=True (#1499).  Returns
  // the empty string when the active provider does not require a base URL,
  // so the existing call sites can continue to template-interpolate this in
  // place of the previous inline `<label …>` snippet.
  if(!showBaseUrl)return '';
  const probe=ONBOARDING.probe||{status:'idle'};
  const msg=_onboardingProbeMessage(probe);
  let banner='';
  if(msg){
    const cls={ok:'onboarding-probe-ok',probing:'onboarding-probe-probing',error:'onboarding-probe-error'}[probe.status]||'';
    banner=`<p class="onboarding-copy onboarding-probe-banner ${cls}">${esc(msg)}</p>`;
  }
  const testBtnLabel=t('onboarding_probe_test_button')||'Test connection';
  const testBtnDisabled=(probe.status==='probing')?'disabled':'';
  return `<label class="onboarding-field"><span>${t('onboarding_base_url_label')}</span><input id="onboardingBaseUrlInput" value="${esc(ONBOARDING.form.baseUrl||'')}" placeholder="${t('onboarding_base_url_placeholder')}" oninput="ONBOARDING.form.baseUrl=this.value;_scheduleOnboardingProbe()" onblur="_runOnboardingProbe()"></label><div class="onboarding-probe-row"><button type="button" class="onboarding-probe-btn" ${testBtnDisabled} onclick="_runOnboardingProbe({force:true})">${esc(testBtnLabel)}</button></div>${banner}`;
}

function _renderOnboardingApiKeyField(){
  // Renders the API-key input.  For providers flagged `key_optional` in the
  // setup catalog (lmstudio, ollama, custom — typically self-hosted servers
  // that run keyless by default), the field shows an "(optional)" hint and
  // empty input is accepted on Continue.  Pre-#1499-third-sub-bug-fix the
  // wizard required a non-empty string here even for keyless installs, which
  // forced users to type random gibberish to clear onboarding.
  const provider=_getOnboardingSetupProvider(ONBOARDING.form.provider);
  const keyOptional=!!(provider&&provider.key_optional);
  const labelKey=keyOptional?'onboarding_api_key_label_optional':'onboarding_api_key_label';
  const placeholderKey=keyOptional?'onboarding_api_key_placeholder_optional':'onboarding_api_key_placeholder';
  const helpHtml=keyOptional?`<p class="onboarding-copy onboarding-api-key-help">${esc(t('onboarding_api_key_help_keyless')||'')}</p>`:'';
  return `<label class="onboarding-field" id="onboardingApiKeyField"><span>${t(labelKey)}</span><input id="onboardingApiKeyInput" type="password" value="${esc(ONBOARDING.form.apiKey||'')}" placeholder="${t(placeholderKey)}" oninput="ONBOARDING.form.apiKey=this.value" onblur="_runOnboardingProbe()"></label>${helpHtml}`;
}

function _getOnboardingSelectedModel(){
  return ONBOARDING.form.model||'';
}

function _renderOnboardingModelField(){
  const choices=_getOnboardingProviderModelChoices();
  if(ONBOARDING.form.provider==='custom'){
    return `<label class="onboarding-field"><span>${t('onboarding_model_label')}</span><input id="onboardingModelInput" value="${esc(_getOnboardingSelectedModel())}" placeholder="${t('onboarding_custom_model_placeholder')}" oninput="ONBOARDING.form.model=this.value"></label><p class="onboarding-copy">${t('onboarding_custom_model_help')}</p>`;
  }
  if(typeof _mountSearchableModelSelect==='function'){
    return `<div class="onboarding-field onboarding-model-field"><span>${t('onboarding_model_label')}</span><div id="onboardingModelPickerRoot"></div></div><p class="onboarding-copy">${t('onboarding_workspace_help')}</p>`;
  }
  const options=choices.map(m=>`<option value="${esc(m.id)}">${esc(m.label)}</option>`).join('');
  return `<label class="onboarding-field"><span>${t('onboarding_model_label')}</span><select id="onboardingModelSelect" onchange="ONBOARDING.form.model=this.value">${options}</select></label><p class="onboarding-copy">${t('onboarding_workspace_help')}</p>`;
}

function _renderOnboardingProviderOAuthField(provider){
  if(!provider||provider.oauth_provider!=='anthropic')return '';
  return `<div class="onboarding-oauth-card onboarding-oauth-pending" style="margin-top:12px">
    <div class="onboarding-oauth-icon">🔑</div>
    <div style="flex:1">
      <strong>Use Claude Code OAuth instead</strong>
      <p style="margin-top:6px;color:var(--muted);font-size:13px"><strong>Claude Code subscription credentials are not the same as an Anthropic API key.</strong> Use this path only when you want Hermes to use Claude Code credentials already available on the server, or start a short polling flow while you complete <code>claude setup-token</code> on the host.</p>
      <div style="margin-top:10px;display:flex;gap:8px;align-items:center;flex-wrap:wrap"><button class="sm-btn" id="anthropicOAuthBtn" onclick="startAnthropicOAuth()" type="button">Login with Claude Code</button></div>
      <div id="anthropicOAuthFlow" style="display:none;margin-top:12px"></div>
    </div>
  </div>`;
}

function _providerStatusLabel(system){
  if(system.chat_ready) return t('onboarding_check_provider_ready');
  if(system.provider_configured) return t('onboarding_check_provider_partial');
  return t('onboarding_check_provider_pending');
}

function _localizedOnboardingProviderNote(system){
  const key=system&&system.provider_note_key;
  if(key){
    const args=Array.isArray(system&&system.provider_note_args)?system.provider_note_args:[];
    const localized=t(key,...args);
    if(localized&&localized!==key&&!/\{\d+\}/.test(localized))return localized;
  }
  return (system&&system.provider_note)||'';
}

function _aresOnboardingServerUrl(){
  try{return window.location.origin||'';}catch{return '';}
}

function _aresOnboardingPrompt(){
  const serverUrl=_aresOnboardingServerUrl()||'http://<tailscale-ip>:8787';
  return `Set up ARES Web UI on this machine for mobile access over a private network such as Tailscale.

Use the ARES repo as the app source. Install dependencies, enable password auth, and run the WebUI on port 8787. Prefer Tailscale/private-network access over public exposure.

If Tailscale is not installed, install it using the correct method for this OS and sign into the user's tailnet/private network. If Tailscale Serve is available, try to expose the WebUI cleanly; otherwise bind the server to 0.0.0.0 only after confirming password auth is active.

Set up auto-start appropriate for this OS so ARES survives reboots.

Configure MCP servers using this rule:
- local-only app/device MCPs run on the owning machine (example: Safari MCP on macOS)
- stateless/API/database/file MCPs can run on a server, homelab, VPS, NAS, or other machine reachable over the user's private network with auth

Run these ARES bootstrap checks if present:
python3 tools/mcp-bootstrap/mcp_bootstrap.py --catalog --plan
# macOS Safari automation only, from the ARES repo root:
python3 tools/safari-mcp-bootstrap/safari_mcp_bootstrap.py --configure-hermes

Verify it works: curl ${serverUrl}/api/onboarding/status should return JSON.

Reply with:
- the exact server URL the user should enter on mobile or another client
- the password or auth status
- which MCP servers are local vs remote
- any one-time setup steps I still need to do on my phone or Mac.`;
}

async function copyAresOnboardingPrompt(){
  const text=_aresOnboardingPrompt();
  try{await navigator.clipboard.writeText(text);showToast('ARES setup prompt copied');}
  catch(e){showToast(text);}
}

async function copyAresConnectUrl(){
  const text=_aresOnboardingServerUrl()||'http://<tailscale-ip>:8787';
  try{await navigator.clipboard.writeText(text);showToast('Server URL copied');}
  catch(e){showToast(text);}
}

async function testAresOnboardingConnection(){
  try{
    const res=await api('/api/onboarding/status');
    if(res&&typeof res==='object'){
      const ready=res.system&&res.system.chat_ready;
      _setOnboardingNotice(ready?'Connection test passed. ARES is reachable and chat-ready.':'Connection test passed. ARES is reachable; provider setup may still need completion.', ready?'success':'info');
    }else{
      _setOnboardingNotice('Connection test returned an unexpected response.', 'warn');
    }
  }catch(e){
    _setOnboardingNotice(`Connection test failed: ${(e&&e.message)||String(e)}`, 'warn');
  }
}

function _renderOnboardingBody(){
  const body=$('onboardingBody');
  if(!body||!ONBOARDING.status)return;
  const key=ONBOARDING.steps[ONBOARDING.step];
  const system=ONBOARDING.status.system||{};
  const settings=ONBOARDING.status.settings||{};
  const setup=ONBOARDING.status.setup||{};
  const nextBtn=$('onboardingNextBtn');
  const backBtn=$('onboardingBackBtn');
  if(backBtn) backBtn.style.display=ONBOARDING.step>0?'':'none';
  if(nextBtn) nextBtn.textContent=key==='finish'?t('onboarding_open'):t('onboarding_continue');

  if(key==='system'){
    const hermesOk=system.hermes_found&&system.imports_ok;
    const setupOk=!!system.chat_ready;
    const providerNote=_localizedOnboardingProviderNote(system);
    _setOnboardingNotice(providerNote|| (setupOk?t('onboarding_notice_system_ready'):t('onboarding_notice_system_unavailable')),setupOk?'success':(hermesOk?'info':'warn'));
    body.innerHTML=`
      <div class="onboarding-panel-grid">
        <div class="onboarding-check ${hermesOk?'ok':'warn'}"><strong>${t('onboarding_check_agent')}</strong><span>${hermesOk?t('onboarding_check_agent_ready'):t('onboarding_check_agent_missing')}</span></div>
        <div class="onboarding-check ${(setupOk?'ok':system.provider_configured?'warn':'muted')}"><strong>${t('onboarding_check_provider')}</strong><span>${_providerStatusLabel(system)}</span></div>
        <div class="onboarding-check ${(settings.password_enabled?'ok':'muted')}"><strong>${t('onboarding_check_password')}</strong><span>${settings.password_enabled?t('onboarding_check_password_enabled'):t('onboarding_check_password_disabled')}</span></div>
      </div>
      <div class="onboarding-copy">
        <p><strong>${t('onboarding_config_file')}</strong> ${esc(system.config_path||t('onboarding_unknown'))}</p>
        <p><strong>${t('onboarding_env_file')}</strong> ${esc(system.env_path||t('onboarding_unknown'))}</p>
        ${providerNote?`<p>${esc(providerNote)}</p>`:''}
        ${system.current_provider?`<p><strong>${t('onboarding_current_provider')}</strong> ${esc(system.current_provider)}${system.current_model?` — ${esc(system.current_model)}`:''}</p>`:''}
        ${system.current_base_url?`<p><strong>${t('onboarding_base_url_label')}</strong> ${esc(system.current_base_url)}</p>`:''}
        ${system.missing_modules&&system.missing_modules.length?`<p><strong>${t('onboarding_missing_imports')}</strong> ${esc(system.missing_modules.join(', '))}</p>`:''}
      </div>`;
    return;
  }

  if(key==='agentPrompt'){
    _setOnboardingNotice(t('onboarding_notice_agent_prompt')||'Copy this prompt into the agent running on the machine that will host ARES. It installs WebUI, password auth, private-network access, auto-start, and MCP bootstrap checks. If no backend exists yet, install ARES Web UI or connect to an existing agent backend.','info');
    body.innerHTML=`
      <div class="onboarding-hero-icon">›_</div>
      <div class="onboarding-centered-copy">
        <div class="onboarding-kicker">${t('onboarding_kicker_step_1')||'STEP 1'}</div>
        <h3>${t('onboarding_agent_prompt_heading')||'Set up ARES Web UI'}</h3>
        <p>${t('onboarding_agent_prompt_body')||'Send this prompt to the agent backend on the target machine. If no backend exists yet, install ARES Web UI or connect to an existing agent backend.'}</p><div class="onboarding-command-card"><code>curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash</code><a class="onboarding-secondary-wide" href="https://hermes-agent.nousresearch.com/docs" target="_blank" rel="noopener">${t('onboarding_hermes_docs_link')||'Open ARES Web UI docs'}</a></div>
      </div>
      <div class="onboarding-prompt-card">
        <pre>${esc(_aresOnboardingPrompt())}</pre>
        <button class="onboarding-primary-wide" type="button" onclick="copyAresOnboardingPrompt()">✓ ${t('onboarding_copy_setup_prompt')||'Copy setup prompt'}</button>
      </div>`;
    return;
  }

  if(key==='iphone'){
    _setOnboardingNotice(t('onboarding_notice_iphone')||'ARES mobile access is designed around Tailscale/private networking, not public Cloudflare exposure.','info');
    body.innerHTML=`
      <div class="onboarding-hero-icon">⇥</div>
      <div class="onboarding-centered-copy">
        <div class="onboarding-kicker">${t('onboarding_kicker_step_2')||'STEP 2'}</div>
        <h3>${t('onboarding_iphone_heading')||'Install Tailscale on iPhone'}</h3>
        <p>${t('onboarding_iphone_body')||'Install Tailscale on your iPhone and sign into the same tailnet/private network as the computer or server running ARES.'}</p>
      </div>
      <div class="onboarding-number-list">
        <div><span>1</span><p>${t('onboarding_iphone_step_1')||'Install Tailscale from the App Store.'}</p></div>
        <div><span>2</span><p>${t('onboarding_iphone_step_2')||'Sign in with the same account/tailnet used by the ARES host.'}</p></div>
        <div><span>3</span><p>${t('onboarding_iphone_step_3')||'Keep Tailscale connected while using ARES from Safari, the WebClip, or the native shell.'}</p></div>
      </div>
      <a class="onboarding-secondary-wide" href="https://apps.apple.com/app/tailscale/id1470499037" target="_blank" rel="noopener">↗ ${t('onboarding_tailscale_app_store')||'Get Tailscale on the App Store'}</a>`;
    return;
  }

  if(key==='connect'){
    const url=_aresOnboardingServerUrl()||'http://<tailscale-ip>:8787';
    _setOnboardingNotice(t('onboarding_notice_connect')||'Use the private-network IP/hostname URL from the host machine. If this page is already loaded over Tailscale, the URL below is ready to copy.','info');
    body.innerHTML=`
      <div class="onboarding-centered-copy onboarding-connect-head">
        <h3>${t('onboarding_connect_heading')||'Connect'}</h3>
        <p>${t('onboarding_connect_body')||'Enter this server URL in the mobile app or open it directly from another device after the private network is connected.'}</p>
      </div>
      <div class="onboarding-connect-fields">
        <div class="onboarding-connect-field"><div class="onboarding-connect-icon">🔗</div><div><strong>${t('onboarding_connect_server_url')||'Server URL'}</strong><span>${esc(url)}</span></div><button type="button" onclick="copyAresConnectUrl()">${t('onboarding_copy')||'Copy'}</button></div>
        <div class="onboarding-connect-field"><div class="onboarding-connect-icon">🔑</div><div><strong>${t('onboarding_connect_password')||'Password'}</strong><span>${settings.password_enabled?(t('onboarding_connect_password_enabled')||'Password auth is enabled'):(t('onboarding_connect_password_pending')||'Set one on the password step before sharing this URL')}</span></div></div>
      </div>
      <div class="onboarding-dual-actions"><button class="onboarding-secondary-wide" type="button" onclick="testAresOnboardingConnection()">🌐 ${t('onboarding_test_connection')||'Test connection'}</button></div>`;
    return;
  }

  if(key==='mcp'){
    _setOnboardingNotice(t('onboarding_notice_mcp')||'MCP setup is part of ARES onboarding: app-bound servers stay local; stateless services can live on a server, homelab, VPS, NAS, or another trusted machine.','info');
    body.innerHTML=`
      <div class="onboarding-centered-copy">
        <div class="onboarding-kicker">${t('onboarding_kicker_step_3')||'STEP 3'}</div>
        <h3>${t('onboarding_mcp_heading')||'Place MCP servers correctly'}</h3>
        <p>${t('onboarding_mcp_body')||'ARES should guide users to install each MCP where it actually belongs instead of dumping everything on one machine.'}</p>
      </div>
      <div class="onboarding-mcp-grid">
        <div class="onboarding-mcp-card"><strong>${t('onboarding_mcp_local_title')||'Local-only MCP'}</strong><p>${t('onboarding_mcp_local_desc')||'Runs on the machine that owns the app/device permission.'}</p><ul><li>Safari / Apple Events</li><li>Find My / Mail / Messages</li><li>USB hardware or cameras</li></ul></div>
        <div class="onboarding-mcp-card"><strong>${t('onboarding_mcp_remote_title')||'Remote/server MCP'}</strong><p>${t('onboarding_mcp_remote_desc')||'Runs remotely when it is stateless, API-based, or near shared storage.'}</p><ul><li>GitHub / Linear / Notion</li><li>Databases and file stores</li><li>Long-running workers</li></ul></div>
        <div class="onboarding-mcp-card"><strong>${t('onboarding_mcp_filesystem_title')||'Filesystem MCP'}</strong><p>${t('onboarding_mcp_filesystem_desc')||'Runs where the target files live. Start with this ARES repo or a user-selected workspace, then add shared drives only after verification.'}</p><ul><li>ARES repo</li><li>User-selected workspace</li><li>Verified shared storage</li></ul></div>
      </div>
      <div class="onboarding-command-card"><code>python3 tools/mcp-bootstrap/mcp_bootstrap.py --catalog --plan</code><code># macOS Safari automation only:<br>python3 tools/safari-mcp-bootstrap/safari_mcp_bootstrap.py --configure-hermes</code></div>`;
    return;
  }

  if(key==='setup'){
    const selectedId=ONBOARDING.form.provider;
    const groupedOptions=_renderProviderSelectOptions(selectedId);
    const provider=_getOnboardingSetupProvider(selectedId)||_getOnboardingSetupProviders()[0]||null;
    const showBaseUrl=provider&&provider.requires_base_url;
    const keyHelp=provider
      ? (provider.id==='anthropic'
        ? 'Anthropic API key path: paste an Anthropic Console API key here. This is separate from a Claude Code subscription; use the Claude Code OAuth card if you want subscription credentials instead.'
        : `${t('onboarding_api_key_help_prefix')} ${esc(provider.env_var)}.`)
      : '';

    // OAuth provider path: configured via CLI, no API key input needed.
    const currentIsOauth=!!(ONBOARDING.status.setup||{}).current_is_oauth;
    const currentProviderName=((ONBOARDING.status.setup||{}).current||{}).provider||'';
    if(currentIsOauth){
      const isReady=!!(ONBOARDING.status.system||{}).chat_ready;
      const providerLabel=esc(currentProviderName);
      const codexOauthPendingBody=currentProviderName==='openai-codex'
        ? 'This instance is configured to use <strong>openai-codex</strong>, which uses OAuth rather than an API key. Use the button below to authenticate with ChatGPT, then continue once provider status refreshes.'
        : t('onboarding_oauth_provider_not_ready_body').replace('{provider}',providerLabel);
      if(isReady){
        _setOnboardingNotice(t('onboarding_notice_setup_already_ready'),'success');
        body.innerHTML=`
          <div class="onboarding-oauth-card onboarding-oauth-ready">
            <div class="onboarding-oauth-icon">✓</div>
            <div>
              <strong>${t('onboarding_oauth_provider_ready_title')}</strong>
              <p>${t('onboarding_oauth_provider_ready_body').replace('{provider}',providerLabel)}</p>
            </div>
          </div>
          <p class="onboarding-copy" style="margin-top:20px">${t('onboarding_oauth_switch_hint')}</p>
          <label class="onboarding-field">
            <span>${t('onboarding_provider_label')}</span>
            <select id="onboardingProviderSelect" onchange="syncOnboardingProvider(this.value)">${groupedOptions}</select>
          </label>
          ${_renderOnboardingApiKeyField()}
          ${_renderOnboardingBaseUrlField(showBaseUrl)}
          <p class="onboarding-copy">${keyHelp}</p>`;
      } else {
        _setOnboardingNotice(t('onboarding_notice_setup_required'),'warn');
        body.innerHTML=`
          <div class="onboarding-oauth-card onboarding-oauth-pending">
            <div class="onboarding-oauth-icon">⚠</div>
            <div style="flex:1">
              <strong>${t('onboarding_oauth_provider_not_ready_title')}</strong>
              <p>${codexOauthPendingBody}</p>
              ${currentProviderName==='openai-codex'?`<div style="margin-top:12px;display:flex;gap:8px;align-items:center;flex-wrap:wrap"><button class="sm-btn" id="codexOAuthBtn" onclick="startCodexOAuth()" type="button">${t('oauth_login_codex')}</button></div><div id="codexOAuthFlow" style="display:none;margin-top:12px"></div>`:''}
            </div>
          </div>
          <p class="onboarding-copy" style="margin-top:20px">${t('onboarding_oauth_switch_hint')}</p>
          <label class="onboarding-field">
            <span>${t('onboarding_provider_label')}</span>
            <select id="onboardingProviderSelect" onchange="syncOnboardingProvider(this.value)">${groupedOptions}</select>
          </label>
          ${_renderOnboardingApiKeyField()}
          ${_renderOnboardingBaseUrlField(showBaseUrl)}
          <p class="onboarding-copy">${keyHelp}</p>`;
      }
      return;
    }

    _setOnboardingNotice(system.chat_ready?t('onboarding_notice_setup_already_ready'):t('onboarding_notice_setup_required'),system.chat_ready?'success':'info');
    body.innerHTML=`
      <label class="onboarding-field">
        <span>${t('onboarding_provider_label')}</span>
        <select id="onboardingProviderSelect" onchange="syncOnboardingProvider(this.value)">${groupedOptions}</select>
      </label>
      ${_renderOnboardingApiKeyField()}
      ${_renderOnboardingProviderOAuthField(provider)}
      ${_renderOnboardingBaseUrlField(showBaseUrl)}
      <p class="onboarding-copy">${keyHelp}</p>
      ${showBaseUrl?`<p class="onboarding-copy">${t('onboarding_base_url_help')}</p>`:''}
      <p class="onboarding-copy">${esc(setup.unsupported_note||'')||''}</p>`;
    return;
  }

  if(key==='workspace'){
    const workspaceOptions=_getOnboardingWorkspaceChoices().map(ws=>`<option value="${esc(ws.path)}">${esc(ws.name||ws.path)} — ${esc(ws.path)}</option>`).join('');
    _setOnboardingNotice(t('onboarding_notice_workspace'), 'info');
    body.innerHTML=`
      <label class="onboarding-field">
        <span>${t('onboarding_workspace_label')}</span>
        <select id="onboardingWorkspaceSelect" onchange="syncOnboardingWorkspaceSelect(this.value)">${workspaceOptions}</select>
      </label>
      <label class="onboarding-field">
        <span>${t('onboarding_workspace_or_path')}</span>
        <input id="onboardingWorkspaceInput" value="${esc(ONBOARDING.form.workspace||'')}" placeholder="${t('onboarding_workspace_placeholder')}" oninput="ONBOARDING.form.workspace=this.value">
      </label>
      ${_renderOnboardingModelField()}`;
    const wsSel=$('onboardingWorkspaceSelect');
    if(wsSel && ONBOARDING.form.workspace) wsSel.value=ONBOARDING.form.workspace;
    const modelPickerRoot=$('onboardingModelPickerRoot');
    if(modelPickerRoot && typeof _mountSearchableModelSelect==='function'){
      _mountSearchableModelSelect({
        root:modelPickerRoot,
        selectId:'onboardingModelSelect',
        customInputId:'onboardingModelInput',
        choices:_getOnboardingProviderModelChoices(),
        selectedValue:ONBOARDING.form.model,
        onModelChange:(value)=>{ ONBOARDING.form.model=(value||'').trim(); },
      });
    }else{
      // Fallback path (searchable picker unavailable): rehydrate the plain
      // <select> so a saved/default model that isn't the first option isn't
      // silently replaced by option[0] on render.
      const modelSel=$('onboardingModelSelect');
      if(modelSel && ONBOARDING.form.model) modelSel.value=ONBOARDING.form.model;
    }
    return;
  }

  if(key==='password'){
    _setOnboardingNotice(settings.password_enabled?t('onboarding_notice_password_enabled'):t('onboarding_notice_password_recommended'), settings.password_enabled?'success':'info');
    body.innerHTML=`
      <label class="onboarding-field">
        <span>${t('onboarding_password_label')}</span>
        <input id="onboardingPasswordInput" type="password" value="${esc(ONBOARDING.form.password||'')}" placeholder="${t('onboarding_password_placeholder')}" oninput="ONBOARDING.form.password=this.value">
      </label>
      <p class="onboarding-copy">${t('onboarding_password_help')}</p>`;
    return;
  }

  const provider=_getOnboardingSetupProvider(ONBOARDING.form.provider);
  _setOnboardingNotice(t('onboarding_notice_finish'), 'success');
  body.innerHTML=`
    <div class="onboarding-summary">
      <div><strong>${t('onboarding_provider_label')}</strong><span>${esc((provider&&provider.label)||ONBOARDING.form.provider||t('onboarding_not_set'))}</span></div>
      <div><strong>${t('onboarding_model_label')}</strong><span>${esc(_getOnboardingSelectedModel()||t('onboarding_not_set'))}</span></div>
      <div><strong>${t('onboarding_workspace_label')}</strong><span>${esc(ONBOARDING.form.workspace||t('onboarding_not_set'))}</span></div>
      <div><strong>${t('onboarding_check_password')}</strong><span>${t(_getOnboardingPasswordSummaryKey(settings))}</span></div>
    </div>
    ${ONBOARDING.form.baseUrl?`<p class="onboarding-copy"><strong>${t('onboarding_base_url_label')}</strong> ${esc(ONBOARDING.form.baseUrl)}</p>`:''}
    <p class="onboarding-copy">${t('onboarding_finish_help')}</p>`;
}

function _getOnboardingPasswordSummaryKey(settings){
  const hasExistingPassword=!!(settings&&settings.password_enabled);
  const hasNewPassword=!!((ONBOARDING.form.password||'').trim());
  if(hasNewPassword) return hasExistingPassword?'onboarding_password_will_replace':'onboarding_password_will_enable';
  return hasExistingPassword?'onboarding_password_keep_existing':'onboarding_password_remains_disabled';
}

function syncOnboardingWorkspaceSelect(value){
  ONBOARDING.form.workspace=value;
  const input=$('onboardingWorkspaceInput');
  if(input) input.value=value;
}

function syncOnboardingProvider(value){
  const provider=_getOnboardingSetupProvider(value);
  ONBOARDING.form.provider=value;
  if(provider){
    if(!ONBOARDING.form.model || !_getOnboardingProviderModelChoices().some(m=>m.id===ONBOARDING.form.model) || value==='custom'){
      ONBOARDING.form.model=provider.default_model||'';
    }
    if(provider.requires_base_url){
      ONBOARDING.form.baseUrl=ONBOARDING.form.baseUrl||provider.default_base_url||'';
    }else{
      ONBOARDING.form.baseUrl=provider.default_base_url||'';
    }
  }
  _renderOnboardingBody();
}

async function loadOnboardingWizard(){
  try{
    const status=await api('/api/onboarding/status');
    ONBOARDING.status=status;
    const current=((status.setup||{}).current)||{};
    ONBOARDING.form.provider=current.provider||'openrouter';
    ONBOARDING.form.workspace=(status.workspaces&&status.workspaces.last)||status.settings.default_workspace||'';
    ONBOARDING.form.model=status.settings.default_model||current.model||'';
    ONBOARDING.form.password='';
    ONBOARDING.form.apiKey='';
    ONBOARDING.form.baseUrl=current.base_url||'';
    ONBOARDING.active=!status.completed;
    if(!ONBOARDING.active) return false;
    $('onboardingOverlay').style.display='flex';
    _renderOnboardingSteps();
    _renderOnboardingBody();
    return true;
  }catch(e){
    console.warn('onboarding status failed',e);
    return false;
  }
}

function prevOnboardingStep(){
  if(ONBOARDING.step===0)return;
  ONBOARDING.step--;
  _renderOnboardingSteps();
  _renderOnboardingBody();
}

async function _syncAresProviderToBackends(providerId, model, baseUrl, apiKeyEnv){
  const syncProvider=ARES_PROVIDER_SYNC_IDS[providerId];
  if(!syncProvider || !model) return null;
  try{
    return await api('/api/ares/provider/sync',{
      method:'POST',
      body:JSON.stringify({
        provider:syncProvider,
        model,
        base_url:baseUrl||undefined,
        api_key_env:apiKeyEnv||undefined,
        targets:['hermes','jros'],
      }),
    });
  }catch(e){
    console.warn('ARES provider sync skipped',e);
    return null;
  }
}

async function _saveOnboardingProviderSetup(){
  const provider=(ONBOARDING.form.provider||'').trim();
  const model=(ONBOARDING.form.model||'').trim();
  const apiKey=(ONBOARDING.form.apiKey||'').trim();
  const baseUrl=(ONBOARDING.form.baseUrl||'').trim();
  const current=_getOnboardingCurrentSetup();
  const isUnchanged=current.provider===provider&&((current.model||'')===model)&&((current.base_url||'')===baseUrl);
  // Skip the POST when nothing changed.  We also skip when the provider is
  // unsupported/OAuth-based and already working — chat_ready may be false for
  // providers not in the quick-setup list (e.g. minimax-cn) even though they are
  // fully configured.  Posting in that case would either be a no-op (the server
  // just marks complete for unsupported providers) or could silently overwrite
  // config.yaml if the user accidentally changed the provider dropdown.
  const currentIsOauth=!!(ONBOARDING.status&&ONBOARDING.status.setup&&ONBOARDING.status.setup.current_is_oauth);
  if(isUnchanged && !apiKey && ((ONBOARDING.status.system||{}).chat_ready || currentIsOauth)){
    const setupProvider=_getOnboardingSetupProvider(provider);
    await _syncAresProviderToBackends(provider, model || current.model || '', baseUrl || current.base_url || '', setupProvider&&setupProvider.env_var);
    return;
  }
  const body={provider,model};
  if(apiKey) body.api_key=apiKey;
  if(baseUrl) body.base_url=baseUrl;
  const status=await api('/api/onboarding/setup',{method:'POST',body:JSON.stringify(body)});
  ONBOARDING.status=status;
  const setupProvider=_getOnboardingSetupProvider(provider);
  await _syncAresProviderToBackends(provider, model, baseUrl, setupProvider&&setupProvider.env_var);
}

async function _saveOnboardingDefaults(){
  const workspace=(ONBOARDING.form.workspace||'').trim();
  const model=(ONBOARDING.form.model||'').trim();
  const password=(ONBOARDING.form.password||'').trim();
  if(!workspace) throw new Error(t('onboarding_error_choose_workspace'));
  if(!model) throw new Error(t('onboarding_error_choose_model'));
  const known=_getOnboardingWorkspaceChoices().some(ws=>ws.path===workspace);
  if(!known){
    await api('/api/workspaces/add',{method:'POST',body:JSON.stringify({path:workspace})});
  }
  // Model persisted by /api/onboarding/setup — no /api/default-model call needed here
  const body={default_workspace:workspace};
  if(password) body._set_password=password;
  const saved=await api('/api/settings',{method:'POST',body:JSON.stringify(body)});
  if(ONBOARDING.status){
    ONBOARDING.status.settings={...(ONBOARDING.status.settings||{}),password_enabled:!!saved.auth_enabled};
  }
  try{localStorage.setItem('hermes-webui-model',model)}catch{}
  if($('modelSelect')) _applyModelToDropdown(model,$('modelSelect'));
}

async function _finishOnboarding(){
  await _saveOnboardingProviderSetup();
  await _saveOnboardingDefaults();
  const done=await api('/api/onboarding/complete',{method:'POST',body:'{}'});
  ONBOARDING.status=done;
  ONBOARDING.active=false;
  $('onboardingOverlay').style.display='none';
  showToast(t('onboarding_complete'));
  await loadWorkspaceList();
  if(typeof renderSessionList==='function') await renderSessionList();
  if(!S.session && typeof newSession==='function'){
    await newSession(true);
    await renderSessionList();
  }
}

async function skipOnboarding(){
  try{
    // Mark onboarding completed server-side without changing any config
    await api('/api/onboarding/complete',{method:'POST',body:'{}'});
    ONBOARDING.active=false;
    $('onboardingOverlay').style.display='none';
    showToast(t('onboarding_skipped')||'Setup skipped');
  }catch(e){
    _setOnboardingNotice((e.message||String(e)),'warn');
  }
}

async function nextOnboardingStep(){
  try{
    if(ONBOARDING.steps[ONBOARDING.step]==='setup'){
      ONBOARDING.form.provider=(($('onboardingProviderSelect')||{}).value||ONBOARDING.form.provider||'').trim();
      ONBOARDING.form.apiKey=(($('onboardingApiKeyInput')||{}).value||'').trim();
      ONBOARDING.form.baseUrl=(($('onboardingBaseUrlInput')||{}).value||ONBOARDING.form.baseUrl||'').trim();
      if(!ONBOARDING.form.provider) throw new Error(t('onboarding_error_provider_required'));
      if(ONBOARDING.form.provider==='custom' && !ONBOARDING.form.baseUrl) throw new Error(t('onboarding_error_base_url_required'));
      // For self-hosted providers (requires_base_url=True), gate Continue on a
      // successful probe of <base_url>/models — otherwise the wizard would
      // happily persist an unreachable URL and finish in 200ms with no
      // outbound HTTP, exactly the bug in #1499.  Run the probe synchronously
      // here, then check status; the probe is idempotent & cached on
      // (provider, baseUrl, apiKey) so this rarely triggers a second network
      // call when the user already saw a green banner.
      const cat=_getOnboardingSetupProvider(ONBOARDING.form.provider);
      if(cat&&cat.requires_base_url){
        if(!ONBOARDING.form.baseUrl) throw new Error(t('onboarding_error_base_url_required'));
        await _runOnboardingProbe();
        if(ONBOARDING.probe.status!=='ok'){
          // Surface the same localized error string the inline banner shows.
          const msg=_onboardingProbeMessage(ONBOARDING.probe)||t('onboarding_error_probe_failed')||'Could not reach the configured base URL.';
          throw new Error(msg);
        }
      }
    }
    if(ONBOARDING.steps[ONBOARDING.step]==='workspace'){
      ONBOARDING.form.workspace=(($('onboardingWorkspaceInput')||{}).value||ONBOARDING.form.workspace||'').trim();
      ONBOARDING.form.model=(($('onboardingModelInput')||{}).value||($('onboardingModelSelect')||{}).value||ONBOARDING.form.model||'').trim();
      if(!ONBOARDING.form.workspace) throw new Error(t('onboarding_error_workspace_required'));
      if(!ONBOARDING.form.model) throw new Error(t('onboarding_error_model_required'));
    }
    if(ONBOARDING.steps[ONBOARDING.step]==='password'){
      ONBOARDING.form.password=(($('onboardingPasswordInput')||{}).value||'').trim();
    }
    if(ONBOARDING.step===ONBOARDING.steps.length-1){
      await _finishOnboarding();
      return;
    }
    ONBOARDING.step++;
    _renderOnboardingSteps();
    _renderOnboardingBody();
  }catch(e){
    _setOnboardingNotice(e.message||String(e),'warn');
  }
}

/* ── Codex OAuth device-code flow ── */
let _codexOAuthPollTimer=null;
let _codexOAuthFlowId=null;

function _clearCodexOAuthPoll(){
  if(_codexOAuthPollTimer){clearTimeout(_codexOAuthPollTimer);_codexOAuthPollTimer=null;}
}

function _setCodexOAuthButton(enabled){
  const btn=$('codexOAuthBtn');
  if(btn){btn.disabled=!enabled;btn.textContent=enabled?t('oauth_login_codex'):'...';}
}

async function copyCodexOAuthCode(code){
  try{
    await navigator.clipboard.writeText(code||'');
    showToast('Code copied');
  }catch(e){
    showToast(code||'');
  }
}

async function cancelCodexOAuth(){
  const flowDiv=$('codexOAuthFlow');
  const flowId=_codexOAuthFlowId;
  _clearCodexOAuthPoll();
  _codexOAuthFlowId=null;
  if(flowId){
    try{await api('/api/onboarding/oauth/cancel',{method:'POST',body:JSON.stringify({flow_id:flowId})});}catch(e){}
  }
  _setCodexOAuthButton(true);
  if(flowDiv){
    flowDiv.innerHTML=`<div class="onboarding-oauth-card"><div class="onboarding-oauth-icon">⏹</div><div><strong>OAuth login cancelled</strong><p style="margin-top:6px;color:var(--muted);font-size:13px">Start again whenever you're ready.</p></div></div>`;
  }
}

function _renderCodexOAuthTerminal(status,message){
  const flowDiv=$('codexOAuthFlow');
  if(!flowDiv)return;
  const ok=status==='success';
  const icon=ok?'✅':status==='expired'?'⌛':status==='cancelled'?'⏹':'❌';
  const title=ok?t('oauth_codex_success'):(status==='expired'?t('oauth_codex_expired'):(status==='cancelled'?'OAuth login cancelled':t('oauth_codex_error')));
  flowDiv.innerHTML=`
    <div class="onboarding-oauth-card ${ok?'onboarding-oauth-ready':''}" ${ok?'':'style="border-color:var(--error,#e55)"'}>
      <div class="onboarding-oauth-icon">${icon}</div>
      <div><strong>${title}</strong><p style="margin-top:6px;color:var(--muted);font-size:13px">${esc(message||'')}</p></div>
    </div>`;
}

async function _pollCodexOAuth(){
  const flowId=_codexOAuthFlowId;
  if(!flowId)return;
  try{
    const resp=await api('/api/onboarding/oauth/poll?flow_id='+encodeURIComponent(flowId));
    const status=(resp&&resp.status)||'error';
    if(status==='pending'){
      _codexOAuthPollTimer=setTimeout(_pollCodexOAuth,3000);
      return;
    }
    _clearCodexOAuthPoll();
    _codexOAuthFlowId=null;
    _setCodexOAuthButton(true);
    if(status==='success'){
      _renderCodexOAuthTerminal('success','Credentials saved to the Hermes credential pool. Refreshing provider status…');
      showToast(t('oauth_codex_success'));
      try{await loadOnboardingWizard();}catch(e){}
    }else if(status==='expired'){
      _renderCodexOAuthTerminal('expired','The code expired. Start a new login flow to try again.');
    }else if(status==='cancelled'){
      _renderCodexOAuthTerminal('cancelled','The login flow was cancelled.');
    }else{
      _renderCodexOAuthTerminal('error',(resp&&resp.error)||'OAuth login failed. Please try again.');
    }
  }catch(e){
    _clearCodexOAuthPoll();
    _codexOAuthFlowId=null;
    _setCodexOAuthButton(true);
    _renderCodexOAuthTerminal('error',(e&&e.message)||String(e));
  }
}

async function startCodexOAuth(){
  const flowDiv=$('codexOAuthFlow');
  if(!flowDiv)return;
  _clearCodexOAuthPoll();
  _codexOAuthFlowId=null;
  _setCodexOAuthButton(false);
  flowDiv.style.display='block';
  flowDiv.innerHTML=`<div class="onboarding-oauth-card onboarding-oauth-pending"><div class="onboarding-oauth-icon">⏳</div><div><strong>${t('oauth_codex_polling')}</strong><p>Starting device-code flow…</p></div></div>`;
  try{
    const resp=await api('/api/onboarding/oauth/start',{method:'POST',body:JSON.stringify({provider:'openai-codex'})});
    if(resp.error) throw new Error(resp.error);
    const{flow_id,user_code,verification_uri}=resp;
    if(!flow_id||!user_code||!verification_uri) throw new Error('Invalid OAuth response');
    _codexOAuthFlowId=flow_id;
    flowDiv.innerHTML=`
      <div class="onboarding-oauth-card onboarding-oauth-pending">
        <div class="onboarding-oauth-icon">📋</div>
        <div style="flex:1">
          <strong>${t('oauth_codex_step1')}</strong>
          <p><a href="${esc(verification_uri)}" target="_blank" rel="noopener" style="color:var(--accent);word-break:break-all">${esc(verification_uri)}</a></p>
          <p style="margin-top:8px"><strong>${t('oauth_codex_step2')}</strong></p>
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:4px">
            <code style="display:inline-block;font-size:18px;letter-spacing:0.1em;background:rgba(255,255,255,.08);padding:6px 14px;border-radius:8px;user-select:all">${esc(user_code)}</code>
            <button class="sm-btn" type="button" onclick="copyCodexOAuthCode('${esc(user_code)}')">Copy code</button>
            <button class="sm-btn" type="button" onclick="cancelCodexOAuth()">Cancel</button>
          </div>
          <p style="margin-top:8px;color:var(--muted);font-size:13px">${t('oauth_codex_polling')}</p>
        </div>
      </div>`;
    _codexOAuthPollTimer=setTimeout(_pollCodexOAuth,Math.max(1000,Number(resp.poll_interval_seconds||3)*1000));
  }catch(e){
    _clearCodexOAuthPoll();
    _codexOAuthFlowId=null;
    _renderCodexOAuthTerminal('error',(e&&e.message)||String(e));
    _setCodexOAuthButton(true);
  }
}

/* ── Anthropic / Claude Code credential-link flow ── */
let _anthropicOAuthPollTimer=null;
let _anthropicOAuthFlowId=null;

function _clearAnthropicOAuthPoll(){
  if(_anthropicOAuthPollTimer){clearTimeout(_anthropicOAuthPollTimer);_anthropicOAuthPollTimer=null;}
}

function _setAnthropicOAuthButton(enabled){
  const btn=$('anthropicOAuthBtn');
  if(btn){btn.disabled=!enabled;btn.textContent=enabled?'Login with Claude Code':'...';}
}

async function cancelAnthropicOAuth(){
  const flowDiv=$('anthropicOAuthFlow');
  const flowId=_anthropicOAuthFlowId;
  _clearAnthropicOAuthPoll();
  _anthropicOAuthFlowId=null;
  if(flowId){
    try{await api('/api/onboarding/oauth/cancel',{method:'POST',body:JSON.stringify({flow_id:flowId,provider:'anthropic'})});}catch(e){}
  }
  _setAnthropicOAuthButton(true);
  if(flowDiv){
    flowDiv.innerHTML=`<div class="onboarding-oauth-card"><div class="onboarding-oauth-icon">⏹</div><div><strong>Claude Code OAuth cancelled</strong><p style="margin-top:6px;color:var(--muted);font-size:13px">Start again whenever you're ready.</p></div></div>`;
  }
}

function _renderAnthropicOAuthTerminal(status,message){
  const flowDiv=$('anthropicOAuthFlow');
  if(!flowDiv)return;
  const ok=status==='success';
  const icon=ok?'✅':status==='expired'?'⌛':status==='cancelled'?'⏹':'❌';
  const title=ok?'Claude Code OAuth linked':(status==='expired'?'Claude Code polling expired':(status==='cancelled'?'Claude Code OAuth cancelled':'Claude Code OAuth failed'));
  flowDiv.style.display='block';
  flowDiv.innerHTML=`
    <div class="onboarding-oauth-card ${ok?'onboarding-oauth-ready':''}" ${ok?'':'style="border-color:var(--error,#e55)"'}>
      <div class="onboarding-oauth-icon">${icon}</div>
      <div><strong>${title}</strong><p style="margin-top:6px;color:var(--muted);font-size:13px">${esc(message||'')}</p></div>
    </div>`;
}

async function _pollAnthropicOAuth(){
  const flowId=_anthropicOAuthFlowId;
  if(!flowId)return;
  try{
    const resp=await api('/api/onboarding/oauth/poll?flow_id='+encodeURIComponent(flowId));
    const status=(resp&&resp.status)||'error';
    if(status==='pending'){
      _anthropicOAuthPollTimer=setTimeout(_pollAnthropicOAuth,3000);
      return;
    }
    _clearAnthropicOAuthPoll();
    _anthropicOAuthFlowId=null;
    _setAnthropicOAuthButton(true);
    if(status==='success'){
      _renderAnthropicOAuthTerminal('success','Hermes is now linked to Claude Code credentials. Refreshing provider status…');
      showToast('Claude Code OAuth linked');
      try{await loadOnboardingWizard();}catch(e){}
    }else if(status==='expired'){
      _renderAnthropicOAuthTerminal('expired','Claude Code credentials were not detected before this flow expired. Start a new flow to try again.');
    }else if(status==='cancelled'){
      _renderAnthropicOAuthTerminal('cancelled','The login flow was cancelled.');
    }else{
      _renderAnthropicOAuthTerminal('error',(resp&&resp.error)||'Claude Code OAuth linking failed. Please try again.');
    }
  }catch(e){
    _clearAnthropicOAuthPoll();
    _anthropicOAuthFlowId=null;
    _setAnthropicOAuthButton(true);
    _renderAnthropicOAuthTerminal('error',(e&&e.message)||String(e));
  }
}

async function startAnthropicOAuth(){
  const flowDiv=$('anthropicOAuthFlow');
  if(!flowDiv)return;
  _clearAnthropicOAuthPoll();
  _anthropicOAuthFlowId=null;
  _setAnthropicOAuthButton(false);
  flowDiv.style.display='block';
  flowDiv.innerHTML=`<div class="onboarding-oauth-card onboarding-oauth-pending"><div class="onboarding-oauth-icon">⏳</div><div><strong>Checking Claude Code credentials…</strong><p>Hermes is checking for existing Claude Code OAuth credentials on this server.</p></div></div>`;
  try{
    const resp=await api('/api/onboarding/oauth/start',{method:'POST',body:JSON.stringify({provider:'anthropic'})});
    if(resp.error) throw new Error(resp.error);
    const{flow_id,status,action_required}=resp;
    if(!flow_id) throw new Error('Invalid OAuth response');
    _anthropicOAuthFlowId=flow_id;
    if(status==='success'){
      _clearAnthropicOAuthPoll();
      _anthropicOAuthFlowId=null;
      _setAnthropicOAuthButton(true);
      _renderAnthropicOAuthTerminal('success','Hermes is now linked to Claude Code credentials. Refreshing provider status…');
      showToast('Claude Code OAuth linked');
      try{await loadOnboardingWizard();}catch(e){}
      return;
    }
    flowDiv.innerHTML=`
      <div class="onboarding-oauth-card onboarding-oauth-pending">
        <div class="onboarding-oauth-icon">🖥️</div>
        <div style="flex:1">
          <strong>Complete Claude Code login on this host</strong>
          <p style="margin-top:6px">${esc(action_required||"Run 'claude setup-token' on the server, then return here. Hermes will detect the credential automatically.")}</p>
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:10px">
            <code style="display:inline-block;background:rgba(255,255,255,.08);padding:6px 10px;border-radius:8px;user-select:all">claude setup-token</code>
            <button class="sm-btn" type="button" onclick="cancelAnthropicOAuth()">Cancel</button>
          </div>
          <p style="margin-top:8px;color:var(--muted);font-size:13px">Waiting for Claude Code credentials...</p>
        </div>
      </div>`;
    _anthropicOAuthPollTimer=setTimeout(_pollAnthropicOAuth,Math.max(1000,Number(resp.poll_interval_seconds||3)*1000));
  }catch(e){
    _clearAnthropicOAuthPoll();
    _anthropicOAuthFlowId=null;
    _renderAnthropicOAuthTerminal('error',(e&&e.message)||String(e));
    _setAnthropicOAuthButton(true);
  }
}
