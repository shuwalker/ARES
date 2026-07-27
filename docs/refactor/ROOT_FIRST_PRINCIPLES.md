# Root first principles

**Policy:** If it is not required to run, build, license, or enter the product, it does not stay at the repository root. Non-essential material goes to `TBR/` and may be deleted after full testing.

## What stays at root (required)

| Path | Why |
|------|-----|
| `apps/`, `services/`, `core/`, `integrations/` | Product code |
| `docs/` | Current product/runtime truth + archive/refactor notes |
| `Package.swift` | SwiftPM root |
| `start.sh`, `ctl.sh`, `install.sh`, `uninstall.sh`, `bin/ares` | Operator entry |
| `README.md`, `INSTALL.md`, `CONTRIBUTING.md`, `LICENSE`, `COMMERCIAL-LICENSE.md`, `VERSION`, `CONTRIBUTORS.md` | Entry + legal |
| `CLAUDE.md`, `.claude/`, `.github/` | Agents + CI |
| `TBR/` | Temporary quarantine only |

## Moved to TBR (not required at root)

Batch `TBR/20260727-root-ops-tbr/`:

| Was | Contents |
|-----|----------|
| `scripts/` | si_doctor, smoke_si_init, talk_ares, update helpers |
| `tools/` | email_ai_assistant (+ tools CLAUDE) |
| `config/` | ports/providers **examples** only |

**Exception:** `check-source-ownership.sh` is still used by CI → `.github/scripts/check-source-ownership.sh`.

## After tests pass

`TBR/` may be reviewed for future removal only with **explicit human approval**
and a dedicated task. Reorganization agents must not delete TBR content.
Status `approved_for_future_removal` in the manifest is still not agent
permission to delete (see `TBR/README.md`).
