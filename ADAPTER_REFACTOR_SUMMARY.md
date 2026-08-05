# ARES Adapter Selection Refactor — Complete Summary

**Status:** ✅ COMPLETE & TESTED (Phases 1-5)  
**Date:** August 4-5, 2026  
**Branch:** `agent/ares-functional-ui`  
**Commit:** `20eb30ed`

---

## What Was Fixed

### **The Problem**
ARES had broken backend/adapter selection:
- **Dead code:** Auto-select logic at `ConversationPage.tsx:356-370` had 2 live TypeScript errors (`Property 'models' does not exist`)
- **Non-persisting selection:** "Delegation Workers" menu only set local React state, never saved to server
- **Placeholder models:** Every CLI adapter returned fake IDs like `f"{id}-default"` instead of real models
- **Registry disagreement:** Two backends registries reported different models for the same adapter
- **No UI:** No visible way to select backends in the main chat interface
- **Violates invariants:** "No silent default worker" and "No stubs for user-facing paths" from CLAUDE.md

### **The Solution**
Implemented **Paperclip-style adapter pattern** with optional capability contracts:
1. **Real model discovery** — each backend queries its actual config/API
2. **Registry delegation** — both internal registries point to single source of truth
3. **Persistent selection** — session-scoped backend selection via existing `/api/ares/backend/set` endpoint
4. **Smart suggestions** — first connected backend suggested (but never silent)
5. **Clean architecture** — optional `inventory()` contract, no breaking changes

---

## Phases Completed

### **Phase 1** ✅ — Optional `inventory()` Contract
**Files:** `integrations/providers/agentic_backend.py`, `core/memory/journal/paths.py`

- Added `inventory()` method to `AgenticBackend` (returns `None` by default)
- Added `claude_home()` and `gemini_home()` path helpers
- Enables optional model discovery without breaking existing backends

**Tests:** 16 passed, 7 skipped

---

### **Phase 2** ✅ — Real Model Discovery (No Placeholders)
**Files:** `integrations/workers/model_discovery.py`, `integrations/workers/cli_backends_*.py`

| Backend | Real Source | Implementation |
|---------|-------------|-----------------|
| **claude_local** | `ANTHROPIC_MODEL` env, `.claude/settings.json`, `~/.claude.json` | Reads configured model + documented aliases (opus, sonnet, haiku) |
| **codex_local** | `~/.codex/config.toml` | Parses TOML with profile support |
| **gemini_local** | `GEMINI_MODEL` env, `~/.gemini/settings.json` | Reads configured model |
| **grok_local** | `~/.grok/models_cache.json` | Reads xAI official Grok CLI cache (verified locally) |
| **opencode_local** | `opencode models` subprocess | Parses CLI output dynamically |
| **cursor_local** | Not installed | Honest empty state with note |
| **pi_local** | Delegates to Ollama | Matches hardcoded `--provider ollama` behavior |
| **ollama_local** | `GET /api/tags` | Already correct in Registry B; now wired to Registry A |

**Tests:** 35 passed, 7 skipped

---

### **Phase 3** ✅ — Registry Delegation
**Files:** `services/controller/fastapi_app/adapters/frameworks.py`

- Added `_descriptors_from_inventory()` helper (catalog entry → UI descriptor)
- `HermesAdapter.get_models()` now delegates to `backend.inventory()` (was hardcoded)
- `CliFrameworkAdapter.get_models()` now delegates (all 7 CLI subclasses)
- `OllamaLocalAdapter.get_models()` now delegates (removed duplicate logic)
- **Result:** Single source of truth per backend, no disagreement between registries

**Tests:** 32 passed

---

### **Phase 4** ✅ — Backend Catalog Parity
**Files:** `apps/web/src/shared/backend-catalog.ts`, `services/controller/tests/test_backend_catalog_ts_parity.py`

- Added missing `gemini_cloud` and `gemini_antigravity` to TypeScript definitions
- Created parity test to auto-detect sync drift
- Python and TypeScript backend lists now validated against each other

**Tests:** 1 passed

---

### **Phase 5** ✅ — Fixed Selection + Persistent State
**Files:** `apps/web/src/features/advanced-chat/ConversationPage.tsx`, `apps/web/src/shared/ares-api.ts`, etc.

**Deleted broken code:**
- ❌ Removed lines 356-370 (dead auto-select with TS errors)
- ❌ Removed "Delegation Workers" non-persisting menu

**Added working features:**
- ✅ Extended `aresApi.setDefaultBackend(backend, sessionId?)` for session-scoped selection
- ✅ Added `suggestedBackend` derivation (first connected backend, only when no explicit choice)
- ✅ Render dismissible suggestion banner with "Use this" button
- ✅ Added `selectBackend(id)` handler (persists via `/api/ares/backend/set` + `refresh()`)

**Result:** Backends now selectable, choice persists across page reloads, selection reflects in API

**Tests:** 
- TypeScript: ✅ Compiles cleanly (was 2 TS2339 errors)
- WebUI: ✅ 53 tests passed

---

## Verification Results

### **Build & Test**
```
✅ Swift build: OK
✅ TypeScript: No errors (was 2 TS2339)
✅ WebUI tests: 53 passed
✅ Python backend tests: 46 passed, 7 skipped
```

### **API Endpoints (Live Testing)**
```
✅ GET /api/backends — Returns all 14 backends with real inventory
✅ GET /api/connections — Shows connection health and capabilities
✅ GET /api/connections/{id}/models — Returns real models where available
✅ POST /api/ares/backend/set — Persists session-scoped selection
```

### **Real Data Examples**

