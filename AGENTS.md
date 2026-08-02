# ARES Agent Entry Point

| Attribute | Value |
| --- | --- |
| **Status** | Current / canonical |
| **Owner** | ARES maintainers |
| **Last verified** | 2026-08-01 |
| **Authority** | Repository-wide instructions and documentation router |

Read this file before changing ARES. It gives coding agents the minimum stable
context and routes deeper work to the document that owns it. Do not copy this
context into tool-specific instruction files.

## What ARES is

ARES is a Mac-first, local-first application that hosts a persistent Synthetic
Intelligence experience. ARES owns identity, user context, sessions, policy,
permissions, task state, artifacts, routing, and verification. Replaceable
workers such as Jaeger AI, Hermes, Codex, Claude, Ollama, and cloud models supply
reasoning or execution.

The product principle is **one identity, many workers**. The user talks to one
continuous SI. ARES may plan work, create sessions, and delegate steps to
specialist workers, but a worker is never the product identity.

## Non-negotiable boundaries

- ARES writes only ARES-owned state. Read external worker stores read-only.
- Invoke workers through adapters; do not absorb their execution loops.
- Normalize worker payloads before they reach product UI components.
- Keep worker, model/provider, and tool selection as separate concerns.
- New state and UI use `jaeger_local` and “Jaeger AI.” `jros` names are accepted
  only at explicit legacy-input boundaries.
- Settings owns stable configuration of the SI, presentation, conversation,
  desktop application, and local ARES runtime. Control Center is the live
  dashboard for agents, delegated work, AI tools, connected services, devices,
  approvals, memory/privacy, and autonomy.
- Settings is a utility destination, not a seventh environment.
- Preserve user changes in a dirty worktree and avoid unrelated rewrites.

## Product surfaces

The primary environments are:

`Agent | Engineering | Studio | Life | Library | Control Center`

The Settings utility contains:

`SI | Appearance | Chat | System`

See [Product Specification](docs/PRODUCT_SPEC.md) and the relevant feature
specification before changing navigation or ownership.

## Repository map

| Path | Responsibility | Scoped instructions |
| --- | --- | --- |
| `apps/web/` | React/Vite Web UI | [`apps/web/AGENTS.md`](apps/web/AGENTS.md) |
| `apps/macos/` | Native Swift app and ARESCore | [`apps/macos/AGENTS.md`](apps/macos/AGENTS.md) |
| `services/controller/` | FastAPI controller and compatibility API | [`services/controller/AGENTS.md`](services/controller/AGENTS.md) |
| `core/` | ARES-owned SI, memory, event, and knowledge modules | Architecture rules apply |
| `integrations/` | Worker/provider/tool adapters | Worker boundary rules apply |
| `docs/` | Product and engineering memory | [`docs/README.md`](docs/README.md) |

## Read by task

| If changing… | Read first |
| --- | --- |
| Product language, tabs, or ownership | [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md), relevant `docs/features/` spec |
| Processes, state, adapters, or events | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Routes, settings keys, or wire formats | [`docs/API.md`](docs/API.md) |
| Permissions, secrets, or external actions | [`docs/SECURITY.md`](docs/SECURITY.md) |
| Setup, tests, packaging, or deployment | [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) |
| Current milestone or known gaps | [`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md) |
| SI Settings | [`docs/features/si-personalization.md`](docs/features/si-personalization.md) |
| App/System Settings | [`docs/features/system-settings.md`](docs/features/system-settings.md) |
| Agent delegation or orchestration | [`docs/features/multi-agent-orchestration.md`](docs/features/multi-agent-orchestration.md) |

When documents disagree, do not choose silently. Source and tests describe
implemented behavior; accepted architecture/decision records describe required
boundaries; feature specs must label intended behavior and known gaps. Report
the drift and update the affected contract with the code change.

## Working protocol

1. Run `git status -sb` and identify existing user work.
2. Read `docs/CURRENT_STATE.md` and route through `docs/README.md`.
3. Inspect the source and tests named by the relevant feature spec.
4. State the owner of changed state, the contract, and the acceptance evidence.
5. Make the smallest coherent change. Do not mix repository-wide cleanup into a
   feature commit.
6. Update docs in the same commit when product behavior, ownership, settings,
   routes, or architectural decisions change.
7. Run proportionate verification and report failures honestly.

## Standard verification

```bash
cd apps/web
npm run typecheck
npm test -- --run
npm run build

cd ../..
swift test

cd services/controller
./scripts/test.sh
```

Use targeted controller tests while iterating. The complete controller suite is
large and currently has inherited reorganization debt recorded in
`docs/CURRENT_STATE.md`.

## Documentation contract

- Canonical information has one owner; other files link to it.
- Feature specs include status, data ownership, related code/tests, acceptance
  criteria, and known gaps.
- Decision records explain durable choices, not implementation diaries.
- Planning notes and audits are not canonical until their accepted decisions
  are merged into `docs/`.
- Retired documents are removed or clearly marked; active tests and runtime
  links must be migrated before deletion.
- Never claim intended behavior is implemented without a source or test anchor.
