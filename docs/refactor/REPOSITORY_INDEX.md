# ARES Repository Index

Snapshot date: 2026-07-26

This index describes the tracked repository before the move-only
reorganization. It is an orientation map, not a claim that features are
unfinished or that the current directory layout is permanent.

## Product framing for the reorganization

- **ARES is the repository/project name.**
- The repository builds a modern protocol-droid platform.
- The intelligence presented to a person is user-named; it is not named ARES
  merely because this repository is.
- Existing models, agents, providers, tools, and device runtimes are
  replaceable components.
- Existing behavior is source material to preserve while the accidental
  structure and outdated framing are reorganized.

Some checked-in documents use different naming or time-bound phase/status
language. They remain part of the index so the reorganization can move them
deliberately rather than silently deleting history.

## Tracked inventory

The snapshot contains **1,440 tracked files**.

| Root | Tracked files | Primary role |
| --- | ---: | --- |
| `webui/` | 1,119 | Python controller, React application, tests, extensions, WebUI-specific documentation |
| `ARES-Mac_os/` | 222 | Swift application, shared native services, native MCP executable, Swift tests |
| `docs/` | 30 | Product, runtime, architecture, roadmap, history, and UI documents |
| `.claude/` | 17 | Agent instructions and the current internal product foundation |
| `observer/` | 11 | File, terminal, session, and Git observation service |
| `.github/` | 7 | Repository automation |
| `tools/` | 6 | Standalone utilities |
| `scripts/` | 5 | Repository-level operational scripts |
| `attic/` | 5 | Already-quarantined historical implementation |
| `config/` | 2 | Example configuration |
| root files and wrappers | 16 | Package manifest, install/start/control wrappers, licenses, contribution docs |

Dominant tracked file types:

| Type | Count |
| --- | ---: |
| Python | 907 |
| Swift | 198 |
| Markdown | 103 |
| TSX | 71 |
| TypeScript | 24 |
| JavaScript | 16 |
| Shell | 17 |

Generated and local directories such as `.build/`, `.venv/`, `node_modules/`,
application bundles, caches, runtime databases, and built frontend output are
not part of the tracked-source move plan.

## Active build and runtime boundaries

These boundaries must remain operational during reorganization.

| Boundary | Current entry point | Notes |
| --- | --- | --- |
| Swift package | `Package.swift` | Declares `ARESCore`, `ARES`, `ARESNativeMCP`, and `ARESTests` |
| Native application | `ARES-Mac_os/Sources/ARES/ARESApp.swift` | macOS lifecycle and product shell |
| Native shared code | `ARES-Mac_os/Sources/ARESCore/` | Contracts, services, voice, conversation, tools, models, utilities |
| Native MCP | `ARES-Mac_os/Sources/ARESNativeMCP/main.swift` | Exposes native capabilities |
| Python HTTP service | `webui/fastapi_app/main.py` | FastAPI application factory and router registration |
| Python product/runtime services | `webui/api/` | Persistence, sessions, workers, tools, SI/control logic, integrations |
| React application | `webui/frontend/src/main.tsx` | The only tracked web frontend |
| Frontend contracts | `webui/frontend/src/shared/` | ARES-owned shapes and translators |
| Observer | `observer/observer.py` | Optional observation process |
| Root operator commands | `start.sh`, `ctl.sh`, `install.sh`, `bin/ares` | Stable human/operator entry points |

## Current source composition

### Python and WebUI

| Area | Tracked files | Shape |
| --- | ---: | --- |
| `webui/tests/` | 615 | Large regression and contract suite |
| `webui/api/` | 231 | Broad, partly flat service/runtime namespace |
| `webui/frontend/` | 121 | React/TypeScript application |
| `webui/fastapi_app/` | 71 | FastAPI transport, routers, adapters, memory bridge |
| `webui/docs/` | 39 | Upstream/component documentation and RFCs |
| `webui/scripts/` | 10 | WebUI setup, test, and operational scripts |
| `webui/extensions/` | 4 | Extension packages |

Notable existing Python groups:

- `webui/api/si/`: identity, context, memory, trust, routing, planning,
  orchestration, evaluation, and response composition.
- `webui/api/journal/`: ARES-owned conversation/document index and importers.
- `webui/api/providers/`: worker/provider implementations.
- `webui/api/backends/`: execution backends and streaming bridges.
- `webui/api/research/`: reachable research service.
- `webui/fastapi_app/routers/`: approximately fifty transport modules organized
  mostly as a flat package.

### Native Swift

| Area | Tracked files |
| --- | ---: |
| `ARES-Mac_os/Sources/ARESCore/` | 179 |
| `ARES-Mac_os/Sources/ARES/` | 26 |
| `ARES-Mac_os/Tests/ARESTests/` | 10 |
| `ARES-Mac_os/Sources/ARESNativeMCP/` | 1 |

