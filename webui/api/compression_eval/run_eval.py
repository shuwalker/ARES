#!/usr/bin/env python3
"""Compression eval — entry point.

Runs the full probe-based eval over one or more fixtures, produces a
markdown report in ``results/<label>/report.md`` paired with per-run JSON
for later diffing.

Not a pytest. Requires a configured provider + credentials (same path the
agent uses). Does not run in CI. See README.md for usage examples.
"""
from __future__ import annotations

import json
import logging
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

# Make our sibling modules importable whether invoked as a script or as -m.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

try:
    import fire  # noqa: F401
except ImportError:
    fire = None  # fallback to argparse if fire is unavailable

# Import compressor_driver first — its module-level `_locate_hermes_agent()`
# adds the hermes-agent checkout to sys.path so `hermes_cli.*` imports below
# resolve.
from compressor_driver import run_compression  # noqa: E402
from hermes_cli.runtime_provider import resolve_runtime_provider  # noqa: E402
from grader import answer_probe, grade_probe  # noqa: E402
from report import (  # noqa: E402
    load_baseline_summaries,
    render_report,
    summarize_fixture_runs,
    write_run_json,
)

logger = logging.getLogger("compression_eval")


FIXTURES_DIR = _HERE / "fixtures"
PROBES_DIR = _HERE / "probes"
RESULTS_DIR = _HERE / "results"


def _load_fixture(name: str) -> Dict[str, Any]:
    path = FIXTURES_DIR / f"{name}.json"
    if not path.exists():
        available = sorted(p.stem for p in FIXTURES_DIR.glob("*.json"))
        raise FileNotFoundError(
            f"Fixture not found: {name}. Available: {available}"
        )
    with path.open() as fh:
        return json.load(fh)


def _load_probes(name: str) -> Dict[str, Any]:
    path = PROBES_DIR / f"{name}.probes.json"
    if not path.exists():
        raise FileNotFoundError(f"Probe bank not found for fixture {name}: {path}")
    with path.open() as fh:
        return json.load(fh)


def _resolve_runtime(
    *,
    provider_override: Optional[str],
    model_override: Optional[str],
) -> Dict[str, Any]:
    """Resolve provider credentials via the same path the agent uses."""
    runtime = resolve_runtime_provider(
        requested=provider_override,
        target_model=model_override,
    )
    if not runtime.get("api_key") and not runtime.get("base_url"):
        raise RuntimeError(
            "No provider configured. Run `hermes setup` or set provider "
            "credentials in the environment before running the eval."
        )
    return runtime


def _available_fixtures() -> List[str]:
    return sorted(p.stem for p in FIXTURES_DIR.glob("*.json"))


