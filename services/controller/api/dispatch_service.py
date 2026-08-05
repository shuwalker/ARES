"""ARES Master-Worker Dispatch Service.

Bridges core.si.orchestrator, BackendRegistry worker adapters, evaluator.py,
and turn_journal.py into a single unified execution pipeline.
"""

from __future__ import annotations

import logging
import time
from typing import Any, Dict, Optional

from core.si.orchestrator import orchestrate_request, complete_step, load_plan, save_plan
from core.si.evaluator import evaluate_result
from core.si.types import WorkerResult, PlanStatus
from integrations.workers.cli_backends import BackendRegistry
from core.events.turn_journal import append_turn_journal_event
from api.budget_service import check_budget, record_cost
from api.cost_calculator import estimate_cost, get_model_provider

logger = logging.getLogger(__name__)


class DispatchService:
    """Unified Master-Worker Dispatch Orchestrator."""

    def __init__(self, backend_registry: type[BackendRegistry] = BackendRegistry):
        self.registry = backend_registry

    def dispatch_turn(
        self,
        user_message: str,
        conversation_id: str,
        local_only_mode: bool = False,
        si_name: str = "Leo",
        owner_name: str = "User",
        model: str | None = None,
        model_provider: str | None = None,
    ) -> Dict[str, Any]:
        """Execute a full dispatch turn for a user message.

        1. Orchestrate plan & briefing via core.si.orchestrator
        2. Check for human approval gate requirement
        3. Dispatch to assigned worker backend adapter
        4. Pass output through evaluator.py (6 verification checks)
        5. Complete step & record turn to turn_journal.py
        """
        # 1. Orchestrate request
        orch_res = orchestrate_request(
            user_message=user_message,
            conversation_id=conversation_id,
            local_only_mode=local_only_mode,
            si_name=si_name,
            owner_name=owner_name,
        )

        status = orch_res.get("status")

        # 2. Check approval requirement
        if status == "awaiting_approval":
            logger.info("Plan %s awaiting user approval for intent %s", orch_res.get("plan_id"), orch_res.get("intent"))
            append_turn_journal_event(
                session_id=conversation_id,
                event={"event": "awaiting_approval", "plan_id": orch_res.get("plan_id"), "reason": orch_res.get("approval_reason")},
            )
            return orch_res

        if status == "completed":
            return orch_res

        if status != "ready":
            return orch_res

        plan_id = orch_res["plan_id"]
        step_info = orch_res["step"]
        assigned_worker = step_info.get("assigned_worker") or "jaeger_local"

        # 2.5 NEW: Check budget before execution
        cost_estimate = 0.01  # Rough estimate, refine based on model
        budget_check = check_budget(assigned_worker, cost_estimate)

        if not budget_check["can_execute"]:
            logger.warning("Budget limit for %s: %s", assigned_worker, budget_check["reason"])

            # Pause the plan
            plan = load_plan(plan_id)
            plan.status = PlanStatus.PAUSED
            save_plan(plan)

            append_turn_journal_event(
                session_id=conversation_id,
                event={
                    "event": "budget_limit_exceeded",
                    "plan_id": plan_id,
                    "step_id": step_info["step_id"],
                    "reason": budget_check["reason"],
                    "daily_spent": budget_check["daily_spent"],
                    "daily_limit": budget_check["daily_limit"],
                },
            )

            return {
                "plan_id": plan_id,
                "status": "paused_budget_limit",
                "reason": budget_check["reason"],
                "budget_info": budget_check,
            }

        if budget_check["warning"]:
            logger.warning("Budget warning for %s: %s", assigned_worker, budget_check["warning"])

        # 3. Find and execute assigned worker backend
        available = self.registry.get_available()
        worker = available.get(assigned_worker)

        start_time = time.time()

        if worker is None:
            # Fallback to any available worker if assigned worker is unavailable
            logger.warning("Worker '%s' unavailable, attempting fallback", assigned_worker)
            if available:
                assigned_worker, worker = next(iter(available.items()))
            else:
                raw_output = f"[Fallback Response] Processed: '{user_message}' (No active worker backend found)"

        if worker is not None:
            try:
                if hasattr(worker, "run_turn"):
                    turn_res = worker.run_turn(
                        user_message,
                        session_id=conversation_id,
                        model=model,
                        model_provider=model_provider,
                    )
                    if isinstance(turn_res, dict):
                        raw_output = turn_res.get("text") or turn_res.get("response") or str(turn_res)
                    else:
                        raw_output = str(turn_res)
                elif hasattr(worker, "generate_response"):
                    raw_output = worker.generate_response(user_message)
                else:
                    raw_output = f"[Worker Response] Executed via {assigned_worker}"
            except Exception as exc:
                logger.error("Worker %s execution failed: %s", assigned_worker, exc)
                raw_output = f"[Worker Error] Execution failed: {exc}"

        duration = round(time.time() - start_time, 3)

        # 4. Deterministic evaluation (6 checks)
        eval_result = evaluate_result(
            result=raw_output,
            intent=orch_res.get("intent", "conversation"),
        )

        passed = eval_result.verdict in ("pass", "needs_review")

        # 5. Complete step & record to journal
        complete_step(
            plan_id=plan_id,
            step_id=step_info["step_id"],
            result=raw_output,
            evaluation=eval_result.recommendation,
        )

        # 6. Record cost using LiteLLM pricing (industry standard)
        model_name = getattr(worker, "model_name", "unknown") if worker else "unknown"
        input_tokens = 0
        output_tokens = 0

        if isinstance(raw_output, dict):
            input_tokens = raw_output.get("input_tokens", 0)
            output_tokens = raw_output.get("output_tokens", 0)

        # Calculate cost using LiteLLM (supports 100+ models)
        if input_tokens > 0 or output_tokens > 0:
            cost_usd = estimate_cost(model_name, input_tokens, output_tokens)
            provider = get_model_provider(model_name)

            record_cost(
                worker_id=assigned_worker,
                session_id=conversation_id,
                plan_id=plan_id,
                step_id=step_info["step_id"],
                cost_usd=cost_usd,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                model=model_name,
                provider=provider,
            )

            logger.info(
                "Recorded cost: worker=%s, model=%s, input=%d, output=%d, cost=$%.6f",
                assigned_worker, model_name, input_tokens, output_tokens, cost_usd
            )

        append_turn_journal_event(
            session_id=conversation_id,
            event={
                "event": "step_completed",
                "plan_id": plan_id,
                "step_id": step_info["step_id"],
                "worker": assigned_worker,
                "passed_eval": passed,
                "eval_score": eval_result.overall_score,
                "duration_sec": duration,
            },
        )

        return {
            "plan_id": plan_id,
            "status": "step_completed",
            "assigned_worker": assigned_worker,
            "output": raw_output,
            "evaluation": {
                "passed": passed,
                "score": eval_result.overall_score,
                "recommendation": eval_result.recommendation,
                "verdict": eval_result.verdict.value if hasattr(eval_result.verdict, "value") else str(eval_result.verdict),
                "checks": [c.check_name for c in eval_result.checks],
            },
            "duration_sec": duration,
        }

    def approve_step(self, plan_id: str, step_id: str) -> Dict[str, Any]:
        """Approve an awaiting_approval step in a plan and execute it."""
        plan = load_plan(plan_id)
        if not plan:
            return {"error": f"Plan {plan_id} not found", "status": "not_found"}

        target_step = None
        for step in plan.steps:
            if step.step_id == step_id:
                target_step = step
                break

        if not target_step:
            return {"error": f"Step {step_id} not found in plan {plan_id}", "status": "not_found"}

        from core.si.types import StepStatus
        target_step.status = StepStatus.PENDING
        save_plan(plan)

        append_turn_journal_event(
            session_id=plan.conversation_id or "default",
            event={"event": "approval_granted", "plan_id": plan_id, "step_id": step_id},
        )

        return {"plan_id": plan_id, "step_id": step_id, "status": "approved"}

    def reject_step(self, plan_id: str, step_id: str, reason: str = "User rejected step") -> Dict[str, Any]:
        """Reject an awaiting_approval step in a plan."""
        plan = load_plan(plan_id)
        if not plan:
            return {"error": f"Plan {plan_id} not found", "status": "not_found"}

        target_step = None
        for step in plan.steps:
            if step.step_id == step_id:
                target_step = step
                break

        if not target_step:
            return {"error": f"Step {step_id} not found in plan {plan_id}", "status": "not_found"}

        from core.si.types import StepStatus, PlanStatus
        target_step.status = StepStatus.FAILED
        plan.status = PlanStatus.FAILED
        save_plan(plan)

        append_turn_journal_event(
            session_id=plan.conversation_id or "default",
            event={"event": "approval_rejected", "plan_id": plan_id, "step_id": step_id, "reason": reason},
        )

        return {"plan_id": plan_id, "step_id": step_id, "status": "rejected", "reason": reason}


# Singleton service helper
_default_dispatch_service: Optional[DispatchService] = None


def get_dispatch_service() -> DispatchService:
    global _default_dispatch_service
    if _default_dispatch_service is None:
        _default_dispatch_service = DispatchService()
    return _default_dispatch_service
