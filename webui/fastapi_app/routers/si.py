"""
ARES SI — FastAPI router for Synthetic Intelligence endpoints.

These endpoints expose the SI subsystems: context compilation,
trust engine, worker registry, orchestration, and disclosure audit.
"""

from __future__ import annotations

from fastapi import APIRouter, Query

router = APIRouter(prefix="/api/si", tags=["si"])


# ── Routing ─────────────────────────────────────────────────────────────

@router.get("/route")
def si_route_task(
    intent: str = Query(..., description="Task intent type"),
    sensitivity: str = Query("personal", description="Data sensitivity level"),
    local_only: bool = Query(False, description="Require local workers only"),
    prefer: str | None = Query(None, description="Preferred worker ID"),
    exclude: str | None = Query(None, description="Comma-separated worker IDs to exclude"),
):
    """Select the best worker for a task based on capability, privacy, effectiveness, and cost."""
    from api.si.router import route_task

    exclude_list = exclude.split(",") if exclude else None
    return route_task(
        intent=intent,
        data_sensitivity=sensitivity,
        require_local=local_only,
        prefer_worker=prefer,
        exclude_workers=exclude_list,
    )


# ── Context Compiler ──────────────────────────────────────────────────

@router.get("/context/compile")
def si_compile_context(
    q: str = Query(..., description="User message to compile context for"),
    worker: str | None = Query(None, description="Target worker ID"),
    budget: int = Query(4000, ge=500, le=32000, description="Token budget"),
    local_only: bool = Query(False, description="Force local-only mode"),
):
    """Compile a context briefing for a worker based on the user's message."""
    from api.si.context_compiler import compile_context

    briefing = compile_context(
        user_message=q,
        target_worker_id=worker,
        token_budget=budget,
        local_only_mode=local_only,
    )
    return {
        "intent": "classified",
        "items_included": len(briefing.recent_conversation) + len(briefing.relevant_memories),
        "items_excluded": len([m for m in briefing.context_manifest if m.action.value != "included"]),
        "total_tokens": briefing.total_tokens,
        "manifest": [
            {
                "item_id": m.item_id,
                "action": m.action.value,
                "reason": m.reason,
                "original_tokens": m.original_tokens,
                "final_tokens": m.final_tokens,
            }
            for m in briefing.context_manifest
        ],
    }


# ── Worker Registry ───────────────────────────────────────────────────

@router.get("/workers")
def si_list_workers():
    """List all registered workers and their capabilities."""
    from api.si.worker_registry import get_registry
    registry = get_registry()
    workers = registry.list_all()
    return {
        "workers": [
            {
                "worker_id": w.worker_id,
                "provider": w.provider,
                "display_name": w.display_name,
                "capabilities": [
                    {"id": c.capability_id, "description": c.description, "proficiency": c.proficiency}
                    for c in w.capabilities
                ],
                "privacy_class": w.privacy_class.value,
                "data_location": w.data_location,
                "context_limit": w.context_limit,
                "supports_streaming": w.supports_streaming,
                "supports_files": w.supports_files,
                "supports_images": w.supports_images,
            }
            for w in workers
        ],
    }


@router.get("/workers/{worker_id}")
def si_get_worker(worker_id: str):
    """Get details for a specific worker."""
    from api.si.worker_registry import get_registry
    worker = get_registry().get(worker_id)
    if not worker:
        return {"error": f"Worker {worker_id} not found"}
    return {
        "worker_id": worker.worker_id,
        "provider": worker.provider,
        "display_name": worker.display_name,
        "capabilities": [
            {"id": c.capability_id, "description": c.description, "proficiency": c.proficiency}
            for c in worker.capabilities
        ],
        "privacy_class": worker.privacy_class.value,
        "data_location": worker.data_location,
    }


@router.get("/workers/eligible/{capability}")
def si_find_eligible_workers(
    capability: str,
    sensitivity: str = Query("personal", description="Data sensitivity level"),
    local_only: bool = Query(False, description="Require local workers only"),
):
    """Find workers eligible for a task with the given data sensitivity."""
    from api.si.worker_registry import get_registry
    registry = get_registry()
    eligible = registry.find_eligible(
        capability=capability,
        data_sensitivity=sensitivity,
        require_local=local_only,
    )
    return {
        "capability": capability,
        "sensitivity": sensitivity,
        "eligible_workers": [
            {"worker_id": w.worker_id, "display_name": w.display_name, "privacy_class": w.privacy_class.value}
            for w in eligible
        ],
    }


# ── Trust Engine ───────────────────────────────────────────────────────

@router.get("/trust/classify")
def si_classify_data(
    content: str = Query(..., description="Content to classify"),
    source: str = Query("unknown", description="Data source"),
):
    """Classify data sensitivity level."""
    from api.si.trust_engine import classify_data
    classification = classify_data(content, {"source": source})
    return {
        "content_preview": content[:100] + "..." if len(content) > 100 else content,
        "classification": classification.value,
        "source": source,
    }


