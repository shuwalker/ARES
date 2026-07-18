# gbrain Knowledge Engine — ARES Drain

Source: [gbrain](https://github.com/garrytan/gbrain) — TypeScript/Bun personal knowledge brain.

## What was drained

The core architecture patterns from gbrain's `src/core/` that power synthesis, entity extraction, gap analysis, and the dream cycle — the knowledge engine heart of a 146K+ page personal brain.

### Key subsystems

| Directory | Purpose |
|-----------|---------|
| `think/` | Query intent classification, entity extraction, citation rendering, context gathering |
| `context/` | Entity salience, volunteer context injection, retrieval reflex, IPC resolution |
| `cycle/` | Dream cycle phases: extract-atoms, extract-facts, synthesize, enrich, consolidate, drift detection |
| `ingestion/` | Source ingestion daemon, file watcher, dedup, skillpack loading |
| `brainstorm/` | Multi-agent brainstorm orchestrator with judges and domain banks |
| `chunkers/` | Code, LLM, recursive, semantic, and edge-extraction chunking strategies |
| `advisor/` | Health advisor: setup smells, stalled jobs, migration, version checks |
| `conversation-parser/` | Conversation parsing with LLM fallback and polish |
| `eval-contradictions/` | Cross-source contradiction detection and calibration |
| `calibration/` | Recall calibration, undo waves, SVG rendering, voice gating |

### Key standalone modules

- `engine.ts` / `engine-factory.ts` — Engine abstraction (PGLite + Postgres)
- `embedding.ts` — Embedding pipeline with pricing, dim checks, stale/embed logic
- `context-engine.ts` — Core context engine orchestration
- `brain-writer.ts` / `brain-registry.ts` — Brain management
- `operations.ts` — Operation descriptions and dispatch
- `schema-embedded.ts` / `schema-events.ts` — Schema definitions
- `vector-index.ts` — Vector index management
- `guardrails.ts` / `destructive-guard.ts` — Safety guards

## Integration notes

- Original codebase is TypeScript/Bun; ARES API is Python. These files serve as **architecture reference** for reimplementing the patterns in Python.
- Import paths reference gbrain internals (`@core/...`) and will need adaptation.
- The dream cycle (`cycle/`) is the most valuable pattern: a phased loop of extract → synthesize → consolidate that runs overnight to grow knowledge.