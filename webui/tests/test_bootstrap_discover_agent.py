"""Tests for `discover_agent_dir` shebang-based fallback.

When the standard candidate paths (`~/.ares/ares-agent`, `~/ares-agent`,
`<webui-parent>/ares-agent`, `ARES_WEBUI_AGENT_DIR`) don't match, bootstrap
should fall back to introspecting the `ares` console-script's shebang —
that's a reliable pointer to the install root because the installer writes the
venv-relative interpreter path there.
"""

from __future__ import annotations

import textwrap

import bootstrap


def _make_agent_install(tmp_path, *, with_run_agent: bool = True):
    """Build a fake ares-agent install with venv/bin/python3 + run_agent.py."""
    install = tmp_path / "agent"
    venv_python = install / "venv" / "bin" / "python3"
    venv_python.parent.mkdir(parents=True)
    venv_python.write_text("", encoding="utf-8")
    if with_run_agent:
        (install / "run_agent.py").write_text("", encoding="utf-8")
    return install, venv_python


def _make_ares_cli(tmp_path, shebang_target: str | None):
    """Write a `ares` console-script with the given shebang interpreter."""
    bin_dir = tmp_path / "user-bin"
    bin_dir.mkdir()
    ares = bin_dir / "ares"
    if shebang_target is None:
        ares.write_text("not a script", encoding="utf-8")
    else:
        ares.write_text(
            textwrap.dedent(
                f"""\
                #!{shebang_target}
                from ares_cli.main import main
                main()
                """
            ),
            encoding="utf-8",
        )
    return ares


def _make_ares_bash_wrapper(tmp_path, exec_target: str):
    """Write a `ares` POSIX shell wrapper that ``exec``s the venv entrypoint.

    This is the current installer shape: a bash wrapper whose shebang is
    ``#!/usr/bin/env bash`` (so the shebang itself points at /usr/bin/env, not
    the agent), and whose ``exec`` line carries the real venv path.
    """
    bin_dir = tmp_path / "user-bin"
    bin_dir.mkdir(exist_ok=True)
    ares = bin_dir / "ares"
    ares.write_text(
        textwrap.dedent(
            f"""\
            #!/usr/bin/env bash
            unset PYTHONPATH
            unset PYTHONHOME
            exec "{exec_target}" "$@"
            """
        ),
        encoding="utf-8",
    )
    return ares


def _isolate_discover_agent_dir(monkeypatch, tmp_path, ares_path):
    """Point `which("ares")` at our fake CLI and clear all standard candidates."""
    monkeypatch.setattr(bootstrap.shutil, "which", lambda name: str(ares_path) if name == "ares" else None)
    monkeypatch.setenv("ARES_HOME", str(tmp_path / "no-such-ares-home"))
    monkeypatch.delenv("ARES_WEBUI_AGENT_DIR", raising=False)
    # Force REPO_ROOT.parent to a dir that won't accidentally contain a
    # `ares-agent` sibling on the dev machine running these tests.
    monkeypatch.setattr(bootstrap, "REPO_ROOT", tmp_path / "isolated-repo-root")
    # Pin Path.home() to a directory with no `.ares/ares-agent` or
    # `ares-agent` so the hard-coded `Path.home() / ".ares" / "ares-agent"`
    # / `Path.home() / "ares-agent"` candidates in `discover_agent_dir()`
    # cannot pick up the dev machine's real install. Stage-313 absorbed
    # this in-stage after the original test file isolated only env vars
    # and REPO_ROOT, missing the Path.home() leakage.
    monkeypatch.setattr(bootstrap.Path, "home", classmethod(lambda cls: tmp_path / "isolated-home"))


def test_discovers_agent_dir_from_ares_shebang(monkeypatch, tmp_path):
    """Happy path: ares shebang → walk up parents → find run_agent.py → return install."""
    install, venv_python = _make_agent_install(tmp_path)
    ares = _make_ares_cli(tmp_path, str(venv_python))
    _isolate_discover_agent_dir(monkeypatch, tmp_path, ares)
    monkeypatch.chdir(tmp_path)  # make Path.home() candidates won't match install

    assert bootstrap.discover_agent_dir() == install.resolve()


def test_returns_none_when_ares_not_on_path(monkeypatch, tmp_path):
    _make_agent_install(tmp_path)  # install exists, but no `ares` CLI to point at it
    _isolate_discover_agent_dir(monkeypatch, tmp_path, ares_path=tmp_path / "missing")
    monkeypatch.setattr(bootstrap.shutil, "which", lambda name: None)

    assert bootstrap.discover_agent_dir() is None


