# ARES Memory and Context Model

## Memory Architecture

The SI has one memory system: the Journal. Workers have leased scratchpads only.

### Memory Types

| Type | What | Storage | Lifecycle |
|------|------|---------|-----------|
| **Episodic** | Conversations, events, actions | `conversations` + `messages` tables | Permanent, searchable |
| **Semantic** | Facts, preferences, decisions, commitments | `documents` table (tags: decision, preference, commitment) | Permanent, searchable |
| **Working** | Current task state, active plan | `plans` table (not yet built) | Cleared when task completes |
| **Scratchpad** | Worker temporary state | Not stored in Journal; worker-internal | Cleared when worker task completes |

### Memory Lifecycle

```
Event (conversation turn, document, decision)
  │
  ▼
Ingestion → classify type (episodic, decision, preference, etc.)
  │
  ▼
Sensitivity Label → public, personal, private, sensitive, secret
  │
  ▼
Deduplication → check if this fact already exists; merge if so
  │
  ▼
Importance Scoring → based on recency, relevance, user emphasis
  │
  ▼
Entity/Project Association → tag with relevant projects, people, topics
  │
  ▼
Short-term Storage → immediately searchable in Journal
  │
  ▼
Consolidation (periodic) → summarize old conversations, extract decisions
  │
  ▼
Retrieval → Context Compiler pulls relevant items per task
  │
  ▼
Correction → user can edit, delete, or reclassify any memory
```

### Current Journal Schema vs Target

| Feature | Current | Target |
|---------|---------|--------|
| Conversations | ✅ 359 from 6 sources | Same |
| Messages | ✅ 48,657 with FTS5 | Same |
| Documents | ✅ 628 from 5 sources | Same |
| Sensitivity labels | ❌ Not present | Add `sensitivity` column |
| Importance scoring | ❌ Not present | Add `importance` column |
| Entity/project tags | ❌ Not present | Add `tags` column |
| Decision tracking | ❌ Not present | Add `is_decision` flag |
| Provenance tracking | ❌ Not present | Add `source_type`, `confidence` columns |
| Memory corrections | ❌ Not present | Add `corrections` table |
| Consolidation | ❌ Not present | Add `summaries` table |

## Context Compiler

The Context Compiler is the highest-priority missing system. It decides what information the SI sends to a worker for each task.

### Input

```python
@dataclass
class CompilationRequest:
    user_message: str                # What the user just said
    conversation_id: str | None      # Current conversation (if continuing)
    active_plan: Plan | None         # Current plan (if mid-task)
    target_worker: str | None        # Which worker will receive this
    token_budget: int                # Max tokens for the briefing
```

### Compilation Steps

```
1. Classify Intent
   → What is this about? (coding, research, conversation, action, etc.)
   → Deterministic rules first (keyword matching, conversation topic)
   → Small model classification only if rules are insufficient

2. Retrieve Context
   → FTS5 search for relevant conversations and documents
   → Temporal boost: recent > old
   → Decision boost: final decisions > exploration drafts
   → Project boost: same project > different project
   
3. Filter for Privacy
   → Apply Trust Engine rules
   → Remove items the target worker can't see
   → Redact sensitive content
   → Log all redactions in the context manifest

4. Budget Packing
   → Sort retrieved items by relevance score
   → Pack items until token budget is reached
   → Prioritize: recent conversation > decisions > project context > background
   → If over budget: summarize older items

5. Assemble Briefing
   → SI identity block (who the SI is, principles)
   → User context block (preferences, relevant facts)
   → Project context block (current project info)
   → Recent conversation block (last N turns)
   → Relevant memories block (search results)
   → Constraints block (what to do/not do)
   → Output requirements block (format, length, style)
   → Context manifest (what was included, excluded, redacted)
```

### Context Manifest

Every briefing includes a manifest explaining what was included, excluded, and redacted:

```python
@dataclass
class ManifestEntry:
    item_id: str
    action: str          # "included", "excluded", "redacted", "summarized"
    reason: str          # "relevant", "over_budget", "privacy:private_to_cloud", "sensitivity:requires_approval"
    original_size: int   # tokens before any processing
    final_size: int      # tokens after redaction/summarization
```

### Why Deterministic First, Model Second

The Context Compiler uses deterministic rules for 80% of its work:
- FTS5 search is deterministic and instant
- Temporal boosting is a date comparison
- Privacy filtering is a simple classification check
- Budget packing is a knapsack sort

Only the intent classification and relevance reranking steps benefit from a small model. And even those can start with rules (keyword matching, conversation topic matching) and add model classification later.

### Tests Required

1. **Irrelevant context is excluded** — search for "journal importer" does not include conversations about "boot bug" unless they overlap
2. **Sensitive context is redacted** — private data is not sent to cloud workers
3. **Token budgets are respected** — total briefing tokens ≤ budget
4. **Context manifests are accurate** — every item is accounted for
5. **Secret data never appears** — API keys, passwords are never in any briefing
6. **Recent > old** — given equal relevance, recent conversations rank higher
7. **Decisions > exploration** — conversations tagged as "decision" rank higher than drafts