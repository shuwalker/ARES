# SI Companion Settings

| Attribute | Value |
| --- | --- |
| **Status** | Active |
| **Owner** | ARES Settings and JaegerAI adapter |
| **Last verified** | 2026-08-01 |
| **Source of truth** | `/api/companion`, its adapter, and contract tests |

## User purpose

The SI page configures the one assistant the user talks to. ARES owns the
relationship and product experience. JaegerAI supplies the selected local agent,
character, voice, and model runtime.

The page is intentionally small:

1. What should the Companion call the user?
2. What is the Companion's name?
3. Which real JaegerAI character should it use?
4. Is the JaegerAI dependency connected, and which agent/model is selected?

It is a settings page, not an explanation of SI architecture or a runtime
diagnostic console.

## Product and repository boundary

ARES and JaegerAI are separate applications and independently versioned
repositories. ARES never edits JaegerAI YAML, databases, or character files.
It reads and changes Companion state through JaegerAI bridge protocol v1.

| ARES owns | JaegerAI owns |
| --- | --- |
| User-facing relationship and ARES display name | Agent identity file |
| User name | Active and default character |
| ARES sessions and task continuity | Character profile, traits, and voice |
| Backend election | Model/runtime configuration |
| Permissions and product policy | Runtime execution and native persistence |

Changing the Companion name calls JaegerAI's `save_identity` command and then
stores the matching ARES display name. Changing Character calls both
`select_character` (effective now) and `make_default` (effective after restart).
ARES reads the result back instead of assuming the write succeeded.

## Dependency discovery

The Mac-owned controller receives canonical environment variables:

- `ARES_JAEGER_HOME`: selected JaegerAI product root.
- `JAEGER_HOME`: the same root for JaegerAI's launcher.
- `ARES_JAEGER_SOURCE_DIR`: optional development-checkout root.
- `ARES_JAEGER_INSTANCE`: selected instance ID.

Resolution order is explicit configuration, a valid `~/jaeger` product install,
then a valid sibling `JaegerAI` development checkout. A valid root must contain
both the `jaeger_ai` package and executable `jaeger` launcher. A legacy JROS
tree is rejected. Explicit invalid configuration fails closed instead of
silently selecting another checkout.

## API flow

```text
Settings → SI
  → GET /api/companion
  → ARES Companion adapter
  → jaeger bridge <instance> (protocol v1 queries)

Save Companion
  → PATCH /api/companion
  → validated JaegerAI commands
  → read back live JaegerAI state
  → persist matching ARES name
  → explicitly elect jaeger_local as the default backend
```

`GET /api/companion` may start a local bridge. The bridge remains cached by the
controller for low-latency chat and is closed when the controller exits or the
runtime is reset.

## Settings vs Control Center

| Settings → SI | Control Center / Hatchery |
| --- | --- |
| Companion and user names | Provider health and connection details |
| Real JaegerAI character picker | Start/restart and failure recovery |
| Compact active agent/model status | Model install and hardware tuning |
| Save and synchronize identity | Memory, privacy, permissions, autonomy |

Old `local_profile_character` and `si_cal_*` keys remain accepted as migration
data, but are no longer presented as working SI controls. They must not be
reintroduced until an adapter-backed behavior contract proves they affect the
selected runtime safely.

## Source anchors

| Concern | Source |
| --- | --- |
| SI page | `apps/web/src/features/settings/SISection.tsx` |
| Web hook | `apps/web/src/features/settings/useCompanionSettings.ts` |
| Web contract | `apps/web/src/shared/companion-contract.ts` |
| API route | `services/controller/fastapi_app/routers/companion.py` |
| JaegerAI adapter | `integrations/providers/jaeger/companion_control.py` |
| Bridge client | `integrations/providers/jaeger/bridge_client.py` |
| Dependency resolver | `integrations/providers/jaeger/paths.py` |
| Controller tests | `services/controller/tests/test_companion_integration.py` |

## Acceptance criteria

- The page contains one navigation system and no architecture lecture.
- Names and Character are loaded from live JaegerAI state.
- Saving uses JaegerAI commands; ARES never writes JaegerAI files directly.
- Character changes are live and restart-persistent.
- A save reads state back and visibly reports synchronization.
- Invalid or legacy dependency roots are rejected.
- Memory, privacy, permissions, autonomy, and detailed diagnostics do not
  reappear in SI Settings.
- The Mac app and browser UI consume the same controller and contract.