def test_returns_none_when_ares_has_no_shebang(monkeypatch, tmp_path):
    """A `ares` file without a #! line gives us nothing to introspect."""
    _make_agent_install(tmp_path)
    ares = _make_ares_cli(tmp_path, shebang_target=None)
    _isolate_discover_agent_dir(monkeypatch, tmp_path, ares)

    assert bootstrap.discover_agent_dir() is None


def test_returns_none_when_shebang_interpreter_does_not_walk_to_run_agent(monkeypatch, tmp_path):
    """Shebang points at a system Python — no parent of /usr/bin/python3 has run_agent.py."""
    ares = _make_ares_cli(tmp_path, "/usr/bin/python3")
    _isolate_discover_agent_dir(monkeypatch, tmp_path, ares)

    assert bootstrap.discover_agent_dir() is None


def test_explicit_candidate_takes_precedence_over_shebang(monkeypatch, tmp_path):
    """ARES_WEBUI_AGENT_DIR and the standard layout still win when present."""
    explicit_install = tmp_path / "explicit"
    (explicit_install).mkdir()
    (explicit_install / "run_agent.py").write_text("", encoding="utf-8")

    # Also set up a ares-shebang install at a different location — this should NOT win.
    other_install, venv_python = _make_agent_install(tmp_path)
    ares = _make_ares_cli(tmp_path, str(venv_python))
    _isolate_discover_agent_dir(monkeypatch, tmp_path, ares)
    monkeypatch.setenv("ARES_WEBUI_AGENT_DIR", str(explicit_install))

    assert bootstrap.discover_agent_dir() == explicit_install.resolve()


def test_discovers_agent_dir_from_ares_bash_wrapper(monkeypatch, tmp_path):
    """Current installer shape: a `#!/usr/bin/env bash` wrapper that execs the
    venv entrypoint. The shebang is useless (/usr/bin/env), so discovery must
    follow the quoted exec target up to run_agent.py. Regression for the
    root-on-Linux report where bootstrap built a deps-only local venv and chat
    failed with 'cannot import both WebUI dependencies and Ares Agent'."""
    install, _venv_python = _make_agent_install(tmp_path)
    venv_ares = install / "venv" / "bin" / "ares"
    venv_ares.write_text("", encoding="utf-8")
    ares = _make_ares_bash_wrapper(tmp_path, str(venv_ares))
    _isolate_discover_agent_dir(monkeypatch, tmp_path, ares)
    monkeypatch.chdir(tmp_path)

    assert bootstrap.discover_agent_dir() == install.resolve()


def test_root_fhs_layout_is_in_candidate_list(monkeypatch, tmp_path):
    """Root-on-Linux installs put agent code at /usr/local/lib/ares-agent and
    link the CLI into /usr/local/bin. ARES_HOME stays at /root/.ares, so the
    `home / 'ares-agent'` candidate never covers it. Verify the explicit FHS
    path is probed by discover_agent_dir() — we can't create a real /usr/local
    dir in tests, so capture the candidates the function actually checks by
    stubbing Path.exists to record probed paths."""
    monkeypatch.setattr(bootstrap.shutil, "which", lambda name: None)
    monkeypatch.setenv("ARES_HOME", str(tmp_path / "root-dot-ares"))
    monkeypatch.delenv("ARES_WEBUI_AGENT_DIR", raising=False)
    monkeypatch.setattr(bootstrap, "REPO_ROOT", tmp_path / "isolated-repo-root")
    monkeypatch.setattr(bootstrap.Path, "home", classmethod(lambda cls: tmp_path / "isolated-home"))

    probed: list[str] = []
    real_exists = bootstrap.Path.exists

    def recording_exists(self):
        probed.append(str(self))
        return real_exists(self)

    monkeypatch.setattr(bootstrap.Path, "exists", recording_exists)

    bootstrap.discover_agent_dir()

    assert any(p == "/usr/local/lib/ares-agent" for p in probed), (
        f"/usr/local/lib/ares-agent was not probed; checked: {probed}"
    )


def test_bash_wrapper_without_agent_target_returns_none(monkeypatch, tmp_path):
    """A bash wrapper whose exec target is a system path (no run_agent.py in any
    parent) must not false-positive."""
    ares = _make_ares_bash_wrapper(tmp_path, "/usr/bin/python3")
    _isolate_discover_agent_dir(monkeypatch, tmp_path, ares)

    assert bootstrap.discover_agent_dir() is None
