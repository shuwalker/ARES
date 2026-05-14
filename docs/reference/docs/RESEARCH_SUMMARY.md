# AI Agent & Robotics Research: Quick Summary

**Research Date:** March 31, 2026
**Focus:** GitHub stats, architecture comparison, ARES positioning

---

## GitHub Star Rankings (March 2026)

| Rank | Project | Stars | Category | Status |
|------|---------|-------|----------|--------|
| 1 | AutoGPT | 183,000 | Autonomous Agent | Stable but aging |
| 2 | AutoGen | 56,300 | Multi-Agent Conversation | Maintenance mode (merging into MS Agent Framework) |
| 3 | OpenHands | 68,600 | Autonomous Coding | Active, Series A funded ($18.8M) |
| 4 | CrewAI | 45,900 | Multi-Agent Orchestration | Fastest-growing (most active development) |
| 5 | LangGraph | 27,900 | Graph-Based Orchestration | Active, production-grade |
| 6 | Letta (MemGPT) | ~12,000 | Persistent Memory Agents | Active, rapidly growing post-rebrand |
| 7 | LeRobot | ~5,000-8,000 | Robotics + ML | Active, Hugging Face + NVIDIA partnership |
| 8 | Swarms | 5,600 | Enterprise Multi-Agent | Growing, well-funded |
| 9 | Stretch ROS | 186 | Robot Hardware Driver | Maintenance mode (official support) |
| 10 | ARES (Martian) | Unknown | Coding Agent Training RL | Just open-sourced (Jan 30, 2026) |

---

## What Each System Actually Does (In One Sentence)

1. **Letta:** Persistent memory platform where agents actively decide what to remember and forget (like an OS managing RAM/disk).

2. **LangGraph:** Graph-based workflow orchestration with robust checkpointing for stateful, resilient multi-agent systems.

3. **AutoGen:** Multi-agent conversation framework where agents negotiate via message-passing to solve problems.

4. **CrewAI:** Role-based team orchestration framework (agents = employees with skills; tasks = assignments).

5. **AutoGPT:** Autonomous agent that breaks down goals into steps and executes them without human intervention.

6. **OpenHands:** Autonomous software engineer that can write code, run tests, and debug end-to-end.

7. **LeRobot:** Imitation learning framework for training robot controllers from human demonstrations.

8. **Stretch ROS:** ROS driver package for Hello Robot's Stretch mobile manipulator.

9. **Swarms:** Enterprise multi-agent orchestration framework designed for 100s-1000s of parallel agents.

10. **ARES (Martian):** RL training infrastructure that treats LLM as policy for coding agent training.

---

## Core Architecture Patterns

### Memory Approaches

| System | Memory Type | Persistence | Retrieval |
|--------|-------------|-------------|-----------|
| Letta | OS-inspired (RAM/disk/archival) | Survives restarts | Agent-controlled via tools |
| LangGraph | Explicit state schema | Checkpoints at each node | Automatic (deterministic merges) |
| AutoGen | Conversation history | In-memory or optional persistence | Implicit (chat context) |
| CrewAI | SQLite3 + RAG | Survives restarts | Automatic (semantic search) |
| AutoGPT | Vector DB | Optional | Retrieved via semantic search |
| OpenHands | Session-based | Per-execution | Implicit (code context) |
| Your ARES | LanceDB + Kuzu + Skill Tree | Survives restarts | Both automatic + agentic |

### Execution Patterns

| System | Trigger | Control | State |
|--------|---------|---------|-------|
| Letta | Reactive (respond to query) | Agentic (agent decides next action) | Persistent |
| LangGraph | Reactive (workflow triggered) | Explicit graph (you define flow) | Checkpointed |
| AutoGen | Reactive (dispatch task) | Emergent (agents negotiate) | Implicit |
| CrewAI | Reactive (crew triggered) | Task-based (task defines flow) | Per-task |
| AutoGPT | Autonomous (goal-driven) | Self-directed (agent plans) | Stateless |
| OpenHands | Reactive (issue dispatched) | Autonomous (agent debugs) | Session-based |
| Your ARES | Both (reactive + autonomous loop) | Explicit (queues + approval) | Persistent |

---

## ARES Competitive Positioning

