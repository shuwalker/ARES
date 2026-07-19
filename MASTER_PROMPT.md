# ARES Production Readiness — Master Prompt

Paste this into Gemini Code Assist, Claude Code, or Codex CLI. It is a complete, self-contained brief to bring ARES from development to production today.

---

## YOUR JOB

You are a senior full-stack engineer. Take the ARES codebase at `/path/to/ARES` from its current porting/drain state to a **production-ready, single-user Synthetic Person application** that runs on macOS. Work on branch `wip/odysseus-import`. Push frequently.

**CRITICAL: There are 92 uncommitted files in the working tree from the user's VS Code session. Do not commit, stage, or modify these files unless explicitly fixing a specific finding listed below. Your work should be in new commits on top of the last committed state (`37947e52`).**

---

## WHAT ARES IS

ARES is a Synthetic Person — a multi-agent controller with **no internal LLM code**. Every AI model is reached through an external adapter that shells out to the real tool's CLI or API. It is local-first with cloud fallbacks. Single user, macOS native.

Stack:
- **macOS app**: `ARES-Mac_os/` — 701 Swift source files, builds via `build-app.sh`
- **Backend**: `webui/` — FastAPI on port 8787 (0.0.0.0), private network via Tailscale/LAN at `http://<tailscale-ip>:8787`
- **Frontend**: `webui/frontend/` — React + Vite + shadcn/ui + Tailwind + framer-motion
- **Reference sources** (drained, do not delete):
  - `reference_sources/paperclip_drained/`
  - `reference_sources/hermes_web_drained/`
  - `reference_sources/hermes_desktop_drained/`
  - `reference_sources/colibri_drained/`

Design system (locked, do not change):
- Palette: bg `#151614`, sidebar `#242624`, surface `#1B1C1A`, surface-subtle `#20211F`, border `#343631`, border2 `#4B4D47`, text `#ECEBE4`, strong `#FAF9F3`, muted `#A7A79D`, accent `#D7D6CE`, user-bubble `#2E302D`
- No linear transitions — use framer-motion spring physics only
- shadcn/ui + Tailwind only
- Visual reference: design tokens and screenshots under `webui/docs/` / `docs/`

---

## CURRENT STATE (AUDITED + CODE REVIEWED)

### What works (committed, verified)
- Server runs on `127.0.0.1:8787` and on the private Tailscale/LAN URL when configured
- Frontend Vite build passes (production bundle: 586 KB main chunk)
- 36 frontend pages exist, all exported, all substantial (100-860 lines each), none are stubs
- 43 FastAPI routers exist, all registered, all have routes
- `/api/health` returns 200
- `/api/discover/frameworks` returns 200 with 12 detected adapters
- AI adapter discovery scanner at `webui/api/ai_framework_discovery.py`
- 3 adapters verified working: `hermes_local`, `claude_local`, `codex_local`
- 7 AI CLIs installed: hermes, claude, codex, gemini, grok, pi, ollama
- Ollama running with models: `kai:latest`, `qwen3.6:35b-mlx`
- Antigravity IDE.app and OpenCode.app exist on disk
- `launchctl` plist exists at `~/Library/LaunchAgents/com.ares.webui.plist`

### What is broken or incomplete

**BLOCKER — Frontend does not build (5,017 TypeScript errors across 388 files):**

A code review of the uncommitted working tree identified these specific root causes:

1. **Duplicate `useNavigate` export** — `webui/frontend/src/lib/router.ts:36`. `useNavigate` is exported twice in the same module. This is a hard ES module syntax error, not a lint issue. Confirmed via esbuild: `Multiple exports with the same name "useNavigate"`. Nearly every page under `pages/paperclip/*.tsx` imports from `@/lib/router`, so `npm run build` cannot succeed. **Fix:** remove the duplicate export.

