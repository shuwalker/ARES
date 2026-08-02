# Multi-Agent Orchestration

| Attribute | Value |
| --- | --- |
| **Status** | Active / partially implemented |
| **Owner** | Controller orchestration, Agent sessions, and Control Center activity |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Linked planner/orchestrator source and end-to-end acceptance evidence |

## Product principle

**One identity, many workers.**

The user communicates with ARES as one persistent SI. ARES may answer directly
or delegate bounded work to specialist agents, but workers do not become new
product identities. Ordinary work should not require the user to operate a
swarm manually.

## User experience

1. The user makes one request in the Agent conversation.
2. ARES determines whether the request needs a direct response, a planned
   session, specialist delegation, or parallel work.
3. ARES creates organized sessions and assigns steps by capability, privacy,
   availability, cost, and user preference.
4. Control Center shows the plan, active workers, progress, approvals, failures,
   provenance, and results.
5. ARES verifies and combines the work into one coherent response while
   preserving links to the underlying sessions and artifacts.

## Surface ownership

| Surface | Owns |
| --- | --- |
| **Agent** | User conversation, session creation, progress summaries, results, and approval requests in context. |
| **Control Center** | Live plans, workers, task queues, tool/device availability, failures, alerts, and detailed provenance. |
| **Settings / System** | Durable defaults such as delegation posture, preferred capabilities, concurrency, background operation, and notification behavior. |

## Orchestration rules

- A simple request should remain simple; delegation is not a goal by itself.
- Each delegated step has an owner, bounded objective, status, dependencies,
  provenance, and result.
- ARES owns the plan and product session. External workers own their native
  execution state and are invoked through adapters.
- Parallel work is used only for independent steps and respects configured
  resource limits.
- Permissions, privacy, and approvals apply to every worker and tool action.
- Worker failure degrades a capability; it must not erase the ARES session or
  fragment the SI identity.
- ARES reports uncertainty and partial completion rather than presenting an
  unverified combined answer as complete.

## Implementation status

- Implemented: SI planner, step dependencies, worker registry assignment,
  persisted plans, retry/cancel behavior, and orchestration invariant tests.
- Implemented: ARES session lifecycle and external worker adapter boundaries.
- Partial: worker/model provenance and session projection exist across several
  controller paths but need one product-level contract.
- Missing or unverified: automatic delegation from the primary chat path,
  coherent specialist-session creation, live Control Center visualization, and
  end-to-end result synthesis/verification.

## Source anchors

| Concern | Source |
| --- | --- |
| Planner | `services/controller/api/si/planner.py` |
| Orchestrator | `services/controller/api/si/orchestrator.py` |
| Worker registry | `services/controller/api/si/worker_registry.py` |
| Trust checks | `services/controller/api/si/trust_engine.py` |
| Streaming and worker dispatch | `services/controller/api/streaming.py` |
| Session lifecycle | `services/controller/api/session_lifecycle.py` |
| Control Center agent UI | `apps/web/src/features/system/AgentsPage.tsx` |
| Orchestration tests | `services/controller/tests/test_si_orchestration.py` |

## Acceptance criteria

- The user can ask ARES once and receive either a direct response or an
  understandable delegated plan without selecting agents manually.
- Delegated work appears as related sessions under the original request.
- Control Center shows live status and lets the user inspect, pause, cancel, or
  approve work according to policy.
- Each result retains worker, model, tool, artifact, and verification provenance.
- A worker can be replaced or fail without changing the SI identity or losing
  ARES-owned plan/session state.
- Concurrency and delegation defaults are configurable without exposing routine
  users to unnecessary orchestration detail.
- End-to-end tests cover direct, sequential, parallel, approval-gated, failed,
  retried, cancelled, and synthesized work.
