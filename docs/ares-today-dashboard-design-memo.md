# ARES Today Dashboard: Product and Implementation Design Memo

**Status:** Implemented through the React frontend migration; implementation appendix superseded  
**Date:** 2026-07-14  
**Scope:** ARES WebUI shell, installer, Today dashboard, vocabulary, and onboarding  
**Current implementation:** `webui/frontend/src/`, `webui/frontend/public/`, and the `/api/` adapter boundary

> Historical note: file-level instructions later in this memo describe the
> retired Vanilla JavaScript frontend. They are retained as design provenance,
> not as current implementation guidance. `.claude/FOUNDATION.md` and
> `webui/frontend/README.md` define the current architecture.

## Executive decision

ARES should adopt Paperclip's engineering discipline without adopting its virtual-company metaphor.

Keep the two-speed setup path, live credential validation, explicit reachability choices, a small coherent command family, and one shared status vocabulary. Do not import company setup, CEO accounts, org charts, headcount management, mission-to-goal-to-task cascades, P&L-shaped budgets, or multi-company mode.

The product model is a **Synthetic Mind with one Companion**, not a company staffed by agents. The default destination becomes **Today**: a calm account of what ARES handled, what needs attention, and which areas of the user's life it is watching. The workspace around it uses a three-part “Split-Brain” shell:

1. **Cortex (left):** the persistent Companion, conversation, and voice/text input.
2. **Orchestrator (center):** Today and task-oriented work surfaces such as Code, Kanban, Terminal, and Artifacts.
3. **Meta-System (right):** delegations, connected tools, memory context, runtime health, and provenance.

This is an information-architecture change, not a backend rewrite. Existing APIs and internal identifiers may remain temporarily while the user-facing language and shell migrate in controlled stages.

## Product thesis: yours, not a company's

Paperclip puts the user at a boss's desk watching employees work. ARES should put the user nowhere in particular, because it is not watching them work—it is helping them live: their money, obligations, health, home, projects, and time.

The Companion is the one relationship. Everything else is a tool it reaches for.

That distinction is the test for every design choice in this memo. If a surface makes the user manage artificial headcount, it belongs to the rejected company metaphor. If it helps the user understand what their Companion did, what needs attention, or how far it may act, it belongs in ARES.

## Product principles

### One mind, many capabilities

ARES presents one named Companion. Cloud models, local runtimes, subagents, and MCP servers are capabilities that the Companion can use, not employees or peers in an org chart. The interface should always make clear who the user is speaking with and which capability performed background work.

Tools stay unobtrusive during ordinary use. The Meta-System exists for trust, debugging, and control, but defaults to a quiet summary and progressive disclosure—not an always-demanding operator console.

### Today before administration

The home screen answers four questions in order:

- What did ARES already handle?
- What needs me soon?
- What is currently in progress?
- Which life areas deserve attention?

Configuration, runtime health, and provider details remain available but do not dominate the default experience.

### Local profile before runtime

Onboarding creates a **Local Profile** in `~/.ares/config.yaml` and `~/.ares/.env`. This profile contains the user's name, Companion identity, voice preference, authentication, reachability choice, and optional provider credentials. No external agent framework is required to save it.

JaegerAI, Ares Agent, Gemini, Claude, and future frameworks are optional connections that can consume the profile later. Their absence may limit live capabilities; it must not block identity setup or local configuration.

### Personal autonomy, not a budget

Paperclip expresses governance through budgets and approval policy. ARES asks the human question: **“How much should it do without asking first?”**

Use three plain-language levels:

- **Tell me things:** observe, organize, and recommend; do not take external action.
- **Ask before acting:** prepare work, but ask before spending, sending, booking, publishing, or changing external systems.
- **Just handle it:** act within explicitly granted scopes, with receipts and easy revocation.

This is permission posture, not P&L. High-risk actions still require policy-enforced confirmation regardless of the selected label.

### One vocabulary per concept

Use the following user-facing vocabulary everywhere:

