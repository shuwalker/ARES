# Feature Specifications

| Attribute | Value |
| --- | --- |
| **Status** | Current / canonical index |
| **Owner** | ARES maintainers |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Linked feature documents, code, and tests |

Feature specifications connect product intent to implementation. Create one
when a feature spans multiple layers, has important ownership boundaries, or
would otherwise require repeating context to every new contributor.

## Active specifications

| Feature | Status | Primary owner |
| --- | --- | --- |
| [`si-personalization.md`](si-personalization.md) | Active / partially implemented | Settings + controller prompt assembly |
| [`system-settings.md`](system-settings.md) | Planned / partially implemented | Web Settings + native macOS + controller lifecycle |
| [`multi-agent-orchestration.md`](multi-agent-orchestration.md) | Active / partially implemented | Controller orchestration + Agent/Control Center UI |

Use [`../templates/feature-spec.md`](../templates/feature-spec.md) for new
specifications. Avoid specs for isolated one-file fixes.
