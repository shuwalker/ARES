# ARES Synthetic Intelligence — Repository Audit & Gap Matrix

**Date**: 2026-07-20  
**Branch**: `wip/odysseus-import`  
**Auditor**: Hermes Agent (codex/local model)

---

## 1. Definition Invariant

> ARES is the codebase. The SI is the owner-named persistent intelligence. Providers, agents, models, and tools are replaceable workers used by the SI.

---

## 2. Documentation Language Violations

Every place the repo contradicts the invariant above.

| File | Line(s) | Violation | Fix |
|------|---------|-----------|-----|
| `README.md` | 7 | "A Mac-first presentation and integration layer for a user-facing AI assistant" | Replace "AI assistant" with "Synthetic Intelligence (SI) host" |
| `README.md` | 179 | `email_ai_assistant/` module name | Rename to `email_si/` or similar |
| `webui/api/config.py` | 415 | `"helpful": "You are a helpful, friendly AI assistant."` | Change to SI-aligned language |
| `webui/api/config.py` | 421 | `"catgirl": "You are Neko-chan, an anime catgirl AI assistant, nya~!"` | Change "AI assistant" to "Synthetic Intelligence" |
| `webui/FORK_CHANGES.md` | 171 | "ARES is a separate product from Ares" | Already correct separation but "Ares" naming still conflates |
| `webui/tests/test_issue4465_builtin_personalities.py` | 36, 80 | Asserts "helpful" personality = "You are a helpful, friendly AI assistant." | Update test to match corrected personality |
| `webui/docs/troubleshooting.md` | 11 | "WebUI starts, shows the chat interface" | Replace "chat interface" with "SI conversation surface" |
| `webui/api/ares_identity.py` | 108 | `_default_assistant_name` — "assistant" throughout | Rename to `_default_si_name` or `_default_companion_name` |

**Pattern**: The codebase uses "assistant" and "AI assistant" in 20+ places where the product definition says "Companion" or "SI." This is not cosmetic — it leaks into the identity payload that gets injected into worker prompts.

---

## 3. Architectural Gap Matrix

Scored on: integrated, reachable, tested, performing real work. Placeholders and dead code score 0%.