| Concept | Canonical term | Avoid in UI | Notes |
|---|---|---|---|
| A discrete thing to do | **Task** | Mission, Todo, Action item | “Task” is already the strongest existing domain term and matches Kanban. |
| Time-triggered automation | **Schedule** | Task, Cron task | Individual entries are “scheduled runs” or “schedules.” |
| A bounded background execution | **Run** | Job, Mission | A task can have many runs. |
| Work sent to another model/tool | **Delegation** | Employee assignment | Display capability and provenance, not hierarchy. |
| High-level desired outcome | **Goal** | Mission | A goal may group tasks, but it does not create an organizational cascade. |
| Companion/framework connectivity | **Connection** | Employee, worker | Connections are optional capabilities. |

Task status uses one system across Today, Kanban, detail views, and the Meta-System:

| Canonical status | Meaning |
|---|---|
| **Inbox** | Captured but not yet committed |
| **Ready** | Clear and available to start |
| **In progress** | Actively being worked |
| **Waiting** | Blocked on a person, event, or dependency |
| **Done** | Completed |
| **Canceled** | Intentionally stopped |

Runtime connection health remains a separate vocabulary: **Connected**, **Connecting**, **Needs attention**, and **Offline**. Task state and system health must never reuse one another's labels or colors.

## Target experience

### Install and launch

Retain a single command family:

```text
ares run
ares configure
ares doctor
```

Existing `./start.sh` and `./ctl.sh start` can remain compatible entry points while the command family is introduced. Documentation and UI should teach one primary family; compatibility aliases should not become a second product vocabulary.

`ares configure` must detect an existing profile and offer to review or edit it. It must never silently replace credentials, identity, reachability, or permission settings. Quickstart must state which decisions it is defaulting; Advanced exposes storage, reachability, provider, and framework controls.

The intended tone is personal and technically honest:

```text
ARES — a synthetic mind that works on your life, not your org chart.

How much do you want to set up right now?
  Just start          Sensible defaults, running in under a minute
  Set it up properly  Storage, reachability, model provider, all of it
```

### Onboarding

The first question becomes **“What should your Companion call you?”**, followed by Companion identity. It must not ask the user to name a company or create a CEO account.

The proposed flow is:

1. **Welcome:** choose Quickstart or Advanced.
2. **You:** preferred name and optional personalization.
3. **Companion:** name, character, and voice.
4. **Life areas:** choose what ARES should pay attention to now—Finance, Health, Work, Home, or a specific project. This sets attention, not automatic access.
5. **Autonomy:** Tell me things, Ask before acting, or Just handle it.
6. **Access:** configure password/passkey and who may sign in.
7. **Reachability:** This machine, This network, or Your tailnet.
8. **Intelligence (optional):** connect a provider and validate credentials live.
9. **Frameworks (optional):** connect JaegerAI, Ares Agent, Gemini, Claude, or another adapter.
10. **Review:** show exactly which local files will be written and what is optional.
11. **Finish:** save the Local Profile and open Today.

Quickstart supplies safe defaults and shows only required fields. Advanced reveals provider base URLs, workspace selection, MCP placement, network binding, and framework connections. Both paths write the same profile schema.

### Today

Today is the default center-canvas tab and contains:

- **Handled by ARES:** completed or materially advanced work since the last visit.
- **Needs you:** approvals, questions, credential problems, and waiting tasks.
- **Due soon:** time-sensitive tasks ordered by urgency.
- **In progress:** active tasks and delegations, with honest live state.
- **Life areas:** compact Finance, Health, Work, and Home summaries. These are extensible modules, not fixed database columns.
- **Capture:** one fast path to create a Task or tell the Companion what changed.

Today is not another task database view. It is a composed projection over tasks, schedules, runs, delegations, memory, and alerts.

The visual hierarchy should resemble a personal briefing:

```text
Good afternoon.
3 things happened while you were away. Nothing needs you yet.

THIS MONTH       DUE SOON
+$1,240          2 bills

DONE   Paid the electric bill
DONE   Booked your dentist follow-up
DOING  Comparing flight prices for your trip

LIFE AREAS ARES IS WATCHING
Finance · Home · Work
```

The Companion may use its own restrained identity gradient or accent as a presence cue. Do not assign a rainbow of employee colors to tools or delegations.

## Split-Brain information architecture

