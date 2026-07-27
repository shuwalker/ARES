# Repository folder structure (target = current direction)

This is the **protocol-droid layout**. Roots are product surfaces, not fork history names.

## Repository root

```text
ARES/
├── apps/
│   ├── macos/                 # native Mac product (was ARES-Mac_os)
│   └── web/                   # React UI (was webui/frontend)
├── services/
│   ├── controller/            # FastAPI + api + tests (was webui without frontend)
│   └── observer/              # optional observation service
├── core/                      # Companion control-plane modules (fill by moving real code)
├── integrations/              # workers / tools / sensors / providers (fill next)
├── docs/
│   ├── product/
│   ├── architecture/
│   ├── decisions/
│   ├── guides/
│   ├── archive/               # historical material
│   └── refactor/              # this process
├── TBR/                       # quarantine; nothing deleted
├── bin/                       # CLI entry
├── config/                    # public examples
├── scripts/                   # repo ops
├── tools/                     # standalone utilities
├── Package.swift              # paths → apps/macos/...
├── start.sh, ctl.sh, install.sh, uninstall.sh
├── README.md, LICENSE, VERSION, CONTRIBUTING.md, CLAUDE.md
├── .claude/, .github/
```

## What is not the product layout

| Path | Role |
|------|------|
| `TBR/` | Quarantine of moved-out material |
| `docs/refactor/` | Reorganization process only |
| `docs/archive/` | Historical docs |
| local `.venv`, `node_modules`, `.build`, app bundles | Generated; not structure |

## Pass status

| Area | Status |
|------|--------|
| `apps/macos` | **Moved** from `ARES-Mac_os` |
| `apps/web` | **Moved** from `webui/frontend` |
| `services/controller` | **Moved** from remainder of `webui` |
| `services/observer` | **Moved** from `observer` |
| `core/si`, `core/memory/*`, `core/events/*`, `core/authority/*`, `core/knowledge/*` | **Moved** (api.* shims remain) |
| `integrations/workers`, `providers`, `tools/adapters` | **Moved** (api.* shims remain) |
| Empty `.gitkeep` shells | **Removed** (not structure) |

## Rules

1. Do not create empty destination folders as a substitute for moves.
2. Move with `git mv`; quarantine with `TBR/`; no content deletes.
3. Path repairs only in move batches (imports, wrappers, CI, Package.swift, frontend root).
4. Old names `webui/` and `ARES-Mac_os/` are retired from the active tree.

## Root first principles (2026-07-27)

Keep at repository root only what the product or tooling requires:

- `apps/`, `services/`, `core/`, `integrations/`, `docs/`
- `Package.swift`, licenses, README/INSTALL/CONTRIBUTING, VERSION
- Thin operator wrappers: `start.sh`, `ctl.sh`, `install.sh`, `uninstall.sh`, `bin/ares`
- Agent/CI: `.claude/`, `.github/`
- `TBR/` — temporary quarantine (To Be Reviewed). **Not** auto-deleted.
  Deletion requires a separate, explicit human-approved task after review
  (see `TBR/README.md`). Agents must never delete TBR content.

Moved to TBR (not required at root): former `scripts/`, `tools/` (except
ownership check → `.github/scripts/`, and `si_doctor` restored under
`services/controller/scripts/`), `config/` examples.
