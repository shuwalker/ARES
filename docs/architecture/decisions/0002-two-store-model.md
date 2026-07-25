# ADR-0002: ARES owns its store; workers own theirs

**Status:** Accepted
**Date:** 2026-07-22 (recorded retroactively)

## Context

The upstream WebUI and its CLI share **one** `state.db`, written by the
agent. The WebUI keeps a JSON "sidecar" as a cache and self-heals it from
`state.db` whenever the agent has written newer turns
(`_sync_sidecar_from_state_db_if_newer`). Continuing a terminal session works
because both surfaces are views onto a single store.

ARES is not a client of one agent. It is a product that connects to several,
each with its own home directory and its own store. `.claude/CLAUDE.md`
forbids modifying a worker's runtime state.

## Decision

Two stores, with a one-way boundary:

- **ARES owns** `ARES_HOME/webui/sessions/*.json` — read and write.
- **Workers own** their stores (a worker's own `state.db`, `~/.claude/projects`,
  JaegerAI instance DBs) — ARES reads them **read-only**.
- When a worker session needs a new turn, ARES asks the *worker* to write it
  (ADR-0001), and never writes the worker's store itself.

`ARES_HOME/state.db` does not exist in a normal install.

## Consequences

Good:

- A worker's history stays intact and portable; uninstalling ARES loses nothing.
- No write contention on a multi-GB WAL database an agent is actively streaming into.
- Each worker's provenance is preserved because the store it came from identifies it.

Costs:

- Inherited upstream code assumes one shared store. Every such path silently
  degrades to empty rather than failing loudly, because it resolves a file that
  does not exist. Known survivors are tracked in
  [RUNTIME.md §6](../RUNTIME.md#6-inherited-assumptions-still-outstanding).
- Reads must use read-only SQLite URIs (`?mode=ro`). A writable handle on a
  worker's database creates WAL/journal files inside that worker's home and
  breaks the boundary. Two existing call sites (`insights.py`,
  `schedules_store.py`) still open writable handles and must not be repointed
  at a worker store without being converted first.

## Revisit if

ARES ever becomes the sole writer of a runtime's state — at which point the
sidecar could collapse into that store. Until then, prefer fixing a read seam over
widening write access.
