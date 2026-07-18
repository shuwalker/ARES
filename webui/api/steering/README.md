# Neural Steering — ARES Drain

Source: `neural-steering` — Python contrastive neuron attribution library for LLM alignment.

## What was drained

A library for steering LLM behavior via contrastive activation attribution — identifying and manipulating specific neurons that encode refusal, harm, or alignment-relevant concepts.

### Directory structure

| Path | Purpose |
|------|---------|
| `neuron_steer/` | Core library package |
| `neuron_steer/core.py` | Main steering API: activation capture, contrastive attribution, steering vector computation |
| `experiments/` | Experimental scripts: jailbreak benchmarks, refusal ablations, steering comparisons, layer localization, StrongREJECT rubric |
| `examples/` | Usage examples: refusal steering, interactive demo |
| `quickstart.py` | Quick-start script |

### Key concepts

- **Contrastive Attribution**: Compare activations on refused vs. accepted completions to identify steering neurons.
- **Steering Vectors**: Computed from contrastive pairs; applied at inference to shift model behavior.
- **Layer Localization**: Find which transformer layers contain the most alignment-relevant signal.
- **StrongREJECT**: Automated rubric for evaluating refusal quality.

### Key modules

- `neuron_steer/core.py` — Primary API surface: `SteeringVector`, `AttributeContrastive`, `apply_steering()`
- `experiments/jailbreak_benchmark.py` — Run steering against standard jailbreak benchmarks
- `experiments/refusal_ablations.py` — Ablate refusal neurons and measure behavior change
- `experiments/steering_comparison.py` — Compare steering methods (act-add, act-sub, linear)
- `experiments/layer_localization.py` — Find optimal layers for steering intervention
- `experiments/strongreject_rubric.py` — StrongREJECT scoring for refusal evaluation

## Integration notes

- Pure Python with minimal dependencies (`requirements.txt`).
- `setup.py` + `pyproject.toml` for dual install compatibility.
- The steering API is designed to integrate into any transformer model pipeline (PyTorch-based).
- `ANTI-SLOP.md` documents coding standards for the project.