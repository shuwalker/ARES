"""Markdown report rendering + diff-against-baseline for compression-eval runs.

Report format is optimised for pasting directly into a PR description.
Top-of-report table is the per-fixture medians; below that is the
probe-by-probe miss list (scores < 3.0 on overall).

Diff mode (``compare_to``) emits a second table with deltas per fixture
per dimension against a previous run directory.
"""
from __future__ import annotations

import json
import statistics
from pathlib import Path
from typing import Any, Dict, List, Optional

from rubric import DIMENSIONS


def write_run_json(
    *,
    results_dir: Path,
    fixture_name: str,
    run_index: int,
    payload: Dict[str, Any],
) -> Path:
    """Dump one fixture's per-run results as JSON for later diffing."""
    results_dir.mkdir(parents=True, exist_ok=True)
    path = results_dir / f"{fixture_name}-run-{run_index}.json"
    with path.open("w") as fh:
        json.dump(payload, fh, indent=2, ensure_ascii=False)
    return path


def _median(values: List[float]) -> float:
    return statistics.median(values) if values else 0.0


def _format_score(value: float) -> str:
    return f"{value:.2f}"


def _format_delta(baseline: float, current: float) -> str:
    delta = current - baseline
    if abs(delta) < 0.01:
        return f"{current:.2f} (±0)"
    sign = "+" if delta > 0 else ""
    return f"{current:.2f} ({sign}{delta:.2f})"


