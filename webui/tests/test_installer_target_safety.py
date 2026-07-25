"""Regression coverage for clean installer destination handling."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess


INSTALLER = Path(__file__).parents[1] / "scripts" / "install.sh"


def _fake_git(bin_dir: Path) -> None:
    git = bin_dir / "git"
    git.write_text(
        "#!/bin/bash\n"
        "set -eu\n"
        "if [ \"${1:-}\" = clone ]; then\n"
        "  destination=\"${@: -1}\"\n"
        "  /bin/mkdir -p \"$destination/.git\" \"$destination/webui\"\n"
        "  exit 0\n"
        "fi\n"
        "exit 0\n",
        encoding="utf-8",
    )
    git.chmod(0o755)


def _run_repository_stage(target: Path, fake_bin: Path) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env["PATH"] = f"{fake_bin}:{env['PATH']}"
    return subprocess.run(
        ["bash", str(INSTALLER), "--stage", "repository", "--dir", str(target)],
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )


def test_repository_stage_accepts_existing_empty_secure_temp_directory(tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _fake_git(fake_bin)
    target = tmp_path / "existing-empty"
    target.mkdir()

    result = _run_repository_stage(target, fake_bin)

    assert result.returncode == 0, result.stdout + result.stderr
    assert (target / ".git").is_dir()
    assert (target / "webui").is_dir()


def test_repository_stage_refuses_nonempty_non_repository(tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _fake_git(fake_bin)
    target = tmp_path / "user-data"
    target.mkdir()
    marker = target / "keep.txt"
    marker.write_text("do not overwrite", encoding="utf-8")

    result = _run_repository_stage(target, fake_bin)

    assert result.returncode != 0
    assert "not a git repository" in result.stdout
    assert marker.read_text(encoding="utf-8") == "do not overwrite"


def test_repository_stage_can_stage_current_source_without_build_caches(tmp_path: Path) -> None:
    source = tmp_path / "source"
    (source / "webui" / "fastapi_app").mkdir(parents=True)
    (source / "webui" / "frontend" / "node_modules").mkdir(parents=True)
    (source / "webui" / "frontend" / "package.json").write_text("{}", encoding="utf-8")
    (source / "webui" / "fastapi_app" / "main.py").write_text("app = None\n", encoding="utf-8")
    (source / "webui" / "frontend" / "node_modules" / "cache").write_text("x", encoding="utf-8")
    (source / "webui" / "runtime.txt").write_text("keep", encoding="utf-8")
    target = tmp_path / "target"

    result = subprocess.run(
        [
            "bash",
            str(INSTALLER),
            "--stage",
            "repository",
            "--dir",
            str(target),
            "--source",
            str(source),
        ],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert (target / "webui" / "runtime.txt").read_text(encoding="utf-8") == "keep"
    assert not (target / "webui" / "frontend" / "node_modules").exists()
    assert (target / ".ares-source-install").is_file()

    (source / "webui" / "runtime.txt").write_text("updated", encoding="utf-8")
    updated = subprocess.run(
        ["bash", str(INSTALLER), "--stage", "repository", "--dir", str(target), "--source", str(source)],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    assert updated.returncode == 0, updated.stdout + updated.stderr
    assert (target / "webui" / "runtime.txt").read_text(encoding="utf-8") == "updated"