```text
+------------------------+-----------------------------------------+--------------------------+
| CORTEX                 | ORCHESTRATOR                            | META-SYSTEM              |
| Companion identity     | Today | Code | Kanban | Terminal | ... | Delegations             |
| Avatar / presence      |                                         | MCP tools                |
| Conversation stream   | Active tab content                      | Memory in use            |
| Voice / text composer  |                                         | Runtime / connection     |
+------------------------+-----------------------------------------+--------------------------+
```

The Cortex owns conversation. The Orchestrator owns durable work surfaces. The Meta-System explains what the mind is doing and what context/capabilities it is using. A feature belongs in exactly one region by default.

On medium screens, the Meta-System becomes a drawer. On narrow screens, the regions become three top-level modes—Companion, Work, and Context—while preserving the same DOM landmarks and state model. Do not squeeze three desktop columns onto mobile.

## File-by-file implementation design

### `webui/static/index.html`

The current `.layout` contains useful primitives (`.rail`, `.sidebar`, the chat/main views, and `.rightpanel`) but their ownership is historical. Introduce semantic shell containers while preserving existing element IDs during the first migration:

```html
<main class="ares-shell" id="aresShell">
  <aside class="cortex" id="cortex" aria-label="Companion">
    <header class="companion-presence"><!-- avatar, name, state --></header>
    <section class="companion-conversation" aria-label="Conversation">
      <!-- move/reparent existing message stream here -->
    </section>
    <footer class="companion-composer"><!-- existing composer controls --></footer>
  </aside>

  <section class="orchestrator" id="orchestrator" aria-label="Workspace">
    <nav class="canvas-tabs" id="canvasTabs" aria-label="Workspace tabs"></nav>
    <div class="canvas-viewport" id="canvasViewport">
      <section class="canvas-view" data-canvas-view="today"></section>
      <section class="canvas-view" data-canvas-view="code" hidden></section>
      <section class="canvas-view" data-canvas-view="kanban" hidden></section>
      <section class="canvas-view" data-canvas-view="terminal" hidden></section>
      <section class="canvas-view" data-canvas-view="artifacts" hidden></section>
    </div>
  </section>

  <aside class="meta-system" id="metaSystem" aria-label="System context">
    <section data-meta-module="delegations"></section>
    <section data-meta-module="tools"></section>
    <section data-meta-module="memory"></section>
    <section data-meta-module="connections"></section>
  </aside>
</main>
```

Implementation order:

1. Wrap existing regions and retain IDs/classes used by JavaScript and tests.
2. Add Today as a new canvas view and make it the default for new/local-profile sessions.
3. Move Code, Kanban, Terminal, and Artifacts behind a data-driven canvas tab bar.
4. Rename the visible scheduled-task panel to **Schedules**; keep `panelTasks`, `mainTasks`, and current handler names as compatibility IDs until a later internal refactor.
5. Remove the Missions navigation item and `mainMissions` from the active shell. If existing mission data must remain reachable, provide a one-time migration/import route rather than a permanent competing tab.
6. Remove company, CEO, roster, and org-chart elements. Replace any useful background activity content with the Delegations meta module.
7. Add semantic landmarks, focus targets, `aria-selected`, and `hidden` state to tabs. Do not encode visibility only in CSS classes.

Dynamic tabs should be registered, not hard-coded through another large switch statement:

```js
registerCanvasTab({
  id: 'kanban',
  labelKey: 'canvas_tab_kanban',
  order: 30,
  mount: mountKanbanCanvas,
  unmount: unmountKanbanCanvas,
  capability: 'kanban'
});
```

This registry is the extension seam for future agnostic features.

### `webui/static/style.css`

The layout CSS belongs in `style.css`, not inline in `index.html`. Build the desktop shell with grid so the center can shrink safely and either rail can collapse independently:

