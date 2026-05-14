"""Task executor for ARES.

Executes plan stages via the tool registry. Each stage names a tool;
the registry resolves it to an invoker and runs it. Pre-flight validates
that every tool in the plan is known and installed before any stage runs.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Awaitable, Callable

from ..audit import log
from ..reasoning import Plan, PlanStage
from ..tools import registry
from .queue import Task, update_task


# ---------------------------------------------------------------------------
# Checkpoint / approval protocol
# ---------------------------------------------------------------------------

ApprovalCallback = Callable[[str], Awaitable[bool]]


async def _default_approval(message: str) -> bool:
    """Default: print message and wait for input (blocks — for interactive use)."""
    print(f"\n[CHECKPOINT] {message}")
    print("Continue? [y/n]: ", end="", flush=True)
    loop = asyncio.get_event_loop()
    answer = await loop.run_in_executor(None, input)
    return answer.strip().lower() in ("y", "yes", "")


# ---------------------------------------------------------------------------
# Main executor
# ---------------------------------------------------------------------------

class PlanExecutor:
    def __init__(
        self,
        approval_cb: ApprovalCallback | None = None,
        paused_event: asyncio.Event | None = None,
    ) -> None:
        self.approval_cb = approval_cb or _default_approval
        self.paused_event = paused_event or asyncio.Event()
        self.paused_event.set()  # Not paused by default

    async def execute(self, task: Task, plan: Plan) -> str:
        """Execute all stages of a plan. Returns final result."""
        task.status = "executing"
        task.started_at = datetime.now(timezone.utc).isoformat()
        task.plan_json = plan.raw_json
        update_task(task)

        await log(task_id=task.id, action="execute_start", stages=len(plan.stages))

        # Pre-flight: every stage's tool must be resolvable + installed before
        # we start running anything. Fails fast with all gaps in one message.
        try:
            registry.validate_plan(plan)
        except (registry.ToolNotFoundError, registry.ToolNotInstalledError) as exc:
            await log(
                task_id=task.id,
                action="preflight_failed",
                error=str(exc)[:500],
            )
            task.error = str(exc)[:500]
            task.status = "failed"
            update_task(task)
            return f"Pre-flight failed: {exc}"

        results = []

        for stage in plan.stages:
            # Wait if paused (user took over)
            await self.paused_event.wait()

            task.current_stage = stage.id
            update_task(task)

            await log(
                task_id=task.id,
                stage=stage.name,
                action="stage_start",
                tool=stage.tool,
            )

            # Approval gate — requires_approval on the stage is the single source
            # of truth. No duplicate checkpoints list.
            if stage.requires_approval:
                task.status = "paused"
                update_task(task)

                approved = await self.approval_cb(
                    f"Stage {stage.id}: {stage.name}\n"
                    f"  Tool: {stage.tool}\n"
                    f"  Action: {stage.action}\n"
                    f"  Output: {stage.output_file} ({stage.output_format})"
                )
                if not approved:
                    task.status = "paused"
                    update_task(task)
                    return f"Paused at stage {stage.id} — user declined."

                task.status = "executing"
                update_task(task)

            # Execute
            try:
                result = await self._run_stage(stage, task)
                results.append(f"Stage {stage.id} ({stage.name}): {str(result)[:200]}")
                await log(
                    task_id=task.id,
                    stage=stage.name,
                    action="stage_done",
                )
            except Exception as exc:
                await log(
                    task_id=task.id,
                    stage=stage.name,
                    action="stage_failed",
                    error=str(exc)[:200],
                )
                task.error = str(exc)[:500]
                task.status = "failed"
                update_task(task)
                return f"Failed at stage {stage.id}: {exc}"

        task.status = "done"
        task.completed_at = datetime.now(timezone.utc).isoformat()
        task.result = "\n".join(results)
        update_task(task)

        await log(task_id=task.id, action="execute_done", stages_completed=len(plan.stages))
        return task.result

    async def _run_stage(self, stage: PlanStage, task: Task) -> str:
        """Dispatch a stage to its registered tool invoker."""
        return await registry.invoke(stage, task)

    def pause(self) -> None:
        """Pause execution (user is taking over)."""
        self.paused_event.clear()

    def resume(self) -> None:
        """Resume execution."""
        self.paused_event.set()