### Head-to-Head: ARES vs. Each Competitor

#### ARES vs. Letta
- **Letta wins:** Memory abstraction is more elegant; portable across LLM vendors
- **ARES wins:** Includes voice, robots, identity, autonomous background loop, two-clock model

#### ARES vs. LangGraph
- **LangGraph wins:** Checkpointing is more granular; battle-tested in production; framework-agnostic
- **ARES wins:** Complete system (not a framework); includes voice, robots, content production, identity

#### ARES vs. AutoGen
- **AutoGen wins:** Group chat and emergent negotiation; multi-agent diversity; code execution tightly integrated
- **ARES wins:** Autonomous background loop; persistent identity; voice; robots; content production; deterministic routing

#### ARES vs. CrewAI
- **CrewAI wins:** Cleaner mental model (role/task/crew); larger community; easier to prototype
- **ARES wins:** Persistent identity; two-clock autonomy; voice; robots; hybrid memory (episodic+semantic); deterministic execution

#### ARES vs. AutoGPT
- **AutoGPT wins:** Pure autonomy; no domain constraints; simpler mental model
- **ARES wins:** Structured goals (skill tree); persistent identity; two-clock model; voice; robots; production-ready (not proof-of-concept)

#### ARES vs. OpenHands
- **OpenHands wins:** Best-in-class at autonomous coding; safety sandbox; well-funded; Series A support
- **ARES wins:** Multi-domain (not just coding); voice; robots; life operations; content production; lower cost (local models)

#### ARES vs. LeRobot
- **LeRobot wins:** Hardware diversity (works with any ROS robot); imitation learning flexibility; research-backed
- **ARES wins:** Autonomous planning (not just learned controllers); voice; safety constraints before action; life operations

#### ARES vs. Swarms
- **Swarms wins:** Designed for 100s-1000s of agents; enterprise features; distributed orchestration
- **ARES wins:** Single-founder optimization; persistent identity; two-clock autonomy; voice; robots; content

---

## Features Unique to ARES

✓ **Persistent Constitutional Identity** — No other system models "who the agent is" as a persistent graph
✓ **Two-Clock Autonomy** — Reactive (respond to you) + Autonomous (background loop) is unique
✓ **Robot Arm + Voice** — Combined integration not attempted elsewhere
✓ **Content Production Pipeline** — End-to-end automation of script → voice → avatar → upload
✓ **Tiered LLM Routing with Cost Tracking** — Cost-conscious routing from first principles
✓ **Approval Queue for Irreversible Actions** — Explicit safety model for dangerous operations
✓ **Hybrid Memory** — Episodic (LanceDB) + Semantic (Kuzu) + Constitutional (Skill Tree)
✓ **Skill Tree as Life Graph** — Goals modeled as interconnected graph with unlock dependencies

---

## Where Each System Excels

| System | Best For | Not For |
|--------|----------|---------|
| **Letta** | Persistent conversational agents | Robotics, content, multi-agent teams |
| **LangGraph** | Complex, stateful workflows | Simple tasks, zero setup friction |
| **AutoGen** | Multi-agent code review, group debates | Deterministic workflows, safety-critical |
| **CrewAI** | Rapid prototyping, data teams | Robotics, voice, persistent identity |
| **AutoGPT** | Pure autonomy, open-ended problem solving | Production use, auditable decisions |
| **OpenHands** | Autonomous coding, bug fixing | Non-code tasks, robotics, voice |
| **LeRobot** | Learning new robot behaviors from demos | Autonomous planning, voice, life operations |
| **Swarms** | Enterprise scale (100s of agents) | Solo founders, simplicity, low overhead |
| **Your ARES** | Solo founder, multi-domain ops | Scaling to teams, simplicity, general frameworks |

---

## Architecture Comparison Matrix

| Capability | Letta | LangGraph | AutoGen | CrewAI | AutoGPT | OpenHands | LeRobot | Your ARES |
|-----------|-------|-----------|---------|--------|---------|-----------|---------|----------|
| Persistent Memory | ✓ | ✓ (checkpoints) | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| Autonomous Loop | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ |
| Voice (STT+TTS) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Robot Control | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ |
| Multi-Agent | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ (partial) |
| Constitutional Identity | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Content Production | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ (code) | ✗ | ✓ |
| Local LLM Support | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Checkpointing | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Approval Queue | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Audit Trail | Implicit | Implicit | ✗ | Implicit | ✗ | ✗ | ✗ | ✓ (explicit) |

