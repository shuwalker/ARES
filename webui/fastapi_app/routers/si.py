"""
ARES SI — FastAPI router for Synthetic Intelligence endpoints.

These endpoints expose the SI subsystems: context compilation,
trust engine, worker registry, orchestration, and disclosure audit.
"""

from __future__ import annotations

from fastapi import APIRouter, Query

router = APIRouter(prefix="/api/si", tags=["si"])


# ── Response Composer ──────────────────────────────────────────────────

@router.post("/compose")
def si_compose_response(
    content: str = Query(..., description="Worker result content"),
    intent: str = Query("conversation", description="Detected intent"),
    worker_id: str | None = Query(None, description="Source worker ID"),
    plan_id: str | None = Query(None, description="Plan ID"),
    step_id: str | None = Query(None, description="Step ID"),
):
    """Compose the final SI response from a worker result."""
    from api.si.response_composer import compose_response
    response = compose_response(
        worker_result=content,
        intent=intent,
        plan_id=plan_id,
        step_id=step_id,
    )
    return {
        "content": response.content,
        "source_worker": response.source_worker,
        "intent": response.intent,
        "confidence": response.confidence,
        "activity_summary": response.activity_summary,
        "warnings": response.warnings,
        "needs_approval": response.needs_approval,
    }


# ── Activity Audit ──────────────────────────────────────────────────────

@router.get("/activity")
def si_activity(limit: int = Query(50, ge=1, le=500)):
    """Get the SI activity log for user inspection."""
    from api.si.trust_engine import get_disclosure_log
    entries = get_disclosure_log(limit=limit)
    return {
        "disclosures": entries,
        "count": len(entries),
        "note": "Every data disclosure to workers is logged here for user inspection.",
    }


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


# ── Identity ────────────────────────────────────────────────────────────

@router.get("/identity")
def si_get_identity():
    """Get the current SI identity configuration."""
    from api.si.identity import load_identity
    config = load_identity()
    return {
        "name": config.name,
        "owner_name": config.owner_name,
        "mission": config.mission,
        "principles": config.principles,
        "loyalty": config.loyalty,
        "communication_style": config.communication_style,
        "uncertainty_behavior": config.uncertainty_behavior,
        "privacy_commitment": config.privacy_commitment,
        "disagreement_conditions": config.disagreement_conditions,
        "refusal_conditions": config.refusal_conditions,
        "approval_conditions": config.approval_conditions,
    }


@router.patch("/identity")
def si_patch_identity(
    name: str | None = Query(None),
    owner_name: str | None = Query(None),
    mission: str | None = Query(None),
    communication_style: str | None = Query(None),
    uncertainty_behavior: str | None = Query(None),
    privacy_commitment: str | None = Query(None),
):
    """Update the SI identity configuration."""
    from api.si.identity import patch_identity
    updates = {k: v for k, v in {
        "name": name, "owner_name": owner_name, "mission": mission,
        "communication_style": communication_style,
        "uncertainty_behavior": uncertainty_behavior,
        "privacy_commitment": privacy_commitment,
    }.items() if v is not None}
    config = patch_identity(updates)
    return {"status": "updated", "name": config.name}


# ── Memory Controls ────────────────────────────────────────────────────

@router.get("/memory")
def si_list_memories(
    q: str = Query("", description="Search query"),
    limit: int = Query(20, ge=1, le=100),
    max_sensitivity: str = Query("personal", description="Max sensitivity level"),
):
    """Search and list memories."""
    from api.si.memory import retrieve_memories
    from api.si.types import DataClassification, PERSONAL as SI_PERSONAL
    sensitivity = DataClassification(max_sensitivity) if max_sensitivity in DataClassification._value2member_map_ else SI_PERSONAL
    memories = retrieve_memories(q or "*", limit=limit, max_sensitivity=sensitivity)
    return {
        "memories": [
            {"memory_id": m.memory_id, "content": m.content, "source": m.source,
             "sensitivity": m.sensitivity.value, "importance": m.importance}
            for m in memories
        ],
        "count": len(memories),
    }


@router.delete("/memory/{memory_id}")
def si_delete_memory(memory_id: str):
    """Soft-delete a memory (marks deleted, preserves audit trail)."""
    from api.si.memory import delete_memory
    ok = delete_memory(memory_id)
    return {"deleted": ok, "memory_id": memory_id}


@router.post("/memory/{memory_id}/correct")
def si_correct_memory(
    memory_id: str,
    correction: str = Query(..., description="Corrected content"),
    reason: str = Query("user_correction", description="Reason for correction"),
):
    """Record a user correction to a memory."""
    from api.si.memory import correct_memory
    correction_id = correct_memory(memory_id, correction, reason)
    return {"memory_id": memory_id, "correction_id": correction_id, "reason": reason}


@router.get("/memory/{memory_id}/history")
def si_memory_history(memory_id: str):
    """Get the correction history for a memory."""
    from api.si.memory import get_memory_history
    history = get_memory_history(memory_id)
    return {"memory_id": memory_id, "corrections": history}


# ── User Model ──────────────────────────────────────────────────────────