2. **56 pages import a context module that doesn't exist** — `webui/frontend/src/stubs.d.ts:22`. 56 pages import `useDomain` from `@/context/CompanyContext`, a path with no backing file anywhere in the repo. The real hook lives in the newly added `DomainContext.tsx` under a different name/path. `CompanyContext` is only declared as an ambient TS module to silence `tsc`, but Vite has no real module to resolve — the dev server/build fails at runtime. Additionally, 23 relative-path imports of the same missing module from `components/paperclip/*.tsx` produce explicit `TS2307` errors. **Fix:** point all `CompanyContext` imports at `DomainContext.tsx`, or rename/relocate `DomainContext` to match the import path.

3. **No-op stubs shadow existing working components** — New stub files at `webui/frontend/src/components/` shadow fully-implemented versions that already exist at `webui/frontend/src/components/paperclip/`:
   - `AgentConfigForm.tsx` renders `() => null` but is imported live in `NewAgent.tsx`, `AgentDetail.tsx`, `DomainImport.tsx` — the entire create/edit-agent form disappears. A ~200+ line working implementation sits at `components/paperclip/AgentConfigForm.tsx`.
   - `MarkdownBody.tsx` — same pattern, breaks chat/comment rendering in `BoardChat.tsx`, `ApprovalDetail.tsx`.
   - `MarkdownEditor.tsx` — same pattern, breaks `DomainSkills.tsx`, `SkillStudio.tsx`, `WorkflowSettings.tsx`, `Routines.tsx`.
   - `InlineEntitySelector.tsx`, `SystemNotice.tsx`, `ExternalObjectPill.tsx` — same pattern.
   **Fix:** repoint imports to `components/paperclip/*` and delete the no-op stubs. Do not flesh out the stubs — the real components already exist.

4. **`agentsApi` stub missing ~20 methods callers use** — `webui/frontend/src/api/agents.ts:6`. Stub only implements `listAgents`/`getAgent` while real pages call ~20 other methods (`list`, `get`, `update`, `hire`, `updatePermissions`, `approve`, `loginWithClaude`, etc.). Confirmed in `npm run typecheck`: `Property 'list' does not exist on type...`. `AgentDetail.tsx` and `Agents.tsx` call `agentsApi.list`/`.get`/`.update`/`.updatePermissions` — these throw at runtime. **Fix:** implement all methods the pages actually call, or generate/derive them from the real backend contract.

5. **Broken `apiFetch` import in two API modules** — `webui/frontend/src/api/execution-workspaces.ts:2` and `pipelines.ts`. Import `apiFetch` from `./client`, but `client.ts` only re-exports `ApiError`. Every other new `api/*.ts` file correctly imports `apiFetch` from `@/shared/api-client` directly. Confirmed via esbuild: `No matching export in src/api/client.ts for import "apiFetch"`. **Fix:** change import to `@/shared/api-client`.

6. **`@ts-nocheck` masks stub-API type errors on 6 pages** — `Workflows.tsx`, `WorkflowSettings.tsx`, `TeamCatalog.tsx`, `UserProfile.tsx`, `WhatNeedsMe.tsx`, `Workspaces.tsx` all have `// @ts-nocheck` as their first line, blanket-disabling type checking exactly where the new loosely-typed stub API modules are consumed. Any mismatched field access compiles silently and only surfaces at runtime. **Fix:** remove `@ts-nocheck` after fixing the underlying stub types.

7. **Drained hermes-workspace components have wrong import paths** — Under `webui/frontend/src/components/drained/hermes-workspace/`. Common patterns: `@/components/ui/tooltip` has no `TooltipRoot` export, `@/components/ui/dialog` has no `DialogRoot` export, namespace types like `ChatMessage`/`SwarmSession`/`AgentPersona` used as values, missing modules `@/hooks/use-agent-view`, `@tanstack/react-router`. These components are NOT used by any active page — they are drained reference code. **Fix:** either fix the imports to match actual shadcn/ui exports, or remove the directory.

**CRITICAL — Chat path is non-functional end-to-end:**