```css
.ares-shell {
  --cortex-width: clamp(280px, 24vw, 380px);
  --meta-width: clamp(260px, 21vw, 340px);
  display: grid;
  grid-template-columns: var(--cortex-width) minmax(0, 1fr) var(--meta-width);
  min-height: 0;
  height: 100%;
  overflow: hidden;
}

.cortex,
.orchestrator,
.meta-system {
  min-width: 0;
  min-height: 0;
}

.cortex {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  border-inline-end: 1px solid var(--border);
  background: var(--sidebar);
}

.orchestrator {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  background: var(--bg);
}

.canvas-viewport,
.canvas-view {
  min-height: 0;
  overflow: auto;
}

.meta-system {
  overflow: auto;
  border-inline-start: 1px solid var(--border);
  background: var(--sidebar);
}

@media (max-width: 1180px) {
  .ares-shell { grid-template-columns: var(--cortex-width) minmax(0, 1fr); }
  .meta-system { position: fixed; inset-block: 0; inset-inline-end: 0; width: min(360px, 92vw); }
  .meta-system:not([data-open="true"]) { visibility: hidden; transform: translateX(100%); }
}

@media (max-width: 720px) {
  .ares-shell { display: block; }
  .cortex, .orchestrator, .meta-system { position: absolute; inset: 0; width: auto; }
  .ares-shell[data-mobile-mode="companion"] > :not(.cortex),
  .ares-shell[data-mobile-mode="work"] > :not(.orchestrator),
  .ares-shell[data-mobile-mode="context"] > :not(.meta-system) { display: none; }
}
```

Also:

- Reuse theme tokens (`--bg`, `--sidebar`, `--surface`, `--border`, `--text`, `--muted`, and accent tokens) rather than creating Today-only colors.
- Reserve red for failures/destructive states; task status colors must be consistent in every surface.
- Preserve existing resizable-rail behavior by writing widths to the new custom properties.
- Respect `prefers-reduced-motion`, keyboard resizing, safe-area insets, and 44px touch targets.
- Keep module cards visually quiet. Today should read as a briefing, not a wall of bordered widgets.

### `webui/static/ui.js`

`ui.js` should own shell state and rendering primitives, not product-specific task fetching.

Add:

```js
const ARES_SHELL = {
  activeCanvas: 'today',
  mobileMode: 'work',
  metaOpen: false,
  tabs: new Map()
};

function registerCanvasTab(definition) { /* validate, store, render tab */ }
function activateCanvasTab(id, options = {}) { /* mount once, update ARIA/history */ }
function setMobileShellMode(mode) { /* companion | work | context */ }
function setMetaSystemOpen(open) { /* drawer and focus management */ }
```

Update existing panel switching so `switchPanel()` remains a compatibility adapter during migration and delegates durable work surfaces to `activateCanvasTab()`. Do not rename every old function in the same release; that creates unnecessary regression risk in a very large script. First change labels and routing, then remove dead identifiers after tests and telemetry show no callers.

Move any Companion name/avatar/presence rendering into a small `renderCompanionPresence(profile, connection)` function. A framework being offline should render a capability warning, not erase or disable the Companion identity.

### `webui/static/panels.js`

This file currently contains the active `switchPanel(name, opts)`, `loadTodos(forceRefresh)`, mission rendering, scheduled-task rendering, and Kanban behavior. Consolidate in three layers:

1. **Task domain adapter:** normalize existing Todo, Mission, and Kanban records into one display model without immediately breaking backend APIs.
2. **Surface renderers:** Today, Task list/detail, and Kanban consume the normalized model.
3. **Compatibility wrappers:** old global handlers call the new adapter until old markup and tests are migrated.

Proposed client model:

```js
function normalizeTask(raw, source) {
  return {
    id: String(raw.id),
    source,                 // temporary provenance: todo | mission | kanban
    title: raw.title || raw.name || raw.description,
    status: normalizeTaskStatus(raw.status),
    dueAt: raw.due_at || raw.deadline || null,
    goalId: raw.goal_id || null,
    activeRun: normalizeRun(raw.active_run),
    requiresUser: Boolean(raw.requires_user || raw.approval_required)
  };
}
```

Replace mission-specific entry points with task/goal equivalents. Candidate functions and callers should be identified by `rg -i "mission|todo" webui/static webui/tests` before deletion. `loadTodos()` can initially become a wrapper around `loadTasks()`:

```js
async function loadTasks(options = {}) { /* canonical implementation */ }
async function loadTodos(forceRefresh) {
  return loadTasks({ forceRefresh, legacySource: 'todo' });
}
```

