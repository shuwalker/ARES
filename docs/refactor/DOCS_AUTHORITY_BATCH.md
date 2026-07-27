# Documentation Authority Batch — Dependency Map

Batch ID: `20260727-docs-authority`  
Status: **executed and verified**  
Depends on: Phase 0 baseline (`BASELINE.md`)

## Goal

Separate current product/runtime truth from historical, time-bound, and
conflicting prose so a new agent can identify authority without reading status
checkboxes or superseded architecture proposals.

## Authority model (target)

| Role | Location after batch |
| --- | --- |
| Product definition | `.claude/FOUNDATION.md` + `docs/product/*` |
| Runtime how-it-works | `docs/architecture/RUNTIME.md` + ADRs in `docs/decisions/*` |
| Architecture models (contracts) | `docs/architecture/*` (non-historical) |
| Operator / user guides | `docs/guides/*` |
| Agent instructions | `.claude/CLAUDE.md`, `.claude/webui/*`, root/component `CLAUDE.md` pointers |
| Refactor process | `docs/refactor/*` |
| Point-in-time history | `docs/history/*` |
| Quarantine (not current truth) | `TBR/20260727-docs-authority/<original/path>` |

## Classification summary

### Stay current (no move in this batch)

| Path | Why |
| --- | --- |
| `.claude/FOUNDATION.md` | Canonical product ownership (later framing edit only if needed) |
| `.claude/CLAUDE.md`, `.claude/webui/CLAUDE.md`, `.claude/webui/AGENTS.md` | Live agent entry points |
| `.claude/webui/ARCHITECTURE.md`, `.claude/TESTING.md` | Load-bearing architecture/verification (link repairs below) |
| `docs/architecture/RUNTIME.md` | Canonical runtime |
| `docs/architecture/PRODUCT_SURFACES.md` | UI domain authority |
| `docs/architecture/SYSTEM_BOUNDARIES.md` | SI ownership boundaries; referenced by `webui/api/si/__init__.py` |
| `docs/architecture/WORKER_ADAPTER_CONTRACT.md` | Worker contracts; code comments reference |
| `docs/architecture/TRUST_AND_PRIVACY_MODEL.md` | Trust model; PRODUCT_SURFACES links |
| `docs/architecture/MEMORY_AND_CONTEXT_MODEL.md` | Memory model; SI package docstring |
| `docs/architecture/ORCHESTRATION_MODEL.md` | Orchestration model; SI package docstring |
| `docs/refactor/*` | This process |
| Root `README.md`, `CONTRIBUTING.md`, licenses | Operator entry |

### Proposed active-tree regroup (git mv)

| Original | Destination | Risk |
| --- | --- | --- |
| `docs/product-vision.md` | `docs/product/product-vision.md` | low — few links |
| `docs/source-ownership.md` | `docs/product/source-ownership.md` | low — agent prompt + index |
| `docs/companion-journal.md` | `docs/guides/companion-journal.md` | low |
| `docs/advanced-chat-setup.md` | `docs/guides/advanced-chat-setup.md` | low |
| `docs/provider-registry.md` | `docs/guides/provider-registry.md` | low |
| `docs/architecture/decisions/0001-subprocess-workers.md` | `docs/decisions/0001-subprocess-workers.md` | medium — ADR cross-links |
| `docs/architecture/decisions/0002-two-store-model.md` | `docs/decisions/0002-two-store-model.md` | medium |
| `docs/architecture/decisions/0003-read-only-means-no-write-back.md` | `docs/decisions/0003-read-only-means-no-write-back.md` | medium |
| `docs/architecture/decisions/0004-translator-layer.md` | `docs/decisions/0004-translator-layer.md` | medium |
| `docs/architecture/decisions/0005-sse-streaming.md` | `docs/decisions/0005-sse-streaming.md` | medium |
| `docs/architecture/decisions/README.md` | `docs/decisions/README.md` | medium |
| `docs/architecture/ARES_SI_AUDIT.md` | `docs/history/ARES_SI_AUDIT.md` | low — audit snapshot |
| `docs/upstream-sync-2026-07-12.md` | `docs/history/upstream-sync-2026-07-12.md` | low — FORK_CHANGES cites it |
| `docs/ares-today-dashboard-design-memo.md` | `docs/history/ares-today-dashboard-design-memo.md` | low — already marked historical |

### Proposed TBR quarantine

| Original | TBR path | Reason |
| --- | --- | --- |
| `docs/si-disabled.md` | `TBR/20260727-docs-authority/docs/si-disabled.md` | Time-bound runtime switch notes; not product definition |
| `docs/architecture/MULTIAGENT_REFACTOR.md` | `TBR/20260727-docs-authority/docs/architecture/MULTIAGENT_REFACTOR.md` | Conflicts with Companion/worker ownership in FOUNDATION |
| `docs/roadmap/ARES_IMPLEMENTATION_ROADMAP.md` | `TBR/20260727-docs-authority/docs/roadmap/ARES_IMPLEMENTATION_ROADMAP.md` | Phase checkboxes disagree with implemented SI modules |
| `docs/JAEGERAI-INTEGRATION.md` | `TBR/20260727-docs-authority/docs/JAEGERAI-INTEGRATION.md` | Status banner claims SI disabled / direct JROS as “current”; not safe as current integration guide without rewrite (rewrite is out of scope for move-only) |
| `.claude/PHASE3_MEMORY_AND_DELEGATION_PROPOSAL.md` | `TBR/20260727-docs-authority/.claude/PHASE3_MEMORY_AND_DELEGATION_PROPOSAL.md` | Explicitly unapproved proposal |

