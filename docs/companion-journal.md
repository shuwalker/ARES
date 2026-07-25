# Companion journal & worker rankings

## Naming

| Term | Meaning |
|------|---------|
| **ARES** | Application package only |
| **Companion** | Everything that is not a worker (identity, journal, routing, scores) |
| **Workers** | Ollama, jros, Hermes, cloud, MCP, devices |

## Journal (source of truth)

- Durable conversation history lives in **Companion-owned sessions** (`ares_backend` / `backendId` on the session).
- Message-level `worker_id` is optional provenance when present.
- Workers may use **session scratchpads** only; they must not become lifelong SI memory.

## Rankings (technical intelligence)

API:

- `GET /api/workers/rankings` — leaderboard + weights
- `POST /api/workers/evaluations` — record metrics for a worker

Metrics (0–100): `task_success`, `faithfulness`, `safety`, `latency`, `cost`, `tool_efficiency`, `user_preference`.

Storage: profile-scoped `webui/worker-rankings.json` under ARES home.

UI: Connections → **Worker effectiveness**.
