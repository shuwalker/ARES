"""Rubric for probe-based compression eval grading.

Six dimensions scored 0-5 by a judge model. The scoring anchors are spelled
out so the judge interpretation is stable across runs and across judge
models.

Adapted from the methodology in
https://factory.ai/news/evaluating-compression. Their scoreboard is not
adopted; only the dimension definitions and the 0-5 scale.
"""
from __future__ import annotations

from typing import Any, Dict, List

# Canonical dimension order. All reports, parsers, and comparisons derive
# from this list — do not hardcode the order elsewhere.
DIMENSIONS: List[str] = [
    "accuracy",
    "context_awareness",
    "artifact_trail",
    "completeness",
    "continuity",
    "instruction_following",
]

DIMENSION_DESCRIPTIONS: Dict[str, str] = {
    "accuracy": (
        "Are concrete facts correct — file paths, function names, PR/issue "
        "numbers, error codes, command outputs, line numbers? A single wrong "
        "path or error code should cost points. Vague but non-contradicting "
        "answers score mid-range."
    ),
    "context_awareness": (
        "Does the answer reflect the CURRENT state of the session, not a "
        "mid-session snapshot? For example, if a file was modified then "
        "reverted, does the answer describe the reverted state? If three "
        "PRs were opened, does the answer know which was merged?"
    ),
    "artifact_trail": (
        "Does the answer correctly enumerate the artifacts (files read, "
        "files modified, commands run, tools called, PRs opened, cron jobs "
        "created)? Missing artifacts cost more than extra unrelated ones."
    ),
    "completeness": (
        "Does the answer address ALL parts of the probe question? If the "
        "probe asks for three things and only two are answered, that is "
        "incomplete regardless of accuracy on the two."
    ),
    "continuity": (
        "Could the next assistant continue the work using only this answer, "
        "without having to re-fetch files or re-explore the codebase? An "
        "answer that lists files by name but doesn't mention the change is "
        "poor continuity even if accurate."
    ),
    "instruction_following": (
        "Is the answer in the format the probe requested (list, number, "
        "short phrase, yes/no)? Ignore tone and length, only assess "
        "whether the requested form was honoured."
    ),
}

SCORE_SCALE: Dict[int, str] = {
    0: "No useful information; wrong or hallucinated.",
    1: "Major gaps or a key fact is wrong.",
    2: "Partially correct but significant omissions.",
    3: "Mostly correct with minor omissions or imprecision.",
    4: "Correct and complete with only trivial imprecision.",
    5: "Fully correct, complete, and in the requested format.",
}


_RUBRIC_HEADER = """You are an evaluator grading a single answer produced by an AI assistant \
that was given a COMPRESSED handoff summary of an earlier conversation and \
asked a probe question. You are NOT evaluating the compression summary \
directly — you are evaluating whether the answer the assistant produced \
from that summary is correct, complete, and useful.

Grade on six dimensions, each 0-5:

{dimension_block}

0-5 scale:
{scale_block}

Grade strictly. Fractional scores are NOT allowed — output integers only. \
If the answer is ambiguous, use the lower of the two candidate scores."""


def build_judge_prompt(
    *,
    probe_question: str,
    probe_type: str,
    expected_facts: List[str],
    assistant_answer: str,
) -> str:
    """Build the full judge prompt for one (probe, answer) pair.

    The judge is told the expected_facts up front so grading is anchored to
    concrete signal rather than judge taste. Expected facts are intentionally
    NOT shown to the assistant that produces the answer.
    """
    dim_block = "\n".join(
        f"- {d}: {DIMENSION_DESCRIPTIONS[d]}" for d in DIMENSIONS
    )
    scale_block = "\n".join(
        f"  {score}: {desc}" for score, desc in sorted(SCORE_SCALE.items())
    )
    header = _RUBRIC_HEADER.format(
        dimension_block=dim_block,
        scale_block=scale_block,
    )

    expected_block = (
        "\n".join(f"- {f}" for f in expected_facts) if expected_facts else "(none provided)"
    )

    output_schema = (
        "Respond with ONLY a JSON object, no prose before or after, matching "
        "this schema exactly:\n"
        "{\n"
        '  "accuracy": <int 0-5>,\n'
        '  "context_awareness": <int 0-5>,\n'
        '  "artifact_trail": <int 0-5>,\n'
        '  "completeness": <int 0-5>,\n'
        '  "continuity": <int 0-5>,\n'
        '  "instruction_following": <int 0-5>,\n'
        '  "notes": "<one short sentence, <=200 chars, identifying the '
        'single biggest issue with the answer if any>"\n'
        "}"
    )

    return (
        f"{header}\n\n"
        f"PROBE TYPE: {probe_type}\n\n"
        f"PROBE QUESTION:\n{probe_question}\n\n"
        f"EXPECTED FACTS (the answer should contain these concrete anchors; "
        f"missing any is a material defect in accuracy and/or completeness):\n"
        f"{expected_block}\n\n"
        f"ASSISTANT ANSWER TO GRADE:\n{assistant_answer}\n\n"
        f"{output_schema}"
    )


def parse_judge_response(raw: str) -> Dict[str, Any]:
    """Parse the judge model's JSON response into a score dict.

    Tolerates surrounding prose (judges ignore instructions sometimes) by
    extracting the first {...} block. Validates that every dimension is
    present as an integer 0-5.

    Returns dict with keys: scores (dim->int), notes (str), overall (float).
    Raises ValueError if the response cannot be parsed into a complete
    score set.
    """
    import json
    import re

    if not raw or not raw.strip():
        raise ValueError("empty judge response")

    # Strip code fences and any ```json prefix judges sometimes emit.
    stripped = raw.strip()
    fence_match = re.match(r"^```(?:json)?\s*(.*?)\s*```$", stripped, re.DOTALL)
    if fence_match:
        stripped = fence_match.group(1).strip()

    # Extract the first {...} block greedy-to-matching-brace.
    brace_match = re.search(r"\{.*\}", stripped, re.DOTALL)
    if not brace_match:
        raise ValueError(f"no JSON object found in judge response: {raw[:200]!r}")
    candidate = brace_match.group(0)

    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError as exc:
        raise ValueError(f"judge response not valid JSON: {exc}; raw={candidate[:200]!r}")

    scores: Dict[str, int] = {}
    for dim in DIMENSIONS:
        if dim not in parsed:
            raise ValueError(f"judge response missing dimension {dim!r}: {parsed}")
        value = parsed[dim]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"dimension {dim} is not numeric: {value!r}")
        int_val = int(round(value))
        if int_val < 0 or int_val > 5:
            raise ValueError(f"dimension {dim} out of range: {int_val}")
        scores[dim] = int_val

    notes_val = parsed.get("notes", "")
    notes = str(notes_val)[:200] if notes_val else ""

    overall = sum(scores.values()) / len(scores)
    return {
        "scores": scores,
        "notes": notes,
        "overall": overall,
    }
