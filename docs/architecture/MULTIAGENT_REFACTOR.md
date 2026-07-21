# ARES Multi-Agent Refactor

## Problem

ARES started as a Hermes WebUI fork rewired to use JaegerAI. Along the way it
built its own agent brain (SI layer: identity, memory, context compiler, trust
engine, planner, evaluator) that duplicates what JaegerAI already does better.
Meanwhile, cloud AI subscriptions (Claude, Gemini, Grok, etc.) are wired as
thin single-turn API calls instead of going through JaegerAI's full agent loop.

## Vision

ARES is the **orchestrator** — like LangGraph or CrewAI — that coordinates
multiple agents into something bigger than any one of them:

- **JaegerAI** = primary agent (persona, memory, skills, tools, local inference)
- **Cloud AIs** (Claude, Gemini, Grok, etc.) = additional agents, routed through
  JaegerAI's adapter system so they get persona + tools + memory, not raw calls
- **CLI tools** (Claude Code, Codex, Gemini CLI, Grok) = standalone workers for
  specialized tasks

The conductor doesn't play instruments. It directs them.

## What stays in ARES

These are ARES's actual product value — multi-agent orchestration that no
single agent provides:

| Module | Purpose | Status |
|--------|---------|--------|
| `si/orchestrator.py` | Step-by-step plan execution, retries, fallbacks | Keep |
| `si/planner.py` | Break goals into steps, assign workers | Keep |
| `si/router.py` | Pick best worker for a task | Keep |
| `si/evaluator.py` | Verify worker outputs | Keep |
| `si/response_composer.py` | Compose final answer from worker results | Keep |
| `si/types.py` | Shared type definitions | Keep |
| `si/protocols.py` | Worker adapter protocol | Keep |
| `si/worker_registry.py` | Registry of available workers | Keep |
| `si/bridge.py` | Wire orchestration into existing backend system | Keep (refactor) |

## What gets deleted from ARES (JaegerAI does this better)

| Module | Why delete | JaegerAI replacement |
|--------|-----------|---------------------|
| `si/identity.py` | ARES has its own identity system | JaegerAI `personality/` |
| `si/memory.py` | ARES has its own memory schema | JaegerAI `core/memory/` |
| `si/context_compiler.py` | ARES assembles context independently | JaegerAI `core/context.py` |
| `si/trust_engine.py` | ARES has its own privacy engine | JaegerAI `agent/safety.py` |
| `si/user_model.py` | ARES maintains a separate user model | JaegerAI `core/people.py` |
| `si/migration.py` | Migrating columns ARES shouldn't own | JaegerAI manages its own schema |

## What gets refactored

### Backend routing — JaegerAI becomes the primary agent path

Current: ARES picks a backend, each backend is a thin adapter. JaegerAI is just
one option among many. Cloud AIs bypass JaegerAI entirely.

After: When JaegerAI is available, ALL agent turns go through JaegerAI. Cloud
AI model selection becomes a JaegerAI concern (which adapter to use), not an
ARES concern. ARES just says "use Claude" and JaegerAI handles the adapter,
persona, memory, tools, and streaming.

### Cloud AI backends — delegate to JaegerAI

Current `cli_backends.py` has direct OpenAI/xAI/Gemini SDK calls. These become
unnecessary because JaegerAI's `OpenAIAdapter` and `AnthropicAdapter` already
handle the same providers with full tool support, streaming, and persona
integration.

The CLI backends (Claude Code, Codex, Grok CLI) stay — they're standalone
tools that ARES can spawn as workers in the orchestration layer.

### `si/bridge.py` — simplify

Currently bridges the SI pipeline into the AgenticBackend system. After the
refactor, it bridges the orchestrator to JaegerAI via JrosClient. Much simpler.

## Execution order

1. Delete SI modules that JaegerAI owns (identity, memory, context_compiler,
   trust_engine, user_model, migration)
2. Refactor `si/bridge.py` to delegate to JaegerAI instead of running its own
3. Replace cloud API backends with JaegerAI adapter routing
4. Keep CLI backends as standalone workers
5. Wire the orchestrator (planner → router → JaegerAI/CLI → evaluator → compose)
6. Update tests — remove SI unit tests for deleted modules, add integration
   tests for JaegerAI bridge
7. Update FOUNDATION.md to reflect the new architecture

## Dependency on JaegerAI

ARES will import `jaeger_ai.interfaces.client.JrosClient` and
`jaeger_ai.interfaces.bridge` to communicate with JaegerAI. JaegerAI remains a
separate repo and a separate process. ARES talks to it over the NDJSON bridge
protocol — no direct import of JaegerAI internals.

For cloud AI routing, ARES tells JaegerAI which model/adapter to use via the
bridge protocol. JaegerAI handles the actual API calls, credentials, persona
injection, and tool execution.