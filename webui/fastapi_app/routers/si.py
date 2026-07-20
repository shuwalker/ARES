"""
ARES SI — FastAPI router for Synthetic Intelligence endpoints.

These endpoints expose the SI subsystems: context compilation,
trust engine, worker registry, orchestration, and disclosure audit.
"""

from __future__ import annotations

from fastapi import APIRouter, Query

router = APIRouter(prefix="/api/si", tags=["si"])


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


# ── Migration ──────────────────────────────────────────────────────────

@router.post("/migrate")
def si_migrate():
    """Run the SI schema migration (add sensitivity columns to Journal)."""
    from api.journal.schema import get_db
    from api.si.migration import migrate_journal_sensitivity
    db = get_db()
    results = migrate_journal_sensitivity(db)
    return results