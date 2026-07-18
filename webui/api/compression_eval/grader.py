"""Two-phase probe grading.

Phase 1 — **Continuation**: simulate the next assistant turn. Feed the
compressed message list plus the probe question and ask the continuing
model to answer using only the compressed context. This is exactly what
a real next-turn call would look like.

Phase 2 — **Grading**: a separate judge-model call scores the answer on
the six rubric dimensions using ``rubric.build_judge_prompt``.

Both phases use the OpenAI SDK directly against the resolved provider
endpoint, so the explicit api_key + base_url we pass always reaches the
wire. (``agent.auxiliary_client.call_llm`` is designed for task-tagged
auxiliary calls backed by config lookups; for eval we need the explicit
credentials to win unconditionally.)
"""
from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# Make sibling imports work (rubric.py is next to grader.py).
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from openai import OpenAI  # noqa: E402

from rubric import build_judge_prompt, parse_judge_response  # noqa: E402

logger = logging.getLogger(__name__)


_CONTINUATION_SYSTEM = (
    "You are the continuing assistant in a long session. Earlier turns have "
    "been compacted into a handoff summary that is now part of the "
    "conversation history. The user has just asked you a question. "
    "Answer using ONLY what you can determine from the conversation history "
    "you see (including the handoff summary). Do NOT invent details. If the "
    "summary does not contain a specific fact, say so explicitly rather "
    "than guessing. Be direct and concrete — cite file paths, PR numbers, "
    "error codes, and exact values when they are present in the summary."
)


def answer_probe(
    *,
    compressed_messages: List[Dict[str, Any]],
    probe_question: str,
    model: str,
    provider: str,
    base_url: str,
    api_key: str,
    max_tokens: int = 1024,
    timeout: Optional[float] = 120.0,
) -> str:
    """Run the continuation call: what does the next assistant answer?

    Builds a messages list of [system_continuation, *compressed, probe_user]
    and asks the configured model. Returns the answer content as a string.
    """
    # Strip any pre-existing system message from the compressed list and
    # replace with our continuation system prompt. The fixture's generic
    # system is not the right frame for the continuation simulation.
    history = [m for m in compressed_messages if m.get("role") != "system"]
    messages = (
        [{"role": "system", "content": _CONTINUATION_SYSTEM}]
        + _sanitize_for_chat_api(history)
        + [{"role": "user", "content": probe_question}]
    )

    client = OpenAI(api_key=api_key, base_url=base_url, timeout=timeout)
    response = client.chat.completions.create(
        model=model,
        messages=messages,
        max_tokens=max_tokens,
    )
    content = response.choices[0].message.content
    if not isinstance(content, str):
        content = "" if content is None else str(content)
    return content.strip()


def grade_probe(
    *,
    probe_question: str,
    probe_type: str,
    expected_facts: List[str],
    assistant_answer: str,
    judge_model: str,
    judge_provider: str,
    judge_base_url: str,
    judge_api_key: str,
    max_tokens: int = 512,
    timeout: Optional[float] = 120.0,
) -> Dict[str, Any]:
    """Run the judge call and parse the six dimension scores.

    Returns dict {scores: {dim: int}, notes: str, overall: float,
    raw: str, parse_error: str|None}. On parse failure, scores are zeros
    and parse_error is populated — the caller decides whether to retry
    or accept.
    """
    prompt = build_judge_prompt(
        probe_question=probe_question,
        probe_type=probe_type,
        expected_facts=expected_facts,
        assistant_answer=assistant_answer,
    )
    client = OpenAI(api_key=judge_api_key, base_url=judge_base_url, timeout=timeout)
    response = client.chat.completions.create(
        model=judge_model,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
    )
    raw = response.choices[0].message.content or ""
    if not isinstance(raw, str):
        raw = str(raw)

    try:
        parsed = parse_judge_response(raw)
        parsed["raw"] = raw
        parsed["parse_error"] = None
        return parsed
    except ValueError as exc:
        logger.warning("Judge response parse failed: %s | raw=%r", exc, raw[:200])
        from rubric import DIMENSIONS
        return {
            "scores": {d: 0 for d in DIMENSIONS},
            "notes": "",
            "overall": 0.0,
            "raw": raw,
            "parse_error": str(exc),
        }


def _sanitize_for_chat_api(
    messages: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Drop tool_calls/tool pairs that are incomplete.

    A compressed message list may contain tool_call references whose matching
    ``tool`` result was summarized away, which breaks strict-validator
    providers (Anthropic, OpenAI). Easiest correct behaviour for the eval:
    strip tool_calls entirely and drop ``tool`` role messages — the
    continuation model only needs the summary + recent turns to answer the
    probe, not the precise tool-call bookkeeping.
    """
    clean: List[Dict[str, Any]] = []
    for m in messages:
        role = m.get("role")
        if role == "tool":
            # Convert tool result to a plain user note so the continuation
            # model still sees the content without needing the structured
            # tool_call_id pairing.
            content = m.get("content")
            if isinstance(content, list):
                content = "\n".join(
                    p.get("text", "") for p in content if isinstance(p, dict)
                )
            clean.append({
                "role": "user",
                "content": f"[earlier tool result]\n{content or ''}",
            })
            continue
        new = {"role": role, "content": m.get("content", "")}
        # Drop tool_calls — the downstream assistant message's content
        # still describes what the agent was doing.
        clean.append(new)
    # Collapse consecutive same-role turns into one (alternation rule)
    merged: List[Dict[str, Any]] = []
    for m in clean:
        if merged and merged[-1]["role"] == m["role"]:
            prev = merged[-1]
            prev_c = prev.get("content") or ""
            new_c = m.get("content") or ""
            prev["content"] = f"{prev_c}\n\n{new_c}" if prev_c else new_c
        else:
            merged.append(m)
    return merged
