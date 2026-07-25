# ARES product vision (locked)

Aligned with [`.claude/FOUNDATION.md`](../.claude/FOUNDATION.md).

## Naming (most important)

| Word | Meaning |
|------|---------|
| **ARES** | **Just the application name** — Mac app, WebUI, controller package. Not a character. Not an agent. Not who you talk to. |
| **Companion** | **Everything that is not a worker** — your personal SI: identity, journal, context, routing, scores, permissions, workspace. Who you talk to. |
| **Workers** | LLMs, agent frameworks, tools that execute (Ollama, jros, Hermes, cloud, MCP, devices). |

```text
You  ←→  Companion (non-worker intelligence + memory + control)
              hosted by the ARES application
                    ↓ routes work
              Workers (predictive / agent execution)
```

## One sentence

The **ARES app** hosts your **Companion**: full Mac product on device, light
WebUI off device, unified journal and technical control so every worker stops
living in a silo.

## Surfaces

| Surface | Role |
|---------|------|
| **macOS app** | Primary interaction with the Companion on the host machine. |
| **WebUI** | Light remote client to the same Companion/controller (LAN / Tailscale). |
| **Controller** | FastAPI: APIs, auth, persistence, adapters. |

## Companion vs workers

| Companion (not a worker) | Workers |
|--------------------------|---------|
| Profile, name, preferences | Ollama, jros, Hermes, cloud models |
| Unified journal (source of truth) | Session scratchpads only (leased) |
| Context compiler, routing, ranking | Sense → think → act execution |
| Permissions, approvals, reachability | Tool runtimes they own |
| Honest status / scores | Generate and act under Companion package |

## Memory

- **Option A primary:** Companion journal is source of truth; workers are
  executors for a turn.
- **Option B scratchpad:** advanced workers may lease short-term memory for a
  task, then yield results back; wipe scratchpad.

## Intelligence inside the Companion

Not “another chat LLM named ARES.”

Technical / programmed intelligence (rules, metrics, ranking, optional classical
ML later) that makes **workers** more effective on **your** scores — still
part of the **Companion**, still not a worker.

## UI merge policy

Liked elements from Scarf, HermesDesktop, Command Center, prototypes merge into
**one ARES app shell** for the Companion — not parallel products.

## Priority path

1. Activation with explicit worker choice
2. Honest connections
3. Chat through Companion journal
4. Scoring / ranking workers
5. Mac full capacity + remote WebUI parity
