# ARES Implementation Roadmap

## Phase 0 — Definition and Boundaries (Current)

**Goal**: Correct repository understanding before building.

### Deliverables
- [x] Audit with evidence (`ARES_SI_AUDIT.md`)
- [x] System boundaries (`SYSTEM_BOUNDARIES.md`)
- [x] Worker adapter contract (`WORKER_ADAPTER_CONTRACT.md`)
- [x] Trust and privacy model (`TRUST_AND_PRIVACY_MODEL.md`)
- [x] Memory and context model (`MEMORY_AND_CONTEXT_MODEL.md`)
- [x] Orchestration model (`ORCHESTRATION_MODEL.md`)
- [ ] SI language replacement ("AI assistant" → "Companion" / "SI")
- [ ] Update README to define ARES correctly
- [ ] Update `config.py` personalities
- [ ] Update tests to match corrected personalities

### Estimated effort: 1 session

---

## Phase 1 — Core Contracts

**Goal**: Define the interfaces the SI will use before implementing behavior.

### Deliverables
- [ ] `ReasoningProvider` protocol (`api/si/protocols.py`)
- [ ] `ContextBriefing` and `WorkerResult` data classes (`api/si/types.py`)
- [ ] `Plan` and `Step` data classes (`api/si/types.py`)
- [ ] Sensitivity column on Journal tables (migration)
- [ ] Worker capability registry (`api/si/worker_registry.py`)
- [ ] CostEstimate and LatencyProfile types
- [ ] Architecture tests: workers cannot bypass trust, secrets never appear

### Estimated effort: 1-2 sessions

---

## Phase 2 — Context Compiler

**Goal**: The SI assembles relevant, privacy-filtered context before sending anything to a worker.

### Deliverables
- [ ] `api/si/context_compiler.py` — the core module
  - FTS5 retrieval from Journal
  - Temporal boost (recent > old)
  - Decision boost (final > draft)
  - Budget-aware packing
  - Context manifest generation
- [ ] `api/si/intent_classifier.py` — deterministic rules + optional model
- [ ] `api/si/trust_engine.py` — data classification, privacy filtering
- [ ] Sensitivity labeling for existing Journal data
- [ ] Tests: irrelevant context excluded, sensitive context redacted, token budgets respected, secrets never appear

### Estimated effort: 2-3 sessions

---

## Phase 3 — Trust and Privacy Engine

**Goal**: Data never reaches an ineligible worker.

### Deliverables
- [ ] Data classification pipeline (deterministic rules)
- [ ] Provider eligibility matrix
- [ ] Local-only mode enforcement
- [ ] Approval gates for sensitive data and destructive actions
- [ ] Disclosure ledger table and logging
- [ ] Tests: private data blocked from cloud workers, local-only mode enforced, approval gates work

### Estimated effort: 1-2 sessions

---

## Phase 4 — Orchestration

**Goal**: Complex tasks can be planned, tracked, retried, and resumed.

### Deliverables
- [ ] `plans` and `steps` tables in Journal database
- [ ] `api/si/planner.py` — creates plans from user requests
- [ ] `api/si/orchestrator.py` — executes plans with step routing
- [ ] State persistence across restarts
- [ ] Retry logic with fallback workers
- [ ] Approval gate mechanism
- [ ] Tests: state survives restart, retries are bounded, cancellation works, failed steps recorded

### Estimated effort: 2-3 sessions

---

## Phase 5 — Capability-Aware Routing

**Goal**: The SI picks the best worker based on capability, privacy, cost, and history.

### Deliverables
- [ ] Wire `worker_rankings.py` into chat flow
- [ ] Privacy-aware routing (trust engine gates)
- [ ] Cost and latency considerations
- [ ] User preference overrides
- [ ] Fallback worker selection
- [ ] Tests: unauthorized workers rejected, unavailable workers skipped, local-only mode blocks cloud, fallback works

### Estimated effort: 1-2 sessions

---

## Phase 6 — Verification

**Goal**: Worker output is never blindly trusted.

### Deliverables
- [ ] `api/si/verifier.py` — deterministic checks (file existence, format, lint, tests)
- [ ] Evaluator interface for model-based evaluation
- [ ] Confidence scoring
- [ ] Contradiction detection (basic)
- [ ] Tests: deterministic checks pass/fail correctly, model evaluation interface works

### Estimated effort: 1-2 sessions

---

## Phase 7 — Unified SI Experience

**Goal**: The user interacts with one continuous intelligence, not a model selector.

### Deliverables
- [ ] `api/si/response_composer.py` — SI voice layer over worker output
- [ ] Activity timeline with routing decisions, data disclosures
- [ ] Task controls (pause, cancel, approve)
- [ ] Memory inspection and correction UI
- [ ] Privacy controls (local-only mode, provider restrictions)
- [ ] Cost tracking and disclosure inspection

### Estimated effort: 2-3 sessions

---

## Phase 8 — Optional Local Reasoning Model

**Goal**: Evaluate whether a small local model improves intent classification and context reranking.

### Prerequisites: Phases 2-6 must be working with deterministic rules first.

### Deliverables
- [ ] Benchmark: rules-only vs model-assisted intent classification
- [ ] Benchmark: rules-only vs model-assisted context reranking
- [ ] If model improves results by >20%: integrate 2-4B model as optional SI component
- [ ] If model doesn't improve results: keep rules-only, document why

### Estimated effort: 1-2 sessions (evaluation only)

---

## First Vertical Slice (Phase 2 Partial)

The highest-value slice that demonstrates the full architecture:

```
User sends a message
  → Intent classification (deterministic rules)
  → Journal retrieval (FTS5, already built)
  → Context compilation (sensitivity filter + token budget)
  → Privacy check (trust engine gates data by classification)
  → Worker selection (rankings + privacy eligibility)
  → Worker execution (existing backend infrastructure)
  → Deterministic verification (basic checks)
  → SI response composition (identity + verification status)
  → Activity audit (log routing decision + data shared)
  → Optional memory update (tag important outcomes)
```

This requires building: Context Compiler (partial), Trust Engine (minimal), Response Composer (minimal). Everything else uses existing infrastructure.

---

## Invariant

> ARES owns identity, memory, policy, planning, trust, and the user relationship. Models, agents, and tools are replaceable workers.