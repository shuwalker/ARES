# ARES Runtime Architecture

**Status:** Canonical runtime reference (2026-07-22)
**Audience:** maintainers and coding agents
**Companion documents:** [FOUNDATION.md](../../.claude/FOUNDATION.md) (product),
[PRODUCT_SURFACES.md](./PRODUCT_SURFACES.md) (information architecture),
[decisions/](../decisions/) (ADRs — *why* the runtime is shaped this way)

This document describes **how the running system actually works**: what happens
when a message is sent, where conversation data lives, and which assumptions the
code makes. FOUNDATION defines the product; this defines the machine.

ARES's WebUI is a fork of Hermes WebUI (MIT, preserved in `services/controller/LICENSE`). Several
runtime bugs have come from inherited code that assumed upstream's storage model.
Section 6 lists the ones still outstanding.

---

## 1. Process topology

```text
Browser (React SPA, Vite build)
   │  HTTP + SSE, same origin
   ▼
FastAPI controller  (services/controller/fastapi_app/, uvicorn)
   │  routers → services → api/ business logic
   ▼
Worker adapters (integrations/workers via api.backends shim)
   │  subprocess per turn
   ▼
Worker processes: Hermes Agent · jros · Claude Code · Codex · Ollama · cloud
```

Three trees, one product:

| Tree | Owns |
|---|---|
| `apps/web/` | React + TypeScript SPA. The only web frontend (FOUNDATION forbids a second vanilla/`static/` frontend). |
| `services/controller/fastapi_app/` | HTTP surface: routers, endpoints, Pydantic schemas, auth/identity. |
| `services/controller/api/` + `core/` + `integrations/` | Business logic: sessions, streaming; Companion core and worker integrations. |

The frontend never consumes framework-native shapes. `apps/web/src/shared/translators.ts`
normalizes backend payloads into ARES-owned contracts (`apps/web/src/shared/contracts.ts`). That
seam is load-bearing — it is what lets a Claude Code row and a Hermes row render
through one component.

---

## 2. Storage model — two stores, one direction

This is the most important thing to understand, and the source of most historical bugs.

```text
ARES_HOME/webui/sessions/*.json     ARES-owned sessions (state dir name; not source tree)  read + WRITE
$HERMES_HOME/state.db               Hermes Agent's store     read ONLY
~/.claude/projects/**/*.jsonl       Claude Code transcripts  read ONLY
<jaeger>/instances/*/memory/*.db    JaegerAI store           read ONLY (not parsed yet)
~/.codex/sessions/**                Codex store              detected, not parsed
~/.gemini/antigravity-ide/…         Gemini store             detected, not parsed
```

**ARES never writes another app's store.** When a worker session needs a new turn,
ARES asks *the worker* to write it (see §3). This is a deliberate boundary, not an
implementation gap.

`ARES_HOME/state.db` **does not exist in a normal install.** ARES keeps its own
sessions as JSON sidecars. Any inherited code path that resolves
`_active_state_db_path()` and expects rows is reading a file that isn't there —
it will silently return empty rather than error.

Path resolution goes through `api/journal/paths.py`, which honours
`ARES_HOME`, `HERMES_HOME`, `CLAUDE_HOME`, `CODEX_HOME`, `GEMINI_HOME`. Nothing
may assume a maintainer's home layout (see the privacy boundary in
`.claude/CLAUDE.md`).

### Read seams

| Helper | Resolves to | Notes |
|---|---|---|
| `_active_state_db_path()` | `ARES_HOME/state.db` | Usually absent. **Do not add new callers.** |
| `_agent_state_db_path()` | profile store → falls back to the **worker's** store | Correct helper for reading worker history. |
| `_worker_state_db_path()` | `$HERMES_HOME/state.db` | Read-only; `None` when absent. |

---

## 3. Chat round trip

What happens when the user presses Send in the Chat surface:

1. `ConversationPage.sendMessage()` → `POST /api/chat/start {session_id, message, …}`.
2. The router resolves identity/profile and hands off to the streaming layer.
3. `api/backends/hermes_streaming.py` builds an argv for the worker CLI:
   ```
   hermes chat -q "<message>" -Q --yolo --source webui -m <model> --provider <p>
   ```
4. **Resume:** `_get_hermes_session_id(session_id)` decides whether this turn
   continues an existing worker session. It checks an in-process map first, then
   probes the worker's `state.db` for a session with the same id. On a hit,
   `--resume <id>` is appended.
