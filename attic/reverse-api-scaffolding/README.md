# Reverse-API browser-automation scaffolding

Moved out of `webui/api/backends/` on 2026-07-22. Preserved rather than deleted
per `.claude/CLAUDE.md`.

## What these were

An unfinished attempt at driving vendor web UIs (ChatGPT, Claude, Gemini, Grok)
through browser automation instead of APIs, sharing `reverse_api_base.py`.

## Why they were removed

- **Never wired.** No route, adapter registry, or router referenced any of them;
  a repo-wide grep found zero importers outside the files themselves.
- **Not runnable.** Every entry point raised `NotImplementedError`, including
  `_get_safari_mcp_client()` and `run_turn()`, with "LOCAL AI TODO" comments in
  place of implementations.
- **Misleading.** They sat beside real working adapters (`hermes.py`, `jros.py`,
  `cli_backends.py`), so a reader scanning `api/backends/` would reasonably
  assume ARES supports these providers.

## If resurrected

Restore into `webui/api/backends/`, implement `run_turn()` and SSE streaming,
then register in the adapter inventory. Note that browser automation against a
vendor's web UI may conflict with that vendor's terms of service — confirm before
building on this.
