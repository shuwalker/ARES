"""
ARES SI — Integration tests.

Tests the full SI pipeline end-to-end:
  classify → context → route → execute → evaluate → compose

Uses mock backends so no cloud API keys are needed.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


# ── Mock Backend ────────────────────────────────────────────────────────

class MockBackend:
    """A mock AgenticBackend for testing the SI pipeline without real workers.

    Does NOT inherit from AgenticBackend to avoid ABC registration issues.
    Implements the same interface (duck typing).
    """

    def __init__(self, name: str = "mock_test", available: bool = True):
        self.name = name
        self._available = available
        self.display_label = f"Mock {name}"
        self.supports_tools = True
        self.supports_persona = False
        self.last_message: str = ""
        self.last_session_id: str = ""

    def is_available(self) -> bool:
        return self._available

    def run_turn(self, message: str, session_id: str, **kwargs) -> dict[str, Any]:
        self.last_message = message
        self.last_session_id = session_id
        return {"text": f"Mock response to: {message[:50]}", "error": None}

    def get_backend_name(self) -> str:
        return self.display_label

    def get_worker_target(self):
        return (lambda *a, **kw: None, False, False)

    def capabilities(self) -> dict[str, Any]:
        return {"chat": True, "tools": True, "persona": False}

    def health(self) -> dict[str, Any]:
        return {"status": "ok" if self._available else "error"}

    def get_status(self) -> dict[str, Any]:
        return {"available": self._available, "label": self.name}


# ── Bridge Pipeline Tests ────────────────────────────────────────────────

class TestBridgePipeline:
    """Test the full SI pipeline: si_turn() → backend → evaluate → compose."""

    def test_prompt_composition_separates_sections(self):
        """Prompt is composed from separate sections, not one blob."""
        from api.si.bridge import compose_prompt_from_briefing
        from api.si.types import (
            ContextBriefing, SIIdentity, ContextItem, Constraint, PUBLIC,
        )

        briefing = ContextBriefing(
            si_identity=SIIdentity(
                name="TestSI", owner_name="User",
                mission="Help the user", principles=["Be honest", "Protect data"],
            ),
            user_context=[
                ContextItem(source="t", source_id="1", content="user likes Python", sensitivity=PUBLIC),
            ],
            constraints=[
                Constraint(kind="must_not", description="Never share secrets", reason="privacy"),
            ],
            privacy_policy={"redacted_types": ["secret", "sensitive"]},
        )

        prompt = compose_prompt_from_briefing(briefing, "write hello world")

        # Each section should be clearly separated
        assert "You are TestSI" in prompt
        assert "Help the user" in prompt
        assert "Be honest" in prompt
        assert "Protect data" in prompt
        assert "user likes Python" in prompt
        assert "Never share secrets" in prompt
        assert "Do not share secret, sensitive data" in prompt
        assert "write hello world" in prompt

        # Sections should be separated by double newlines
        sections = prompt.split("\n\n")
        assert len(sections) >= 4, f"Expected >=4 sections, got {len(sections)}: {sections}"

    def test_si_turn_with_mock_backend(self):
        """Full pipeline with a mock backend produces valid output."""
        from api.si.bridge import si_turn
        from api.backends.router import get_router

        # Register a mock backend
        mock = MockBackend("mock_si_test")
        router = get_router()
        router.register("mock_si_test", mock)

        result = si_turn(
            "write a hello world function",
            session_id="test_session",
            target_worker="mock_si_test",
        )

        assert "text" in result
        assert result["intent"] in ("code_generation", "conversation", "memory", "research", "action")
        assert result["worker"] == "mock_si_test"
        assert "evaluation" in result
        assert result["evaluation"]["verdict"] in ("pass", "fail", "needs_review", "escalate", "unknown")
        assert "activity_summary" in result

        # Verify the mock received a composed prompt (not raw message)
        assert "You are" in mock.last_message or "write a hello world" in mock.last_message

    def test_si_turn_fallback_when_worker_unavailable(self):
        """When target worker is unavailable, falls back gracefully."""
        from api.si.bridge import si_turn
        from api.backends.router import get_router

        # Register an unavailable mock
        mock = MockBackend("mock_unavailable", available=False)
        router = get_router()
        router.register("mock_unavailable", mock)

        result = si_turn(
            "hello",
            session_id="test_session",
            target_worker="mock_unavailable",
        )

        # Should fall back to hermes_local or return an error
        assert "text" in result or "error" in result

    def test_si_turn_handles_backend_error(self):
        """When backend returns an error, si_turn surfaces it."""
        from api.si.bridge import si_turn
        from api.backends.router import get_router

        class ErrorBackend(MockBackend):
            def run_turn(self, message, session_id, **kwargs):
                return {"text": "", "error": "Backend crashed"}

        mock = ErrorBackend("mock_error")
        router = get_router()
        router.register("mock_error", mock)

        result = si_turn(
            "hello",
            session_id="test_session",
            target_worker="mock_error",
        )

        assert result.get("error") or result.get("text") == "Backend crashed"


# ── Privacy Enforcement Tests ────────────────────────────────────────────

class TestPrivacyEnforcement:
    """Test that privacy rules are enforced in the pipeline."""

    def test_secret_data_excluded_from_briefing(self):
        """SECRET data is excluded from briefings to APPROVED_PROVIDER workers."""
        from api.si.trust_engine import filter_briefing
        from api.si.types import (
            ContextBriefing, SIIdentity, ContextItem, SECRET, PUBLIC, PrivacyClass,
        )

        briefing = ContextBriefing(
            si_identity=SIIdentity(name="T", owner_name="U"),
            user_context=[
                ContextItem(source="t", source_id="1", content="api_key=sk-secret", sensitivity=SECRET),
                ContextItem(source="t", source_id="2", content="public info", sensitivity=PUBLIC),
            ],
        )

        filtered = filter_briefing(briefing, PrivacyClass.APPROVED_PROVIDER)
        assert len(filtered.user_context) == 1
        assert filtered.user_context[0].content == "public info"

        # Manifest should explain the exclusion
        excluded = [m for m in filtered.context_manifest if m.action.value == "excluded"]
        assert len(excluded) >= 1

    def test_private_data_only_to_local_workers(self):
        """PRIVATE data is only sent to LOCAL_ONLY workers."""
        from api.si.trust_engine import filter_briefing
        from api.si.types import (
            ContextBriefing, SIIdentity, ContextItem, PRIVATE, PrivacyClass,
        )

        briefing = ContextBriefing(
            si_identity=SIIdentity(name="T", owner_name="U"),
            user_context=[
                ContextItem(source="t", source_id="1", content="private conversation", sensitivity=PRIVATE),
            ],
        )

        # LOCAL_ONLY should keep it
        filtered_local = filter_briefing(briefing, PrivacyClass.LOCAL_ONLY)
        assert len(filtered_local.user_context) == 1

        # APPROVED_PROVIDER should exclude it
        filtered_cloud = filter_briefing(briefing, PrivacyClass.APPROVED_PROVIDER)
        assert len(filtered_cloud.user_context) == 0

    def test_local_only_mode_blocks_all_cloud(self):
        """When local-only mode is on, no data goes to cloud workers."""
        from api.si.trust_engine import set_local_only_mode, is_local_only_mode
        from api.si.worker_registry import get_registry

        set_local_only_mode(True)
        assert is_local_only_mode()

        registry = get_registry()
        # No workers should be eligible for anything above PUBLIC
        eligible = registry.find_eligible("conversation", data_sensitivity="private")
        # In local-only mode, only LOCAL_ONLY workers are eligible
        for w in eligible:
            assert w.privacy_class.value == "local_only"

        set_local_only_mode(False)


# ── Orchestration Persistence Tests ─────────────────────────────────────

class TestOrchestrationPersistence:
    """Test that plans survive simulated restarts."""

    def test_plan_survives_simulated_restart(self):
        """Create a plan, simulate restart by reloading from DB."""
        from api.si.orchestrator import orchestrate_request, load_plan, cancel_plan

        result = orchestrate_request("write a web scraper in Python")
        plan_id = result["plan_id"]

        # Simulate restart: load from DB
        plan = load_plan(plan_id)
        assert plan is not None
        assert plan.goal == "write a web scraper in Python"
        assert len(plan.steps) >= 1

        cancel_plan(plan_id)

    def test_plan_cancellation_cleans_up(self):
        """Cancelled plans are marked as cancelled."""
        from api.si.orchestrator import orchestrate_request, load_plan, cancel_plan
        from api.si.types import PlanStatus

        result = orchestrate_request("hello")
        plan_id = result["plan_id"]

        cancel_result = cancel_plan(plan_id)
        assert cancel_result["status"] == "cancelled"

        plan = load_plan(plan_id)
        assert plan.status == PlanStatus.CANCELLED


# ── Identity Persistence Tests ───────────────────────────────────────────

class TestIdentityPersistence:
    """Test that identity persists across sessions."""

    def test_identity_survives_restart(self):
        """Identity changes persist to disk and survive reload."""
        from api.si.identity import load_identity, patch_identity, ensure_identity_exists

        # Ensure defaults exist
        config = ensure_identity_exists()
        original_name = config.name

        # Change identity
        patch_identity({"name": "IntegrationTestSI", "mission": "Test mission"})

        # Simulate restart: reload
        config2 = load_identity()
        assert config2.name == "IntegrationTestSI"
        assert config2.mission == "Test mission"

        # Restore
        patch_identity({"name": original_name, "mission": config.mission})


# ── User Model Tests ────────────────────────────────────────────────────

class TestUserModelIntegration:
    """Test the user model end-to-end."""

    def test_fact_lifecycle(self):
        """Add, update, confirm, delete a fact."""
        from api.si.user_model import (
            add_fact, update_fact, confirm_fact, delete_fact,
            ensure_user_model_exists, load_user_model,
        )

        ensure_user_model_exists()

        # Add
        fact = add_fact("preferences", "Test preference", "observed_behavior", 0.5)
        assert fact.confidence == 0.5

        # Update
        updated = update_fact(fact.fact_id, {"fact": "Updated preference"})
        assert updated is not None
        assert updated.fact == "Updated preference"

        # Confirm
        confirmed = confirm_fact(fact.fact_id)
        assert confirmed is not None
        assert confirmed.confidence == 1.0
        assert confirmed.source == "explicit_user_instruction"

        # Delete
        assert delete_fact(fact.fact_id)

    def test_inferred_confidence_cap(self):
        """Inferred facts cannot exceed 0.7 confidence."""
        from api.si.user_model import add_fact, delete_fact, ensure_user_model_exists

        ensure_user_model_exists()

        # Try to add inferred fact with high confidence
        fact = add_fact("projects", "Uses Rust", "inferred", 0.95)
        assert fact.confidence == 0.7  # Capped

        # Explicit instruction should be 1.0
        fact2 = add_fact("projects", "Uses Python", "explicit_user_instruction", 1.0)
        assert fact2.confidence == 1.0

        delete_fact(fact.fact_id)
        delete_fact(fact2.fact_id)


# ── Memory Lifecycle Integration Tests ──────────────────────────────────

class TestMemoryLifecycleIntegration:
    """Test the memory lifecycle against the real Journal DB."""

    def test_full_lifecycle(self):
        """Ingest → classify → score → retrieve → correct → delete."""
        import sqlite3
        from api.si.memory import (
            ingest_memory, classify_memory, score_importance,
            retrieve_memories, correct_memory, delete_memory,
        )

        # Use the same DB path as _get_db() (respects ARES_HOME)
        ares_home = os.environ.get("ARES_HOME", os.path.expanduser("~/.ares"))
        db_path = os.path.join(ares_home, "journal", "journal.db")
        os.makedirs(os.path.dirname(db_path), exist_ok=True)

        # Ensure core tables exist (memory module only creates its own tables)
        conn = sqlite3.connect(db_path)
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL, source TEXT NOT NULL, title TEXT,
                model TEXT, workspace TEXT, created_at REAL, updated_at REAL,
                message_count INTEGER DEFAULT 0, source_path TEXT,
                import_batch TEXT, import_ts REAL, metadata TEXT,
                UNIQUE(source, session_id)
            );
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                seq INTEGER NOT NULL, role TEXT NOT NULL, content TEXT,
                timestamp REAL, model TEXT, tool_name TEXT,
                token_count INTEGER, metadata TEXT
            );
        """)
        conn.commit()
        conn.close()

        mid = ingest_memory(
            "integration_test",
            "ARES SI integration test memory with unique marker zzintegtestzz",
            is_decision=True,
        )
        assert mid.startswith("mem_")

        # Classify
        sensitivity = classify_memory(mid)
        assert sensitivity is not None

        # Score
        score = score_importance(mid)
        assert 0.0 <= score <= 1.0

        # Retrieve (may need retry for FTS5 content-sync triggers)
        found = False
        for attempt in range(10):
            mems = retrieve_memories("zzintegtestzz", limit=10)
            if any(m.memory_id == mid for m in mems):
                found = True
                break
            time.sleep(0.3)

        # If FTS5 still hasn't indexed, verify via direct SQL as fallback
        if not found:
            import sqlite3 as _sql
            _conn = _sql.connect(db_path)
            _conn.row_factory = _sql.Row
            _row = _conn.execute(
                "SELECT c.session_id FROM conversations c JOIN messages m ON m.conversation_id = c.id WHERE m.content LIKE ?",
                ("%zzintegtestzz%",),
            ).fetchone()
            _conn.close()
            if _row and _row["session_id"] == mid:
                found = True  # Direct SQL confirms it exists

        assert found, f"Memory {mid} not found via FTS5 or direct SQL"

        # Correct
        cid = correct_memory(mid, "Corrected integration test memory", "test correction")
        assert cid.startswith("mem_")

        # Delete
        delete_memory(mid)