5. `subprocess.Popen` runs the worker. stdout/stderr are parsed for tokens, tool
   activity, and the worker's `session_id:` line.
6. Events are pushed onto a queue; the browser consumes them over
   `EventSource('/api/chat/stream?stream_id=…')`.
7. On completion the ARES-side session (JSON sidecar) is updated and the sidebar
   refreshes.

**Conversation history is not serialized per turn.** Only the new message crosses
the process boundary; the worker reloads its own history from its own store via
`--resume`. This is why the resume path is correctness-critical rather than a
performance nicety — without it the worker starts a *new* session on every reply
and context is lost outright.

---

## 4. Session identity and provenance

A session row carries both what it is and where it came from:

| Field | Meaning |
|---|---|
| `session_source` | Normalized bucket: `webui`, `cli`, `messaging`, … Machine value. |
| `source_tag` / `raw_source` | Raw value from the producing app (`claude_code`, `cli`, `tui`). |
| `source_label` | **Display string** (`"Claude Code"`). Never branch on this. |
| `is_cli_session` | True for anything imported from another agent app. |
| `read_only` | True only when ARES has **no write-back path** (Claude Code). |
| `ares_backend` | Adapter that owns the session; stamped from the store it was read from. |

`read_only` means *"nothing can add turns to this"* — not *"ARES cannot write it."*
A Hermes CLI session is not read-only: ARES cannot write `state.db` directly, but
the Hermes agent can continue it, so it stays writable from the user's point of view.
Claude Code transcripts are read-only because no process will append to them on request.

Titles are sanitized before display (`sanitize_session_title`). Agent clients inject
wrapper blocks (`<conversation_history>`, `<ide_opened_file>`, `# Role …`) ahead of
the user's text; titling on the raw turn produced dozens of identical unreadable rows.

---

## 5. Discovery and indexing

`api/agent_sources.py` enumerates every known agent store on the machine and reports
what ARES can actually read (`GET /api/library/agent-sources`). This exists because
silent truncation is the failure mode that looks like success: a sidebar showing 174
rows when 215 transcripts exist reads as "that's all my history."

Known caps, surfaced in the payload rather than applied silently:

| Cap | Value | Effect |
|---|---|---|
| `CLAUDE_CODE_MAX_FILES` | 200 | Oldest transcripts beyond this are not indexed. |
| `CLAUDE_CODE_MAX_FILE_BYTES` | 10 MB | Larger transcripts skipped entirely. |
| `CLAUDE_CODE_MAX_MESSAGES_PER_FILE` | 1000 | Long transcripts truncate. |
| `CLI_VISIBLE_SESSION_LIMIT` | 20 | Per-backend sidebar cap. |

---

## 6. Inherited assumptions still outstanding

The fork changed the storage model (§2) but not every inherited code path. These
resolve `_active_state_db_path()` — i.e. a file that normally does not exist — and
degrade to empty rather than failing loudly:

| Location | Symptom |
|---|---|
| `api/insights.py` | Usage analytics under-report: 32 sessions counted against 220 present. Also opens a **writable** connection, so it must never be pointed at a worker store. |
| `api/schedules_store.py` | Schedule metadata lookups no-op. Writable connection — same constraint. |
| `api/route_session_list_cache.py` | Cache key derived from a path that does not exist. |
| `models.py` `_read_state_db_sidebar_overrides` | Sidebar overrides never match worker rows. |
| `models.py` `read_session_lineage_metadata` | Lineage/branch metadata missing for worker sessions. |

Fixing these is not a mechanical swap to `_agent_state_db_path()`: two of them open
write-capable SQLite handles, which would create WAL/journal files inside a worker's
home and violate §2. Each needs a read-only handle first.

`claim_or_synthesize_cli_session()` is an ARES invention with no upstream equivalent.
It materializes a foreign session into ARES's store on open. With `--resume` working,
that copy now behaves as a cache rather than a fork, but the seam should eventually
be retired for workers that support resume.

---

## 7. Conventions for new work

- New endpoints go in `fastapi_app/routers/` with a Pydantic schema and an
  identity dependency (`require_identity` for reads, `require_mutation_identity`
  for writes).
- New backend reads of another app's store must use a **read-only** SQLite URI
  (`?mode=ro`) and resolve paths through `api/journal/paths.py`.
- Frontend must not consume framework-native shapes — add a translator.
- Never branch on `source_label` or any display string.
- If you add a cap or a limit, report what it dropped.