@router.get("/user-model")
def si_get_user_model(category: str | None = Query(None)):
    """Get the user model, optionally filtered by category."""
    from api.si.user_model import load_user_model
    model = load_user_model()
    if category:
        facts = getattr(model, category, [])
        return {"category": category, "facts": [
            {"fact_id": f.fact_id, "fact": f.fact, "source": f.source,
             "confidence": f.confidence, "category": f.category}
            for f in facts
        ]}
    return {
        "preferences": [{"fact_id": f.fact_id, "fact": f.fact, "source": f.source, "confidence": f.confidence} for f in model.preferences],
        "projects": [{"fact_id": f.fact_id, "fact": f.fact, "source": f.source, "confidence": f.confidence} for f in model.projects],
        "people": [{"fact_id": f.fact_id, "fact": f.fact, "source": f.source, "confidence": f.confidence} for f in model.people],
        "devices": [{"fact_id": f.fact_id, "fact": f.fact, "source": f.source, "confidence": f.confidence} for f in model.devices],
        "routines": [{"fact_id": f.fact_id, "fact": f.fact, "source": f.source, "confidence": f.confidence} for f in model.routines],
        "privacy_preferences": [{"fact_id": f.fact_id, "fact": f.fact, "source": f.source, "confidence": f.confidence} for f in model.privacy_preferences],
        "restrictions": [{"fact_id": f.fact_id, "fact": f.fact, "source": f.source, "confidence": f.confidence} for f in model.restrictions],
    }


@router.post("/user-model")
def si_add_user_fact(
    category: str = Query(..., description="Category: preferences, projects, people, devices, routines, privacy_preferences, restrictions"),
    fact: str = Query(..., description="The fact to add"),
    source: str = Query("observed_behavior", description="Source: explicit_user_instruction, observed_behavior, inferred"),
    confidence: float = Query(0.5, ge=0.0, le=1.0),
):
    """Add a fact to the user model."""
    from api.si.user_model import add_fact
    new_fact = add_fact(category, fact, source, confidence)
    return {"fact_id": new_fact.fact_id, "fact": new_fact.fact, "source": new_fact.source, "confidence": new_fact.confidence}


@router.delete("/user-model/{fact_id}")
def si_delete_user_fact(fact_id: str):
    """Delete a fact from the user model."""
    from api.si.user_model import delete_fact
    ok = delete_fact(fact_id)
    return {"deleted": ok, "fact_id": fact_id}


@router.post("/user-model/{fact_id}/confirm")
def si_confirm_user_fact(fact_id: str):
    """Confirm a fact, bumping its confidence to 1.0."""
    from api.si.user_model import confirm_fact
    updated = confirm_fact(fact_id)
    if updated:
        return {"fact_id": updated.fact_id, "confidence": updated.confidence, "source": updated.source}
    return {"error": f"Fact {fact_id} not found"}


# ── Privacy Controls ────────────────────────────────────────────────────

@router.get("/privacy/rules")
def si_get_privacy_rules():
    """Get all privacy rules."""
    from api.si.trust_engine import get_privacy_rules
    return {"rules": get_privacy_rules()}


@router.post("/privacy/rules")
def si_add_privacy_rule(
    rule_type: str = Query(..., description="Rule type: block_worker, require_approval, local_only"),
    target: str = Query(..., description="Target worker_id or data_class"),
    reason: str = Query("", description="Reason for the rule"),
):
    """Add a privacy rule."""
    from api.si.trust_engine import add_privacy_rule
    rule = add_privacy_rule(rule_type, target, reason)
    return {"rule": rule}


@router.delete("/privacy/rules/{rule_id}")
def si_delete_privacy_rule(rule_id: str):
    """Delete a privacy rule."""
    from api.si.trust_engine import delete_privacy_rule
    ok = delete_privacy_rule(rule_id)
    return {"deleted": ok, "rule_id": rule_id}


@router.post("/privacy/local-only")
def si_toggle_local_only(enabled: bool = Query(..., description="Enable or disable local-only mode")):
    """Toggle local-only mode. When enabled, no data leaves the device."""
    from api.si.trust_engine import set_local_only_mode
    set_local_only_mode(enabled)
    return {"local_only": enabled, "note": "When enabled, all data above PUBLIC stays local."}


# ── Worker Controls ─────────────────────────────────────────────────────

@router.patch("/workers/{worker_id}/restrict")
def si_restrict_worker(worker_id: str):
    """Restrict a worker from receiving any data above PUBLIC."""
    from api.si.trust_engine import restrict_worker
    ok = restrict_worker(worker_id)
    return {"restricted": ok, "worker_id": worker_id}


@router.post("/workers/{worker_id}/approve")
def si_approve_worker(worker_id: str):
    """Approve a worker for sensitive data access."""
    from api.si.trust_engine import approve_worker
    ok = approve_worker(worker_id)
    return {"approved": ok, "worker_id": worker_id}


# ── Migration ──────────────────────────────────────────────────────────

@router.post("/migrate")
def si_migrate():
    """Run the SI schema migration (add sensitivity columns to Journal)."""
    from api.journal.schema import get_db
    from api.si.migration import migrate_journal_sensitivity
    db = get_db()
    results = migrate_journal_sensitivity(db)
    return results