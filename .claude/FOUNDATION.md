# ARES Product and Architecture Foundation

This document is the canonical internal definition of ARES for maintainers and
AI coding agents. Read it before changing product architecture, onboarding,
runtime integration, navigation, or the native applications. It defines the
intended system independent of implementation history. Older prose does not
override it.

## Product definition

### Naming (locked)

| Name | What it is |
|------|------------|
| **ARES** | **Only the application name** (product package: Mac app, WebUI, controller). Not a character, not an agent, not a second brain. |
| **Companion** (SI) | **Everything that is not a worker.** The personal Synthetic Intelligence experience: identity, journal, context, routing, scoring, permissions, workspace, and how the person is spoken to. |
| **Workers** | Models, agent frameworks, and tools that **execute** (Ollama, jros, Hermes, cloud LLMs, MCP servers, device tools). |

In product UI, the person talks to their **Companion**, not to “ARES.”
Technical docs may say “the ARES app hosts the Companion.”

### Architecture in one line

The **ARES application** hosts your **Companion**.
The Companion is the control plane + unified memory + technical intelligence.
**Workers** do generative/agent execution when the Companion routes work to them.

- **macOS app (primary on-device product):** full native capacity — same jobs as
  WebUI. Primary surface for living with the Companion on the host machine.
- **WebUI (remote / light client):** same Companion contracts; lighter shell for
  LAN / trusted Tailscale / other devices.
- **Controller service (FastAPI):** auth, persistence, adapters, APIs shared by
  native and web clients. Startable from the Mac app or terminal.

Mac-first, not Mac-only. Surfaces must not become incompatible products.

### Product surfaces (UI domains)

Primary navigation and domain boundaries live in
[docs/architecture/PRODUCT_SURFACES.md](../docs/architecture/PRODUCT_SURFACES.md).

Near-term top-level surfaces:

`Chat | Companion | Self | Workshop | Library | System`

Long-term, Chat demotes to advanced/developer mode; Companion remains the SI
front door. **Self** (knowledge about the person) is not Library (knowledge
owned by the person). **System** is infrastructure (including memory
*indexing*); Library holds knowledge *content*. Do not invent parallel
framework-branded top-level sections.

## Purpose

People use many AI tools, agents, models, and CLIs. Without a center, each tool
keeps its own conversations, memory, and context — quality fragments and control
is lost. The **Companion** (hosted by the ARES app) exists to:

1. Give one continuous SI experience over changing workers.
2. **Centralize conversations, artifacts, tool results, approvals, and
   preferences** so the person owns their data.
3. Let the person pick **local or cloud models** and **agent frameworks** as
   workers — never as the Companion’s identity.
4. Use **technical intelligence** (rules, scores, ranking, routing — not a
   competing chat LLM) to raise worker effectiveness on the person’s metrics.
5. Help manage work and devices through workers when configured — without the
   Companion pretending to be the execution engine.

A common use case: local model via **Ollama or jros** as a worker, which may
call other agentic tools. That is one configuration, not the architecture.

## What the Companion owns (everything that is not a worker)

The Companion is the non-worker layer of the product:

- Local Profile and how the Companion is named / presented;
- **unified conversation journal, artifacts, searchable context** (source of
  truth, with provenance of which worker produced each turn);
- context compilation (what package is sent to a worker this turn);
- capability routing and worker selection;
- effectiveness scoring and framework ranking;
- authentication, reachability, pairing, permissions, approvals;
- activity, health, and honest readiness presentation;
- workspace views and optional animated activity renderer;
- Mac + WebUI product surfaces that host this experience.

A Local Profile can be saved without any worker online. First-run **must force
an explicit worker choice** (Ollama, jros, Hermes, cloud, or explicit
“organizer only for now”). Nothing is pre-selected as a default worker.

Profile readiness is not execution readiness:

- **Profile ready:** Local Profile saved;
- **Connection ready:** a worker/provider is reachable;
- **Execution available:** at least one connected worker can perform the
  requested capability.