8. **Chat payload shape rejected by paired backend schema** — `ARES-Mac_os/Sources/ARESCore/Conversation/FastAPIProvider.swift:18`. `FastAPIProvider` POSTs `{model, messages[], temperature, session_id}` to `/api/sam-conversation/chat`, but the paired `ChatStart` Pydantic schema (`extra='forbid'`, `strict=True`) requires a singular `message` string and forbids `messages`/`temperature` as extra fields. Every call gets HTTP 422. **Fix:** align the Swift payload with the Python schema, or vice versa.

9. **Chat/compress endpoints are hardcoded stubs, already wired live** — `webui/fastapi_app/routers/sam_conversation.py:12`. `/chat` and `/compress` handlers return hardcoded canned responses (`"Inference task received"`, a fixed success message) instead of performing real inference. `ConversationManager.swift` defaults to `FastAPIProvider()` as its `AIProviderProtocol` — every user prompt returns the literal placeholder string. `/compress` returns a canned success without calling the existing `webui/fastapi_app/memory/compressor.py`. **Fix:** replace stubs with real logic, or explicitly gate the feature as unavailable per the "must degrade honestly" rule.

10. **New mutating endpoints skip CSRF/owner-scope checks** — `webui/fastapi_app/routers/sam_conversation.py:25`. Both new POST endpoints use `require_identity` instead of `require_mutation_identity` (the CSRF-protecting dependency every other mutating router uses), and neither wraps logic in `profile_scope(identity.profile)`. Sibling routers `memory.py`, `secrets.py`, `settings.py`, `controls.py` all use `require_mutation_identity` + `profile_scope(...)`. **Fix:** switch to `require_mutation_identity` + `profile_scope`.

**CRITICAL — Backend gaps:**

11. **`ares-agent` package not installed** — `webui/api/chat_runtime.py` references `ares_agent` which is not installed. The current chat path bypasses it. **Fix:** either install the package or remove the dependency.

12. **`/api/connections/verify` hangs** — It tries to test all adapters including grok/pi which hang. **Fix:** add per-adapter timeouts (15s max) and a skip-list for known-slow adapters.

13. **Settings not persisted** — `~/.ares/settings.json` does not exist. Discovered adapters and user preferences are not saved across restarts. **Fix:** create `~/.ares/settings.json` on first run, save discovered adapters under a `connections` key, load on startup. `webui/api/config.py` already has `save_settings`/`load_settings` — ensure `connections` is in the allowed keys list.

14. **Chat backend selector not wired to discovery** — `ConversationPage.tsx` has a backend selector but it's hardcoded, not populated from `/api/discover/frameworks`. **Fix:** fetch discovery on mount, populate dropdown, pass selected `adapter_id` through `sendMessage` → `startChat` → WebSocket.

**HIGH — Swift bugs (pre-existing, not from this session):**

15. **Documented cross-conversation isolation isn't enforced** — `ARES-Mac_os/Sources/ARESCore/MCP/Internal/ReadToolResultTool.swift:130`. The tool's docstring promises "Cross-conversation access is denied," but `conversationId` is fetched from context and then never passed into `storage.retrieveChunk`. `ToolResultStorage` keys purely off `toolCallId` with no conversation scoping. Any conversation that learns another's `toolCallId` can retrieve its persisted tool output. **Fix:** thread `conversationId` through `ToolResultStorage` to enforce the documented guarantee.

16. **Out-of-range offset traps instead of throwing** — `ARES-Mac_os/Sources/ARESCore/MCP/Internal/ToolResultStorage.swift:89`. `retrieveChunk` clamps `startIndex` but computes `endIndex` using the unclamped `offset`, going negative when `offset` exceeds string length and fatally trapping. `ToolResultStorageError.invalidOffset` exists but is never thrown on this path. **Fix:** clamp `offset` before computing `endIndex`.

17. **`Equatable` on `RiseAndSetEvent` ignores subclass state** — `ARES-Mac_os/Sources/ARESCore/Astronomy/RiseAndSet.swift:28`. `static func ==` only compares base-class stored properties; Swift operators can't be overridden by subclasses. Two different subclass instances with matching base fields compare `==` true. **Fix:** include a type-check or dynamic-type dispatch in the equality operator.

