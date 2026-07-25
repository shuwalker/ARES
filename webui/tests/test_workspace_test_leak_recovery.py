from pathlib import Path

from api import workspace


def test_production_ignores_existing_leaked_test_workspace(monkeypatch, tmp_path: Path):
    leaked = tmp_path / "ares-webui-tests" / "old-run" / "test-workspace"
    leaked.mkdir(parents=True)
    fallback = tmp_path / "real-workspace"
    fallback.mkdir()
    last_file = tmp_path / "last_workspace.txt"
    last_file.write_text(str(leaked), encoding="utf-8")

    monkeypatch.delenv("ARES_WEBUI_TEST_STATE_DIR", raising=False)
    monkeypatch.setattr(workspace, "_last_workspace_file", lambda: last_file)
    monkeypatch.setattr(workspace, "_GLOBAL_LW_FILE", tmp_path / "missing-global.txt")
    monkeypatch.setattr(workspace, "_profile_default_workspace", lambda: str(fallback))
    monkeypatch.setattr(workspace, "_remote_terminal_cwd", lambda: None)

    assert workspace.get_last_workspace() == str(fallback)


def test_test_process_keeps_its_isolated_workspace(monkeypatch, tmp_path: Path):
    isolated = tmp_path / "ares-webui-tests" / "current-run"
    candidate = isolated / "test-workspace"
    candidate.mkdir(parents=True)
    monkeypatch.setenv("ARES_WEBUI_TEST_STATE_DIR", str(isolated))

    assert workspace._is_leaked_test_workspace(str(candidate)) is False
