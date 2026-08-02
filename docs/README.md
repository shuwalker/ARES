# ARES Documentation Router

| Attribute | Value |
| --- | --- |
| **Status** | Current / canonical index |
| **Owner** | ARES maintainers |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Documentation ownership and task routing |

ARES documentation is development memory. It should let a new contributor
understand the product, find the correct state owner, and verify a change
without receiving a custom context prompt.

Start with [`../AGENTS.md`](../AGENTS.md), then read only the documents routed
for the task.

## Canonical documents

| Document | Owns | Does not own |
| --- | --- | --- |
| [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) | User experience, vocabulary, surfaces, product ownership | Process topology or route schemas |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Processes, state, adapters, data flow, invariants | UI copy or milestone status |
| [`API.md`](API.md) | Routes, settings keys, events, schemas | Product rationale |
| [`SECURITY.md`](SECURITY.md) | Trust, secrets, permissions, external actions | General UI layout |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Setup, testing, packaging, contribution workflow | Product requirements |
| [`CURRENT_STATE.md`](CURRENT_STATE.md) | Current milestone, delivered work, known gaps, next sequence | Permanent architecture decisions |

## Task routing

| Task | Required context |
| --- | --- |
| Change tabs, labels, or feature ownership | Product spec + relevant [`features/`](features/README.md) spec |
| Change controller state or runtime integration | Architecture + API + scoped controller instructions |
| Add or change a setting | Feature spec + API + persistence/prompt tests |
| Change agent delegation or sessions | Multi-agent spec + Architecture + API |
| Change native app or local service settings | System Settings spec + Development + API |
| Change permissions or data handling | Security + Architecture |
| Change installation, CI, or Docker | Development + Current State |
| Change a durable boundary | Existing [`decisions/`](decisions/README.md) records or a new ADR |

## Feature specifications

Feature specs translate product intent into code and acceptance evidence. They
must distinguish implemented behavior from intended behavior.

- [`features/si-personalization.md`](features/si-personalization.md)
- [`features/system-settings.md`](features/system-settings.md)
- [`features/multi-agent-orchestration.md`](features/multi-agent-orchestration.md)
- [`features/README.md`](features/README.md)
- [`templates/feature-spec.md`](templates/feature-spec.md)

## Decision records

Accepted durable choices live under [`decisions/`](decisions/README.md). An ADR
explains why a boundary exists and its consequences. It is not a changelog.

## Controller compatibility contracts

`services/controller/docs/` contains active, test-backed controller and
upstream compatibility contracts. Root documents remain canonical for the ARES
product, but controller documents must not be deleted until their runtime links
and contract tests are migrated.

## Freshness rules

- Every canonical or feature document names its status, owner, last verification
  date, and source of truth.
- Update documentation in the same commit as a contract change.
- Link code and tests instead of copying implementation detail into prose.
- If source and docs disagree, report the drift; do not silently choose one.
- Audits and proposals outside `docs/` are evidence, not authority.
- Remove obsolete guidance or replace it with a compatibility pointer.
- Update `CURRENT_STATE.md` at milestone boundaries, not after every small edit.

## Review question

Every pull request should answer: **Did this change alter product behavior,
ownership, a setting, an API, a trust boundary, or an accepted decision?** If
yes, name and update the owning document.
