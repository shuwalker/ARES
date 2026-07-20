"""
ARES SI — Bridge between the SI pipeline and existing AgenticBackend system.

The SI pipeline produces a ContextBriefing. The bridge:
1. Takes the briefing
2. Composes a prompt from its sections (identity, context, constraints, privacy)
3. Selects the right AgenticBackend via BackendRouter
4. Calls backend.run_turn() with the composed message
5. Returns the result as a WorkerResult

No new adapters. The existing backends ARE the workers.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Any

from api.si.types import (
    ContextBriefing,
    ContextItem,
    Constraint,
    MemoryItem,
    SIIdentity,
    WorkerResult,
    DataClassification,
    PrivacyClass,
    PUBLIC,
    PERSONAL,
    PRIVATE,
    SENSITIVE,
    SECRET,
)

logger = logging.getLogger(__name__)

_ENV_SI_ENABLED = "ARES_SI_ENABLED"


def si_enabled() -> bool:
    """Check if the SI pipeline is enabled via ARES_SI_ENABLED env var."""
    return os.environ.get(_ENV_SI_ENABLED, "").strip().lower() in ("1", "true", "yes", "on")


def compose_prompt_from_briefing(briefing: ContextBriefing, message: str) -> str:
    """Compose a prompt from briefing sections. NOT one monolithic system prompt.

    Each section is separate so workers can't confuse identity with instructions.
    """
    parts: list[str] = []

    # 1. Identity — who the SI is
    if briefing.si_identity:
        ident = briefing.si_identity
        parts.append(f"You are {ident.name}.")
        if ident.mission:
            parts.append(ident.mission)
        if ident.owner_name:
            parts.append(f"Your owner is {ident.owner_name}. You are loyal to {ident.loyalty}.")
        if ident.principles:
            principles = "\n".join(f"- {p}" for p in ident.principles)
            parts.append(f"Principles:\n{principles}")

    # 2. Context — what the SI knows
    context_items: list[str] = []
    for item in briefing.user_context:
        context_items.append(f"- {item.content}")
    for item in briefing.project_context:
        context_items.append(f"- [Project] {item.content}")
    for mem in briefing.relevant_memories:
        context_items.append(f"- [Memory] {mem.content}")
    if context_items:
        parts.append("Context:\n" + "\n".join(context_items))

    # 3. Recent conversation
    if briefing.recent_conversation:
        conv_lines = []
        for item in briefing.recent_conversation:
            conv_lines.append(f"- {item.content}")
        parts.append("Recent conversation:\n" + "\n".join(conv_lines))

    # 4. Constraints — what the worker should/shouldn't do
    if briefing.constraints:
        constraint_lines = []
        for i, c in enumerate(briefing.constraints, 1):
            constraint_lines.append(f"{i}. [{c.kind}] {c.description}")
        parts.append("Constraints:\n" + "\n".join(constraint_lines))

    # 5. Privacy policy
    if briefing.privacy_policy:
        policy = briefing.privacy_policy
        redacted = policy.get("redacted_types", [])
        if redacted:
            parts.append(f"Privacy: Do not share {', '.join(redacted)} data outside this conversation.")

    # 6. The user's message
    parts.append(message)

    return "\n\n".join(parts)


def _worker_to_backend_name(worker_id: str) -> str:
    """Map SI WorkerRecord IDs to existing AgenticBackend names.

    They're already the same: hermes_local, claude_local, gemini_local, etc.
    """
    return worker_id


def _backend_name_to_privacy_class(backend_name: str) -> PrivacyClass:
    """Infer privacy class from backend name convention."""
    if backend_name.endswith("_local"):
        return PrivacyClass.LOCAL_ONLY
    if backend_name.endswith("_cloud") or backend_name.endswith("_antigravity"):
        return PrivacyClass.APPROVED_PROVIDER
    return PrivacyClass.EXTERNAL_PROVIDER


def si_turn(
    user_message: str,
    session_id: str = "",
    *,
    target_worker: str | None = None,
    model: str = "",
    model_provider: str | None = None,
    cancel_event: Any = None,
) -> dict[str, Any]:
    """Full SI pipeline: classify → context → route → execute → evaluate → compose.

    This is the main entry point that wires the SI into the existing chat flow.
    When ARES_SI_ENABLED is true, this replaces the direct backend call.
    """
    from api.si.context_compiler import classify_intent, compile_context
    from api.si.trust_engine import classify_data, filter_briefing
    from api.si.router import route_task
    from api.si.evaluator import evaluate_result
    from api.si.response_composer import compose_response
    from api.backends.router import get_router as get_backend_router

    started_at = time.time()

    # 1. Classify intent
    intent, confidence = classify_intent(user_message)

    # 2. Compile context
    briefing = compile_context(user_message)

    # 3. Classify data sensitivity
    sensitivity = classify_data(user_message)

    # 4. Route to worker
    if target_worker:
        backend_name = target_worker
    else:
        routing = route_task(
            intent,
            data_sensitivity=sensitivity.value if sensitivity else "personal",
        )
        selected = routing.get("selected_worker")
        if isinstance(selected, dict):
            backend_name = selected.get("worker_id", "hermes_local")
        else:
            backend_name = "hermes_local"

    # 5. Filter briefing for this worker's privacy class
    privacy_class = _backend_name_to_privacy_class(backend_name)
    filtered_briefing = filter_briefing(briefing, privacy_class)

    # 6. Compose prompt from briefing sections
    prompt = compose_prompt_from_briefing(filtered_briefing, user_message)

    # 7. Execute via existing AgenticBackend
    backend_router = get_backend_router()
    backend = backend_router.select(backend_name)

    if backend is None:
        # Fallback to hermes_local
        backend = backend_router.select("hermes_local")

    if backend is None:
        return {
            "text": "",
            "error": "No worker is available right now.",
            "intent": intent,
            "worker": None,
            "evaluation": {"verdict": "fail"},
        }

    # 8. Run the turn
    try:
        result = backend.run_turn(
            prompt,
            session_id,
            model=model,
            model_provider=model_provider,
            cancel_event=cancel_event,
        )
        text = str((result or {}).get("text", ""))
        error = str((result or {}).get("error", ""))
    except Exception as e:
        text = ""
        error = str(e)

    # 9. Evaluate result
    if text:
        evaluation = evaluate_result(text, intent=intent)
        verdict = evaluation.verdict.value if hasattr(evaluation, "verdict") else "unknown"
        checks = [c.check_name for c in evaluation.checks] if hasattr(evaluation, "checks") else []
    else:
        verdict = "fail"
        checks = ["empty_response"]

    # 10. Compose final response
    worker_result = WorkerResult(
        worker_id=backend_name,
        content=text or error,
        confidence=confidence,
    )
    response = compose_response(
        worker_result=worker_result,
        si_identity=briefing.si_identity,
        intent=intent,
        verification={"verdict": verdict, "checks": checks},
        activity_summary=f"Routed to {backend_name} for {intent}",
    )

    duration_ms = int((time.time() - started_at) * 1000)

    return {
        "text": response.content,
        "error": error if error else None,
        "intent": intent,
        "worker": backend_name,
        "evaluation": {"verdict": verdict, "checks": checks},
        "activity_summary": response.activity_summary,
        "warnings": response.warnings,
        "duration_ms": duration_ms,
    }
