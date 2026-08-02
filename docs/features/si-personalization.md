# SI Personalization

| Attribute | Value |
| --- | --- |
| **Status** | Active / partially implemented |
| **Owner** | Settings UI and controller prompt assembly |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Linked source files and acceptance tests below |

## User purpose

The SI page answers one question: **How should my SI understand, communicate,
and work with me?** It configures the continuous relationship the user has with
ARES, independent of whichever worker performs a turn.

“SI” is the compact Settings label. “Companion” may describe the continuous
experience in product prose. Neither term names a worker. ARES is the
application hosting that experience.

## Ownership boundary

| SI Settings owns | Control Center owns |
| --- | --- |
| What the SI calls the user | Active agents, workers, and delegated tasks |
| SI display name | AI tools, providers, and connection health |
| Voice preference | Memory indexing and privacy policy |
| Personality base | Permissions and approvals |
| Communication calibration | Autonomy and device/network reachability |
| Additional personal guidance | Worker activity, setup, and diagnostics |

Calibration changes communication behavior. It never grants a permission,
changes data-retention policy, or silently selects a worker.

## Intended page layout

1. **Your SI** — a short explanation that identity remains stable while workers
   can change. Detailed SI architecture belongs in Product documentation or an
   optional disclosure, not a large lecture card.
2. **Identity** — user display name, SI name, voice, and **Personality base**.
   Preserve the stored `local_profile_character` key; only the misleading
   “Character” label changes.
3. **Behavior** — detail level, tone, challenge style, initiative, and personal
   guidance. Explain each control in ordinary language.
4. **Active worker** — one compact status row and a link to Control Center.
   Worker setup and diagnostics do not render here. Local ARES application and
   service controls belong in System Settings.
5. **Advanced identity** — when implemented, link to Hatchery for deeper
   persona construction rather than expanding basic Settings indefinitely.

## Persisted contract

`POST /api/settings` accepts partial updates. These keys remain stable:

| Key | Values | Default |
| --- | --- | --- |
| `local_profile_character` | `grounded`, `warm`, `direct`, `curious` | `grounded` |
| `si_cal_verbosity` | `concise`, `balanced`, `explanatory` | `balanced` |
| `si_cal_tone` | `direct`, `balanced`, `conversational` | `balanced` |
| `si_cal_support` | `supportive`, `balanced`, `challenging` | `balanced` |
| `si_cal_initiative` | `reactive`, `balanced`, `proactive` | `balanced` |
| `si_cal_notes` | trimmed string, maximum 2,000 characters | empty |

## Required behavior mapping

The controller must render a bounded, clearly delimited calibration block into
the ephemeral system instructions for every applicable worker turn.

| Value | Required instruction meaning |
| --- | --- |
| `concise` | Lead with the result and keep explanation brief unless requested. |
| `balanced` verbosity | Give enough context to act without unnecessary detail. |
| `explanatory` | Explain unfamiliar concepts and important reasoning in more depth. |
| `direct` tone | Use plain, direct language with minimal conversational padding. |
| `balanced` tone | Be clear and natural without forcing formality or informality. |
| `conversational` | Use a warmer, natural conversational style while remaining precise. |
| `supportive` | Be constructive and encouraging without hiding risks. |
| `balanced` support | Support good ideas and challenge material weaknesses. |
| `challenging` | Stress-test assumptions, evidence, and counterarguments respectfully. |
| `reactive` | Answer the request without adding unsolicited plans or next actions. |
| `balanced` initiative | Mention an obvious useful next step when it materially helps. |
| `proactive` | Surface relevant risks, opportunities, and next actions without acting beyond permission. |

Personal guidance is appended after the structured mapping. It is user-authored
preference text, not authorization: it cannot override system safety,
permissions, approvals, or worker/tool constraints.

## Data flow

```text
SI Settings controls
  -> POST /api/settings
  -> validated profile settings
  -> calibration renderer
  -> ephemeral ARES system instructions
  -> selected worker adapter
  -> response and execution events
```

## Implementation status

- Implemented: typed Web controls, persistence keys, validation, reload, and
  ownership tests.
- Implemented: Jaeger status/setup component and Control Center destinations.
- Missing: calibration renderer and injection into prompt assembly.
- Needs refinement: SI lecture copy, “Character” label, and detailed Jaeger card
  placement.

Do not remove or rename the persisted keys while fixing the missing behavior.

## Source anchors

| Concern | Source |
| --- | --- |
| SI page | `apps/web/src/features/settings/SISection.tsx` |
| Calibration types and keys | `apps/web/src/features/settings/si-calibration.ts` |
| Settings controller | `apps/web/src/features/settings/useSettingsController.ts` |
| Settings validation | `services/controller/api/config.py` |
| Settings route | `services/controller/fastapi_app/routers/settings.py` |
| Prompt assembly | `services/controller/api/streaming.py` |
| Frontend ownership tests | `apps/web/src/features/settings/settings-ownership.test.ts` |
| Controller persistence tests | `services/controller/tests/test_si_calibration_settings.py` |

## Acceptance criteria

- The page can be understood without knowing what an LLM, gateway, provenance,
  or context assembly is.
- “Personality base” replaces the user-facing “Character” label without a
  storage-key migration.
- Detailed Jaeger infrastructure appears only in Control Center.
- Each calibration value produces deterministic prompt text covered by tests.
- Prompt assembly includes personal guidance once, safely delimited and capped.
- Balanced defaults do not produce contradictory or excessive instructions.
- Calibration cannot elevate autonomy, permissions, or network access.
- Switching workers preserves identity and calibration.
- Product, API, and feature docs update with any contract change.
