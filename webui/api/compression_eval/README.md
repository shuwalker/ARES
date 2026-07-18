# hermes-compression-eval

Offline evaluation harness for `agent/context_compressor.py` in
[hermes-agent](https://github.com/NousResearch/hermes-agent). Runs a real
conversation fixture through `ContextCompressor.compress()`, asks the
compressor model to answer probe questions from the compressed state, and
has a judge model score each answer 0–5 on six dimensions
(accuracy, context_awareness, artifact_trail, completeness, continuity,
instruction_following).

Methodology adapted from Factory's December 2025 write-up
[*Evaluating Compression*](https://factory.ai/news/evaluating-compression).
The scoreboard framing is not adopted.

## Why this exists

`agent/context_compressor.py` decides what survives compression when a
session exceeds the context-window threshold. Its prompts and template
sections are tuned by hand. Until now there was no signal between *"test
suite green"* and *"a user hits a bad summary in production."*

This harness gives that signal: edit the compressor prompt, re-run the
eval, compare the per-dimension scores against a saved baseline.

## Costs

LLM-graded and non-deterministic. Each probe = 1 continuation call +
1 grading call. A full run across the three checked-in fixtures with
default settings runs ~30 probe pairs against your configured provider.
Budget accordingly. Not appropriate for CI.

## Install

```bash
git clone https://github.com/NousResearch/hermes-compression-eval.git
cd hermes-compression-eval
pip install -r requirements.txt   # openai, fire
```

The harness imports `ContextCompressor` and `agent.redact` from
hermes-agent. Locate your hermes-agent checkout one of three ways
(checked in this order):

1. `HERMES_AGENT_ROOT=/path/to/hermes-agent` — explicit override.
2. `~/.hermes/hermes-agent/` — the default location `hermes setup` writes.
3. Sibling directory: clone hermes-agent next to hermes-compression-eval.

## Usage

```bash
# Baseline run (writes results/baseline/)
python3 run_eval.py \
    --compressor-provider=nous --compressor-model=openai/gpt-5.4-mini \
    --judge-provider=nous      --judge-model=openai/gpt-5.4-mini \
    --runs=3 --label=baseline

# After editing context_compressor.py prompts, compare:
python3 run_eval.py \
    --compressor-provider=nous --compressor-model=openai/gpt-5.4-mini \
    --judge-provider=nous      --judge-model=openai/gpt-5.4-mini \
    --runs=3 --label=my-tweak \
    --compare-to=results/baseline
```

`results/<label>/report.md` is paste-ready for a PR body. Per-run JSON
goes to `results/<label>/runs/`.

## What ships

| Path | Purpose |
|---|---|
| `run_eval.py` | Fire CLI — the entry point |
| `compressor_driver.py` | Thin wrapper that forces a single-shot compress() over fixture messages |
| `grader.py` | Two-phase continuation + grading via the OpenAI SDK |
| `rubric.py` | Six-dimension scoring rubric, judge-prompt builder, JSON parser |
| `report.py` | Markdown report rendering + `--compare-to` delta mode |
| `scrub_fixtures.py` | Pipeline to convert real `~/.hermes/sessions/*.jsonl` into public-safe JSON fixtures |
| `fixtures/` | Three checked-in scrubbed sessions (feature-impl, debug, config-build) |
| `probes/` | Three probe banks, 10–11 probes each, covering recall / artifact / continuation / decision |
| `tests/` | 33 hermetic unit tests for non-LLM paths |

## Adding a fixture

1. Pick a session under `~/.hermes/sessions/*.jsonl` worth measuring.
2. Add a `SPECS` entry in `scrub_fixtures.py` (source filename, output
   name, description, user-message paraphrase, model guess, context
   length, optional truncate-at).
3. Run `python3 scrub_fixtures.py` — writes `fixtures/<name>.json`.
4. Add a probe bank at `probes/<name>.probes.json` covering all four
   types (`recall`, `artifact`, `continuation`, `decision`).
5. Re-run `python3 -m pytest tests/ -q` to verify it loads and parses.

See `DESIGN.md` for the full scrubber pipeline and probe-format spec.

## Tests

```bash
python3 -m pytest tests/ -q
```

33 hermetic tests cover rubric parsing edge cases, judge-prompt
building, report rendering, summariser medians, per-run JSON roundtrip,
fixture and probe loading, and a PII smoke check on the checked-in
fixtures.

The LLM paths (continuation + grading) require credentials and real API
calls; they're exercised by running the eval itself, not by these tests.

## License

MIT, same as hermes-agent.