18. **Default-location weather fallback silently dropped** — `ARES-Mac_os/Sources/ARESCore/MCP/Tools/WeatherTool.swift:129`. The fallback to `LocationManager.shared.getEffectiveLocation()` was deleted from `resolveLocation()`, but the error message still tells users to "configure location in SAM Preferences." **Fix:** restore the default-location fallback.

19. **`ExecutionRequest` context silently defaults to `/`** — `ARES-Mac_os/Sources/ARESCore/Models/ExecutionBackendModels.swift:154`. `ConversationContext` gained a no-arg initializer defaulting `workingDirectory` to `"/"`. A caller constructing `ExecutionRequest` without an explicit context silently operates against filesystem root. **Fix:** remove the no-arg default or make it explicitly safe.

**HIGH — AI adapter gaps:**

20. **Gemini has no working auth** — The `gemini` CLI is installed but fails with "Please set an Auth method." The OAuth token in `~/.gemini/oauth_creds.json` is not a valid API key. The `gemini_cloud` adapter exists at `webui/api/backends/gemini_cloud.py` but needs a `GEMINI_API_KEY` in ARES secrets. The `gemini_antigravity` adapter needs macOS Accessibility permission for AppleScript.

21. **Duplicate adapters always fake "connected" health** — `webui/fastapi_app/adapters/hermes_local.py:12` and `ollama_local.py`. New `HermesLocalAdapter`/`OllamaLocalAdapter` duplicate the `adapter_id` of already-registered, fully-functional adapters in `frameworks.py`, but `check_health()` is hardcoded to always report `state='connected'` with no real reachability probe. Currently unregistered, but share `adapter_id` strings — wiring them in would silently replace real health logic with always-"connected" stubs. **Fix:** remove the duplicate files or properly wire them without shadowing the real adapters.

**MEDIUM — Adapter issues:**

22. **Ollama direct API times out** — `kai:latest` and `qwen3.6:35b-mlx` are too large for this hardware. The adapter code is correct and universal — it will work on faster machines or with smaller models. The verify endpoint should report "timed out" instead of hanging.

23. **Grok requires a TTY** — `grok` CLI fails with "Device not configured" in headless mode. Needs a PTY or cloud API fallback.

24. **Pi has wrong default model** — `pi` CLI defaults to `glm-4.7-flash` which is not installed. Should default to `kai:latest`.

25. **Cursor not installed** — `/Applications/Cursor.app` does not exist. The `cursor_app` adapter should not claim availability.

**LOW:**

26. **92 uncommitted files** — The user has active VS Code work in progress. Do not commit, stage, or modify these files unless explicitly fixing a finding above.

27. **TODO/FIXME/HACK markers** — Scattered through `webui/api/` and `webui/fastapi_app/`. Should be audited and resolved.

---

## PHASED PLAN

### Phase 1: Unblock the Build (do this first — nothing else matters until the frontend builds)

1. **Fix `router.ts` duplicate export** — Remove the duplicate `useNavigate` export at line 36. This alone blocks the entire build.

2. **Fix `CompanyContext` import path** — Point all 56 page imports and 23 component imports at `DomainContext.tsx`, or rename/relocate `DomainContext` to match the `CompanyContext` import path. Verify with `grep -rl 'CompanyContext' src/` → zero results.

3. **Fix `apiFetch` imports** — In `execution-workspaces.ts` and `pipelines.ts`, change `import { apiFetch } from './client'` to `import { apiFetch } from '@/shared/api-client'`.

4. **Restore shadowed real components** — Repoint imports of `AgentConfigForm`, `MarkdownBody`, `MarkdownEditor`, `InlineEntitySelector`, `SystemNotice`, `ExternalObjectPill` to `components/paperclip/*` and delete the no-op stub files. Do not flesh out the stubs — the real components already exist.

5. **Fill in `agentsApi` stub** — Implement every method the pages actually call, or generate/derive from the real backend contract. Audit other new `api/*.ts` files the same way.

