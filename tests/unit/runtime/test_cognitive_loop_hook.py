"""Unit tests for the on_phase_change observer on CognitiveLoop.

SKIP: CognitiveLoop has been removed from the codebase. The cognitive loop
is now handled by the AgentInterface backend system (Hermes/Lilith/Local).
These tests will be rewritten for the new backend architecture.

See: ares/core/agent.py (AgentInterface) and ares/runtime/hermes_backend.py
"""

import pytest

pytestmark = pytest.mark.skip(reason="CognitiveLoop removed — will be reimplemented via AgentInterface backends")


def test_observer_fires_once_per_phase():
    pass  # placeholder


def test_observer_receives_live_state():
    pass  # placeholder


def test_observer_exception_does_not_crash_loop():
    pass  # placeholder


def test_default_observer_is_safe_noop():
    pass  # placeholder
