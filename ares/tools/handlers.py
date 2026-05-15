"""Built-in stage invokers for the tool registry.

Each handler takes (PlanStage, Task) and returns a string result. They're
registered with `registry.register_invoker(...)` at import time, so importing
this module is what wires the registry up — there's no other entry point.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

from ares.runtime.audit import log
from ares.core.reasoning import PlanStage
from ..tasks.queue import Task
from . import registry


# ---------------------------------------------------------------------------
# llm — LLM-backed content generation
# ---------------------------------------------------------------------------

async def llm_handler(stage: PlanStage, task: Task) -> str:
    from ..llm import cloud
    from ..core.personality import load_personality

    personality = load_personality()
    system_prompt = (
        "You are ARES — Autonomous Reasoning & Execution System.\n\n"
        + personality.to_system_prompt()
    )
    text = await cloud.complete(
        system=system_prompt,
        messages=[{"role": "user", "content": f"Execute stage: {stage.action}"}],
        task_id=task.id,
    )
    if stage.output_file:
        output_dir = Path.home() / "Documents" / "ARES" / task.id
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / stage.output_file
        output_path.write_text(text)
        await log(
            task_id=task.id,
            stage=stage.name,
            action="file_write",
            path=str(output_path),
        )
    return text


# ---------------------------------------------------------------------------
# shell — local command execution
# ---------------------------------------------------------------------------

async def shell_handler(stage: PlanStage, task: Task) -> str:
    cmd = stage.action or ""
    # Tolerate the historical "run:" / "exec:" prefixes that planner output uses.
    for prefix in ("run:", "exec:"):
        if cmd.lower().startswith(prefix):
            cmd = cmd[len(prefix):].strip()
            break
    if not cmd:
        raise RuntimeError(f"Stage {stage.id} has no shell command in action.")

    await log(task_id=task.id, stage=stage.name, action="shell_exec", cmd=cmd[:80])

    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError(
            f"Stage {stage.id} failed (exit {proc.returncode}):\n{stderr.decode()}"
        )
    return stdout.decode()


# ---------------------------------------------------------------------------
# human — manual stage marker
# ---------------------------------------------------------------------------

async def human_handler(stage: PlanStage, task: Task) -> str:
    return f"Manual stage — awaiting human: {stage.action}"


# ---------------------------------------------------------------------------
# n8n — workflow automation bridge
# ---------------------------------------------------------------------------

async def n8n_handler(stage: PlanStage, task: Task) -> str:
    from . import n8n as n8n_mod

    name = (stage.output_file or stage.name or "").strip()
    if not name:
        raise RuntimeError(
            f"Stage {stage.id}: n8n stages must set output_file (workflow name)."
        )
    # stage.action carries either a workflow JSON spec or a known template name.
    action = (stage.action or "").strip()
    if action == "youtube_publish":
        workflow = n8n_mod.youtube_publish_workflow()
    elif action == "notification":
        workflow = n8n_mod.notification_workflow()
    else:
        raise RuntimeError(
            f"Stage {stage.id}: unknown n8n workflow action {action!r}. "
            "Use 'youtube_publish' or 'notification'."
        )
    result = await n8n_mod.ensure_n8n_workflow(name, workflow, task_id=task.id)
    return f"n8n workflow ensured: {result.get('name')} (id={result.get('id')})"


# ---------------------------------------------------------------------------
# Registration (runs at import time)
# ---------------------------------------------------------------------------

registry.register_invoker("llm", llm_handler)
registry.register_invoker("shell", shell_handler)
registry.register_invoker("human", human_handler)
registry.register_invoker("n8n", n8n_handler)
