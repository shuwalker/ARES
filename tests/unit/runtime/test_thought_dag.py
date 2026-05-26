"""Unit tests for the reasoning-DAG emission on CognitiveLoop.

SKIP: CognitiveLoop has been removed from the codebase. The cognitive loop
is now handled by the AgentInterface backend system (Hermes/Lilith/Local).
These tests will be rewritten for the new backend architecture.

See: ares/core/agent.py (AgentInterface) and ares/runtime/hermes_backend.py
"""

import pytest

pytestmark = pytest.mark.skip(reason="CognitiveLoop removed — will be reimplemented via AgentInterface backends")


def test_dag_has_one_node_per_phase_in_a_cycle():
    pass


def test_observer_sees_progressively_growing_dag():
    pass


def test_dag_edges_form_linear_chain_by_default():
    pass


def test_emit_thought_node_appends_extra_branch():
    pass


def test_full_cycle_dag_size_with_extra_emission():
    pass
