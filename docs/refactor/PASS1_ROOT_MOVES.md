# Pass 1 — Root moves report

Branch: `refactor/move-only-folder-structure`  
Date: 2026-07-27

## Moves executed

| Original | New |
|----------|-----|
| `ARES-Mac_os/` | `apps/macos/` |
| `webui/frontend/` | `apps/web/` |
| `webui/` (remainder) | `services/controller/` |
| `observer/` | `services/observer/` |
| `docs/history/*` | `docs/archive/*` |

Empty husks removed (untracked only): `.gitkeep` skeleton trees under old `webui/api/*`, Swift Core placeholders, empty `attic/`, empty `docs/roadmap/`.

## Path repairs (content)

- `Package.swift` → `apps/macos/Sources/...`
- Root `start.sh` / `ctl.sh` → `services/controller/...`
- `install.sh`, `bin/ares`, CI workflows
- `services/controller/fastapi_app/frontend.py` default dist → `apps/web/dist`
- `WebUIServerManager` discovery prefers `services/controller` (legacy `webui` kept as fallback)
- Agent/docs pointers: `.claude/CLAUDE.md`, `docs/product/source-ownership.md`, `README.md` layout

## Verification

| Check | Result |
|-------|--------|
| `swift build` | pass |
| `swift test --filter WebUIServerManagerTests` | 9 passed |
| SI baseline via `services/controller/scripts/test.sh` | **128 passed** |
| Tracked file count | 1440 (no content deleted) |

## Not done yet (Pass 2+)

- Move real modules into `core/` and `integrations/`
- Internal Swift regroup by responsibility
- Frontend feature folders
- Full stale-path sweep of every markdown mention of `webui/` / `ARES-Mac_os/`
- Remove temporary legacy discovery paths after operators migrate

## Root now

```text
apps/ macos web
services/ controller observer
core/  integrations/   (README placeholders for Pass 2 — not empty package spam)
docs/ product architecture decisions guides archive refactor
TBR/
```
