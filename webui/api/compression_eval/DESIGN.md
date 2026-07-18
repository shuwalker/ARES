# Compression Eval — Design

Status: proposal. Nothing under `` runs in CI.
This is an offline tool authors run before merging prompt or algorithm
changes to `agent/context_compressor.py`.

## Why

We tune the compressor prompt and the `_template_sections` checklist by
hand, ship, and wait for the next real session to notice regressions.
There is no automated check that a prompt edit still preserves file
paths, error messages, or the active task across a compression.

Factory.ai's December 2025 write-up
(https://factory.ai/news/evaluating-compression) describes a
probe-based eval that scores compressed state on six dimensions. The
methodology is the valuable part — the benchmarks in the post are a
marketing piece. We adopt the methodology and discard the scoreboard.

## Goal

Given a real session transcript and a bank of probe questions that
exercise what the transcript contained, answer:

1. After `ContextCompressor.compress()` runs, can the agent still
   answer each probe correctly from the compressed state?
2. Which of the six dimensions (accuracy, context awareness, artifact
   trail, completeness, continuity, instruction following) is the
   prompt weakest on?
3. Does a prompt change improve or regress any dimension vs. the
   previous run?

That is the full scope. No "compare against OpenAI and Anthropic"
benchmarking, no public scoreboard, no marketing claims.

## Non-goals

- Not a pytest. Requires API credentials, costs money, takes minutes
  per fixture, and output is LLM-graded and non-deterministic.
- Not part of `pytest`. Not invoked by CI.
- Not a replacement for the existing compressor unit tests in
  `tests/agent/test_context_compressor.py` — those stay as the
  structural / boundary / tool-pair-sanitization guard.
- Not a general trajectory eval. Scoped to context compaction only.

## Where it lives

```

├── DESIGN.md                 # this file
├── README.md                 # how to run, cost expectations, caveats
├── run_eval.py               # entry point (fire CLI, like sample_and_compress.py)
├── scrub_fixtures.py         # regenerate fixtures from ~/.hermes/sessions/*.jsonl
├── fixtures/                 # checked-in scrubbed session snapshots
│   ├── feature-impl-context-priority.json
│   ├── debug-session-feishu-id-model.json
│   └── config-build-competitive-scouts.json
├── probes/                   # probe banks paired with fixtures
│   └── <fixture>.probes.json
├── rubric.py                 # grading prompt + dimension definitions
├── grader.py                 # judge-model call + score parsing
├── compressor_driver.py      # thin wrapper over ContextCompressor
└── results/                  # gitignored; timestamped output per run
    └── .gitkeep
```

this repo is the right home: offline tooling, no CI involvement,
precedent already set by `sample_and_compress.py`,
`contributor_audit.py`, `discord-voice-doctor.py`.

`environments/` is for Atropos RL training environments — wrong shape.
`tests/` is hermetic and credential-free — incompatible with a
probe-based eval that needs a judge model.

## Fixture format

A fixture is a single compressed-enough conversation captured from a
real session. Stored as JSON (pretty-printed, reviewable in PRs):

```json
{
  "name": "401-debug",
  "description": "178-turn session debugging a 401 on /api/auth/login",
  "model": "anthropic/claude-sonnet-4.6",
  "context_length": 200000,
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "...", "tool_calls": [...]},
    {"role": "tool", "tool_call_id": "...", "content": "..."}
  ],
  "notes": "Captured 2026-04-24 from session 20260424_*.jsonl; \
            PII scrubbed; secrets redacted via redact_sensitive_text."
}
```

### Sourcing fixtures

Fixtures are scrubbed snapshots of real sessions from the
maintainer's `~/.hermes/sessions/*.jsonl` store, generated
reproducibly by `scrub_fixtures.py` in this directory. Re-run the
scrubber with `python3 scrub_fixtures.py`
to regenerate them after a scrubber change.

Three shipped fixtures cover three different session shapes:

| Fixture | Source shape | Messages | Tokens (rough) | Tests |
|---|---|---|---|---|
| `feature-impl-context-priority` | investigate → patch → test → PR → merge | 75 | ~45k | continuation, artifact trail (2 files modified, 1 PR, ~16k skill_view in head) |
| `debug-session-feishu-id-model` | PR triage + upstream docs + decision | 59 | ~28k | recall (PR #, error shape), decision (outcome + reason), large PR diff blocks |
| `config-build-competitive-scouts` | iterative config: 11 cron jobs across 7 weekdays | 61 | ~26k | artifact trail (which jobs, which days), iterative-merge |

The `~26k-45k` token range is below the default 50%-of-200k
compression threshold, so the eval will always **force** a
`compress()` call rather than wait for the natural trigger. That is
the intended shape — we want a controlled single-shot compression so
score deltas are attributable to the prompt change, not to whether
the threshold happened to fire at the same boundary twice.

### Scrubber pipeline

`scrub_fixtures.py` applies, per message:

1. `agent.redact.redact_sensitive_text` — API keys, tokens,
   connection strings
2. Username paths: `/home/teknium` → `/home/user`
3. Personal handles: all case variants of the maintainer name → `user`
4. Email addresses → `contributor@example.com`; git
   `Author: Name <addr>` header lines normalised
5. `<REASONING_SCRATCHPAD>...</REASONING_SCRATCHPAD>` and
   `<think>...</think>` stripped from assistant content
6. Messaging-platform user mentions (`<@123456>`, `<@***>`) →
   `<@user>`
7. First user message paraphrased to remove personal voice;
   subsequent user turns kept verbatim after the redactions above
8. System prompt replaced with a generic public-safe placeholder so
   we don't check in the maintainer's tuned soul/skills/memory system
   block
9. Orphan empty-assistant messages (artifact of scratchpad-only
   turns) and trailing tool messages with no matching assistant are
   dropped
10. Tool outputs preserved verbatim. An earlier iteration truncated
    > 2KB tool bodies to keep fixture JSON small, but that defeats
    the purpose: real sessions have 30KB `skill_view` dumps, 10KB
    `read_file` outputs, 5KB `web_extract` bodies — compression has
    to handle them. Truncation is now a no-op; the pipeline note
    remains in `scrubbing_passes` for audit trail clarity.

Before every fixture PR: grep the fixture for PII patterns. An
audit is embedded at the bottom of the scrubber as comments.

**Fixtures must stay small.** Target <200 KB per fixture, <500 KB
total for the directory. Current total: ~410 KB across three
fixtures.  Larger sessions are truncated with a
`truncated_to: <index>` field in the fixture header so the cut is
reviewable.

## Probe format

One probe file per fixture, so reviewers can see the question bank
evolve alongside the fixture:

```json
{
  "fixture": "401-debug",
  "probes": [
    {
      "id": "recall-error-code",
      "type": "recall",
      "question": "What was the original error code and endpoint?",
      "expected_facts": ["401", "/api/auth/login"]
    },
    {
      "id": "artifact-files-modified",
      "type": "artifact",
      "question": "Which files have been modified in this session?",
      "expected_facts": ["session_store.py", "redis_client.py"]
    },
    {
      "id": "continuation-next-step",
      "type": "continuation",
      "question": "What should we do next?",
      "expected_facts": ["re-run the integration tests", "restart the worker"]
    },
    {
      "id": "decision-redis-approach",
      "type": "decision",
      "question": "What did we decide about the Redis issue?",
      "expected_facts": ["switch to redis-py 5.x", "pooled connection"]
    }
  ]
}
```

The four probe types come directly from Factory's methodology:
**recall, artifact, continuation, decision**. `expected_facts` gives
the grader concrete anchors instead of relying purely on LLM taste.

Authoring a probe bank is a one-time cost per fixture. 8-12 probes per
fixture is the target — enough to cover all four types, few enough to
grade in under a minute at reasonable cost.

## Grading

Each probe gets scored 0-5 on **six dimensions** (Factory's six):

| Dimension             | What it measures                                    |
|-----------------------|-----------------------------------------------------|
| accuracy              | File paths, function names, error codes are correct |
| context_awareness     | Reflects current state, not a mid-session snapshot  |
| artifact_trail        | Knows which files were read / modified / created    |
| completeness          | Addresses all parts of the probe                    |
| continuity            | Agent can continue without re-fetching              |
| instruction_following | Probe answered in the requested form                |

Grading is done by a single judge-model call per probe with a
deterministic rubric prompt (see `rubric.py`). The rubric includes the
`expected_facts` list so the judge has a concrete anchor. Default
judge model: whatever the user has configured as their main model at
run time (same resolution path as `auxiliary_client.call_llm`). A
`--judge-model` flag allows overriding for consistency across runs.

Non-determinism caveat: two runs of the same fixture will produce
different scores. A single run means nothing. Report medians over
N=3 runs by default, and require an improvement of >=0.3 on any
dimension before claiming a prompt change is a win.

## Run flow

```
python run_eval.py [OPTIONS]
```

Options (fire-style, mirroring `sample_and_compress.py`):

| Flag                   | Default    | Purpose                                   |
|------------------------|------------|-------------------------------------------|
| `--fixtures`           | all        | Comma-separated fixture names             |
| `--runs`               | 3          | Runs per fixture (for median)             |
| `--judge-model`        | auto       | Override judge model                      |
| `--compressor-model`   | auto       | Override model used *inside* the compressor |
| `--label`              | timestamp  | Subdirectory under `results/`             |
| `--focus-topic`        | none       | Pass-through to `compress(focus_topic=)`  |
| `--compare-to`         | none       | Path to a previous run for diff output    |

Steps per fixture per run:

1. Load fixture JSON and probe bank.
2. Construct a `ContextCompressor` against the fixture's model.
3. Call `compressor.compress(messages)` — capture the compressed
   message list.
4. For each probe: ask the judge model to role-play as the continuing
   agent with only the compressed state, then grade the answer on the
   six dimensions using `rubric.py`.
5. Write a per-run JSON to `results/<label>/<fixture>-run-N.json`.
6. After all runs, emit a markdown summary to
   `results/<label>/report.md`.

## Report format

Pasted verbatim into PR descriptions that touch the compressor:

```
## Compression eval — label 2026-04-25_13-40-02

Main model: anthropic/claude-sonnet-4.6   Judge: same
3 runs per fixture, medians reported.

| Fixture        | Accuracy | Context | Artifact | Complete | Continuity | Instruction | Overall |
|----------------|----------|---------|----------|----------|------------|-------------|---------|
| 401-debug      | 4.1      | 4.0     | 2.5      | 4.3      | 3.8        | 5.0         | 3.95    |
| pr-review      | 3.9      | 3.8     | 3.1      | 4.2      | 3.9        | 5.0         | 3.98    |
| feature-impl   | 4.0      | 3.9     | 2.9      | 4.1      | 4.0        | 5.0         | 3.98    |

Per-probe misses (score < 3.0):
- 401-debug / artifact-files-modified: 1.7 — summary dropped redis_client.py
- pr-review / decision-auth-rewrite: 2.3 — outcome captured, reasoning dropped
```

## Cost expectations

Dominated by the judge calls. For 3 fixtures × 10 probes × 3 runs =
90 judge calls per eval run. On Claude Sonnet 4.6 that is roughly
$0.50-$1.50 per full eval depending on probe length. The compressor
itself makes 1 call per fixture × 3 runs = 9 additional calls.

**This is not a check to run after every commit.** It is a
before-merge check for PRs that touch:

- `agent/context_compressor.py` — any change to `_template_sections`,
  `_generate_summary`, or `compress()`.
- `agent/auxiliary_client.py` — when changing how compression tasks
  are routed.
- `agent/prompt_builder.py` — when the compression-note phrasing
  changes.

## Open questions (to resolve before implementing)

1. **Fixture scrubbing: manual or scripted?** A scripted scrub that
   also replaces project names / hostnames would lower the cost of
   contributing a new fixture. Risk: over-aggressive replacement
   destroys the signal the probe depends on. Propose: start manual,
   add scripted helpers once we have 3 fixtures and know the common
   PII shapes.

2. **Judge model selection.** Factory uses GPT-5.2. We can't pin one
   — user's main model changes. Options: (a) grade with main model
   (cheap, inconsistent across users), (b) require a specific judge
   model (e.g. `claude-sonnet-4.6`), inconsistent for users without
   access. Propose (a) with a `--judge-model` override, and make the
   model name prominent in the report so comparisons across machines
   are legible.

3. **Noise floor.** Before landing prompt changes, run the current
   prompt N=10 times to measure per-dimension stddev. That tells us
   the minimum delta to call a change significant. Suspect 0.2-0.3 on
   a 0-5 scale. Decision deferred until after the first fixture is
   landed.

4. **Iterative-merge coverage.** The real Factory-vs-Anthropic
   difference is incremental merge vs. regenerate. A fixture that
   only compresses once doesn't exercise our iterative path. Add a
   fourth fixture that forces two compressions (manually chained),
   with probes that test whether information from the first
   compression survives the second. Deferred to a follow-up PR.

## Implementation status

This PR ships the full eval end-to-end:

- `scrub_fixtures.py` — reproducible scrubber
- `fixtures/` — three scrubbed session fixtures
- `probes/` — three probe banks (10-11 probes each, all four types)
- `rubric.py` — six-dimension grading rubric + judge-prompt builder + response parser
- `compressor_driver.py` — thin wrapper around `ContextCompressor` for forced single-shot compression
- `grader.py` — two-phase continuation + grading calls via OpenAI SDK
- `report.py` — markdown report renderer + `--compare-to` delta mode + per-run JSON dumper
- `run_eval.py` — entry point (`fire`-style CLI)
- `tests/test_compression_eval.py` — 33 unit tests covering rubric parsing, report rendering, fixture/probe loading, and a PII smoke test on the fixtures (LLM paths not tested — they require credentials and are exercised by the eval itself)

### Noise floor — one empirical data point

A single same-inputs re-run of `debug-session-feishu-id-model`
(compressor + judge = `openai/gpt-5.4-mini` via Nous Portal,
runs=1) produced:

- Run A overall: 3.25
- Run B overall: 3.17 (delta -0.08)

Individual dimensions varied by up to ±0.5 between the two runs on
single-run medians. This confirms DESIGN.md's "< 0.3 is noise"
guidance is the right order of magnitude for a single-run
comparison. With `runs=3` default, per-dimension variance should
tighten; noise-floor measurement at N=10 is still a useful
follow-up to calibrate precisely.

## Open follow-ups (not blocking this PR)

1. **Iterative-merge fixture** — our actual compression win over
   "regenerate from scratch" approaches is only exercised when
   `_previous_summary` is re-used on a second compression. None of
   the three shipped fixtures force two compressions. The natural
   basis is `config-build-competitive-scouts` (already iterative by
   shape); splitting it at the Monday/Tuesday boundary would force
   the second compression to merge rather than regenerate.
2. **Noise-floor precision** — run the current prompt N=10 times
   against one fixture to pin down per-dimension stddev and publish
   the numbers in README.
3. **Scripted scrubber helpers** — the current scrubber is manual
   per-fixture. A helper that identifies candidate sessions to
   scrub (by shape or by keyword) would lower the cost of adding
   fixture #4+.
4. **Judge model selection policy** — current code uses whatever
   the user passes as `--judge-model` (default: same as compressor).
   Pinning the judge across users would stabilise cross-machine
   comparisons, at the cost of blocking users without access to
   the pinned model.
