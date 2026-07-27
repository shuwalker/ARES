# ADR-0003: `read_only` marks the absence of a write-back path

**Status:** Accepted
**Date:** 2026-07-22 (recorded retroactively)

## Context

Imported sessions come from other agent apps. It is tempting to mark all of them
read-only on the reasoning that "ARES does not own them." Upstream does not do
this: the only `read_only: True` in the upstream session model is on the Claude
Code bridge. Hermes CLI and TUI sessions remain writable.

The distinction matters because a user who started a conversation in the terminal
expects to continue it in the UI, and marking it read-only removes that ability
for no benefit.

## Decision

`read_only` means **no process will append turns to this session on request** —
not "ARES cannot write the file."

| Source | `read_only` | Why |
|---|---|---|
| Hermes CLI / TUI | `false` | The agent can resume it (ADR-0001). |
| Claude Code | `true` | JSONL transcripts; nothing will append on request. |
| Codex / Gemini | `true` (when parsed) | Same — detected, no write-back path. |
| ARES WebUI | `false` | ARES owns it. |

## Consequences

- The UI must not use `read_only` to mean "ARES-owned." Ownership is
  `ares_backend` plus the store the row came from.
- Deletion is refused for read-only rows at the mutation layer
  (`session_mutations.delete_session`), which is what protects imported history
  from the sidebar's Delete action.
- A future worker that gains a resume capability flips to writable without any
  UI change.

## Note

This was already correct in ARES for Claude Code, but the *reason* was
undocumented, so it repeatedly read like an inconsistency during review. That
ambiguity is the reason this ADR exists.

## Revisit if

A worker gains an append API that ARES can call directly. That would be a third
state — writable, but by ARES rather than by the worker — and the boolean would
need to become an enum.