def _run_one_fixture(
    *,
    fixture_name: str,
    run_index: int,
    compressor_runtime: Dict[str, Any],
    compressor_model: str,
    judge_runtime: Dict[str, Any],
    judge_model: str,
    focus_topic: Optional[str],
) -> Dict[str, Any]:
    fx = _load_fixture(fixture_name)
    probes = _load_probes(fixture_name)

    logger.info(
        "[%s run=%d] compressing (%d messages, ctx=%d)",
        fixture_name, run_index, len(fx["messages"]), fx["context_length"],
    )
    compression = run_compression(
        messages=fx["messages"],
        compressor_model=compressor_model,
        compressor_provider=compressor_runtime["provider"],
        compressor_base_url=compressor_runtime["base_url"],
        compressor_api_key=compressor_runtime["api_key"],
        compressor_api_mode=compressor_runtime.get("api_mode", ""),
        context_length=fx["context_length"],
        focus_topic=focus_topic,
        # Force the compressor to use the model we're testing, bypassing
        # any auxiliary.compression.model config override. Without this,
        # ContextCompressor.call_llm(task="compression") routes through
        # the user's config which may pin a different model (e.g.
        # google/gemini-3-flash-preview).
        summary_model_override=compressor_model,
    )
    logger.info(
        "[%s run=%d] compressed %d -> %d tokens (%.1f%%)",
        fixture_name, run_index,
        compression["pre_tokens"], compression["post_tokens"],
        compression["compression_ratio"] * 100,
    )

    probe_results: List[Dict[str, Any]] = []
    for probe in probes["probes"]:
        t0 = time.monotonic()
        try:
            answer = answer_probe(
                compressed_messages=compression["compressed_messages"],
                probe_question=probe["question"],
                provider=compressor_runtime["provider"],
                model=compressor_model,
                base_url=compressor_runtime["base_url"],
                api_key=compressor_runtime["api_key"],
            )
        except Exception as exc:
            logger.warning(
                "[%s run=%d probe=%s] continuation failed: %s",
                fixture_name, run_index, probe["id"], exc,
            )
            answer = ""

        try:
            grade = grade_probe(
                probe_question=probe["question"],
                probe_type=probe["type"],
                expected_facts=probe.get("expected_facts", []),
                assistant_answer=answer,
                judge_provider=judge_runtime["provider"],
                judge_model=judge_model,
                judge_base_url=judge_runtime["base_url"],
                judge_api_key=judge_runtime["api_key"],
            )
        except Exception as exc:
            logger.warning(
                "[%s run=%d probe=%s] grading failed: %s",
                fixture_name, run_index, probe["id"], exc,
            )
            from rubric import DIMENSIONS
            grade = {
                "scores": {d: 0 for d in DIMENSIONS},
                "notes": f"grading error: {exc}",
                "overall": 0.0,
                "raw": "",
                "parse_error": str(exc),
            }

        elapsed = time.monotonic() - t0
        logger.info(
            "[%s run=%d probe=%s] overall=%.2f (%.1fs)",
            fixture_name, run_index, probe["id"], grade["overall"], elapsed,
        )

        probe_results.append({
            "id": probe["id"],
            "type": probe["type"],
            "question": probe["question"],
            "expected_facts": probe.get("expected_facts", []),
            "answer": answer,
            "scores": grade["scores"],
            "overall": grade["overall"],
            "notes": grade["notes"],
            "parse_error": grade["parse_error"],
            "elapsed_seconds": elapsed,
        })

    return {
        "fixture_name": fixture_name,
        "run_index": run_index,
        "compression": {
            "pre_tokens": compression["pre_tokens"],
            "post_tokens": compression["post_tokens"],
            "compression_ratio": compression["compression_ratio"],
            "pre_message_count": compression["pre_message_count"],
            "post_message_count": compression["post_message_count"],
            "summary_text": compression["summary_text"],
        },
        "probes": probe_results,
    }


def _coerce_fixtures_arg(arg: Optional[str]) -> List[str]:
    if not arg:
        return _available_fixtures()
    return [s.strip() for s in arg.split(",") if s.strip()]


