# ADR 0001: ARES Owns Product Identity

| Attribute | Value |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-08-01 |
| **Owners** | Product and architecture maintainers |

## Decision

ARES hosts one continuous SI identity. Models and agent frameworks are
replaceable workers and never become the product identity.

## Why

Users need continuity across model changes, outages, local/cloud selection, and
specialized execution. Binding identity to one worker fragments memory,
preferences, sessions, and trust.

## Consequences

- Identity and calibration are ARES-owned state.
- Worker provenance remains visible without renaming the SI.
- Framework-specific terminology stays in connection or diagnostic views.
- A worker can be replaced without migrating the user relationship.

See `docs/PRODUCT_SPEC.md` and `docs/features/si-personalization.md`.
