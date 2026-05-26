# ARES 2 Rebuild

ARES is being rebuilt as a persistent embodied agent system.

The target is not a chatbot, a Hermes skin, or a pile of aspirational "AGI"
comments. The target is closer to Jarvis or a droid: an always-on entity with a
face, memory, sensors, reasoning backends, tools, and clear approval boundaries.

Hermes Agent is one reasoning engine inside ARES. It is not the product.

## Product Thesis

ARES 2 is a persistent embodied agent OS for:

- an AI avatar companion users can talk to through voice or text,
- a 24/7 local runtime that survives restarts and owns its state,
- sensor-aware perception that can eventually extend from desktop to robot,
- hybrid reasoning through local models, cloud models, and Hermes Agent,
- real tool execution for useful work such as content creation, coding,
  research, automation, and later physical tasks.

## First Product

Build the avatar companion first.

The first credible version should feel like a living local AI presence:

- Swift face is always reachable.
- Text chat works.
- Voice states exist: idle, listening, thinking, speaking, sleeping.
- Memory persists across sessions.
- Tool activity is visible instead of hidden.
- A simple content workflow can create a brief, research notes, script, asset
  plan, and publish checklist.

Autonomy comes after the loop is reliable and observable.

## Stack Layers

The canonical layer list lives in `ares.runtime.agent_stack`.

1. Presence
   Avatar, voice, emotion, idle behavior, and visible cognitive/tool activity.

2. Runtime
   Always-on process, home directory, config, health, restart, and service
   lifecycle. This should borrow Lilith's discipline: idempotent bootstrap,
   clean shutdown, no hardcoded user paths, and a single owner for subprocesses.

3. Memory
   Identity, user preferences, episodic history, project memory, and summaries.

4. Perception
   Permissioned sensors: microphone, screen, camera, files, and later robot
   inputs. Sensors can be 24/7, but actions based on them must still honor
   policy.

5. Reasoning
   Model routing, planning, reflection, and agent loops. Hermes is an adapter
   here. Local/cloud routing should be swappable.

6. Tools
   MCP, filesystem, browser/computer control, code, n8n, and creative tools.
   Tool outputs should remain inspectable by humans.

7. Approval
   One policy layer for installs, deletion, publishing, spending, hardware
   control, and other high-risk actions.

8. Workflows
   Composable jobs such as content creation, research, coding, automation, and
   robot tasks.

## What To Keep From Lilith

- Treat the user home as a product boundary.
- Bootstrap idempotently and never overwrite user config.
- Keep the runtime local-first.
- Keep Hermes hidden behind a better application layer.
- Use lifecycle guards for long-running app modes.
- Make voice/text/avatar UI one shared session, not separate worlds.
- Prefer explicit runtime adapters over hardcoded global paths.

## What To Keep From ARES

- The Swift face and cognitive activity surface.
- The goal of a durable always-on daemon.
- Human-readable memory and workflow artifacts.
- Tool registry and MCP direction.
- Content creation as an early flagship workflow.
- Approval gates for risky work.

## What To Remove Or Rewrite

- Hardcoded machine-local interpreter paths.
- Port killing without ownership checks.
- "Autonomous operator" language that is not backed by implementation.
- Hidden pipelines that cannot be inspected or edited.
- Reasoning code that pretends to execute broad jobs before tool adapters are
  real.

## Milestones

### M0: Rebuild Manifest

Done when the stack is named in code and exposed to the UI through `/api/stack`.

### M1: Avatar Companion Foundation

- One API server owns presence state.
- Swift face can show stack status, chat, and tool activity.
- Chat goes through a reasoning adapter, not a bridge full of canned replies.
- Memory records user and assistant turns.

### M2: Runtime Hardening

- Remove hardcoded Hermes Python path.
- Replace unsafe port killing with owned-service tracking.
- Add lifecycle tests for startup, shutdown, and service health.
- Make `ARES_HOME` the only home boundary.

### M3: Reasoning Adapter

- Define a `ReasoningBackend` interface.
- Implement Hermes adapter.
- Implement simple local/cloud LLM fallback.
- Route chat, planning, and tool turns through the adapter.

### M4: Tool Activity And Approvals

- Central approval service.
- Tool calls emit visible UI events.
- File, web, code, and MCP tools report capability and risk level.

### M5: Content Workflow

- Build the first real workflow: content idea -> brief -> research -> script ->
  asset plan -> publish checklist.
- Every artifact is a normal file.
- Publishing remains a hard approval gate.

### M6: Perception

- Mic and screen/camera observations publish normalized events.
- Idle observation can update context.
- Any action triggered from sensors passes through approval policy.

## Rule Of Thumb

If a feature makes ARES feel more present, more reliable, more capable, or more
inspectable, it belongs.

If a feature only makes the repo sound more impressive, it does not.
