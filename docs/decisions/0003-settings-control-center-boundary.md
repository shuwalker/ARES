# ADR 0003: Settings and Control Center Have Separate Ownership

| Attribute | Value |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-08-01 |
| **Owners** | Product and Web UI maintainers |

## Decision

Settings owns durable configuration of the SI, presentation, conversation,
desktop application, and the local ARES runtime. This includes startup and
background behavior, menu-bar presence, shortcuts, local service controls,
updates, and diagnostic/reset actions.

Control Center owns the live digital environment: active agents and delegated
tasks, AI workers and tools, connected services and devices, approvals,
memory/privacy, autonomy, activity, and alerts.

## Why

The useful distinction is configuration versus operation. Settings answers
“How is ARES configured?” Control Center answers “What is ARES connected to,
what is working now, and what needs my attention?” Keeping that mental model
avoids duplicated controls without hiding the system's capabilities.

## Consequences

- Settings remains a utility, not a product environment.
- Memory/privacy and permissions/autonomy remain in Control Center.
- The application settings section is named **System**. Its legacy `app`
  deep-link identifier remains compatible.
- Local ARES service configuration and restart/reset actions live in System
  Settings; live agent, worker, tool, and device operations live in Control
  Center.
- SI Settings may show a compact active-worker indicator that links to Control
  Center.
- Settings may expose durable multi-agent defaults, while Control Center owns
  live plans and worker activity.
- Ownership tests prevent moved controls from returning to Settings.

See `docs/PRODUCT_SPEC.md` and `docs/features/si-personalization.md`.
