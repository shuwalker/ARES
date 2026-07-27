# Pass 3 — Documentation authority

Branch: `refactor/move-only-folder-structure`

## Goal

One place to find **current** product and runtime truth. Historical, phase, and
conflicting prose no longer sit beside it as if they were the definition.

## Current authority (active tree)

| Role | Path |
|------|------|
| Product definition | `.claude/FOUNDATION.md` + `docs/product/product-vision.md` |
| Docs map | **`docs/README.md`** (new) |
| Runtime | `docs/architecture/RUNTIME.md` (paths updated to apps/services/core) |
| Architecture models | `docs/architecture/*` + `docs/architecture/README.md` |
| ADRs | `docs/decisions/` |
| Guides | `docs/guides/` |
| Live UI design notes | `docs/ui/glassmorphism-plan.md` (status reframed; not a phase roadmap) |

## Quarantined this pass (`TBR/20260727-docs-authority-p3/`)

| Original | Reason |
|----------|--------|
| `.claude/ROADMAP.md` | Phase/migration-gate status language |
| `.claude/SPRINTS.md` | Sprint log |
| `.claude/BUGS.md` | Working bug list snapshot |
| `.claude/webui/ROADMAP.md` | Same for WebUI agent tree |
| `.claude/webui/SPRINTS.md` | Same |
| `.claude/webui/BUGS.md` | Same |
| `.claude/PHASE3_MEMORY_AND_DELEGATION_PROPOSAL.md` | Unapproved proposal (was ignored local file; now in TBR) |

Already in TBR from earlier: `si-disabled`, `MULTIAGENT_REFACTOR`, implementation roadmap, stale Jaeger integration status.

## Archive (unchanged set + README)

`docs/archive/` holds audits and memos. New `docs/archive/README.md` labels them non-current.

## Path / framing repairs

- `docs/architecture/RUNTIME.md` — `webui/` → `apps/web`, `services/controller`, `core`/`integrations`
- `.claude/FOUNDATION.md` — frontend path → `apps/web`
- `.claude/webui/AGENTS.md` — read list points at monorepo docs + controller docs
- `.claude/CLAUDE.md` — points at `docs/README.md`
- `docs/product/product-vision.md` — protocol-droid one-liner (still Companion/workers naming)
- Empty `docs/architecture/decisions/` husk removed (ADRs live in `docs/decisions/`)

## What agents should open first

1. `docs/README.md`
2. `.claude/FOUNDATION.md`
3. `docs/architecture/RUNTIME.md`
4. `docs/refactor/FOLDER_STRUCTURE.md` for code layout only

## Not done in Pass 3

- Rewriting every remaining `webui/` string inside large architecture model docs
- Removing TBR content
- Code moves (Pass 2 already placed core/integrations)
