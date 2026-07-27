"""Regression coverage for pytest isolation of Ares config paths."""
import os
from pathlib import Path


def test_pytest_overrides_inherited_ares_config_path():
    """A live-agent ARES_CONFIG_PATH must never leak into WebUI tests.

    Ares agents commonly run with ARES_CONFIG_PATH pointing at the real
    ~/.ares/config.yaml. The test harness must replace it with the isolated
    test home before product modules are imported, otherwise provider/onboarding
    tests can mutate the user's real config.
    """
    test_state_dir = Path(os.environ["ARES_WEBUI_TEST_STATE_DIR"])
    assert Path(os.environ["ARES_CONFIG_PATH"]) == test_state_dir / "config.yaml"
