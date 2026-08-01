# FastAPI connection adapter registry

Status: implemented for the production FastAPI application and React
Connections view.

## Purpose

ARES chooses a connected execution system from Local Profile and session
configuration without putting framework conditionals in HTTP or WebSocket
routers. The registry follows the useful part of Open WebUI's architecture: a
central model/connection catalog and a generic chat dispatcher. It does not copy
Open WebUI's application state or provider-specific route structure.

```text
FastAPI router
  -> RealtimeService
  -> AdapterRegistry.for_session(...)
  -> BaseLLMAdapter
  -> Ares Agent, JaegerAI, Hybrid, or a future runtime
  -> existing ARES run channel and journal
  -> framework-neutral WebSocket envelope
```

Resolution happens for each operation. `api.backend_selector` reads the active
profile's `ares_backend` default and any session-level `ares_backend` override.
An unknown connection is a bounded error; the registry does not silently run a
different framework.

## Interfaces

`BaseConnectionAdapter` defines normalized health and capabilities.
`BaseLLMAdapter` adds:

- `stream_chat` — start a runtime-owned streaming run and return its stable
  stream/session handle;
- `get_models` — return normalized model descriptors for this connection;
- `subscribe_stream` and `replay_stream` — observe the existing channel and
  durable journal;
- `stream_status` and `cancel_stream` — query and control the selected run.

The name is a compatibility term for the requested interface; concrete adapters
may wrap a full agent framework rather than a bare language-model endpoint.
Adapters translate protocols and own no sessions, run registries, worker maps,
cancel maps, journals, terminal processes, or model loops.

`BaseToolAdapter` is intentionally separate. MCP supplies tools to a selected
runtime; it is not itself a model or agent runtime. `McpToolAdapter` reports
already-known server/tool state without probing or spawning MCP processes and
does not expose command environments, headers, credentials, or raw schema
defaults.

## Implementations

- `AresAdapter` wraps the existing Ares Agent integration.
- `JaegerAdapter` wraps the existing JaegerAI/JROS bridge and preserves the
  explicit “Companion not configured” safety state.
- `HybridAdapter` requires both connections and uses the existing additive
  execution mode.
- `McpToolAdapter` normalizes MCP tool health and safe inventory.

The former Hermes integration is represented by `AresAdapter`; no new Hermes
product identity or configuration key is reintroduced.

The concrete framework adapters reuse `api.backends` for existing capability
metadata. Their default turn starter calls the handler-free transaction service
in `api.chat_runtime`; it is injectable in tests and is executed off the ASGI
event loop. The FastAPI router, realtime service, and framework adapters do not
import `api.routes`.

## Public discovery contracts

- `GET /api/connections` returns normalized runtime and tool connection records,
  the profile-selected runtime, stable capability identifiers, and safe health.
- `GET /api/connections/{connection_id}/models` returns normalized models for
  one execution connection. Current Ares/Hybrid discovery uses the network-free
  cached catalog; JaegerAI reports its runtime model when available.
- `GET /api/mcp/tools` returns the existing frontend inventory shape through the
  MCP tool adapter.

One failed connection-health probe does not fail the catalog. It returns a
`needs_attention` record, allowing Local Profile, navigation, settings, and
unrelated connections to remain usable.

## Adding another runtime

To add Gemini, a local model server, or another framework:

1. implement `BaseLLMAdapter` without adding global execution state;
2. map native events into the established ARES run journal/channel contract;
3. register the adapter in `AdapterRegistry`;
4. add a profile/session selection value through the existing backend setting;
5. add contract tests for health failure, model normalization, explicit context,
   selection, replay, cancellation, and unavailable behavior;
6. keep browser response and WebSocket envelope shapes unchanged.

Direct model providers and full execution frameworks remain separate concerns.
If a provider only supplies models to Ares Agent, register it with the provider
catalog rather than manufacturing a new agent-runtime adapter. If a connection
only supplies tools, implement `BaseToolAdapter`.

## Relationship to `api.runtime_adapter`

These interfaces select a connected framework and expose its capabilities.
`api.runtime_adapter.RuntimeAdapter` is the older run-protocol/runner boundary
for start, observe, status, and controls. They are complementary:

- the FastAPI registry answers “which configured connection handles this
  session?”;
- the run adapter answers “which execution transport owns or observes this
  run?”

Neither boundary may become a replacement runtime. A future external runner can
sit behind a concrete connection adapter while retaining the same journal,
cursor, control, and WebSocket contracts.