| # | Domain | Target | Current | Evidence | % | Priority | Security |
|---|--------|--------|---------|----------|---|----------|----------|
| 1 | Product definition alignment | ARES hosts SI, workers execute | "AI assistant" language throughout | `README.md:7`, `config.py:415`, tests | 40 | P0 | — |
| 2 | Identity continuity | Named SI, persistent identity | `ares_identity.py` builds display name + backend badge | `ares_identity.py:191` | 25 | P0 | — |
| 3 | User model | Structured preferences, provenance, confidence | `profiles.py` stores flat profile, no user model | `profiles.py`, `settings_service.py` | 10 | P1 | — |
| 4 | Journal (episodic memory) | Full conversation + document search | 359 convos, 48K msgs, 628 docs, FTS5 | `api/journal/schema.py` | 80 | ✅ | — |
| 5 | Memory lifecycle | Classify → dedup → importance → consolidate → correct | No lifecycle. Journal is write-once, no classification or consolidation | `schema.py` has no tags, importance, or lifecycle columns | 10 | P1 | — |
| 6 | Context compiler | Assemble minimum viable context per task | **Does not exist.** `ares_runtime_context.py` injects identity/capability into system prompt but does no Journal retrieval, no relevance ranking, no budgeting, no sensitivity filtering | `ares_runtime_context.py:102` only builds identity packet | 5 | P0 | **Critical** |
| 7 | Provider abstraction | Common `ReasoningProvider` interface with capability methods | Backends are ad-hoc. `hermes.py`, `jros.py`, `gemini_cloud.py` each have different interfaces. No `classify_intent()`, `rank_context()`, `evaluate_result()` | `webui/api/backends/` — each backend is a standalone module with no shared protocol | 15 | P0 | — |
| 8 | Capability registry | Data-driven worker capabilities | `ai_framework_discovery.py` has hardcoded adapter list, no capability schema | `ai_framework_discovery.py:46-99` hardcoded IDs | 10 | P1 | — |
| 9 | Trust engine | Data classification, provider eligibility, local-only, approval gates | **Does not exist.** No data classification, no provider eligibility rules, no approval gates. Any context goes to any provider. | No `trust_engine.py`, no `privacy_engine.py`, no data classification anywhere | 0 | P0 | **Critical** |
| 10 | Privacy enforcement | Secret filtering, redaction, disclosure ledger | `secret_vault.py` uses OS keychain (good) but `secrets_router` list endpoint returns plaintext values (Grok found this). No redaction, no disclosure tracking | `secret_vault.py` good, but listing API exposes values | 15 | P0 | **Critical** |
| 11 | Planner | Multi-step plan creation, persistence, state | **Does not exist.** No plan model, no step tracking, no dependency graph. | No `planner.py`, no `plan` table in any DB | 0 | P1 | — |
| 12 | Orchestrator | Sequential/parallel execution, retries, branching, cancellation, resumability | `delegation_runner.py` and `delegation_tasks.py` exist for background tasks but are not a general orchestrator. No branching, no resumability, no state persistence across restarts. | `delegation_runner.py` is fire-and-forget task delegation | 10 | P1 | — |
| 13 | Routing | Capability match + privacy + availability + quality + cost + preference | `worker_rankings.py` has effectiveness scoring (good). `backend_selector.py` picks a backend. No privacy filter, no cost consideration, no user preference in routing. | `worker_rankings.py` exists but is not wired into chat flow | 20 | P1 | — |
| 14 | Evaluation / verification | Deterministic checks + model-based evaluation + confidence | `worker_rankings.py` records scores but there is no verification pipeline. No deterministic checks (tests, lint, format validation) on worker output. No contradiction detection. | No `evaluator.py`, no verification step in any chat flow | 5 | P1 | — |
| 15 | Response composition | SI identity + user prefs + verified results + uncertainty → final response | Worker output goes directly to user. No composition step. No SI voice layer. No uncertainty framing. | `gateway_chat.py` streams worker response directly to client | 5 | P0 | — |
| 16 | Activity ledger | What SI understood, what context used, which worker, why, what data shared, what verified, what failed | `run_journal.py` and `turn_journal.py` log turns but not routing decisions, context provenance, or data disclosures | `run_journal.py` logs runs but not the "why" | 15 | P1 | **Important** |
| 17 | User controls | Inspect tasks, pause, cancel, approve, override worker, correct memories, restrict providers, force local-only, delete data, inspect costs, inspect disclosures | Settings page exists. Connections page shows providers. No task inspection. No memory correction. No local-only mode. No disclosure inspection. No cost tracking. | `SettingsPage.tsx`, `ConnectionsPage.tsx` exist | 15 | P2 | — |
| 18 | Hermes integration | Defined adapter contract, structured results, no architecture leak | `hermes.py` and `hermes_streaming.py` are direct backend implementations, not adapter contracts. Hermes-specific types leak into `ares_tools.py`, `ares_tool_adapter.py`, `commands.py` | `webui/api/backends/hermes.py` | 30 | P1 | — |
| 19 | Claude integration | Adapter contract, no special-casing | `ai_framework_discovery.py` hardcodes `claude_local` with special-case config dir. No adapter contract. | `ai_framework_discovery.py:53` | 20 | P2 | — |
| 20 | Gemini integration | Adapter contract | `gemini_cloud.py` backend, `gemini_local` in discovery, `gemini_antigravity` special case | `ai_framework_discovery.py:278` | 15 | P2 | — |
| 21 | Ollama / local model | Adapter contract, local-first priority | `ollama_hatchery.py` is a backend. No adapter contract. No local-first routing priority. | `webui/api/backends/ollama_hatchery.py` | 15 | P1 | — |
| 22 | MCP integration | Tool discovery, permission gating, execution sandbox | `native_mcp.py` and `mcp_config.py` exist. MCP restart button is fake (Grok found this). Native tools compiled but not routed to FastAPI. | `McpPage.tsx:496` fake restart, `ARESCore/MCP/` compiled but disconnected | 20 | P1 | — |
| 23 | macOS native integration | WKWebView, native tools bridge, lifecycle | Shell loads React. Native MCP tools exist but bridge is disconnected. 0 Swift tests in main target. `ARESTests.swift` is empty. | `ARESTests.swift` is 1 line, Command Center not routed | 25 | P1 | — |
| 24 | WebUI | 30 pages, 3 nav sections, lazy loading | All routes wired. CronPage removed. Some pages use mock data (Board, some Schedules). | `app-navigation.ts` complete | 75 | ✅ | — |
| 25 | Testing | Architecture, context, routing, orchestration, integration tests | Python: 143 pass, 1 fail (pre-existing `test_approval_unblock`). Frontend: 15 pass, build green. Swift: 0 real tests. No architecture tests. No integration tests. No context leakage tests. | `pytest` results, Swift test target empty | 15 | P0 | — |
| 26 | Observability | Activity timeline, cost tracking, data disclosure audit | `ActivityPage.tsx` exists. No cost tracking. No data disclosure audit. No routing decision log. | Activity page shows basic events only | 10 | P2 | — |
| 27 | Security | No secrets in prompts, no plaintext exposure, path traversal protection, auth on all routes | `secret_vault.py` uses OS keychain (good). BUT: list endpoint returns plaintext values. No path traversal audit. API keys passed in config to providers without filtering. No audit of what data goes to which worker. | `secret_vault.py:34` returns value, no redaction | 20 | P0 | **Critical** |

