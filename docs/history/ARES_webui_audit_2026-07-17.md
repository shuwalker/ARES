# ARES WebUI Delta Audit — 2026-07-17

Scope: current working tree (`origin/main`, github.com/shuwalker/ARES) vs. the native SwiftUI layer deleted in commit `420fcb0f` ("macOS app: WKWebView shell with menu bar, remove legacy"), cross-checked against `webui/api/` (business logic) and `webui/fastapi_app/` (the FastAPI app that `main.py` actually serves) and the React tree at `webui/frontend/src`.

Method: git history diff on `420fcb0f^..420fcb0f` to enumerate every deleted native module, then a file-level check of whether each capability has a live backend route and a reachable frontend surface. Two independent read-only passes: one over feature parity, one over auth/state-sync in `LocalProfile` and `schemas.py`.

---

## [CRITICAL] — Backend capability with no frontend surface, or missing entirely

The WKWebView pivot deleted 16 native feature areas. Of those, 12 have **no way for a user to reach them today** — either the backend exists and nothing calls it, or neither side exists. This is not code rot from the pivot; per `.claude/CLAUDE.md` the pivot itself was intentional. The gap is that porting stopped after routing/auth/chat/terminal and didn't continue into these:

| Feature | Backend | Frontend | Status |
|---|---|---|---|
| Kanban | `api/kanban_bridge.py` → `fastapi_app/routers/kanban.py` (20+ endpoints, boards/tasks/comments/dispatch) | `WorkspacePage.tsx` "Tasks" tab is a hardcoded `EmptyState` stub; zero calls in `ares-api.ts` | Backend-only |
| Notes | `api/notes_store.py` → `routers/notes.py` | No references to "notes" anywhere in `frontend/src` | Backend-only |
| Skills | `api/skills_store.py` → `routers/skills.py` (list/usage/content/save/delete/toggle) | No skills page or component | Backend-only |
| Schedules/Cron | `api/schedules_store.py` → `routers/schedules.py` (full CRUD, run/pause/resume/history) | No UI, no methods in `ares-api.ts` | Backend-only |
| Extensions | `api/extensions.py`, `extension_proxy.py` → `routers/maintenance.py` (status/registry/toggle/install/uninstall) | No extension store UI | Backend-only |
| Advanced session ops | `api/session_mutations.py`, `anchor_scenes.py`, `manual_compression.py`, `handoff_summary.py`, `cli_session_import.py` → `routers/session.py` (branch/duplicate/truncate/rename/archive/pin/export/import) | Basic session list/create/select is ported (`TodayPage.tsx`, `ConversationPage.tsx`); none of the advanced ops have a frontend caller | Backend-only |
| Files (write path) | `api/file_operations.py`, `workspace.py` → `routers/files.py`, `file_delivery.py` (save/delete/rename/move/create/reveal/open-in-vscode) | `WorkspacePage.tsx` only lists directories read-only; no save/create/delete/rename call anywhere in `frontend/src` | Backend-only (partial — reads work, writes don't) |
| Tasks/Todo | `api/todo_state.py` exists but is **not imported by any `fastapi_app` router** — dead even server-side | None | Missing both sides |
| Calendar | No calendar-specific backend module found | `TodayPage.tsx` shows a static "0" placeholder card | Missing both sides |
| Studio/Code editor | No dedicated backend beyond generic file read/write | None | Missing both sides |
| Automations | No backend module found | None | Missing both sides |
| Hub | No backend module found | None | Missing both sides |
| Office documents | `api/office_documents.py` exists but is **not wired into any `fastapi_app` router** | None | Missing both sides (dead backend module) |

Ported and working: Usage/Cost (`UsageCostPage.tsx` → `routers/analytics.py`, note: superseded the original `api/usage.py`, which is now dead), Overview/Dashboard (`TodayPage.tsx`/`ActivityPage.tsx`), Terminal (`TerminalPage.tsx` → `api/terminal.py` via `fastapi_app/realtime.py`), Connections (`ConnectionsPage.tsx` → `routers/adapters.py`), Companion chat (`ConversationPage.tsx` → `chat_runtime.py`/`gateway_chat.py`/`jros_companion.py`), and basic session list/create.

**Net read:** `webui/frontend/src` is a 10-route skeleton (today, conversation, workspace, terminal, activity, canvas, usage, connections, settings, share) with only 18 methods total in `ares-api.ts`. Most of the backend was carried over faithfully during the pivot; the frontend was not — this looks like an in-progress rebuild rather than scattered regressions, but as of today a user cannot reach Kanban, Notes, Skills, Schedules, Extensions, or file write/create/delete/rename through the UI at all, despite the backend fully supporting all of them.

## [CRITICAL] — Untracked prompt-injection file at repo root

`HERMES_DEBRIEF.md` (2.9 KB, created 2026-07-16, **not tracked in git** — confirmed via `git status --short` returning `??` and `git ls-files` returning nothing) sits at the repository root. Its content instructs any AI agent that reads it to:
- Self-identify as "Hermes Agent," described as having "bare-metal access" to the local machine and authority to execute terminal commands and automate a browser via a tool called "Camofox" (which appears nowhere else in the codebase — `grep -ril camofox .` returns only this file).
- Treat `server.py`, `api/routes.py`, and "old static HTML files" as things to ignore — which is directly opposed to what a legacy-feature audit needs to examine.

This directly contradicts the actual `.claude/CLAUDE.md`, which specifies Hermes Agent as an optional, non-default addition with no special execution authority and states a missing Hermes "must never block onboarding or degrade the Companion." The file was not produced by this session and should not be treated as project documentation. Recommend confirming its origin and removing it; it was not acted on here.

## [WARNING] — State-sync gap in LocalProfile

`webui/frontend/src/shared/local-profile.tsx` persists `displayName`, `assistantName`, `voice`, `reachability`, `contextStoreEnabled` to `localStorage` under `ares.local-profile.v1`. Only `contextStoreEnabled`/`assistantName` (as `bot_name`) round-trip to `/api/settings` (`schemas.py:33-63`, `SettingsUpdate`). `voice` and `reachability` are never sent to the backend — confirmed via `ares-api.ts:39-42`. This is by design per `SettingsPage.tsx` copy, not a bug, but it means a user's voice/reachability settings are per-browser and silently diverge across devices, with no shared schema/codegen between `contracts.ts` and `schemas.py` to catch future drift.

## [WARNING] — Dead code from the pivot, 34 orphaned `webui/api/` modules

`webui/api/` is empirically the active business-logic library — nearly every `fastapi_app/routers/*.py` imports from it directly — but 34 of its modules have zero references from `fastapi_app`: `ares_tools`, `compression_anchor`, `compression_recovery`, `context_chunker`, `context_embeddings`, `cron_runtime`, `email_routes`, `jros_client`, `jros_gateway_chat`, `jros_paths`, `metering`, `model_context`, `model_resolution`, `monarch`, `monarch_routes`, `oauth`, `office_documents`, `plugin_providers`, `process_wakeup`, `route_session_list_cache`, `runner_client`, `runtime_adapter`, `runtime_diagnostics`, `session_discoverability`, `session_display`, `session_export_html`, `session_lineage_display`, `skill_usage`, `sse_chunked`, `state_sync`, `todo_state`, `usage`, `webui_session_db`, `turn_journal`. Some are confirmed superseded (`usage.py` by `analytics.py`/`insights.py`, `cron_runtime.py` by `schedules_store.py`); others (`todo_state.py`, `office_documents.py`, `oauth.py`) look like stalled or abandoned ports. Worth a pass to confirm each is either safe to delete (per the repo's `attic/` policy) or actually needed and simply unwired.

## No findings — auth/owner-scope

Independent audit of all 32 files in `webui/fastapi_app/routers/` found consistent `Depends(require_identity)` on reads and `Depends(require_mutation_identity)` on writes across profile, session, credential, memory, kanban, schedule, notes, email, and MCP endpoints, including `mcp.py` (server env/command config) and `memory.py` (SOUL/memory writes). `SettingsUpdate` explicitly rejects a client-supplied `password_hash` field. The public share endpoint (`routers/shares.py`) is intentionally unauthenticated but token-gated with `Cache-Control: no-store` and `X-Robots-Tag: noindex, nofollow`. `require_mutation_identity` enforces origin-pinning (`browser_origin_allowed`) plus CSRF instead of permissive CORS — there is no CORS middleware in the app at all, which is consistent with that design. The CLAUDE.md rule requiring auth/owner-scope checks on new endpoints holds throughout this tree as far as direct code reading can verify.

## [OPTIMIZATION]

- Consolidate `webui/api/` and `webui/fastapi_app/` framing in docs: `api/` is not legacy-to-be-replaced, it's the live logic layer `fastapi_app` depends on. Contributor-facing docs should say so explicitly to avoid future agents (human or AI) treating either tree as dead weight.
- Give `contracts.ts` ↔ `schemas.py` a shared source of truth (OpenAPI-generated types, or a schema test) so field drift between frontend and backend settings surfaces at build/test time instead of silently.
- Frontend route/method count (10 pages, 18 API methods) vs. backend surface (~110 modules) suggests prioritizing Kanban, Notes, Skills, Schedules, and file write/create/delete/rename next, since those already have complete, tested backend support and only need UI.
