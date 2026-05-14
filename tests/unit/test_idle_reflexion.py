"""Unit tests for idle reflexion (consolidation, deduplication, surface).

SKIP: The idle module has been removed from the codebase. Idle/reflexion
logic will be reimplemented via the AgentInterface backend system.
These tests will be rewritten when the new idle architecture is in place.

See: ares/core/agent.py (AgentInterface)
"""

import pytest

pytestmark = pytest.mark.skip(reason="idle module removed — will be reimplemented via AgentInterface")


def test_idle_pass_consolidates_sessions():
    pass


def test_idle_pass_deduplicates_facts():
    pass


def test_idle_pass_surfaces_open_questions():
    pass