The product must not claim the Companion can execute work when no suitable
worker is connected.

## What workers own

Workers own **execution loops** and framework-native runtimes. Providers may
supply models, speech, vision, embeddings, search, or storage. Devices may
supply perception or embodiment.

The Companion does **not** re-implement JaegerAI, Hermes, Ollama, or cloud
agents as a competing worker. Adapters invoke them.

Workers may have **session scratchpads** (Option B lease). Durable SI memory
stays in the Companion journal (Option A source of truth). Scratchpads yield
summaries/artifacts back; they do not become lifelong identity.

No worker is the product identity. JaegerAI/jros, Hermes, Ollama, Claude,
Gemini, OpenAI, MCP servers are **named connections / workers**.

## Integration model

Use ordinary engineering boundaries:

```text
Person
  -> native controller or WebUI
  -> ARES request and capability selection
  -> runtime/provider/tool adapter
  -> connected system
  -> normalized execution events and result
  -> ARES presentation
```

Adapters translate protocols. They must not become replacement runtimes.
Framework selection, model/provider selection, and tool selection are separate
concerns even when one framework offers all three.

Every integration exposes a normalized connection record with stable
identity, kind, health, and capabilities. UI code should request capabilities
such as conversation, task execution, memory access, voice, tool use, approval,
run observation, and cancellation instead of branching on framework names when
a capability contract is sufficient.

## Multiple agents and models

ARES coordinates multiple models, agents, tools, and processes. It supports
parallel requests, specialized delegation, critique, comparison,
agreement/disagreement analysis, ranking by stated criteria, and synthesis.

Rejecting a mandatory company metaphor does **not** mean rejecting multi-agent
execution. Agents do not need to be employees, the user does not need to be a
CEO, and computation does not need to be expressed as hiring, firing, reporting
lines, headcount, or P&L. Company-style organization may be a user-selected
visual or application convention, but it is not the platform data model.

Every comparative or synthesized result should retain provenance: contributing
connection, runtime/model where available, execution state, source response,
evaluation criteria, and synthesis step.

## User interfaces

Use clear engineering and product terms in documentation. Do not make
metaphorical names such as "Cortex," "Orchestrator," "Meta-System," or
"Split-Brain" canonical architecture.

### Surfaces (not competing products)

| Surface | Role |
|---|---|
| **macOS app** | Primary full product on the host machine. Same capabilities as WebUI. Host lifecycle, permissions, native tools, menus. |
| **WebUI** | Light remote client to the same controller over localhost, LAN, or trusted Tailscale. |
| **CLI / terminal start** | Operator path to start/stop the controller without the GUI. |

Historical UI experiments (Scarf, HermesDesktop, Command Center, prototypes)
are **merge sources**, not parallel apps. Liked elements are integrated into
one shell; superseded trees leave production after their capabilities are
represented. Do not ship multiple entrypoints that fight each other.

The primary interface areas (native and web):

- **Conversation:** assistant identity, transcript, voice/text input, and
  immediate approvals or questions.
- **Workspace:** Today, Tasks, Code, Terminal, Artifacts, Schedules, and
  registered work views.
- **System status:** active executions, delegations, connected tools, memory in
  use, framework/provider connections, provenance, and diagnostics.
- **Settings:** Local Profile, authentication, reachability, connections,
  providers, permissions, appearance, and advanced configuration.

The UI must remain usable as a conventional application. Animated presentation
is an additional real-time view, not the only control surface.

## WebUI implementation boundary

The WebUI has one frontend implementation: the React and TypeScript application
under `webui/frontend/`, built with Vite and served from `webui/frontend/dist`.
The Python server owns authentication, persistence, local system access, and
the `/api/` contracts. React components do not consume framework-native shapes
directly; `frontend/src/shared/` adapters and translators normalize them into
ARES-owned contracts. A missing model or agent runtime degrades a capability,
not the application shell.

