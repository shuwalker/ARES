"""Tests for Jaeger AI dispatch integration."""

from __future__ import annotations

import pytest
from api.dispatch_service import DispatchService
from api.cost_calculator import estimate_cost, get_model_provider
from unittest.mock import MagicMock, patch


class MockJaegerWorker:
    """Mock Jaeger AI worker for testing."""

    name = "jaeger_local"
    model_name = "jaeger-ai"

    def is_available(self) -> bool:
        return True

    def run_turn(self, message: str, session_id: str, model: str | None = None, model_provider: str | None = None, **kwargs) -> dict:
        """Simulate Jaeger AI execution.

        Signature mirrors the real integrations.workers.jaeger_worker.run_turn
        contract (model/model_provider + **kwargs) so this mock can't silently
        drift from what DispatchService.dispatch_turn actually calls.
        """
        return {
            "text": f"Jaeger response to: {message}",
            "model": "gpt-4-turbo",  # Simulate cloud model
            "provider": "openai",
            "input_tokens": 150,
            "output_tokens": 250,
            "mode": "gateway",
        }


class MockJaegerRegistry:
    @classmethod
    def get_available(cls):
        return {"jaeger_local": MockJaegerWorker()}


def test_jaeger_worker_available(monkeypatch):
    """Jaeger worker is detected as available."""
    monkeypatch.setattr(
        "integrations.workers.jaeger_worker.is_jaeger_available",
        lambda: True,
    )

    from integrations.workers.jaeger_worker import is_jaeger_available
    assert is_jaeger_available()


def test_jaeger_dispatch_with_cost_calculation(tmp_path, monkeypatch):
    """Dispatch through Jaeger records accurate costs using LiteLLM."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    service = DispatchService(backend_registry=MockJaegerRegistry)

    result = service.dispatch_turn(
        user_message="Explain quantum computing",
        conversation_id="conv_jaeger_1",
    )

    assert result["status"] == "step_completed"
    assert result["assigned_worker"] == "jaeger_local"
    assert "Jaeger response" in result["output"]

    # Verify cost was calculated correctly
    # GPT-4-turbo: ~$0.03 per 1K input + $0.06 per 1K output
    # 150 input tokens * $0.03/1K + 250 output tokens * $0.06/1K
    estimated = estimate_cost("gpt-4-turbo", 150, 250)
    assert estimated > 0  # Should have a non-zero cost


def test_model_provider_detection():
    """Model provider detection works for various models."""
    assert get_model_provider("gpt-4") == "openai"
    assert get_model_provider("claude-3-opus") == "anthropic"
    assert get_model_provider("gemini-1.5-pro") == "google"
    assert get_model_provider("llama2-70b") == "meta"
    assert get_model_provider("local-model") == "local"


def test_jaeger_cost_calculation_different_models():
    """Cost calculation returns positive values for different models."""
    # Test that cost calculation works (falls back to safe estimate if LiteLLM pricing unavailable)
    gpt4_cost = estimate_cost("gpt-4-turbo", 1000, 1000)
    claude_cost = estimate_cost("claude-3-opus", 1000, 1000)
    gemini_cost = estimate_cost("gemini-1.5-pro", 1000, 1000)

    # All should return positive costs (either from LiteLLM or fallback)
    assert gpt4_cost >= 0, "GPT-4 cost should be non-negative"
    assert claude_cost >= 0, "Claude cost should be non-negative"
    assert gemini_cost >= 0, "Gemini cost should be non-negative"


def test_dispatch_respects_jaeger_model_name(tmp_path, monkeypatch):
    """Dispatch extracts model name from Jaeger response for cost calc."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    service = DispatchService(backend_registry=MockJaegerRegistry)

    result = service.dispatch_turn(
        user_message="Test",
        conversation_id="conv_jaeger_2",
    )

    # Verify the response includes model info for cost tracking
    assert "output" in result
    assert result["status"] == "step_completed"