6. **Remove `@ts-nocheck`** — From `Workflows.tsx`, `WorkflowSettings.tsx`, `TeamCatalog.tsx`, `UserProfile.tsx`, `WhatNeedsMe.tsx`, `Workspaces.tsx`. Only do this after fixing the underlying stub types.

7. **Fix or remove drained hermes-workspace components** — Fix import paths to match actual shadcn/ui exports, or remove the directory since these are reference components not used by any active page.

8. **Verify** — Run `npx tsc --noEmit` → zero errors. Run `npm run build` → passes.

### Phase 2: Fix the Chat Path End-to-End

1. **Align Swift↔Python chat contract** — Fix `FastAPIProvider.swift` payload to match `ChatStart` schema, or vice versa. Verify no 422 errors.

2. **Replace hardcoded chat/compress stubs** — In `sam_conversation.py`, replace canned responses with real inference logic, or explicitly gate the feature as unavailable. For compress, call the existing `webui/fastapi_app/memory/compressor.py`.

3. **Add CSRF/owner-scope checks** — Switch `sam_conversation.py` endpoints from `require_identity` to `require_mutation_identity` + `profile_scope(identity.profile)`.

4. **Wire the backend selector** — In `ConversationPage.tsx`, fetch `/api/discover/frameworks` on mount and populate the dropdown. Pass the selected `adapter_id` through `sendMessage` → `startChat` → WebSocket.

5. **Fix the verify endpoint** — In `webui/api/backend_verification.py`, add per-adapter timeouts (15s max) and skip adapters that are known to hang. Return honest status: "responded in 3s", "timed out", "needs API key", "needs Accessibility permission".

6. **Persist settings** — Create `~/.ares/settings.json` on first run. Save discovered adapters under a `connections` key. Load on startup. Ensure `connections` is in the allowed keys list in `webui/api/config.py`.

7. **Fix `ares_agent` dependency** — Either install the package or remove the reference from `chat_runtime.py`.

### Phase 3: Fix Swift Bugs

1. **Enforce cross-conversation isolation** — Thread `conversationId` through `ToolResultStorage.retrieveChunk` and check it against the stored metadata.

2. **Fix out-of-range offset trap** — Clamp `offset` before computing `endIndex` in `ToolResultStorage.retrieveChunk`. Throw `ToolResultStorageError.invalidOffset` instead of trapping.

3. **Fix `RiseAndSetEvent` Equatable** — Add type-check or dynamic-type dispatch to the equality operator.

4. **Restore weather default-location fallback** — Re-add the `LocationManager.shared.getEffectiveLocation()` call in `WeatherTool.resolveLocation()`.

5. **Fix `ConversationContext` default** — Remove the no-arg initializer or make `workingDirectory` default to something explicitly safe.

### Phase 4: Complete the AI Adapter Layer

1. **Gemini cloud adapter** — The code exists at `webui/api/backends/gemini_cloud.py`. It reads `GEMINI_API_KEY` from env or ARES secrets. Add a UI field for the API key in the adapter config. Test with a real key.

2. **Gemini Antigravity adapter** — Build `ARES-Automation.app` — a tiny macOS app that owns Accessibility permission and exposes a local HTTP endpoint. ARES POSTs prompts to it, it runs AppleScript to type into Antigravity IDE. Add a permission-request flow in the UI.

3. **Fix Pi adapter** — Change default model from `glm-4.7-flash` to `kai:latest` in the discovery scanner.

4. **Fix Grok adapter** — Either add PTY support to the CLI backend (already partially implemented with `needs_tty` flag) or add a `grok_cloud` adapter using xAI API.

5. **Remove duplicate adapter files** — Delete or properly wire `webui/fastapi_app/adapters/hermes_local.py` and `ollama_local.py` without shadowing the real adapters in `frameworks.py`.

6. **Mark unavailable adapters honestly** — Cursor is not installed → don't claim it. OpenCode has no CLI → mark as app-automation-only. Ollama times out on current models → mark as "model too large for this hardware, try a smaller model."

### Phase 5: Production Hardening

1. **Health checks** — Add `/api/health` response that includes adapter status, disk space, memory usage.

