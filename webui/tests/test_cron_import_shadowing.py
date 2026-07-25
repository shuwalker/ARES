"""ARES schedule resources cannot be shadowed by a top-level plugin package."""

from __future__ import annotations

import importlib
from pathlib import Path
import sys


def test_ares_schedule_import_is_namespaced_against_plugin_shadow(monkeypatch, tmp_path):
    shadow_root = tmp_path / "site-packages"
    shadow_cron = shadow_root / "cron"
    shadow_cron.mkdir(parents=True)
    (shadow_cron / "__init__.py").write_text("SHADOW_CRON = True\n", encoding="utf-8")
    (shadow_cron / "jobs.py").write_text("raise RuntimeError('shadow imported')\n", encoding="utf-8")

    monkeypatch.syspath_prepend(str(shadow_root))
    for name in list(sys.modules):
        if name == "cron" or name.startswith("cron."):
            sys.modules.pop(name, None)

    shadowed = importlib.import_module("cron")
    assert Path(shadowed.__file__).resolve() == shadow_cron / "__init__.py"

    from api.schedules_store import ensure_schedule_runtime

    ensure_schedule_runtime()
    jobs = importlib.import_module("api.schedule_jobs")
    assert Path(jobs.__file__).resolve().name == "schedule_jobs.py"
    assert "webui/api" in Path(jobs.__file__).resolve().as_posix()
