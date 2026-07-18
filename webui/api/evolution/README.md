# Hermes Agent Self-Evolution — ARES Drain

Source: `hermes-agent-self-evolution` — Python DSPy+GEPA evolutionary optimizer for skills and prompts.

## What was drained

The core evolutionary optimization loop that evolves Hermes Agent skills and prompts using DSPy for programmatic LLM prompting and GEPA-style genetic programming for search over skill/prompt space.

### Directory structure

| Path | Purpose |
|------|---------|
| `evolution/core/` | Core config, dataset builder, fitness evaluation, constraints, external importers |
| `evolution/skills/` | Skill module definition and per-skill evolution loop |
| `evolution/code/` | Code-level evolution (prompt optimization over code) |
| `evolution/prompts/` | Prompt-level evolution |
| `evolution/tools/` | Tool evolution adapters |
| `evolution/monitor/` | Evolution monitoring and reporting |
| `scripts/` | `run_evolution.py` entry point |
| `generate_report.py` | Post-evolution report generator |

### Key modules

- `evolution/core/config.py` — Evolution configuration (population size, mutation rate, fitness weights)
- `evolution/core/fitness.py` — Fitness function evaluation (accuracy, latency, cost)
- `evolution/core/dataset_builder.py` — Training set construction from skill fixtures
- `evolution/core/constraints.py` — Constraint enforcement (max tokens, format compliance)
- `evolution/core/external_importers.py` — Import skill definitions from external sources
- `evolution/skills/evolve_skill.py` — Main skill evolution loop
- `evolution/skills/skill_module.py` — Skill module abstraction

## Integration notes

- Pure Python, designed to run as a standalone optimizer or integrated into a CI loop.
- `pyproject.toml` captures dependencies (DSPy, GEPA, etc.).
- `PLAN.md` documents the phased roadmap.
- The evolution loop produces evolved skill files that can be directly loaded by Hermes Agent.