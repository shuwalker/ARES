# Source ownership and capability disposition

ARES ships one macOS product architecture:

- `ARES-Mac_os/Sources/ARES` owns the native lifecycle and WKWebView shell.
- `ARES-Mac_os/Sources/ARESCore` owns native services and MCP tools.
- `ARES-Mac_os/Sources/ARESNativeMCP` exposes those tools to the web runtime.
- `webui/fastapi_app` owns HTTP/WebSocket transport.
- `webui/api` owns server-side product services and runtime adapters.
- `webui/frontend/src` owns the visible product experience.

Source code outside a build target or one of these runtime roots is not an
integration strategy. Experimental work belongs on a branch until it has an
owner, entry point, license, and verification.

## Retired source imports

### Scarf

Upstream: <https://github.com/awizemann/scarf> (MIT, Alan Wizemann)

The imported `ScarfCore`, `ScarfDesign`, `ScarfMac`, `ScarfIOS`, and
`ScarfIOSApp` trees formed another complete macOS/iOS application. They owned
their own navigation, persistence, settings, runtime connection model, chat,
projects, Kanban, cron, skills, MCP, webhooks, and update lifecycle. Compiling
them beside ARES would produce competing sources of truth rather than modules.

Capability disposition:

| Scarf capability | Active ARES owner |
| --- | --- |
| Chat, approvals, model selection | `ConversationPage` + runtime adapters |
| Projects and project sessions | `ProjectsPage` + product-state/project APIs |
| Kanban | `BoardChatPage` + product-state/kanban APIs |
| Cron and schedules | `RoutinesPage` + schedule APIs |
| Skills and templates | `SkillsPage`, `SkillStudioPage`, skills APIs |
| MCP servers and tools | `McpPage`, native MCP bridge, MCP APIs |
| Credentials | `SecretsPage` + profile-scoped secret vault |
| Platforms and webhooks | `ConnectionsPage`, `WebhooksPage`, delivery adapters |
| Health, logs, usage | `TodayPage`, `ActivityPage`, `UsageCostPage`, health APIs |
| Profiles and settings | Local Profile + server-authoritative settings |

### Hermes Desktop

Upstream: <https://github.com/dodo-reach/hermes-desktop> (MIT, dodo-reach)

The imported tree was another full SwiftUI app centered on SSH-only remote
Hermes administration. ARES instead treats Hermes as one optional execution
adapter and keeps workspace, terminal, sessions, skills, usage, and schedules
behind shared product contracts. The duplicate Swift app and its bundled
screenshots therefore had no reachable ARES entry point.

Direct remote-host administration is not claimed by ARES today. If it is
added, it must be a transport adapter behind the existing Connections,
Workspace, Terminal, Sessions, Skills, Usage, and Schedule contracts. It must
not reintroduce a second application state tree.

### Hypura extraction

Upstream: <https://github.com/t8/hypura> (`Cargo.toml` declares MIT)

The copied Rust extraction omitted `Cargo.toml`, `Cargo.lock`, `hypura-sys`,
vendored/patch dependencies, tests, CLI/server entry points, and license
material. It could neither compile nor link to ARES and was removed. Local
inference remains an execution-backend concern; currently ARES exposes Ollama
and other maintained runtimes through the common backend router.

## Admission rule

New source is admitted only when all of the following are present:

1. an owning build/runtime target;
2. a reachable product entry point or an explicitly invoked library contract;
3. preserved upstream license/provenance when derived from third-party work;
4. tests covering its boundary and degraded state;
5. no competing persistence, navigation, or lifecycle root.

CI rejects source files under `attic/` so orphaned implementations cannot be
hidden there again.

The same guard rejects the retired `webui/api/langgraph_study`, `evolution`,
`steering`, `compression_eval`, and `hwfit` roots. They were imported studies,
experiments, or partial ports with no FastAPI router, active service owner, or
product entry point. The reachable `webui/api/research` service remains because
it is owned by `fastapi_app/routers/research.py`.

It also rejects Python modules directly under `webui/api/adapters/`. That
surface consisted of unreachable device stubs and a registered astronomy
router whose service was never initialized. Several methods reported connected
or returned fabricated values without I/O. The real compiled astronomy code
remains in `ARESCore/Astronomy`; Safari MCP remains under
`webui/api/adapters/safari_mcp` with its own executable integration boundary.
