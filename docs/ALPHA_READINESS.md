# ARES Production Alpha Readiness

This repo is ready for local production-alpha testing when the goal is to validate the modular backend contracts, local memory/identity, gateway switching, dashboard widgets, and companion chat shell.

It is not yet a production release of the full embodied companion described in the final prompt. The alpha is intentionally local-first and explicit about simulated components.

## Ready for Alpha

- Swift package builds and tests with `swift test`.
- Core contracts are present for the ARES brick system.
- Local gateway providers exist for Ollama and Hermes.
- Companion session listing maps gateway session models into UI session summaries.
- Filesystem identity persists ARES identity to disk.
- SQLite memory store persists memories locally.
- In-memory event bus supports live pub/sub and typed event history.
- In-memory memory, workflow, and scheduler defaults now preserve state across core operations.
- Contract tests cover event bus publish/history, memory CRUD, workflow card lifecycle, and scheduler lifecycle/history.

## Simulated in Alpha

- Desktop embodiment still uses the placeholder body.
- Perceiver, mimicry, world model, voice, workflow filesystem, and scheduler integrations still use local in-memory/default implementations.
- Cron trigger execution is simulated and records history; it does not execute shell commands.
- Workflow data is in-memory unless backed by a future real implementation.
- Event bus history is in-memory and resets on app restart.

## Not Production Complete

- The package is not yet split into the final five Swift modules.
- Production wiring still refuses dummy/default components where configured, but several real providers are not implemented yet.
- The app still has a dashboard-first shell; the face-first onboarding flow is not complete.
- Embodiment is not a 3D avatar with gaze, voice, mimicry, and sub-200ms reaction loop.
- Perception is not a continuous world-model pipeline yet.
- Memory does not yet include vector search or explicit episodic/semantic tiering.
- Voice transcription and synthesis are not integrated as real alpha-grade services.

## Alpha Test Command

```bash
swift test
```

Expected current result: 13 tests passing.

## Suggested Alpha Scope

Use this build to test local companion chat, backend wiring, memory/identity persistence, widget flows, gateway switching, and task/scheduler state behavior.

Do not use it yet to test always-on perception, realistic embodiment, voice latency, autonomous self-improvement, or robot/watch body swapping.
