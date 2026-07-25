# Jaeger runtime ownership

ARES is JaegerAI's presentation and control surface. JaegerAI is the only
conversation runtime and owns model selection, persona, tools, turn execution,
and user-facing session history.

A third-party CLI is not an ARES backend. When explicitly enabled, JaegerAI may
invoke an external CLI as a delegated subtask worker:

```text
ARES WebUI → JaegerAI delegate_task → <worker> --oneshot <subtask>
```

That worker boundary is stdio-only. ARES does not connect to a third-party WebUI
or gateway port, does not expose per-vendor/hybrid backend choices, and does not
merge a worker's `state.db` rows into its conversation sidebar.

To enable the optional worker for a Jaeger process:

```bash
export JAEGER_DELEGATE_WORKER=cli
```

Optional controls:

- `JAEGER_DELEGATE_COMMAND` selects the executable.
- `JAEGER_DELEGATE_TIMEOUT_SECONDS` bounds each delegated task (default: 900).

Without `JAEGER_DELEGATE_WORKER`, Jaeger uses its native subagents.
Legacy ARES backend value `hybrid` is a migration input only and
normalize immediately to `jros`.