@router.get("/trust/disclosure-log")
def si_disclosure_log(limit: int = Query(100, ge=1, le=1000)):
    """Get recent disclosure log entries for user inspection."""
    from api.si.trust_engine import get_disclosure_log
    entries = get_disclosure_log(limit=limit)
    return {"entries": entries, "count": len(entries)}


@router.get("/trust/approval-required")
def si_check_approval(
    action: str = Query(..., description="Action to check"),
    sensitivity: str = Query("personal", description="Data sensitivity"),
):
    """Check if an action requires user approval."""
    from api.si.trust_engine import check_approval_required
    required = check_approval_required(action, sensitivity)
    return {"action": action, "sensitivity": sensitivity, "approval_required": required}


# ── Intent Classification ──────────────────────────────────────────────

@router.get("/context/classify-intent")
def si_classify_intent(message: str = Query(..., description="User message")):
    """Classify the intent of a user message."""
    from api.si.context_compiler import classify_intent
    intent, confidence = classify_intent(message)
    return {"intent": intent, "confidence": confidence, "message": message}


# ── Evaluation ──────────────────────────────────────────────────────────

@router.post("/evaluate")
def si_evaluate_result(
    result: str = Query(..., description="Worker result text to evaluate"),
    intent: str = Query("conversation", description="Task intent type"),
    min_score: float = Query(0.5, ge=0.0, le=1.0, description="Minimum acceptable score"),
):
    """Evaluate a worker result using deterministic verification checks."""
    from api.si.evaluator import evaluate_result
    evaluation = evaluate_result(result, intent=intent, min_score=min_score)
    return {
        "verdict": evaluation.verdict.value,
        "score": evaluation.overall_score,
        "recommendation": evaluation.recommendation,
        "issues": evaluation.issues,
        "checks": [
            {
                "name": c.check_name,
                "passed": c.passed,
                "message": c.message,
                "details": c.details,
            }
            for c in evaluation.checks
        ],
    }


# ── Orchestration ──────────────────────────────────────────────────────

@router.post("/orchestrate")
def si_orchestrate(
    message: str = Query(..., description="User message to orchestrate"),
    conversation_id: str | None = Query(None, description="Conversation ID for continuity"),
    local_only: bool = Query(False, description="Force local-only mode"),
    si_name: str = Query("Assistant", description="SI name for identity injection"),
    owner_name: str = Query("User", description="Owner name for identity injection"),
):
    """Main orchestration endpoint. Classifies intent, creates plan, compiles context, selects worker."""
    from api.si.orchestrator import orchestrate_request
    result = orchestrate_request(
        user_message=message,
        conversation_id=conversation_id,
        local_only_mode=local_only,
        si_name=si_name,
        owner_name=owner_name,
    )
    return result


@router.post("/orchestrate/{plan_id}/complete-step")
def si_complete_step(
    plan_id: str,
    step_id: str = Query(..., description="Step ID to complete"),
    result: str = Query(..., description="Step result"),
    evaluation: str | None = Query(None, description="Evaluation result: pass/fail"),
):
    """Mark a step as completed and advance the plan."""
    from api.si.orchestrator import complete_step
    return complete_step(plan_id, step_id, result, evaluation)


@router.get("/orchestrate/{plan_id}")
def si_get_plan(plan_id: str):
    """Get the current state of a plan."""
    from api.si.orchestrator import load_plan
    plan = load_plan(plan_id)
    if not plan:
        return {"error": f"Plan {plan_id} not found"}
    return {
        "plan_id": plan.plan_id,
        "goal": plan.goal,
        "status": plan.status.value,
        "steps": [
            {
                "step_id": s.step_id,
                "objective": s.objective,
                "assigned_worker": s.assigned_worker,
                "status": s.status.value,
                "retry_count": s.retry_count,
            }
            for s in plan.steps
        ],
        "created_at": plan.created_at,
        "updated_at": plan.updated_at,
    }


@router.post("/orchestrate/{plan_id}/cancel")
def si_cancel_plan(plan_id: str):
    """Cancel a running plan."""
    from api.si.orchestrator import cancel_plan
    return cancel_plan(plan_id)


@router.get("/orchestrate")
def si_list_plans(
    status: str | None = Query(None, description="Filter by plan status"),
    limit: int = Query(20, ge=1, le=100),
):
    """List plans, optionally filtered by status."""
    from api.si.orchestrator import list_plans
    return {"plans": list_plans(status=status, limit=limit)}


# ── Migration ──────────────────────────────────────────────────────────

@router.post("/migrate")
def si_migrate():
    """Run the SI schema migration (add sensitivity columns to Journal)."""
    from api.journal.schema import get_db
    from api.si.migration import migrate_journal_sensitivity
    db = get_db()
    results = migrate_journal_sensitivity(db)
    return results