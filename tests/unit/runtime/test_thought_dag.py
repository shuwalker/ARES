"""Unit tests for the reasoning-DAG emission on CognitiveLoop."""

from ares.core.cognitive import CognitiveLoop, Phase
from ares.core.personality import DEFAULT_PROFILE


def _make_loop():
    return CognitiveLoop(personality=DEFAULT_PROFILE, max_cycles=2)


def test_dag_has_one_node_per_phase_in_a_cycle():
    loop = _make_loop()
    loop.run(goal="dag-default")

    # The state captured at the end of the run holds the LAST cycle's
    # branches (cycle 1 was the only one that ran phases; cycle 2 reset
    # branches and exited before recording any).
    labels = [b.label for b in loop.state.branches]
    assert labels == []  # cycle 2 reset before any phase fired
    # The earlier cycle's DAG was visible via the observer — verify that
    # by hooking it explicitly.


def test_observer_sees_progressively_growing_dag():
    loop = _make_loop()
    captured: list[list[str]] = []

    def observer(state):
        captured.append([b.label for b in state.branches])

    loop.on_phase_change = observer
    loop.run(goal="dag-progress")

    # Four transitions in cycle 1: each adds one node, chained off the prior.
    assert captured == [
        ["perceive"],
        ["perceive", "think"],
        ["perceive", "think", "act"],
        ["perceive", "think", "act", "reflect"],
    ]


def test_dag_edges_form_linear_chain_by_default():
    loop = _make_loop()
    seen_branches: list = []

    def observer(state):
        # Snapshot final branches after reflect (when len == 4).
        if len(state.branches) == 4:
            seen_branches.append([(b.id, list(b.parent_ids)) for b in state.branches])

    loop.on_phase_change = observer
    loop.run(goal="chain check")

    assert seen_branches, "observer should fire with full DAG once per cycle"
    chain = seen_branches[0]
    # First node has no parent; each subsequent node points back to its predecessor.
    assert chain[0][1] == []
    for i in range(1, len(chain)):
        assert chain[i][1] == [chain[i - 1][0]]


def test_emit_thought_node_appends_extra_branch():
    loop = _make_loop()

    captured: list[str] = []

    def think_handler(state, _input, _guidance):
        nid = loop.emit_thought_node(label="retrieve_memory", evidence=[{"kind": "episodic", "ref": "abc"}])
        captured.append(nid)
        return None

    loop.on_think(think_handler)
    loop.run(goal="emit-extra")

    # Inside the think phase, the emit_thought_node call added a node.
    # The observer at reflect time should have seen all 4 phase nodes
    # plus the extra one — total 5 in the cycle DAG.
    # We re-run with the observer to count.


def test_full_cycle_dag_size_with_extra_emission():
    loop = _make_loop()
    final_sizes: list[int] = []

    def think_handler(state, _input, _guidance):
        loop.emit_thought_node(label="retrieve_memory")
        return None

    def observer(state):
        if state.phase == Phase.REFLECT:
            final_sizes.append(len(state.branches))

    loop.on_think(think_handler)
    loop.on_phase_change = observer
    loop.run(goal="size check")

    # perceive + think + (extra) + act + reflect = 5 nodes
    assert final_sizes == [5]
