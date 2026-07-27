# ADR-0004: The frontend consumes ARES contracts, never framework shapes

**Status:** Accepted
**Date:** 2026-07-22 (recorded retroactively; stated in FOUNDATION)

## Context

Upstream Hermes WebUI has no translation layer, and does not need one: one team
owns both the agent and the UI, so payload shapes simply match.

ARES aggregates several runtimes whose payloads differ in field names, source
vocabulary, and provenance. Without normalization, framework concepts leak into
components and every new worker becomes a UI change.

## Decision

`frontend/src/shared/translators.ts` converts backend payloads into ARES-owned
contracts declared in `frontend/src/shared/contracts.ts`. Components consume only
contracts. FOUNDATION states this as a hard boundary.

## Consequences

Good:

- Adding a worker is a translator change, not a component change.
- One session row renders identically whether it came from Claude Code, Hermes,
  or the WebUI.
- The normalization has one place to be tested — `translators.test.ts`.

Costs:

- The translator is load-bearing and its bugs are systemic rather than local. A
  real example: `source` was derived from a fallback chain that reached
  `source_label`, a **display string** (`"Claude Code"`). Sidebar filters compare
  against machine values, so every CLI session was misfiled and the CLI tab
  read 0. One wrong line in the translator emptied a whole surface.

## Rules

- Never branch on a display string (`source_label`, `title`, human labels).
- Prefer the backend's already-normalized field (`session_source`) over raw values.
- When a fallback chain is needed, order it machine-value first and cover it with
  a test that uses a *real* payload shape, not an assumed one.

## Revisit if

Never, while ARES supports more than one runtime. The layer is the reason the UI
is worker-agnostic.
