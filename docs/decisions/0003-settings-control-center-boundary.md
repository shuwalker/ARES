# ADR 0003: Settings and Control Center Have Separate Ownership

| Attribute | Value |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-08-01 |
| **Owners** | Product and Web UI maintainers |

## Decision

Settings owns personal and application preferences. Control Center owns
operational infrastructure, data policy, permissions, and autonomy.

## Why

Mixing personality with authority makes a complex system harder to understand
and encourages duplicated controls. Users should know whether they are changing
how the SI behaves socially or what it may access and do.

## Consequences

- Settings remains a utility, not a product environment.
- Memory/privacy and permissions/autonomy remain in Control Center.
- SI Settings may show a compact active-worker indicator but not gateway setup.
- Ownership tests prevent moved controls from returning to Settings.

See `docs/PRODUCT_SPEC.md` and `docs/features/si-personalization.md`.
