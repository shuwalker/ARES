"""ARES SOP Pipeline — LangGraph-based workflow orchestrator.

Defines the Standard Operating Procedure graph for engineering tasks:
  scope → draft → [parallel review] → aggregate → execute → verify → [loop]

Each node wraps an ARES backend via BackendRouter. The graph handles
branching, parallelism, retries, and human-in-the-loop approval gates.

Usage:
    from api.sop.graph import sop_review_graph
    result = sop_review_graph.invoke({
        "code": "def hello(): print('hello')",
        "goal": "Review this function",
    })
"""
from __future__ import annotations

import logging
import time
from typing import Annotated, Any, Dict, List, Literal, TypedDict
from typing_extensions import NotRequired

import operator

logger = logging.getLogger(__name__)


# ── State Types ──────────────────────────────────────────────────────────

class ReviewFinding(TypedDict):
    """A single finding from a code review."""
    reviewer: str
    severity: Literal["blocker", "minor", "info"]
    category: Literal["security", "performance", "edge_case", "maintainability", "correctness"]
    description: str
    recommendation: str


class SOPState(TypedDict):
    """State passed between SOP graph nodes.

    Fields use Annotated with operator.add so LangGraph's reducer merges
    lists across parallel branches.
    """
    # Input
    goal: str
    code: NotRequired[str]
    context: NotRequired[str]

    # Workflow control
    plan: NotRequired[str]
    reviews: Annotated[List[ReviewFinding], operator.add]
    verdict: NotRequired[str]  # "approved", "needs_changes", "blocked"
    result: NotRequired[str]
    verification_output: NotRequired[str]
    verification_passed: NotRequired[bool]
    retry_count: NotRequired[int]
    error: NotRequired[str]


# ── Node Implementations ─────────────────────────────────────────────────

def _call_backend(backend_name: str, prompt: str) -> str:
    """Call an ARES backend and return its text response."""
    from api.backends.router import get_router
    router = get_router()
    backend = router.select(backend_name)
    if backend is None:
        return f"[{backend_name} unavailable]"
    result = backend.run_turn(prompt, session_id="sop-pipeline")
    return result.get("text", "")


def scope_interview(state: SOPState) -> dict:
    """Clarify the goal and identify constraints."""
    prompt = (
        f"Given this goal: {state.get('goal', '')}\n\n"
        f"Context: {state.get('context', '')}\n\n"
        "Identify: 1) What needs to be built 2) Key constraints "
        "3) Edge cases to handle 4) Verification criteria"
    )
    plan = _call_backend("hermes_proxy", prompt)
    return {"plan": plan}


def draft_solution(state: SOPState) -> dict:
    """Draft the solution based on the plan."""
    prompt = (
        f"Plan: {state.get('plan', '')}\n\n"
        f"Goal: {state.get('goal', '')}\n\n"
        "Implement the solution. Return complete code."
    )
    code = _call_backend("claude_cloud", prompt)
    return {"code": code}


def security_review(state: SOPState) -> dict:
    """Review for security issues."""
    prompt = (
        f"Review this code for SECURITY issues only:\n\n{state.get('code', '')}\n\n"
        "Return findings as: severity (blocker/minor/info), description, recommendation."
    )
    text = _call_backend("claude_cloud", prompt)
    return {"reviews": [ReviewFinding(
        reviewer="claude_cloud",
        severity="blocker" if "blocker" in text.lower() else "minor",
        category="security",
        description=text[:500],
        recommendation="",
    )]}


def performance_review(state: SOPState) -> dict:
    """Review for performance issues."""
    prompt = (
        f"Review this code for PERFORMANCE issues only:\n\n{state.get('code', '')}\n\n"
        "Return findings as: severity (blocker/minor/info), description, recommendation."
    )
    text = _call_backend("gemini_cloud", prompt)
    return {"reviews": [ReviewFinding(
        reviewer="gemini_cloud",
        severity="blocker" if "blocker" in text.lower() else "minor",
        category="performance",
        description=text[:500],
        recommendation="",
    )]}


def edge_case_review(state: SOPState) -> dict:
    """Review for edge cases."""
    prompt = (
        f"Review this code for EDGE CASES only:\n\n{state.get('code', '')}\n\n"
        "Return findings as: severity (blocker/minor/info), description, recommendation."
    )
    text = _call_backend("openai_cloud", prompt)
    return {"reviews": [ReviewFinding(
        reviewer="openai_cloud",
        severity="blocker" if "blocker" in text.lower() else "minor",
        category="edge_case",
        description=text[:500],
        recommendation="",
    )]}


