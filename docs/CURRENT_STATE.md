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
- Settings sections: SI, Appearance, Chat, System.
- Memory/privacy and permissions/autonomy moved to Control Center.
- Controller planner, worker registry, persisted plan state, and orchestration
  tests provide an initial multi-agent foundation.
- Studio routes and initial state model.
- Canonical `jaeger_local` backend identity with legacy input normalization.
- Native and Web launcher isolation between ARES and legacy Hermes services.
- Typed desired/effective native System settings for menu bar, login launch,
  quick launch, background operation, and Mac-owned controller restart.
- Port 8788 lifecycle is owned by the packaged ARES Mac app; the app refuses to
  adopt an unrelated process already using the port.
- Browser branding and production Web build served by ARES on port 8788.
- SI Settings uses a normalized Companion API backed by JaegerAI bridge v1.
- The real `jarvis` JaegerAI agent and character are read and updated through
  JaegerAI-owned commands; legacy JROS installations are rejected.
- SI Settings has one navigation surface and no fake calibration/personality
  controls or duplicated runtime diagnostics.

## Known gaps

| Gap | Impact | Next evidence |
| --- | --- | --- |
| System Settings still lacks default startup destination, preference reset, and complete diagnostic export. | The first native/runtime slice works, but the full maintenance experience is incomplete. | Remaining `features/system-settings.md` acceptance criteria. |
| Multi-agent primitives are not yet presented as one coherent ARES delegation experience. | Users may see workers or sessions without understanding their relationship to ARES. | `features/multi-agent-orchestration.md` and end-to-end delegation evidence. |
| Docker and GitHub CI still reference the pre-reorganization `frontend/` layout or omit controller requirements. | Draft PR checks fail before meaningful execution. | Root-context Docker build and green dependency installation. |
| The complete inherited controller suite contains legacy failures after the repository move. | A broad pass is not yet a clean release gate. | Separate stabilization batch with failures grouped by owner. |
| JaegerAI `master` has local commits and is behind its remote. | Cross-repository work is unsafe until reconciled. | Separate Jaeger safety branch; no ARES-driven mutation. |

## Runtime ownership on this development machine

- ARES controller/Web UI: port `8788`, launched and supervised by ARES.app.
- Legacy Hermes Web UI: port `8787`; do not treat it as ARES.
- Jaeger AI repository: `/Users/matthewjenkins/GitHub/JaegerAI`; changes require
  their own branch and explicit cross-repository task.

Machine-specific values are diagnostic context, not portable defaults.

## Immediate sequence

1. Complete remaining System startup and maintenance controls using the same
   desired/effective contract.
2. Connect existing orchestration primitives to the one-identity, many-workers
   session experience.
3. Repair Docker/CI paths and stabilize remaining ARES functionality.
4. Reconcile JaegerAI separately before unified tray/menu integration.