Rename the existing scheduled “Tasks” surface to Schedules in visible text and navigation before changing internal IDs. This prevents the new canonical Task concept from colliding with cron/scheduled jobs.

Add `loadTodaySummary()` and `renderTodaySummary()` as composition functions. They should accept normalized data and render independent modules so a failed Finance or MCP request cannot blank the whole dashboard. Each module needs loading, empty, ready, stale, and error states using the shared status vocabulary.

Delete org-chart and CEO rendering rather than relabeling it. If those functions also carry useful delegation state, extract only the state/data calls and render them in `renderDelegationsMeta()`.

### `webui/static/onboarding.js`

This requires a behavioral change, not only new prose. The present flow:

- describes the Companion runtime as required;
- hides Skip when JaegerAI is unavailable;
- blocks the Companion step when it is missing;
- throws on finalization when companion defaults are unavailable; and
- offers “Install JaegerAI automatically” as though setup cannot proceed without it.

Refactor the state around a local profile:

```js
const ONBOARDING = {
  // existing state...
  steps: ['welcome', 'you', 'companion', 'lifeAreas', 'autonomy',
          'access', 'reachability', 'intelligence', 'frameworks',
          'review', 'finish'],
  form: {
    installSpeed: 'quick',
    reachability: 'local',
    userName: '',
    companionName: 'Ares',
    companionVoice: '',
    companionPermissionMode: 'confirm',
    lifeAreas: [],
    framework: null
  }
};
```

Required changes:

1. Remove the JaegerAI gate from Companion rendering and next-step validation.
2. Remove the finalization exception that requires companion runtime defaults.
3. Supply frontend-safe profile defaults when a runtime cannot enumerate voices or characters. Mark runtime-specific options as unavailable rather than blocking the form.
4. Save identity/auth/reachability through the local onboarding endpoint before attempting optional framework connection.
5. Move `installJrosFromOnboarding()` into the optional Frameworks step. Rename the visible action to **Connect JaegerAI** or **Install JaegerAI connector**; installation errors must be recoverable and skippable.
6. Preserve `_probeOnboardingProvider()` and its stale-response protection for live credential/base-URL validation.
7. Preserve Quickstart/Advanced and reachability. Expand reachability to the explicit set: `local`, `lan`, and `tailscale` (subject to backend schema support).
8. Replace the iPhone-specific step with device-neutral reachability guidance; show iPhone/Tailscale instructions contextually when tailnet is selected.
9. On Review, distinguish **Saved locally** from **Connected now**.
10. Treat life areas as editable attention preferences, not provider permissions or claims that an integration is already wired up.
11. Map the autonomy choice to the existing permission model conservatively; never let friendly copy weaken hard confirmation rules.

Suggested core copy:

- Welcome: “Create a local ARES profile. You can connect models and agent frameworks now or later.”
- You: “What should your Companion call you?”
- Companion: “Shape the identity you interact with. These choices are saved locally and do not require a runtime connection.”
- Intelligence: “Optional: connect a model provider. ARES will validate credentials before saving them.”
- Frameworks: “Optional: connect a framework that can use this profile. You can skip this and return from Settings.”
- Finish: “Your Local Profile is ready.”

### `webui/static/i18n.js`

Do not perform a blind global replacement: “task” appears in legitimate Kanban and scheduler contexts, while “mission” and “todo” may occur in API-facing keys. Use a key migration table:

```js
const LEGACY_I18N_ALIASES = {
  missions_title: 'tasks_title',
  todos_title: 'tasks_title',
  tasks_scheduled_title: 'schedules_title'
};
```

Add canonical English keys first:

```js
today_title
today_handled
today_needs_you
today_due_soon
today_in_progress
today_life_areas
tasks_title
schedules_title
delegations_title
connections_title
onboarding_local_profile_title
onboarding_local_profile_body
onboarding_life_areas_title
onboarding_autonomy_title
onboarding_autonomy_observe
onboarding_autonomy_confirm
onboarding_autonomy_delegated
onboarding_frameworks_optional
onboarding_profile_saved
```

Then update every locale structurally. Until translations are reviewed, fall back to the canonical English value rather than leaving older company/runtime-required claims in non-English locales. Remove aliases only after templates and JavaScript no longer reference the old keys.

