# ARES Reference-Source Drain Log

Phase 6 was completed on 2026-07-18. The four source snapshots under
`reference_sources/` and the unused `frontend/src/**/drained/hermes-workspace`
tree were reviewed before removal. Active code does not import either tree.

## Patterns retained in ARES

| Reference pattern | Active ARES implementation |
| --- | --- |
| Framework-neutral runtime and tool adapter registry | `webui/fastapi_app/adapters/`, `webui/api/backends/` |
| Explicit runtime selection, separate from model provider | `webui/fastapi_app/schemas.py`, `webui/fastapi_app/realtime.py`, `webui/frontend/src/shared/ares-api.ts` |
| Profile-scoped credential resolution and least-privilege child environments | `webui/fastapi_app/adapters/registry.py`, `webui/fastapi_app/adapters/frameworks.py`, `webui/api/backends/cli_backends.py` |
| Durable stream journal, event cursor, terminal cleanup, and malformed-frame tolerance | `webui/api/run_journal.py`, `webui/fastapi_app/routers/realtime.py`, `webui/frontend/src/shared/chat-stream.ts` |
| Native incremental stream parsing and cancellation | `ARES-Mac_os/Sources/ARESCore/Conversation/FastAPIProvider.swift` |
| Actor/lock-style cross-conversation result isolation | `ARES-Mac_os/Sources/ARESCore/MCP/Internal/ToolResultStorage.swift` |
| Recoverable UI error boundary | `webui/frontend/src/main.tsx` |
| Connection/model selection, schedules, channels, skills, secrets, activity, external-backend inventory, and collaborative board surfaces | `webui/frontend/src/pages/` |
| Paperclip route, form, metric-card, and resource-management patterns | Ported into the reachable ARES pages and components under `webui/frontend/src/` |
| ARES-owned schedule persistence and execution, protected from top-level package shadowing | `webui/api/schedule_jobs.py`, `webui/api/schedule_scheduler.py` |
| ARES-owned skill discovery and profile resource isolation | `webui/api/skill_resources.py`, `webui/api/skills_store.py`, `webui/api/profiles.py` |
| Local inference/resource-planning concepts from Colibri | Existing ARES inference subsystem under `ARES-Mac_os/Sources/ARESCore/Inference/` |

## Intentionally not copied

- Parallel application shells, duplicate state stores, and duplicate routers.
- Reference-only database schemas that do not match ARES persistence contracts.
- Alternative terminal, SSH, and gateway owners that would create a second
  runtime authority.
- Unwired translations and presentation-only components without an active ARES
  product contract.
- The unreachable imported Paperclip UI/support tree. It required 2,295
  TypeScript suppression directives and 64 `null` runtime exports but was not
  reachable from `main.tsx` or any frontend test. The active 69-file graph now
  compiles in TypeScript strict mode with no suppressions.
- Colibri model-specific C/CUDA implementation and bundled binary assets; these
  do not fit the Swift/FastAPI inference boundary and carried separate licensing.

The deleted snapshots were named `paperclip_drained`, `hermes_web_drained`,
`hermes_desktop_drained`, and `colibri_drained` (the latter identified an Apache
2.0 license). No active build, test, or runtime path referenced them at removal.

The nested legacy snapshot formerly at
`ARES-Mac_os/Sources/HermesDesktop/reference_sources/` was also drained after
confirming the active Swift implementation was newer. It is recoverable from
`~/.Trash/ARES-HermesDesktop-reference_sources-20260718`. The unreachable
frontend import scaffold is recoverable from
`~/.Trash/ARES-unreachable-frontend-20260718`.

Two additional unowned TypeScript snapshots under `webui/api/` were also
removed: `paperclip_server/` (an alternative Node server) and `memory/` (an
unwired Bun memory service). Neither had a package manifest, build entry,
Python import, or runtime caller. ARES continues to own these contracts through
FastAPI and `webui/api/memory_store.py`. Both snapshots are recoverable from
`~/.Trash/ARES-dead-typescript-services-20260718`.

## Second-pass verification

The production-hardening pass completed with these verification results:

- Backend repository sweep: 5,138 passed, 74 skipped, 1 expected failure, and
  2 expected passes. The sweep exposed one order-dependent session update
  failure caused by process-global provider state.
- Session-lane fix: provider-prefixed model IDs are now normalized
  deterministically during persistence. The focused model/session set passed
  90 tests, and the order-sensitive neighboring set passed 445 tests after the
  fix.
- Frontend: strict TypeScript/Vite production build passed (2,511 modules) and
  all 15 Vitest tests passed.
- Swift: all 25 package tests passed, including malformed/incremental SSE and
  conversation-scoped tool-result tests; `build-app.sh` produced and signed the
  36 MB `ARES.app` bundle.
- Repository integrity: `git diff --check` passed, and scans found no remaining
  reference-source directories, removed hybrid/Ares runtime classes, legacy
  cron imports, TypeScript suppression directives, or dead TypeScript API
  services.

The skipped backend tests are platform or optional-integration scoped: Windows
CDP/support, Linux `/proc` and terminal lifecycle checks, Playwright Chromium,
and external backend packages that are not installed in this macOS workspace.
They do not hide ARES-owned resource-plane tests. The frontend production build
still reports a non-fatal 589.56 kB main-chunk size warning.