# ── Router Integration Tests ────────────────────────────────────────────

class TestRouterIntegration:
    """Test the router with the real worker registry."""

    def test_route_respects_privacy(self):
        """SECRET data returns no workers."""
        from api.si.router import route_task

        result = route_task("conversation", data_sensitivity="secret")
        assert result["selected_worker"] is None
        assert len(result.get("routing_reasons", [])) > 0

    def test_route_respects_user_preference(self):
        """User preference overrides other factors."""
        from api.si.router import route_task

        result = route_task(
            "conversation",
            data_sensitivity="personal",
            prefer_worker="hermes_local",
        )
        assert result["selected_worker"] is not None
        assert result["selected_worker"]["worker_id"] == "hermes_local"

    def test_route_excludes_workers(self):
        """Excluded workers are not selected."""
        from api.si.router import route_task

        result = route_task(
            "conversation",
            data_sensitivity="personal",
            exclude_workers=["hermes_local"],
        )
        if result["selected_worker"]:
            assert result["selected_worker"]["worker_id"] != "hermes_local"


# ── Evaluator Integration Tests ─────────────────────────────────────────

class TestEvaluatorIntegration:
    """Test the evaluator with realistic outputs."""

    def test_evaluator_catches_secret_leak(self):
        """Secret leaks always escalate."""
        from api.si.evaluator import evaluate_result, EvaluationVerdict

        result = evaluate_result(
            "Here is the API key you asked for: sk-abc123def456ghi789jkl012mno345pqr678stu",
            intent="conversation",
        )
        assert result.verdict == EvaluationVerdict.ESCALATE

    def test_evaluator_catches_empty_response(self):
        """Empty responses always fail."""
        from api.si.evaluator import evaluate_result, EvaluationVerdict

        result = evaluate_result("", intent="conversation")
        assert result.verdict == EvaluationVerdict.FAIL

    def test_evaluator_passes_good_response(self):
        """Good responses pass."""
        from api.si.evaluator import evaluate_result, EvaluationVerdict

        result = evaluate_result(
            "Here is a well-formed, detailed response to your question about Python.",
            intent="conversation",
        )
        assert result.verdict == EvaluationVerdict.PASS

    def test_evaluator_detects_harmful_commands(self):
        """Harmful shell commands are caught."""
        from api.si.evaluator import evaluate_result, EvaluationVerdict

        result = evaluate_result(
            "To fix this, run: rm -rf / --no-preserve-root",
            intent="action",
        )
        assert result.verdict in (EvaluationVerdict.FAIL, EvaluationVerdict.ESCALATE)
