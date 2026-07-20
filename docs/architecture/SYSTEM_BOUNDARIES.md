# ARES System Boundaries

## What ARES Owns

ARES is the codebase. Inside ARES, these subsystems belong to the SI (Companion):

| Subsystem | Owns | Does NOT Own |
|-----------|------|-------------|
| **Identity** | Name, persona, behavioral principles, loyalty to user | Worker identities, model personalities |
| **Memory** | Journal, user model, preferences, decisions, commitments | Worker session scratchpads (leased, not owned) |
| **Context** | What context to send, what to redact, what budget to use | Raw model token limits |
| **Trust** | Data classification, provider eligibility, approval gates | Worker trust models |
| **Planning** | Task decomposition, step ordering, dependency tracking | Worker internal reasoning |
| **Routing** | Which worker for which task, based on capability + privacy + cost + preference | Worker availability (workers report this) |
| **Verification** | Checking worker output against expectations | Worker internal quality |
| **Response** | Final voice, uncertainty framing, activity summary | Raw worker output |
| **Policy** | What actions require approval, what data can leave the device | Worker policy enforcement |

## What Workers Own

Workers own execution. They do NOT own identity, memory, policy, or the user relationship.

| Worker | Owns | Does NOT Own |
|--------|------|-------------|
| Hermes Agent | Tool execution, terminal ops, file ops, agent loops | SI identity, memory, policy |
| Claude | Text generation, code generation, reasoning | Context selection, data boundaries |
| Gemini | Research, long-context reasoning | Memory, user preferences |
| Grok | Real-time information, analysis | Trust decisions, privacy filtering |
| OpenAI/Codex | Code generation, general reasoning | Task routing, verification |
| Ollama (local) | Local inference, privacy-safe computation | Cross-session memory |
| MCP servers | Tool execution within their domain | System-level access, data boundaries |

## Data Flow Boundaries

```
User
  │
  ▼
┌─────────────────────────────┐
│ SI (Companion)              │
│                             │
│  ┌──────────┐  ┌─────────┐ │
│  │ Identity  │  │ Memory   │ │
│  └──────────┘  └─────────┘ │
│  ┌──────────┐  ┌─────────┐ │
│  │ Trust    │  │ Policy   │ │
│  └──────────┘  └─────────┘ │
│  ┌──────────┐  ┌─────────┐ │
│  │ Context  │  │ Routing  │ │
│  └──────────┘  └─────────┘ │
│  ┌──────────┐  ┌─────────┐ │
│  │ Planning │  │ Verify   │ │
│  └──────────┘  └─────────┘ │
│  ┌──────────┐               │
│  │ Response │               │
│  └──────────┘               │
│                             │
│  ← Filtered briefing only → │──── Worker 1 (Claude)
│  ← Filtered briefing only → │──── Worker 2 (Ollama)
│  ← Filtered briefing only → │──── Worker 3 (Hermes)
│                             │
│  ← Structured result only ← │──── Worker 1 returns
│  ← Structured result only ← │──── Worker 2 returns
│                             │
└─────────────────────────────┘
```

**Critical rule**: Workers never see the full Journal. They only see the briefing that the Context Compiler assembles. Workers never see other workers' outputs unless the SI explicitly includes them in a briefing.

## Boundary Enforcement

1. **Workers cannot directly mutate permanent memory** — only the SI writes to the Journal
2. **Workers cannot bypass trust policy** — the Trust Engine gates all data before it reaches workers
3. **Workers cannot access secrets** — API keys are injected by the SI, never included in briefings
4. **Workers cannot initiate actions** — the SI dispatches all tasks; workers only respond
5. **Worker outputs are untrusted input** — the Evaluator checks all results before the Response Composer presents them to the user