def summarize_fixture_runs(
    fixture_runs: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Collapse N runs of one fixture into per-dimension medians + metadata.

    Each run payload is {probes: [{id, type, scores: {...}, overall, ...}]}.
    Returns {fixture_name, runs, dimension_medians, overall_median, misses}.
    """
    if not fixture_runs:
        return {}

    fixture_name = fixture_runs[0]["fixture_name"]
    n_runs = len(fixture_runs)

    # Per-probe-per-dimension aggregation across runs
    probe_ids = [p["id"] for p in fixture_runs[0]["probes"]]
    per_probe: Dict[str, Dict[str, List[float]]] = {
        pid: {d: [] for d in DIMENSIONS} for pid in probe_ids
    }
    per_probe_overall: Dict[str, List[float]] = {pid: [] for pid in probe_ids}

    for run in fixture_runs:
        for p in run["probes"]:
            pid = p["id"]
            for d in DIMENSIONS:
                per_probe[pid][d].append(p["scores"].get(d, 0))
            per_probe_overall[pid].append(p["overall"])

    # Median each probe across runs, then median those medians across probes
    dim_medians: Dict[str, float] = {}
    for d in DIMENSIONS:
        per_probe_med = [_median(per_probe[pid][d]) for pid in probe_ids]
        dim_medians[d] = _median(per_probe_med)
    overall_median = _median([_median(per_probe_overall[pid]) for pid in probe_ids])

    # Misses = probes whose median overall < 3.0
    misses: List[Dict[str, Any]] = []
    for pid in probe_ids:
        med = _median(per_probe_overall[pid])
        if med < 3.0:
            # Pull the notes from the last run to give the reader a
            # concrete clue. (Taking the most recent run is fine —
            # notes vary across runs and any one is illustrative.)
            notes = ""
            probe_type = ""
            for p in fixture_runs[-1]["probes"]:
                if p["id"] == pid:
                    notes = p.get("notes", "")
                    probe_type = p.get("type", "")
                    break
            misses.append({
                "id": pid,
                "type": probe_type,
                "overall_median": med,
                "notes": notes,
            })

    return {
        "fixture_name": fixture_name,
        "runs": n_runs,
        "dimension_medians": dim_medians,
        "overall_median": overall_median,
        "misses": misses,
        "compression": fixture_runs[0].get("compression", {}),
    }


def render_report(
    *,
    label: str,
    compressor_model: str,
    judge_model: str,
    runs_per_fixture: int,
    summaries: List[Dict[str, Any]],
    baseline_summaries: Optional[List[Dict[str, Any]]] = None,
) -> str:
    """Render the full markdown report.

    baseline_summaries is the same shape as summaries, sourced from a
    previous run (via --compare-to). When present, dimension scores in
    the main table render with deltas.
    """
    lines: List[str] = []
    lines.append(f"## Compression eval — label `{label}`")
    lines.append("")
    lines.append(f"- Compressor model: `{compressor_model}`")
    lines.append(f"- Judge model: `{judge_model}`")
    lines.append(f"- Runs per fixture: {runs_per_fixture}")
    lines.append("- Medians over runs reported")
    if baseline_summaries:
        lines.append("- Deltas shown against baseline run")
    lines.append("")

    baseline_by_name: Dict[str, Dict[str, Any]] = {}
    if baseline_summaries:
        baseline_by_name = {s["fixture_name"]: s for s in baseline_summaries}

    # Main table
    header = ["Fixture"] + DIMENSIONS + ["overall"]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * len(header)) + "|")
    for s in summaries:
        row = [s["fixture_name"]]
        baseline = baseline_by_name.get(s["fixture_name"])
        for d in DIMENSIONS:
            cur = s["dimension_medians"][d]
            if baseline and d in baseline.get("dimension_medians", {}):
                row.append(_format_delta(baseline["dimension_medians"][d], cur))
            else:
                row.append(_format_score(cur))
        if baseline:
            row.append(_format_delta(baseline["overall_median"], s["overall_median"]))
        else:
            row.append(_format_score(s["overall_median"]))
        lines.append("| " + " | ".join(row) + " |")
    lines.append("")

    # Compression metadata
    lines.append("### Compression summary")
    lines.append("")
    lines.append("| Fixture | Pre tokens | Post tokens | Ratio | Pre msgs | Post msgs |")
    lines.append("|---|---|---|---|---|---|")
    for s in summaries:
        c = s.get("compression", {})
        lines.append(
            "| {name} | {pre} | {post} | {ratio:.1%} | {pm} | {pom} |".format(
                name=s["fixture_name"],
                pre=c.get("pre_tokens", 0),
                post=c.get("post_tokens", 0),
                ratio=c.get("compression_ratio", 0.0),
                pm=c.get("pre_message_count", 0),
                pom=c.get("post_message_count", 0),
            )
        )
    lines.append("")

    # Per-probe misses
    any_misses = any(s["misses"] for s in summaries)
    if any_misses:
        lines.append("### Probes scoring below 3.0 overall (median)")
        lines.append("")
        for s in summaries:
            if not s["misses"]:
                continue
            lines.append(f"**{s['fixture_name']}**")
            for m in s["misses"]:
                note_part = f" — {m['notes']}" if m["notes"] else ""
                lines.append(
                    f"- `{m['id']}` ({m['type']}): "
                    f"{m['overall_median']:.2f}{note_part}"
                )
            lines.append("")

    lines.append("### Methodology")
    lines.append("")
    lines.append(
        "Probe-based eval adapted from "
        "https://factory.ai/news/evaluating-compression. Each fixture is "
        "compressed in a single forced `ContextCompressor.compress()` call, "
        "then a continuation call asks the compressor model to answer each "
        "probe from the compressed state, then the judge model scores the "
        "answer 0-5 on six dimensions. A single run is noisy; medians "
        "across multiple runs are the meaningful signal. Changes below "
        "~0.3 on any dimension are likely within run-to-run noise."
    )
    return "\n".join(lines) + "\n"


def load_baseline_summaries(baseline_dir: Path) -> List[Dict[str, Any]]:
    """Load summaries from a previous eval run for --compare-to.

    Reads the dumped per-run JSONs and re-summarises them so the
    aggregation matches whatever summariser was current at the time of
    the new run (forward-compatible with schema additions).
    """
    if not baseline_dir.exists():
        raise FileNotFoundError(f"baseline dir not found: {baseline_dir}")

    by_fixture: Dict[str, List[Dict[str, Any]]] = {}
    for path in sorted(baseline_dir.glob("*-run-*.json")):
        with path.open() as fh:
            payload = json.load(fh)
        by_fixture.setdefault(payload["fixture_name"], []).append(payload)

    return [summarize_fixture_runs(runs) for runs in by_fixture.values()]