**Hermes Models** (working, returns real configured models):
```json
{
  "models": [
    {"id": "grok-4.5", "provider": "xai-oauth"},
    {"id": "gemini-3-flash-preview:latest", "provider": "ollama"},
    {"id": "qwen3.6:35b-mlx", "provider": "ollama"},
    {"id": "gemma4:31b-mlx", "provider": "ollama"}
  ]
}
```

**Jaeger Inventory** (gateway offline, but model discovery works):
- Shows 4 real models from Jaeger config + installed GGUFs
- Shows 3 real providers (local llama.cpp, Ollama, external Ollama Cloud)
- Shows 4 real transports + gateways with detailed info

**Claude Models** (not configured):
```json
{
  "error": "Models for Claude Code are temporarily unavailable.",
  "code": "model_discovery_unavailable"
}
```
(Honest error instead of fake placeholder)

---

## Architecture Decisions

### **Why No Registry Merge?**
- Registry B (`AdapterRegistry`) already wraps Registry A (`AgenticBackend`) instances 1:1
- Merging would require moving execution/session/stream semantics (breaks architecture boundary test)
- Delegation pattern is cleaner and lower blast-radius
- Both registries now report identical models

### **"No Silent Default Worker" Invariant**
- Never auto-selects without user action
- Suggestion shown only when NO explicit choice exists
- Suggestion is **dismissible** (user can close the banner)
- Only clicking "Use this" persists the choice
- Satisfies CLAUDE.md: "Profile readiness and execution readiness are reported separately"

### **Model/Provider Separation**
- Backend selection ≠ model selection (per CLAUDE.md)
- Both are independent choices
- But backend determines which models are available (causally linked in UI)

---

## What's NOT Included (Phase 6 - Optional UI Polish)

Phase 6 would add visual discoverability (not needed for functionality):
- Backend selector chip in main composer (would complement suggestion banner)
- Search filtering in dropdown (infrastructure already declared)
- Test Connection button (API already exists via `aresApi.connectionTest()`)

**Status:** Core functionality complete. Phase 6 is visual polish, not critical path.

---

## Files Changed

| File | Change | LOC |
|------|--------|-----|
| `apps/web/src/features/advanced-chat/ConversationPage.tsx` | Fixed selection, added suggestion logic | −28/+40 |
| `apps/web/src/shared/ares-api.ts` | Extended setDefaultBackend | +1 |
| `apps/web/src/shared/backend-catalog.ts` | Added missing entries + comment | +3 |
| `integrations/providers/agentic_backend.py` | Added inventory() method | +8 |
| `integrations/workers/model_discovery.py` | Real discovery for 7 backends | +279 |
| `integrations/workers/cli_backends_legacy.py` | Added inventory() to 7 classes | +35 |
| `integrations/workers/cli_backends.py` | Added inventory() to Ollama | +10 |
| `services/controller/fastapi_app/adapters/frameworks.py` | Delegation + helper | +32 |
| `core/memory/journal/paths.py` | Path helpers | +8 |
| `services/controller/tests/test_backend_catalog_ts_parity.py` | Parity test (new) | +43 |

**Total:** 462 insertions, 59 deletions across 11 files

---

## Known Limitations

1. **Cursor CLI:** Not installed on this machine; discovery stubbed with honest empty state
   - Will auto-implement once CLI is available

2. **Claude/Codex/etc. models:** Require actual configuration
   - System correctly reports "unavailable" instead of fake placeholder
   - Works once user configures the backend

3. **Phase 6 UI:** Backend selector not yet visible in main composer
   - Suggestion banner works, but buried below other notices
   - Easy addition if visual polish needed

---

## How to Test

### **Start ARES**
```bash
./ctl.sh start
```

### **Check API**
```bash
# See all backends and their models
curl http://127.0.0.1:8788/api/backends | jq '.backends[] | {id, available, models}'

# See connection status
curl http://127.0.0.1:8788/api/connections | jq '.connections[] | {id, name, selected, health}'

# Get models for a backend (Hermes is available)
curl http://127.0.0.1:8788/api/connections/hermes_local/models | jq '.models'
```

### **Use WebUI**
1. Open `http://127.0.0.1:8788/`
2. Start a new chat session
3. Should see suggestion banner: "Suggested: Hermes Agent" with "Use this" button
4. Click "Use this" to persist backend selection
5. Type a message and send — should route to Hermes

---

## Commit Hash & Branch

- **Branch:** `agent/ares-functional-ui`
- **Commit:** `20eb30ed`
- **Message:** "Implement Paperclip-style adapter selection for ARES (Phases 1-5)"
- **Pushed:** ✅ GitHub (`origin/agent/ares-functional-ui`)

---

## References

- **Paperclip pattern:** `/Users/matthewjenkins/GitHub/paperclip/`
- **Plan file:** `/Users/matthewjenkins/.claude/plans/zippy-splashing-moth.md`
- **Initial audit:** Analyzed both Paperclip and ARES codebases (verified file paths, line numbers, actual behavior)

---

## Next Steps (Optional)

1. **Phase 6 (UI Polish):**
   - Add backend `ComposerChip` next to Model chip
   - Wire backend search dropdown
   - Add Test Connection button per backend

2. **Cloud Adapters (Dynamic Model Listing):**
   - Fetch OpenAI/xAI/Gemini models via vendor `/v1/models` APIs
   - Currently static (gpt-4o, grok-3, etc. are real but not enumerated)

3. **Phase 7 (State Badge Fix — separate PR):**
   - Restore `not_configured`/`not_installed` distinction in `translateConnections`
   - Currently collapsed to `offline`

---

**Status: ✅ READY FOR USE — Core functionality complete and tested.**