`ARESCore` currently contains:

| Group | Tracked files |
| --- | ---: |
| `MCP/` | 49 |
| `Services/` | 21 |
| `Models/` | 20 |
| `Astronomy/` | 20 |
| `Conversation/` | 19 |
| `Contracts/` | 18 |
| `Dummies/` | 15 |
| `Voice/` | 8 |
| `Utilities/` | 6 |
| `Security/` | 3 |

These are real build inputs. A move must update `Package.swift`, resource paths,
imports, test references, scripts, packaging, and documentation links where
required.

## Documentation authorities and conflicts

Documentation currently spans:

- `.claude/`
- `docs/`
- `docs/architecture/`
- `docs/decisions/`
- `docs/guides/`
- `docs/history/`
- `docs/product/`
- `webui/docs/`
- root and component READMEs

Documents with load-bearing implementation information:

- `docs/architecture/RUNTIME.md`
- `docs/product/source-ownership.md`
- `docs/decisions/`
- `docs/architecture/PRODUCT_SURFACES.md`
- `webui/docs/CONTRACTS.md`

The nested WebUI agent instructions refer to `ARCHITECTURE.md` and `TESTING.md`
as required component references, but no tracked files with those names exist
in the snapshot. The documentation pass must repair those instructions or
restore the intended references; an agent must not invent their contents.

Documents that require classification before being presented as current truth:

- `.claude/FOUNDATION.md` — contains important ownership rules but also naming
  language that must be reconciled with the current user direction.
- `TBR/20260727-docs-authority/docs/roadmap/ARES_IMPLEMENTATION_ROADMAP.md` —
  phase checkboxes do not match the implemented SI modules.
- `TBR/20260727-docs-authority/docs/architecture/MULTIAGENT_REFACTOR.md` —
  conflicts with the ownership model used elsewhere.
- `TBR/20260727-docs-authority/docs/si-disabled.md` — time-bound runtime status.
- `webui/FORK_CHANGES.md` and historical integration/audit documents — useful
  provenance, not necessarily current product definition.

Outdated documents are not to be deleted. They move to a dated path under
`TBR/` or a clearly historical documentation location, with their original
paths recorded.

## Persistence and state boundaries

Current ARES-owned state includes multiple implementations and formats:

- Web session JSON sidecars.
- Journal SQLite database and FTS indexes.
- Context-store SQLite/vector index.
- SI plans, memory metadata, and disclosure ledger.
- Run and turn JSONL journals.
- Continuity and profile state.
- Native Swift conversation/memory implementations.

Worker-owned stores remain external and read-only. Reorganizing source files
must not migrate runtime user data, alter schemas, or write into a worker store.
Storage consolidation is a later behavioral project, not part of a move-only
source pass.

## Structural pressure points

The reorganization should address these shapes without interpreting them as
missing-product claims:

1. `webui/api/` has many unrelated modules in one flat namespace.
2. `webui/fastapi_app/routers/` has a broad flat transport namespace.
3. Frontend pages are mostly organized by page rather than product capability.
4. Native contracts, conversation, memory, perception, integrations, and
   development dummies are not consistently grouped by responsibility.
5. Product truth, current runtime truth, old roadmaps, upstream history, and
   agent instructions are mixed together.
6. Root names still expose integration history (`webui`, `ARES-Mac_os`) but are
   also build and licensing boundaries, so moving them is higher risk than
   regrouping their internals.
7. Historical source formerly under `attic/` now uses the requested `TBR/`
   quarantine convention.

## Reorganization zones

The desired logical zones are:

```text
product applications
controller and transport
protocol-droid core
memory and knowledge
orchestration and authority
workers and provider integrations
sensors and native actions
operator tooling and packaging
tests
current documentation
historical/quarantined material
```

These are responsibility categories, not permission to create parallel
runtimes. The move map must place each file under exactly one active owner or
under `TBR/`.

## Baseline verification

Before this index was created, the selected SI, orchestration, context-store,
run-journal, and turn-journal suite passed:

```text
128 passed in 33.64s
```

The initial sandboxed run could not bind its temporary localhost test port; the
same test selection passed when localhost binding was permitted. That was an
execution-environment restriction, not a source failure.

## Index maintenance

For each move batch:

1. Update `docs/refactor/MOVE_MAP.tsv`.
2. Record TBR moves in `TBR/MANIFEST.tsv`.
3. Recalculate tracked counts.
4. Update only this index's path references affected by completed moves.
5. Never rewrite this document to pretend an old path never existed; the move
   map is the history.
