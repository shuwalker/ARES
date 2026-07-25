# Jaeger runtime ownership

ARES is JaegerAI's presentation and control surface. JaegerAI is the only
conversation runtime and owns model selection, persona, tools, turn execution,
and user-facing session history.

Hermes is not an ARES backend. When explicitly enabled, JaegerAI may invoke the
Hermes CLI as a delegated subtask worker:

```text
ARES WebUI → JaegerAI delegate_task → hermes --oneshot <subtask>
```

That worker boundary is stdio-only. ARES does not connect to a Hermes WebUI or
gateway port, does not expose Hermes/hybrid backend choices, and does not merge
Hermes `state.db` rows into its conversation sidebar.

To enable the optional worker for a Jaeger process:

```bash
export JAEGER_DELEGATE_WORKER=hermes
```

Optional controls:

- `JAEGER_HERMES_COMMAND` selects the executable (default: `hermes`).
- `JAEGER_HERMES_TIMEOUT_SECONDS` bounds each delegated task (default: 900).

Without `JAEGER_DELEGATE_WORKER=hermes`, Jaeger uses its native subagents.
Legacy ARES backend values `hermes` and `hybrid` are migration inputs only and
normalize immediately to `jros`.