---

## Implementation Complexity (Your ARES)

**Code Stats (from your repo):**
- ~14,000 lines of Python
- 79 files
- Mac Studio M2 Ultra (local compute)
- Ollama (Tier 1 local models) + Claude API (Tier 2-4)
- Architecture: skill_tree.json + daily_state.md + context domains + task queue + prediction engine

**Moving Parts:**
1. Context model (skill tree, daily state, trajectory, domains)
2. Prediction engine (identifies what's due next)
3. Task queue (pending, in_progress, awaiting_approval, completed)
4. Tier routing (Ollama → Haiku → Sonnet → Opus)
5. Audit logger (JSONL per date)
6. Voice I/O (Moonshine STT, XTTS TTS)
7. Robot control (arm via behavior trees, safety monitor)
8. Content pipeline (n8n orchestration, FFmpeg, SadTalker)
9. Approval UI (debrief, notification queue)
10. Background loop (launchd scheduling + FastAPI server)

**Comparison:**
- LangGraph: Smaller (~5k lines), but requires you to build everything else
- CrewAI: ~3-5k lines core, but you add agents/tasks/domain-specific logic
- ARES: ~14k lines includes everything; more monolithic, less modular

---

## Key Insights for Matthew

### What ARES Gets Right
1. **Specificity** — Optimized for your exact use case (robotics + content + life ops), not general frameworks
2. **Integration** — Everything is wired together; you don't need to glue pieces
3. **Autonomy** — Two-clock model is genuinely novel; no competitor does this
4. **Identity** — Persistent character that learns over time is unique
5. **Safety** — Approval queue for irreversible actions is rare and valuable

### What ARES Risks
1. **Complexity** — 14k lines is a lot to maintain solo
2. **No community** — You're alone solving problems others haven't faced
3. **Fragility** — Single point of failure in the skill tree, prediction engine, or voice pipeline cascades
4. **Unproven** — This combination hasn't been attempted before; no reference implementation
5. **Portability** — Tightly coupled to Mac + Claude + specific arm; hard to migrate

### The Bet You're Making
**Hypothesis:** A fully autonomous, persistent, multi-domain life assistant optimized for one founder can replace 4-5 specialized tools (ChatGPT, n8n, Monarch Money, video editor, robot control software) and do better than any of them individually.

**If true:** ARES is irreplaceable; you have a system no one else has.
**If false:** You built something overly complex that's harder to use than separate, specialized tools.

The next phase will tell. Phase 1 (skill tree + audit logger) and Phase 2 (two-clock model + prediction engine) are foundational. If those feel natural, you're on the right track. If they feel clunky, pivot to a framework (LangGraph or CrewAI).

---

## Recommendations

1. **Don't try to be a framework.** You're solving your problem, not others'. If someone asks "Can I use ARES for my team?", the answer is "No, but here's how I built this."

2. **Defend the two-clock model.** This is your novelty. Protect it. Every design decision should support reactive + autonomous.

3. **Keep the skill tree simple.** It's the heart of ARES. If it becomes complex, you've added too many features.

4. **Prove the YouTube pipeline first.** Get from "script idea" to "published video" in one autonomous cycle. That's your proof of concept.

5. **Robot control can come later.** The voice and content pipeline are higher-impact near-term.

6. **Make the audit trail sacred.** You need 100% confidence in what ARES did and why. The JSONL log should be the source of truth.

---

## Resources

All research links are in `/sessions/amazing-gallant-carson/mnt/GitHub/ARES/COMPETITIVE_ANALYSIS_2026.md`

Key sources:
- GitHub projects directly
- DataCamp comparison: https://www.datacamp.com/tutorial/crewai-vs-langgraph-vs-autogen
- DEV Community framework comparisons (2026 articles)
- Official documentation for each framework
- Hugging Face blog (LeRobot)
- LiveKit blog (voice agent architecture)

---

**Research completed:** March 31, 2026
**Next session:** Phase 1 audit (catalog existing v1 code)
