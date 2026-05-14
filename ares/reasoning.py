"""Reasoning system for ARES — goal decomposition with the Contractor Test.

When ARES calls an LLM to plan work, it uses the Contractor Test system prompt
to ensure every output is a real file a human could open and continue from.
"""

from __future__ import annotations

import json
import re
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .llm import cloud, local
from .llm.router import route, LLMBackend
from .audit import log
from .thought_dag import ThoughtCheckpoint, get_dag, new_thought_id


# ---------------------------------------------------------------------------
# The Contractor Test system prompt
# ---------------------------------------------------------------------------

CONTRACTOR_TEST_SYSTEM = """You are the planning core of ARES — Autonomous Reasoning & Execution System.

When given a goal, produce a concrete step-by-step execution plan.

For each step specify:
1. The exact tool a professional human would use (name the real application)
2. What file or output it produces
3. The format of that output (so a human could open and edit it)
4. Whether this step requires human approval before proceeding
5. What ARES should do if this step fails

Rules:
- Do not suggest custom code where a real application already exists
- Do not invent file formats — use standard, widely-used formats only
- Every output must pass the Contractor Test: "Could a skilled freelance human
  pick up what ARES produced and continue the work — without special tools or instructions?"
- If you don't know the right tool for a stage, say so and flag for research

Output ONLY valid JSON in this exact structure:
{
  "goal": "<the goal>",
  "stages": [
    {
      "id": 1,
      "name": "<stage name>",
      "tool": "<exact tool name>",
      "action": "<what ARES does>",
      "output_file": "<filename>",
      "output_format": "<format description>",
      "requires_approval": true|false,
      "on_failure": "<what to do if this fails>",
      "new_install_required": false,
      "install_reason": ""
    }
  ],
  "new_installs": [
    {
      "tool": "<tool name>",
      "reason": "<one-line reason it's the right choice>",
      "install_method": "brew|npm|pip|manual",
      "install_command": "<command>"
    }
  ],
  "estimated_api_cost": "<e.g. ~$0.05 or 'none'>"
}

Note: approval gates are set per-stage via "requires_approval": true. There
is no separate checkpoints list — each stage that needs human review must
have requires_approval set to true.."""


# ---------------------------------------------------------------------------
# Plan data models (BaseModel — Pydantic v2)
# ---------------------------------------------------------------------------

class PlanStage(BaseModel):
    model_config = ConfigDict(validate_assignment=False)

    id: int = Field(description="Sequential stage identifier (1-indexed)")
    name: str = Field(description="Human-readable stage name")
    tool: str = Field(description="Real-world tool/application used for this stage")
    action: str = Field(description="What ARES does in this stage (free-form description or 'run:<cmd>')")
    output_file: str = Field(description="Filename produced by this stage")
    output_format: str = Field(description="Format of the produced file (e.g. Markdown, JSON)")
    requires_approval: bool = Field(default=False, description="Whether this stage gates on human approval")
    on_failure: str = Field(default="flag to user", description="What ARES should do if this stage fails")
    new_install_required: bool = Field(default=False, description="True if this stage needs a tool not yet installed")
    install_reason: str = Field(default="", description="One-line reason an install is needed")


class NewInstall(BaseModel):
    model_config = ConfigDict(validate_assignment=False)

    tool: str = Field(description="Tool to install")
    reason: str = Field(description="One-line reason it's the right choice")
    install_method: str = Field(default="brew", description="brew | npm | pip | manual")
    install_command: str = Field(default="", description="Concrete install command, if applicable")


class Plan(BaseModel):
    model_config = ConfigDict(validate_assignment=False)

    goal: str = Field(description="Goal that this plan addresses")
    stages: list[PlanStage] = Field(default_factory=list, description="Ordered execution stages")
    new_installs: list[NewInstall] = Field(default_factory=list, description="Tools that must be installed first")
    estimated_api_cost: str = Field(default="unknown", description="Best-effort API cost estimate")
    raw_json: dict[str, Any] = Field(default_factory=dict, description="Raw LLM JSON response (preserved unmodified)")


# ---------------------------------------------------------------------------
# LLM response schema (lenient — defaults everywhere, extras ignored)
# ---------------------------------------------------------------------------