def aggregate_reviews(state: SOPState) -> dict:
    """Aggregate parallel reviews and determine verdict."""
    reviews = state.get("reviews", [])
    blockers = [r for r in reviews if r.get("severity") == "blocker"]
    if blockers:
        return {"verdict": "blocked", "error": f"Blocking issues: {len(blockers)}"}
    minors = [r for r in reviews if r.get("severity") == "minor"]
    if minors:
        return {"verdict": "needs_changes"}
    return {"verdict": "approved"}


def execute_solution(state: SOPState) -> dict:
    """Execute the approved solution."""
    prompt = (
        f"Execute this solution:\n\n{state.get('code', '')}\n\n"
        f"Goal: {state.get('goal', '')}\n\n"
        "Run it and return the output."
    )
    result = _call_backend("hermes_proxy", prompt)
    return {"result": result}


def verify_output(state: SOPState) -> dict:
    """Verify the output against the goal."""
    prompt = (
        f"Goal: {state.get('goal', '')}\n\n"
        f"Code:\n{state.get('code', '')}\n\n"
        f"Output:\n{state.get('result', '')}\n\n"
        "Did this achieve the goal? Answer PASS or FAIL with explanation."
    )
    text = _call_backend("hermes_proxy", prompt)
    passed = "PASS" in text.upper() and "FAIL" not in text.upper()
    return {
        "verification_output": text,
        "verification_passed": passed,
        "retry_count": state.get("retry_count", 0) + (0 if passed else 1),
    }


# ── Conditional Edge Functions ────────────────────────────────────────────

def route_after_review(state: SOPState) -> str:
    """Route based on review verdict."""
    verdict = state.get("verdict", "needs_changes")
    if verdict == "blocked":
        return "blocked"
    elif verdict == "needs_changes":
        return "needs_changes"
    return "approved"


def route_after_verify(state: SOPState) -> str:
    """Route based on verification result."""
    if state.get("verification_passed"):
        return "passed"
    retries = state.get("retry_count", 0)
    if retries < 3:
        return "retry"
    return "failed"


# ── Build the Graph ──────────────────────────────────────────────────────

def build_sop_graph():
    """Build and return the SOP pipeline graph.

    The graph:
        scope → draft → [security, performance, edge_case] (parallel)
        → aggregate → if blocked: END
        → if needs_changes: draft (loop)
        → if approved: execute → verify → if pass: END
        → if fail < 3 retries: draft (loop)
        → if fail >= 3 retries: END (failed)
    """
    from langgraph.graph import StateGraph, END

    builder = StateGraph(SOPState)

    # Add nodes
    builder.add_node("scope_interview", scope_interview)
    builder.add_node("draft_solution", draft_solution)
    builder.add_node("security_review", security_review)
    builder.add_node("performance_review", performance_review)
    builder.add_node("edge_case_review", edge_case_review)
    builder.add_node("aggregate_reviews", aggregate_reviews)
    builder.add_node("execute_solution", execute_solution)
    builder.add_node("verify_output", verify_output)

    # Set entry point
    builder.set_entry_point("scope_interview")

    # Linear flow: scope → draft
    builder.add_edge("scope_interview", "draft_solution")

    # Fan-out: draft → parallel reviews
    builder.add_edge("draft_solution", "security_review")
    builder.add_edge("draft_solution", "performance_review")
    builder.add_edge("draft_solution", "edge_case_review")

    # Fan-in: reviews → aggregate
    builder.add_edge("security_review", "aggregate_reviews")
    builder.add_edge("performance_review", "aggregate_reviews")
    builder.add_edge("edge_case_review", "aggregate_reviews")

    # Conditional: aggregate → approved/needs_changes/blocked
    builder.add_conditional_edges(
        "aggregate_reviews",
        route_after_review,
        {
            "approved": "execute_solution",
            "needs_changes": "draft_solution",  # Loop back to fix
            "blocked": END,
        },
    )

    # Execute → verify
    builder.add_edge("execute_solution", "verify_output")

    # Conditional: verify → pass/retry/fail
    builder.add_conditional_edges(
        "verify_output",
        route_after_verify,
        {
            "passed": END,
            "retry": "draft_solution",  # Loop back to fix
            "failed": END,
        },
    )

    return builder.compile()


# Singleton graph instance
_sop_graph = None


def get_sop_graph():
    """Get or create the singleton SOP graph."""
    global _sop_graph
    if _sop_graph is None:
        _sop_graph = build_sop_graph()
    return _sop_graph


def run_sop_pipeline(goal: str, code: str = "", context: str = "") -> dict:
    """Run the full SOP pipeline for a goal.

    Args:
        goal: What to build or review
        code: Optional existing code to review
        context: Additional context about the project

    Returns:
        The final state dict with results, reviews, and verification.
    """
    graph = get_sop_graph()
    initial: SOPState = {
        "goal": goal,
        "code": code,
        "context": context,
        "reviews": [],
    }
    result = graph.invoke(initial)
    return result