2. **Graceful shutdown** — Handle SIGTERM/SIGINT in the FastAPI server. Close WebSocket connections cleanly.

3. **Crash restart** — Ensure the `launchctl` plist has `KeepAlive` set to true.

4. **Release checklist** — Create a script or document: build app → run tests → verify chat → verify adapters → commit → push.

### Phase 6: Drain and Close Reference Sources

1. Audit each reference source directory. Identify any code not yet ported.
2. Port remaining useful patterns (especially Paperclip's agent config UI and chat streaming).
3. Add a README to each drained directory noting what was ported and where.
4. Do not delete directories without explicit user approval.

---

## RULES

- **Do not touch uncommitted user files** unless explicitly fixing a finding listed above. There are 92 modified files from the user's VS Code session.
- **Do not delete reference_sources/.**
- **Do not rebrand things as "ARES LLM".**
- **Do not use Hermes as the universal proxy for all adapters.** Each adapter uses its own native CLI/API.
- **Adapter naming is flat:** `{name}_{deployment}` (hermes_local, claude_local, gemini_cloud, etc.).
- **Match the Graphite palette exactly.** No new colors.
- **Use framer-motion spring physics.** No linear transitions.
- **Push to `wip/odysseus-import`.** Commit messages should be descriptive.
- **Ask for API keys or signing details only when genuinely blocked.**
- **Follow the suggested fix order.** Phase 1 unblocks everything else — do it first.

---

## KEY FILES TO READ FIRST

1. `webui/frontend/src/lib/router.ts` — duplicate export (finding 1)
2. `webui/frontend/src/stubs.d.ts` — ambient CompanyContext declaration (finding 2)
3. `webui/frontend/src/context/DomainContext.tsx` — real context to point imports at (finding 2)
4. `webui/frontend/src/components/AgentConfigForm.tsx` — no-op stub shadowing real component (finding 3)
5. `webui/frontend/src/components/paperclip/AgentConfigForm.tsx` — real working component (finding 3)
6. `webui/frontend/src/api/agents.ts` — incomplete stub (finding 4)
7. `webui/frontend/src/api/execution-workspaces.ts` — broken apiFetch import (finding 5)
8. `webui/api/ai_framework_discovery.py` — adapter scanner
9. `webui/api/backends/cli_backends.py` — per-tool CLI invocation patterns
10. `webui/api/backends/gemini_cloud.py` — direct Gemini cloud adapter
11. `webui/frontend/src/pages/ConversationPage.tsx` — chat UI
12. `webui/frontend/src/shared/ares-context.tsx` — sendMessage wiring
13. `webui/api/chat_runtime.py` — chat worker selection (ares_agent dependency)
14. `webui/api/config.py` — settings persistence
15. `webui/fastapi_app/routers/sam_conversation.py` — hardcoded chat stubs + missing CSRF
16. `ARES-Mac_os/Sources/ARESCore/Conversation/FastAPIProvider.swift` — payload mismatch
17. `ARES-Mac_os/Sources/ARESCore/MCP/Internal/ReadToolResultTool.swift` — isolation not enforced
18. `ARES-Mac_os/Sources/ARESCore/MCP/Internal/ToolResultStorage.swift` — offset trap
19. `reference_sources/paperclip_drained/` — canonical adapter/chat patterns
20. `ARES-Mac_os/build-app.sh` — macOS app build script

---

## DELIVERABLES

1. Zero TypeScript errors. `npm run build` passes.
2. Swift build passes. `build-app.sh` produces ARES.app.
3. Backend starts cleanly. All module imports pass.
4. Chat UI shows discovered adapters in the backend selector.
5. Selecting an adapter routes messages to its native CLI/API.
6. `/api/connections/verify` returns honest per-adapter status without hanging.
7. Settings persist to `~/.ares/settings.json`.
8. Gemini works via cloud API or Antigravity automation.
9. All 5 Swift bugs fixed (findings 15-19).
10. All changes committed and pushed to `wip/odysseus-import`.
