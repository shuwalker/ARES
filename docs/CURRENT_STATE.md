# Current Development State

| Attribute | Value |
| --- | --- |
| **Status** | Current milestone snapshot |
| **Owner** | ARES maintainers |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Current branch source, tests, and draft PR evidence |

This file gives a new contributor the current development context. Update it
when a milestone lands or a listed gap is closed; do not turn it into a daily
work log.

## Current direction

ARES is stabilizing its unified product shell and making each setting and
environment functional before deeper cross-repository integration work.

Implemented on the active functional branch:

- Six product environments plus standalone Settings.
- Settings sections: SI, Appearance, Chat, App.
- Memory/privacy and permissions/autonomy moved to Control Center.
- Studio routes and initial state model.
- Canonical `jaeger_local` backend identity with legacy input normalization.
- Native and Web launcher isolation between ARES and legacy Hermes services.
- Browser branding and production Web build served by ARES on port 8788.

## Known gaps

| Gap | Impact | Next evidence |
| --- | --- | --- |
| SI calibration values persist but are not yet assembled into worker system instructions. | Controls appear functional without changing responses. | Prompt-rendering unit tests and end-to-end prompt assembly test. |
| SI Settings still contains a large architecture lesson and detailed Jaeger infrastructure card. | Personalization feels technical and duplicates Control Center. | Layout/copy acceptance criteria in `features/si-personalization.md`. |
| Docker and GitHub CI still reference the pre-reorganization `frontend/` layout or omit controller requirements. | Draft PR checks fail before meaningful execution. | Root-context Docker build and green dependency installation. |
| The complete inherited controller suite contains legacy failures after the repository move. | A broad pass is not yet a clean release gate. | Separate stabilization batch with failures grouped by owner. |
| JaegerAI `master` has local commits and is behind its remote. | Cross-repository work is unsafe until reconciled. | Separate Jaeger safety branch; no ARES-driven mutation. |

## Runtime ownership on this development machine

- ARES controller/Web UI: port `8788`.
- Legacy Hermes Web UI: port `8787`; do not treat it as ARES.
- Jaeger AI repository: `/Users/matthewjenkins/GitHub/JaegerAI`; changes require
  their own branch and explicit cross-repository task.

Machine-specific values are diagnostic context, not portable defaults.

## Immediate sequence

1. Make the documentation system and SI personalization contract canonical.
2. Implement and test calibration prompt assembly and the SI page refinement.
3. Repair Docker/CI paths from the repository reorganization.
4. Stabilize remaining ARES functionality.
5. Reconcile JaegerAI separately before unified tray/menu integration.
