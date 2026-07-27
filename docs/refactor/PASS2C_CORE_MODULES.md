# Pass 2c — more core modules (flat api → core)

## Moved (with `api.*` shims)

### `core/memory/`
- `memory_store.py`
- `context_store.py`
- `context_chunker.py`
- `context_embeddings.py`
- (existing) `journal/`

### `core/events/`
- `run_journal.py`
- `turn_journal.py`

### `core/authority/`
- `route_approvals.py`
- `os_automation_consent.py`

### `core/knowledge/`
- `library_store.py`
- `notes_store.py`
- `wiki_store.py`
- `media_store.py`
- (existing) `research/`

## Verification
SI baseline: **128 passed**

## Still remaining under `services/controller/api/`
Session/streaming/chat/config surface modules, workers ranking, etc. Next batches as ownership allows.