Add an automated vocabulary check over user-visible strings. Allow exceptions for historical migration help, API payload fields, and developer comments:

```text
Forbidden UI terms: Mission, Missions, Todo, Todos, CEO, Org Chart, company
Context exception: “company” may appear in third-party legal/provider names only.
```

## Migration sequence

### Phase 0 — Contract and tests

- Inventory shell selectors, global function callers, browser tests, and backend payload names.
- Add tests proving onboarding can save a Local Profile with no JaegerAI/Ares Agent process.
- Add tests for Quickstart, Advanced, provider validation, and all three reachability choices.
- Define normalized Task and status contracts.

### Phase 1 — Vocabulary and onboarding

- Change visible Scheduled Tasks to Schedules.
- Introduce canonical Task labels and i18n aliases.
- Remove Missions, Todos, CEO, company, and org-chart language from active navigation.
- Remove runtime gates and ship the Local Profile narrative.

This phase delivers conceptual consistency without destabilizing the page shell.

### Phase 2 — Shell and Today

- Add semantic Cortex, Orchestrator, and Meta-System containers around existing components.
- Introduce the tab registry and Today view.
- Rehome conversation/composer in Cortex and diagnostics/context in Meta-System.
- Add responsive drawer/mode behavior and persist user widths/collapse choices.

### Phase 3 — Domain consolidation

- Introduce `loadTasks()` and normalized task status.
- Migrate Kanban and Today to the adapter.
- Provide one-time migration for legacy Mission/Todo records if those are durable backend entities.
- Remove compatibility functions, DOM IDs, stylesheets such as `missions.css`, and localization aliases only when no callers remain.

### Phase 4 — Extensibility and polish

- Document the canvas-tab and meta-module registration contracts.
- Add loading/empty/stale/error states and performance budgets.
- Run accessibility, keyboard, reduced-motion, mobile, and localization reviews.

## Acceptance criteria

The redesign is complete when:

- A new user can finish onboarding and save a Local Profile with no external runtime installed or running.
- Quickstart and Advanced converge on the same saved schema.
- Provider credentials/base URLs are validated live and cannot be overwritten by stale probe responses.
- Reachability explicitly offers This machine, This network, and Your tailnet.
- Today is the default work canvas and degrades module-by-module when a service is unavailable.
- The Companion remains visible and identifiable while work tabs change.
- Code, Kanban, Terminal, and Artifacts are registered through a stable tab contract.
- Delegations, MCP tools, memory context, and runtime health appear in the Meta-System, not as an org chart.
- No active UI contains Mission, Todo, CEO, Org Chart, or company-management language.
- Scheduled automation is called Schedules; actionable work is called Tasks.
- Task status labels and colors match across Today, Kanban, details, and delegation summaries.
- Desktop, drawer, and mobile-mode layouts are keyboard accessible and preserve focus correctly.
- Existing chat streaming, terminal, workspace, authentication, and backend-selection tests remain green.

## Explicit non-goals

- Rewriting backend APIs solely to achieve a label change.
- Turning life areas into a rigid hierarchy or mandatory taxonomy.
- Presenting models, tools, or subagents as employees.
- Requiring a specific framework to create or save the user's identity.
- Building multi-company support, headcount controls, CEO privileges, or P&L budgets.

## Current-code observations and risk notes

This memo merges the supplied **ARES V-Next: Yours, not a company's** product memo with the implementation brief and the current checkout. The source memo was itself grounded in a running Paperclip clone, its CLI onboarding and `DESIGN.md`, and ARES's gold-on-near-black identity. In the current ARES code, `index.html` contains `panelTasks`, `mainTasks`, and `mainMissions`; `panels.js` owns `switchPanel()` and `loadTodos()`; `style.css` already defines desktop sidebar/right-panel primitives and mobile behavior; and `onboarding.js` still contains JaegerAI-required gates. `i18n.js` has many locale-specific legacy strings, so English-only copy replacement would leave contradictory onboarding experiences.

The repository is presently undergoing a broad rename and contains many uncommitted changes. Implementation should be split into narrow commits and must preserve those existing edits.
