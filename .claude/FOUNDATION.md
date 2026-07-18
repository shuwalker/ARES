# ARES Product and Architecture Foundation

This document is the canonical internal definition of ARES for maintainers and
AI coding agents. Read it before changing product architecture, onboarding,
runtime integration, navigation, or the native applications. It defines the
intended system independent of implementation history. Older prose does not
override it.

## Product definition

ARES is a simplified macOS controller application and a remotely accessible
WebUI for operating and communicating with a personal Synthetic Intelligence
(SI).

The macOS application supplies a menu-bar interface and expected host
controls: start, stop, restart, status, diagnostics, opening the WebUI, and
useful native macOS integration. It must remain possible to start the same
server from a terminal. The WebUI is the universal interaction surface used on
the host Mac and from other authenticated devices over an explicitly configured
private network.

ARES is Mac-first, not Mac-only. Native shells and the WebUI are interfaces to
one product and should not acquire incompatible concepts or configuration.

## Purpose

Agent frameworks expose different session, model, tool, memory, and execution
interfaces. ARES provides a stable user experience over those changing systems.
The person communicates with one SI identity while ARES connects the runtimes,
models, agents, tools, memory services, voice services, and devices required to
perform work.

The WebUI communicates with frameworks, providers, tools, memory services, and
devices only through explicit integration interfaces. Streaming, recovery,
terminal, workspace, authentication, and provider behavior are ARES product
capabilities rather than implicit properties of one agent framework.

## What ARES owns

ARES owns the product and presentation layer:

- macOS controller and other native shells;
- WebUI navigation and interaction design;
- Local Profile and presentation preferences;
- assistant display identity and connection status;
- authentication, reachability, and device access;
- permission and approval presentation;
- capability discovery and connection configuration;
- normalized activity, provenance, and health presentation;
- conventional work views and the animated 2D activity view.

A Local Profile can be created and saved without a running agent framework. It
contains the person's preferred name, assistant display name, avatar and
voice preferences, permission posture, configured areas, authentication,
reachability, and connection preferences.

Profile readiness is not execution readiness. The UI must distinguish:

- **Profile ready:** local configuration was saved;
- **Connection ready:** a framework or provider is reachable;
- **Execution available:** at least one connected system can perform the
  requested capability.

ARES must not claim that the SI can execute work when no suitable runtime or
provider is connected.

## What connected systems own

Agent frameworks own their execution loops, runtime sessions, framework-native
tools, runtime persona behavior, and runtime memory. Providers may supply
models, speech, vision, embeddings, search, storage, or other capabilities.
Devices may supply perception or embodiment.

ARES may configure, select, invoke, observe, and present these systems. It must
not silently fork their authoritative runtime persona or memory into a competing
ARES implementation. An ARES-native execution or memory service would need to
be explicit and governed by the same interfaces as every other connection.

No framework is the UI identity. JaegerAI, Ares Agent, Claude, Gemini, OpenAI,
local models, MCP servers, and additional systems are named connections or
capability providers. A preferred or default framework can exist without
becoming an installation prerequisite for saving the Local Profile.

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

The primary interface areas are:

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
| User-facing SI identity | Assistant or Companion |
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
- confuse a saved profile with a working execution connection;
- duplicate framework-owned execution or memory without an explicit service;
- create a second state store for the animated environment;
- hide provenance for multi-agent comparison or consequential external action;
- expose framework concepts globally when a stable ARES concept exists;
- introduce another synonym for Task, Run, Schedule, Connection, or Capability;
- make the native app and WebUI separate products.