**Overall completion: ~18% of target SI architecture**

---

## 4. Fake / Placeholder / Unwired Components

| Component | Location | Status | Evidence |
|-----------|----------|--------|----------|
| Command Center | `components/command-center/` | 4 components built, NOT routed in App.tsx | `grep CommandCenter App.tsx` returns nothing |
| MCP Restart | `McpPage.tsx:496` | Fake action — shows `reload_required` but doesn't restart anything | Grok audit finding |
| Swift Tests | `ARESTests.swift` | Empty file, 0 test methods | `wc -l` = 1 line |
| Secrets List API | `secrets_router` | Returns plaintext values | `secret_vault.py:34` |
| Native MCP Bridge | `ARESCore/MCP/` | Compiled Swift MCP tools, not routed to FastAPI | No bridge endpoint exists |
| Onboarding Worker Choice | `onboarding.py` | Lets user skip without picking a worker | Grok found "organizer only" bypass |
| `config.py` personalities | `config.py:415,421` | Hardcoded "AI assistant" language, not SI-aligned | Strings directly in config |
| Backend verification | `backend_verification.py` | Special-cases `grok_local`, `gemini_antigravity`, `ollama_local` | Lines 55-77 if/elif chain |

---

## 5. Security Concerns

| Concern | Severity | Evidence | Fix |
|---------|----------|----------|-----|
| **Secrets API returns plaintext** | Critical | `secret_vault.py` `get_secret()` returns raw value. List endpoint exposes all values. | Mask values in list, reveal only on explicit GET with audit log |
| **No data classification** | Critical | No sensitivity labels on Journal data, no privacy rules for context compilation | Add `sensitivity` column to conversations/messages; trust engine must check before sending to cloud workers |
| **No context filtering before worker send** | Critical | `ares_runtime_context.py` injects identity into prompt but doesn't filter Journal data. Full conversation history goes to workers. | Context compiler must filter by sensitivity before assembling briefing |
| **API keys in config passed to providers** | High | `providers.py` passes keys directly to provider HTTP clients. No audit of what data each key can access. | Trust engine must gate which providers receive which data |
| **No approval gates for irreversible actions** | High | `commands.py` executes shell commands, `file_operations.py` writes files. No user confirmation for destructive ops in all paths. | Add approval gates for file delete, shell execute, external API calls |

---

## 6. What Exists That's Good