Do not recreate a second Vanilla JavaScript frontend or a `webui/static/`
fallback. Public assets, login support, public-share presentation, and cache
retirement files belong to `webui/frontend/public/`. A missing production build
must fail explicitly while leaving API routing intact.

## Animated 2D activity environment

ARES renders the SI's real computational activity as a living 2D
environment. Models, agents, tools, memory retrieval, schedules, and other
processes can have animated counterparts working at desks, stations, rooms, or
other locations. The intended experience is that the user can look inside the
SI's working environment and see the computer working for them.

The animation must be a renderer over real normalized execution records. It
must not maintain a separate task database or invent activity. Conventional
task/activity views and the 2D view must show the same underlying state.

The environment may visualize:

- which model, agent, tool, or process is active;
- its assigned work and current execution state;
- parallel and comparative work;
- transfers of artifacts or partial results;
- waiting approvals, failures, completion, and synthesis;
- resource usage and provenance where available.

Corporate scenery is allowed as an aesthetic option; corporate hierarchy is
not required by the architecture.

## Setup discipline derived from Paperclip

Paperclip is a reference for engineering discipline, not a product template.
ARES uses:

- Quickstart and Advanced setup paths;
- live credential and endpoint validation;
- reachability as an explicit choice: this machine, this network, or a private
  tailnet;
- safe reruns that detect and review existing configuration;
- a coherent run/configure/doctor command family;
- consistent status vocabulary and visual treatment;
- honest statements about what is configured, connected, and available.

ARES should not inherit a mandatory company, CEO, employee, org-chart,
headcount, or P&L model.

## Canonical vocabulary

Use these terms in product UI unless a technical detail view is explicitly
showing framework-native terminology:

| Concept | Term |
|---|---|
| Application / product package name | **ARES** (not a character; not spoken to as the SI) |
| Everything that is not a worker (SI experience) | **Companion** (preferred) or Assistant |
| Model / agent framework / executor | **Worker** (also Connection when listing links) |
| Work to accomplish | Task |
| Desired outcome | Goal |
| One execution attempt | Run |
| Time-triggered automation | Schedule |
| Work assigned to another process/agent | Delegation |
| Runtime/provider/tool linkage | Connection |
| Function offered by a connection | Capability |
| External operation | Tool |
| Local user configuration | Local Profile |
| Historical user-readable record | Activity |
| Diagnostic output | Logs |
| Built-in non-LLM optimization (rules, scores, ranks) | Companion scoring / routing (not “ARES agent”) |

Do not:

- present “ARES” as the chat persona or second brain;
- call a worker the Companion;
- invent a third named intelligence between Companion and workers.

Use separate status families:

- Task: Inbox, Ready, In progress, Waiting, Done, Canceled.
- Run: Queued, Running, Needs input, Completed, Failed, Canceled.
- Connection: Connected, Connecting, Needs attention, Offline.
- Credential: Not configured, Validating, Valid, Invalid, Expired.

Internal identifiers do not create competing product vocabulary. Technical
detail views may display a connection's native terminology when needed for
configuration or diagnosis.

## Rules for future changes

Before implementing an architecture or UI change, identify the state owner,
capability contract, persistence layer, and renderer affected.

Do not:

- make the main UI structurally dependent on one named framework;
- treat ARES as an agent or re-implement a framework’s execution loop;
- confuse a saved profile with a working execution connection;
- pre-select a default backend at first run without an explicit user choice;
- trap conversation history only inside a framework-private store with no
  ARES-visible journal/provenance path;
- create a second state store for the animated environment;
- hide provenance for multi-agent comparison or consequential external action;
- expose framework concepts globally when a stable ARES concept exists;
- introduce another synonym for Task, Run, Schedule, Connection, or Capability;
- make the native app a thin browser wrapper while claiming product parity;
- make the native app and WebUI separate products with different concepts;
- ship parallel UI shells (prototype vs routed app vs abandoned native trees)
  without a single merge target.