def main(
    fixtures: Optional[str] = None,
    runs: int = 3,
    judge_model: Optional[str] = None,
    judge_provider: Optional[str] = None,
    compressor_model: Optional[str] = None,
    compressor_provider: Optional[str] = None,
    label: Optional[str] = None,
    focus_topic: Optional[str] = None,
    compare_to: Optional[str] = None,
    verbose: bool = False,
) -> int:
    """Run the compression eval.

    Args:
        fixtures: Comma-separated fixture names; default = all in fixtures/.
        runs: Runs per fixture. Medians reported. Default 3.
        judge_model: Override the judge model (default = same as
            compressor model resolved from config).
        judge_provider: Override the judge provider.
        compressor_model: Override the compressor model (default =
            whatever resolve_runtime_provider returns for the active
            configuration).
        compressor_provider: Override the compressor provider.
        label: Output subdirectory under results/. Default = timestamp.
        focus_topic: Optional focus topic passed through to
            ContextCompressor.compress(focus_topic=...).
        compare_to: Path to a previous run directory (e.g.
            results/2026-04-24_baseline) to diff against in the report.
        verbose: Print debug logs.
    """
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    fixture_names = _coerce_fixtures_arg(fixtures)
    # Validate every fixture has a probe bank before spending any money.
    for name in fixture_names:
        _load_fixture(name)
        _load_probes(name)

    compressor_runtime = _resolve_runtime(
        provider_override=compressor_provider,
        model_override=compressor_model,
    )
    effective_compressor_model = (
        compressor_model or compressor_runtime.get("resolved_model") or "auto"
    )
    if effective_compressor_model == "auto":
        # resolve_runtime_provider doesn't always fill resolved_model;
        # fall back to reading model.default from config.
        from hermes_cli.config import load_config
        cfg = load_config()
        mc = cfg.get("model", {}) or {}
        if isinstance(mc, dict):
            effective_compressor_model = (
                mc.get("default") or mc.get("model") or "anthropic/claude-sonnet-4.6"
            )
        else:
            effective_compressor_model = str(mc) or "anthropic/claude-sonnet-4.6"

    if judge_provider or judge_model:
        judge_runtime = _resolve_runtime(
            provider_override=judge_provider,
            model_override=judge_model,
        )
        effective_judge_model = judge_model or effective_compressor_model
    else:
        judge_runtime = compressor_runtime
        effective_judge_model = effective_compressor_model

    effective_label = label or datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    out_dir = RESULTS_DIR / effective_label
    out_dir.mkdir(parents=True, exist_ok=True)

    logger.info(
        "Compression eval starting: label=%s fixtures=%s runs=%d "
        "compressor=%s judge=%s out=%s",
        effective_label, fixture_names, runs,
        effective_compressor_model, effective_judge_model, out_dir,
    )

    all_summaries: List[Dict[str, Any]] = []
    for fixture_name in fixture_names:
        per_run: List[Dict[str, Any]] = []
        for run_i in range(1, runs + 1):
            payload = _run_one_fixture(
                fixture_name=fixture_name,
                run_index=run_i,
                compressor_runtime=compressor_runtime,
                compressor_model=effective_compressor_model,
                judge_runtime=judge_runtime,
                judge_model=effective_judge_model,
                focus_topic=focus_topic,
            )
            write_run_json(
                results_dir=out_dir,
                fixture_name=fixture_name,
                run_index=run_i,
                payload=payload,
            )
            per_run.append(payload)
        summary = summarize_fixture_runs(per_run)
        all_summaries.append(summary)

    baseline_summaries: Optional[List[Dict[str, Any]]] = None
    if compare_to:
        baseline_path = Path(compare_to)
        if not baseline_path.is_absolute():
            baseline_path = _HERE / baseline_path
        baseline_summaries = load_baseline_summaries(baseline_path)

    report_md = render_report(
        label=effective_label,
        compressor_model=effective_compressor_model,
        judge_model=effective_judge_model,
        runs_per_fixture=runs,
        summaries=all_summaries,
        baseline_summaries=baseline_summaries,
    )
    report_path = out_dir / "report.md"
    report_path.write_text(report_md)

    # Also write a machine-readable summary.json alongside the human report.
    summary_path = out_dir / "summary.json"
    with summary_path.open("w") as fh:
        json.dump(
            {
                "label": effective_label,
                "compressor_model": effective_compressor_model,
                "judge_model": effective_judge_model,
                "runs_per_fixture": runs,
                "fixtures": all_summaries,
            },
            fh,
            indent=2,
            ensure_ascii=False,
        )

    print()
    print(report_md)
    print(f"Report written to {report_path}")
    print(f"Per-run JSON in {out_dir}")
    return 0


if __name__ == "__main__":
    if fire is not None:
        # fire preserves docstrings as --help and handles kwarg-style CLI.
        sys.exit(fire.Fire(main))
    else:
        import argparse
        p = argparse.ArgumentParser()
        p.add_argument("--fixtures")
        p.add_argument("--runs", type=int, default=3)
        p.add_argument("--judge-model", dest="judge_model")
        p.add_argument("--judge-provider", dest="judge_provider")
        p.add_argument("--compressor-model", dest="compressor_model")
        p.add_argument("--compressor-provider", dest="compressor_provider")
        p.add_argument("--label")
        p.add_argument("--focus-topic", dest="focus_topic")
        p.add_argument("--compare-to", dest="compare_to")
        p.add_argument("--verbose", action="store_true")
        args = p.parse_args()
        sys.exit(main(**vars(args)))
