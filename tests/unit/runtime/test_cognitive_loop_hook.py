"""Unit tests for the on_phase_change observer on CognitiveLoop.

This is what the API server uses to push CognitiveSnapshot events over the
WebSocket. The observer must:
  * fire after each of perceive / think / act / reflect within one cycle
  * receive the loop's CognitiveState (with the post-transition phase set)
  * not crash the loop if it raises
"""

from ares.core.cognitive import CognitiveLoop, Phase
from ares.core.personality import DEFAULT_PROFILE


def _make_loop():
    # max_cycles=2 lets exactly one cycle run all four phases before the
    # stop hook trips on the next iteration. (The hook is checked at the
    # top of each iteration after cycle += 1.)
    return CognitiveLoop(personality=DEFAULT_PROFILE, max_cycles=2, budget_tokens=100)


def test_observer_fires_once_per_phase():
    loop = _make_loop()
    seen_phases: list[str] = []

    def observer(state):
        seen_phases.append(state.phase.value)

    loop.on_phase_change = observer
    loop.run(goal="test")

    assert seen_phases == [
        Phase.PERCEIVE.value,
        Phase.THINK.value,
        Phase.ACT.value,
        Phase.REFLECT.value,
    ]


def test_observer_receives_live_state():
    loop = _make_loop()
    captured: list[tuple[int, str]] = []

    def observer(state):
        captured.append((state.cycle, state.phase.value))

    loop.on_phase_change = observer
    loop.run(goal="capture")

    assert captured[0] == (1, "perceive")
    assert captured[-1] == (1, "reflect")


def test_observer_exception_does_not_crash_loop():
    loop = _make_loop()
    fire_count = {"n": 0}

    def bad_observer(_state):
        fire_count["n"] += 1
        raise RuntimeError("simulated UI failure")

    loop.on_phase_change = bad_observer
    result = loop.run(goal="resilience check")

    assert result["cycles"] == 2  # increment hit twice; second hits max_cycles
    assert fire_count["n"] == 4  # all four transitions tried in the one full cycle


def test_default_observer_is_safe_noop():
    """A loop without a custom observer must still run cleanly."""
    loop = _make_loop()
    result = loop.run(goal="default observer")
    assert result["cycles"] == 2
