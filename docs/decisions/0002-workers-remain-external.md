# ADR 0002: Workers Remain External

| Attribute | Value |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-08-01 |
| **Owners** | Architecture maintainers |

## Decision

ARES invokes workers through subprocess or network adapters. It does not copy
their execution loops or write their stores.

## Why

Independent processes preserve dependency isolation, worker upgradeability,
native session semantics, and clear data ownership.

## Consequences

- ARES continues a worker session through its supported resume contract.
- External history is read-only unless an explicit write contract exists.
- Adapters normalize capabilities and events into ARES contracts.
- Worker crashes degrade a capability rather than the application shell.

See `docs/ARCHITECTURE.md`.