### Explicitly deferred (do not move in this batch)

| Path | Why defer |
| --- | --- |
| `docs/ui/glassmorphism-plan.md` | Referenced by live frontend (`island-backdrop.ts`, `assets/index.ts`, tests). Move only with coordinated comment/link repairs in a dedicated batch. |
| `webui/FORK_CHANGES.md` | Linked from root `README.md` as changelog; provenance document — keep path stable for now. |
| `.claude/ROADMAP.md` / `.claude/webui/ROADMAP.md` | Differ; mixed currency. Need human read before TBR. |
| Identical dual copies (`.claude` vs `.claude/webui` for `SPRINTS.md`, `BUGS.md`, `THEMES.md`) | Consolidation is a separate decision; move-only must not silently drop a discoverability path. |
| `.claude/webui/ARCHITECTURE.md` / `TESTING.md` location | Prefer **link repair** first (see below) rather than relocating agent-doc trees. |

## Link repairs required with this batch (content edits only)

These are path-dependent documentation fixes, allowed under move-only rules.

1. **Missing webui-root ARCHITECTURE/TESTING paths**  
   `webui/CONTRIBUTING.md` and `webui/docs/CONTRACTS.md` link to `webui/ARCHITECTURE.md` and `webui/TESTING.md`, which are **not tracked**. Actual files:
   - `.claude/webui/ARCHITECTURE.md`
   - `.claude/TESTING.md` (canonical verification; `.claude/webui/TESTING.md` is a short pointer)

   Repair: update those links to the real paths (or add thin pointer files at `webui/` — prefer updating links to avoid inventing new docs).

2. **After ADR move**  
   Update `docs/architecture/RUNTIME.md` decision links (`decisions/` → `../decisions/` or absolute-from-docs paths).  
   Update any ADR internal relative links to `../RUNTIME.md`.

3. **After product/guide moves**  
   Update `.claude/CLAUDE.md` link to `docs/product-vision.md` if present.  
   Update `docs/refactor/AGENT_PROMPT.md` / `REPOSITORY_INDEX.md` paths.  
   Update `webui/FORK_CHANGES.md` path to upstream-sync history location.

4. **After TBR moves**  
   Any remaining references should point at TBR paths or be rephrased as “historical; see TBR/…”. Do not leave silent 404s in current agent read lists.

## Known code references (must not break)

| Reference | File | Implication |
| --- | --- | --- |
| `docs/architecture/PRODUCT_SURFACES.md` | `webui/frontend/src/app-navigation.ts`, `App.tsx`, `library_store.py` | **Do not move** PRODUCT_SURFACES in this batch |
| `docs/architecture/SYSTEM_BOUNDARIES.md` (+ contracts) | `webui/api/si/__init__.py` | **Do not move** those five model docs |
| `docs/ui/glassmorphism-plan.md` | frontend island-backdrop + assets + tests | Defer |
| `webui/FORK_CHANGES.md` | `README.md` | Defer or repair README if moved |

## Verification plan for this batch (when executed)

```bash
# 1. Pure-move hash check for every git mv with no content change
# 2. Link/search gates
rg -n 'docs/product-vision\.md|docs/source-ownership\.md|docs/companion-journal\.md|docs/advanced-chat-setup\.md|docs/provider-registry\.md|docs/architecture/decisions/|docs/si-disabled|MULTIAGENT_REFACTOR|ARES_IMPLEMENTATION_ROADMAP|JAEGERAI-INTEGRATION|PHASE3_MEMORY' \
  --glob '!TBR/**' --glob '!**/node_modules/**' --glob '!**/.venv/**'

# 3. Confirm no tracked file disappeared
test "$(git ls-files | wc -l | tr -d ' ')" -eq 1440   # or +N if only untracked planning files were later added

# 4. Docs are not code — still re-run SI baseline if any non-doc path was touched
cd webui && ./scripts/test.sh tests/test_si_architecture.py tests/test_si_evaluator.py \
  tests/test_si_integration.py tests/test_si_orchestration.py \
  tests/test_run_journal.py tests/test_turn_journal.py \
  tests/test_context_store_retrieval.py tests/test_orchestrator_routes.py -q --tb=no

# 5. Manifests
# - every row status=done in MOVE_MAP.tsv
# - every TBR row in TBR/MANIFEST.tsv with restore_command
```

## Execution order (when approved)

1. Create destination directories with `.gitkeep` only if git requires (prefer `git mv` into new dirs).
2. Active regroup moves (product, guides, decisions, history).
3. Path repairs for those moves.
4. TBR moves + MANIFEST rows.
5. Link repairs for broken ARCHITECTURE/TESTING pointers.
6. Full verification + inverse rollback map appendix.

## Rollback

Inverse of `MOVE_MAP.tsv` for this batch_id: every `new_path` → `original_path` via `git mv`.  
TBR restore commands are recorded per row in `TBR/MANIFEST.tsv` at execution time.

## Execution result

- Tracked-file count remained 1,440 before adding the new planning artifacts.
- Source ownership check passed.
- Stale active-path scan passed after excluding TBR, refactor manifests, and
  immutable historical changelog text.
- Selected documentation, SI integration, architecture, run-journal, and
  turn-journal tests: 82 selected; the first run exposed one incorrect test-path
  repair. That repair was reverted because the test intentionally reads the
  separate WebUI component guide. The two focused documentation tests then
  passed.
- No tracked file was deleted.
