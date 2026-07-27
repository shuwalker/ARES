# Prompt for the repository reorganization agent

Copy below into a fresh coding-agent session rooted at this repository.

---

You are reorganizing ARES into a coherent protocol-droid codebase.

ARES is the project/machine name. It hosts a continuous Companion relationship
(protocol-droid experience). Workers (models, tools, devices) are replaceable.
You reorganize **working** source. You do not freeze the product as unfinished.

## Task

**Move-only structural refactor.** Preserve behavior. Do not rewrite product logic.

## Read first

1. `docs/refactor/FOLDER_STRUCTURE.md` (target tree)
2. `docs/refactor/MOVE_ONLY_REFACTOR_OUTLINE.md`
3. `docs/refactor/MOVE_MAP.tsv`
4. `TBR/README.md`
5. `.claude/FOUNDATION.md` and `docs/product/product-vision.md`
6. `docs/architecture/RUNTIME.md` and `docs/decisions/`

## Non-negotiable

- `git mv` only for tracked moves; no content deletes
- TBR for material leaving the active tree: `TBR/<batch>/<original/path>`
- Record every move in `MOVE_MAP.tsv` and TBR rows in `TBR/MANIFEST.tsv`
- No empty `.gitkeep` destination trees
- Only path/import/build/CI/docs-link repairs (+ temporary import bridges)
- No schema/API/symbol renames; no duplicate consolidation in move pass
- Stop rather than guess ownership

## Current target roots (use these names)

| Role | Path |
|------|------|
| Mac app | `apps/macos/` |
| React UI | `apps/web/` |
| Controller | `services/controller/` |
| Observer | `services/observer/` |
| Companion core (next) | `core/` |
| Integrations (next) | `integrations/` |
| Docs | `docs/product`, `architecture`, `decisions`, `guides`, `archive` |
| Quarantine | `TBR/` |

Retired names: `webui/`, `ARES-Mac_os/`, `observer/` at repo root, empty `attic/`.

## Workflow

1. Baseline (`git status`, tracked list, SHA-256 outside repo)
2. Propose MOVE_MAP rows for the batch
3. `git mv` + path repairs only
4. Search stale paths
5. Run focused verification (`services/controller/scripts/test.sh` for Python;
   `swift build` for Mac; `apps/web` typecheck/build when frontend moves)
6. Update manifests; only then next batch

## Next work after root renames

Fill `core/` and `integrations/` by moving real modules from
`services/controller/api/` (si, journal, backends, providers, …) and
regroup real Swift sources under `apps/macos/Sources/ARESCore/` by responsibility.

## Success

Tree communicates protocol-droid ownership. Every capability, contract, license,
test, and recovery path remains intact. No junk empty folders. No deleted history.