| System | Status | Why It's Good |
|--------|--------|---------------|
| **Journal** | ✅ Working | 359 convos, 48K messages, 628 docs, FTS5 search. The foundation for SI memory. |
| **Worker rankings** | ✅ Partial | `worker_rankings.py` has effectiveness scoring with weighted metrics. Not wired into chat flow but the data model is sound. |
| **Secret vault** | ✅ Partial | Uses OS keychain (Keychain on macOS). Good foundation. Needs masking on list endpoint. |
| **Runtime context** | ✅ Partial | `ares_runtime_context.py` builds identity packet per turn. Good start for context compilation. |
| **Identity** | ✅ Partial | `ares_identity.py` builds display name, backend badge. Needs SI language replacement. |
| **Backend selector** | ✅ Partial | `backend_selector.py` picks a backend. Needs privacy and capability filtering. |
| **Framework discovery** | ✅ Partial | `ai_framework_discovery.py` detects installed AI tools. Needs adapter contract extraction. |
| **Onboarding** | ✅ Partial | `onboarding.py` has endpoint probe, profile creation. Needs forced worker choice. |
| **Self persistence** | ✅ Partial | `ares_self_persistence.py` injects session state into context. Part of the context compiler. |
| **Delegation** | ✅ Partial | `delegation_runner.py` and `delegation_tasks.py` for background tasks. Foundation for orchestration. |
| **WebUI** | ✅ Working | 30 pages, 49 API routers, all routes wired. |
| **Auth** | ✅ Working | Password, passkey, OIDC, trusted-header. |
| **Frontend build** | ✅ Working | Vite + React, builds in 3s. |
| **Profiles** | ✅ Working | Multi-profile support, isolated state dirs. |

---

## 7. Missing Systems (Priority Order)

| # | System | Current | Required | Effort |
|---|--------|---------|----------|--------|
| 1 | **Context Compiler** | `ares_runtime_context.py` injects identity only. No Journal retrieval, no relevance ranking, no budgeting, no sensitivity filtering. | FTS5 search → temporal boost → relevance ranking → sensitivity filter → token budget → structured briefing | M |
| 2 | **Trust & Privacy Engine** | Does not exist. Any data goes to any provider. | Data classification → provider eligibility → local-only enforcement → approval gates → disclosure ledger | M |
| 3 | **Response Composer** | Worker output streams directly to user. No SI voice, no uncertainty framing. | Intercept worker response → apply SI identity → add verification status → frame uncertainty → deliver | S |
| 4 | **Planner** | Does not exist. | Plan model → step tracking → dependency graph → state persistence → resumability | L |
| 5 | **Orchestrator** | `delegation_runner.py` for background tasks only. No branching, no retries, no resumability. | Extend delegation → plan execution → step routing → retry/branch → state persistence | L |
| 6 | **Evaluator / Verifier** | Does not exist. | Deterministic checks (tests, lint, format) → model evaluation → confidence scoring | M |
| 7 | **Memory Lifecycle** | Journal is write-once. No classification, dedup, importance, or consolidation. | Add columns (tags, importance, sensitivity) → classification pipeline → consolidation → user correction UI | M |
| 8 | **User Model** | `profiles.py` stores flat settings. No preferences with provenance/confidence. | Structured user model with provenance, confidence, sensitivity labels, edit/delete UI | M |
| 9 | **Worker Adapter Contract** | Each backend is a standalone module with different interfaces. | `ReasoningProvider` protocol with `classify_intent()`, `generate()`, `evaluate_result()` etc. | M |
| 10 | **Capability Registry** | Hardcoded adapter list in `ai_framework_discovery.py`. | Data-driven registry with capabilities, privacy class, cost, latency, context limits | S |
| 11 | **Activity Ledger** | `run_journal.py` logs runs but not routing decisions or data disclosures. | Add routing decision log → context provenance → data disclosure tracking → user inspection UI | M |
| 12 | **SI Language Replacement** | "AI assistant" throughout codebase. | Global replace with Companion/SI language. Update personalities, tests, docs. | S |
| 13 | **Security Hardening** | Plaintext secret values, no data classification, no approval gates. | Mask secrets, add sensitivity columns, add approval gates for destructive actions | M |

---

## 8. Recommended First Vertical Slice

The highest-value slice that demonstrates the full SI architecture:

```
User request
→ task classification (deterministic rules first)
→ Journal retrieval (FTS5, already built)
→ context compilation (sensitivity filter + token budget)
→ privacy check (trust engine gates data by classification)
→ worker selection (rankings + privacy eligibility)
→ worker execution (existing backend infrastructure)
→ deterministic verification (basic checks on response)
→ SI response composition (apply identity, frame result)
→ activity audit (log routing decision, data shared)
→ optional memory update (tag important outcomes)
```

This requires building: Context Compiler, Trust Engine (minimal), Worker Adapter Contract, and Response Composer. The Journal already exists. The rankings system already exists. The backend infrastructure already exists.

Estimated effort: 2-3 focused sessions to get this end-to-end with real data flow.