class _LLMStage(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: int = 0
    name: str = ""
    tool: str = ""
    action: str = ""
    output_file: str = ""
    output_format: str = ""
    requires_approval: bool = False
    on_failure: str = "flag to user"
    new_install_required: bool = False
    install_reason: str = ""


class _LLMInstall(BaseModel):
    model_config = ConfigDict(extra="ignore")
    tool: str = ""
    reason: str = ""
    install_method: str = "brew"
    install_command: str = ""


class LLMPlanResponse(BaseModel):
    """Schema for the JSON the LLM is asked to emit in CONTRACTOR_TEST_SYSTEM."""

    model_config = ConfigDict(extra="ignore")
    goal: str = ""
    stages: list[_LLMStage] = Field(default_factory=list)
    new_installs: list[_LLMInstall] = Field(default_factory=list)
    estimated_api_cost: str = "unknown"


# ---------------------------------------------------------------------------
# Reasoning call
# ---------------------------------------------------------------------------

async def reason(
    goal: str,
    *,
    task_id: str | None = None,
    context: str = "",
    backend: LLMBackend | None = None,
    sensitive: bool = False,
    requires_vision: bool = False,
    bulk: bool = False,
    resume: bool = True,
) -> Plan:
    """Call LLM to decompose a goal into a concrete execution plan.

    Backend routing: if ``backend`` is explicitly provided, it is used directly.
    Otherwise the router decides based on task characteristics (sensitivity,
    vision, bulk). Planning tasks always default to CLOUD for quality.

    Every major step writes a ``ThoughtCheckpoint`` to the SQLite-backed
    ``ThoughtDAG`` (``~/.ares/thoughts.db``). When ``resume`` is true (the
    default) and ``task_id`` is provided, a previously-parsed plan for the
    same task is returned without re-calling the LLM — this is how the
    daemon recovers after a crash mid-reasoning.
    """
    dag = get_dag()
    parent_id: str | None = None

    # Resume short-circuit: if a previous run already produced a parsed plan
    # for this task, re-use it and record a 'resumed' checkpoint for the trail.
    if resume and task_id:
        cached = dag.find_completed_plan(task_id)
        if cached is not None:
            try:
                plan = Plan.model_validate(cached)
            except ValidationError:
                plan = None
            if plan is not None:
                resume_cp = ThoughtCheckpoint(
                    parent_id=None,
                    task_id=task_id,
                    stage="resumed",
                    inputs={"goal": goal, "context": context},
                    outputs={"stages": len(plan.stages)},
                )
                dag.record(resume_cp)
                await log(task_id=task_id, action="reason_resumed", stages=len(plan.stages))
                return plan

    # ── started ─────────────────────────────────────────────────────────
    started_cp = ThoughtCheckpoint(
        thought_id=new_thought_id(),
        parent_id=parent_id,
        task_id=task_id,
        stage="started",
        inputs={"goal": goal, "context": context},
    )
    dag.record(started_cp)
    parent_id = started_cp.thought_id

    if backend is None:
        backend = route(
            task_type="planning",
            sensitive=sensitive,
            requires_vision=requires_vision,
            bulk=bulk,
        )

    # ── routed ──────────────────────────────────────────────────────────
    routed_cp = ThoughtCheckpoint(
        thought_id=new_thought_id(),
        parent_id=parent_id,
        task_id=task_id,
        stage="routed",
        inputs={"sensitive": sensitive, "requires_vision": requires_vision, "bulk": bulk},
        outputs={"backend": backend.value},
    )
    dag.record(routed_cp)
    parent_id = routed_cp.thought_id

    user_content = f"Goal: {goal}"
    if context:
        user_content += f"\n\nAdditional context:\n{context}"

    await log(task_id=task_id, action="reason_start", goal=goal[:80], backend=backend.value)

    messages = [{"role": "user", "content": user_content}]

    # ── llm_request ─────────────────────────────────────────────────────
    request_cp = ThoughtCheckpoint(
        thought_id=new_thought_id(),
        parent_id=parent_id,
        task_id=task_id,
        stage="llm_request",
        status="running",
        inputs={"backend": backend.value, "system_chars": len(CONTRACTOR_TEST_SYSTEM), "user_chars": len(user_content)},
    )
    dag.record(request_cp)
    parent_id = request_cp.thought_id

    try:
        if backend == LLMBackend.LOCAL:
            raw_text = await local.complete(
                system=CONTRACTOR_TEST_SYSTEM,
                messages=messages,
                task_id=task_id,
            )
        else:
            raw_text = await cloud.complete(
                system=CONTRACTOR_TEST_SYSTEM,
                messages=messages,
                task_id=task_id,
            )
    except Exception as exc:
        failure_cp = ThoughtCheckpoint(
            thought_id=new_thought_id(),
            parent_id=parent_id,
            task_id=task_id,
            stage="llm_response",
            status="failed",
            error=str(exc)[:500],
        )
        dag.record(failure_cp)
        raise

    # ── llm_response ────────────────────────────────────────────────────
    response_cp = ThoughtCheckpoint(
        thought_id=new_thought_id(),
        parent_id=parent_id,
        task_id=task_id,
        stage="llm_response",
        inputs={"request_id": request_cp.thought_id},
        outputs={"raw_text_chars": len(raw_text), "raw_text_preview": raw_text[:500]},
    )
    dag.record(response_cp)
    parent_id = response_cp.thought_id

    # ── parsed ──────────────────────────────────────────────────────────
    plan = _parse_plan(goal, raw_text)
    parsed_cp = ThoughtCheckpoint(
        thought_id=new_thought_id(),
        parent_id=parent_id,
        task_id=task_id,
        stage="parsed",
        outputs={"plan": plan.model_dump(mode="json"), "stage_count": len(plan.stages)},
    )
    dag.record(parsed_cp)
    parent_id = parsed_cp.thought_id

    # ── done ────────────────────────────────────────────────────────────
    done_cp = ThoughtCheckpoint(
        thought_id=new_thought_id(),
        parent_id=parent_id,
        task_id=task_id,
        stage="done",
        outputs={"stage_count": len(plan.stages), "new_installs": len(plan.new_installs)},
    )
    dag.record(done_cp)

    await log(task_id=task_id, action="reason_done", stages=len(plan.stages))
    return plan


def _parse_plan(goal: str, raw_text: str) -> Plan:
    """Parse the LLM response into a Plan object via Pydantic validation."""
    json_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw_text, re.DOTALL)
    if json_match:
        json_str = json_match.group(1)
    else:
        brace_match = re.search(r"\{.*\}", raw_text, re.DOTALL)
        json_str = brace_match.group(0) if brace_match else "{}"

    try:
        data = json.loads(json_str)
        resp = LLMPlanResponse.model_validate(data)
    except (json.JSONDecodeError, ValidationError):
        return Plan(
            goal=goal,
            stages=[
                PlanStage(
                    id=1,
                    name="Manual review required",
                    tool="Human review",
                    action="LLM returned unparseable plan — review raw output",
                    output_file="plan_review.md",
                    output_format="Markdown",
                    requires_approval=True,
                    on_failure="Abort and ask user",
                )
            ],
            raw_json={"raw_text": raw_text[:500]},
        )

    return Plan(
        goal=resp.goal or goal,
        stages=[PlanStage(**s.model_dump()) for s in resp.stages],
        new_installs=[NewInstall(**ni.model_dump()) for ni in resp.new_installs],
        estimated_api_cost=resp.estimated_api_cost,
        raw_json=data,
    )


# ---------------------------------------------------------------------------
# Proposal formatter
# ---------------------------------------------------------------------------

def format_proposal(plan: Plan) -> str:
    """Format a plan as a human-readable proposal."""
    lines = [
        f"Goal: {plan.goal}",
        "",
        "Proposed toolchain:",
    ]

    max_stage_len = max((len(s.name) for s in plan.stages), default=10)
    max_tool_len = max((len(s.tool) for s in plan.stages), default=10)

    for s in plan.stages:
        approval_tag = " [CHECKPOINT]" if s.requires_approval else ""
        line = (
            f"  Stage {s.id}  →  {s.tool:<{max_tool_len}}  "
            f"→  {s.output_file}  ({s.output_format}){approval_tag}"
        )
        lines.append(line)

    if plan.new_installs:
        lines.append("")
        lines.append("New installs required:")
        for ni in plan.new_installs:
            lines.append(f"  {ni.tool} — {ni.reason}")
            if ni.install_command:
                lines.append(f"    Install: {ni.install_command}")

    lines.append("")
    lines.append(f"Estimated API cost: {plan.estimated_api_cost}")
    lines.append("")
    lines.append("Approve? [yes / modify / I'll handle stage X myself]")

    return "\n".join(lines)
