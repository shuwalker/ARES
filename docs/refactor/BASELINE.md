# Move-Only Refactor — Phase 0 Baseline

Recorded: 2026-07-27T01:10:41Z  
Branch: `main`  
Commit: `e7e0633b113666a427c086438a5ed54adbef9091`  
Tracked files: **1440**

## Working tree at baseline

Untracked planning artifacts only (not yet in the 1440 tracked set):

- `docs/refactor/`
- `TBR/`

No tracked source was moved or modified for this baseline.

## Immutable hash manifest

Stored outside the repository (machine-local, not committed):

| File | Purpose |
| --- | --- |
| `/tmp/ares-refactor-baseline/tracked-paths.txt` | Full `git ls-files` list (1440 lines) |
| `/tmp/ares-refactor-baseline/sha256-manifest.txt` | SHA-256 of every tracked file |
| `/tmp/ares-refactor-baseline/entry-points.txt` | Entry-point summary |
| `/tmp/ares-refactor-baseline/created-at.txt` | UTC timestamp |

Re-create on another machine:

```bash
mkdir -p /tmp/ares-refactor-baseline
git ls-files > /tmp/ares-refactor-baseline/tracked-paths.txt
git ls-files -z | xargs -0 shasum -a 256 > /tmp/ares-refactor-baseline/sha256-manifest.txt
```

## Active entry points

| Boundary | Path |
| --- | --- |
| Swift package | `Package.swift` → targets `ARESCore`, `ARES`, `ARESNativeMCP`, `ARESTests` |
| Native app | `ARES-Mac_os/Sources/ARES/ARESApp.swift` |
| Native shared | `ARES-Mac_os/Sources/ARESCore/` |
| Native MCP | `ARES-Mac_os/Sources/ARESNativeMCP/main.swift` |
| Python HTTP | `webui/fastapi_app/main.py` (`create_app` / `app`) |
| React SPA | `webui/frontend/src/main.tsx` |
| Observer | `observer/observer.py` |
| Operator wrappers | `start.sh`, `ctl.sh`, `install.sh`, `bin/ares` |

## Baseline verification run

Command (from `webui/`, via `./scripts/test.sh`):

```text
tests/test_si_architecture.py
tests/test_si_evaluator.py
tests/test_si_integration.py
tests/test_si_orchestration.py
tests/test_run_journal.py
tests/test_turn_journal.py
tests/test_context_store_retrieval.py
tests/test_orchestrator_routes.py
```

Result:

```text
Running 128 items in this shard
128 passed in 33.51s
```

Matches the pre-index claim (128 passed in ~33.6s).

OpenAPI path-set capture was not taken in this baseline pass (FastAPI full boot not required for docs-only Phase 1 mapping). Capture it before Phase 4/5 transport moves.

## Excluded from move planning

Generated/local trees are not in the tracked set and must not be moved:

- `.build/`, `.venv/`, `node_modules/`, app bundles, caches, runtime DBs, built frontend output
- User credentials, profiles, model caches

## Phase 0 exit gate

- [x] Working tree understood
- [x] Tracked path list + SHA-256 manifest exported
- [x] Entry points recorded
- [x] Relevant baseline tests green
- [x] Generated/runtime paths excluded from move plan
