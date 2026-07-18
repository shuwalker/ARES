"""Schedules degrade cleanly when the optional runtime is absent."""

from __future__ import annotations

import builtins


def test_list_schedules_guards_missing_cron_module(monkeypatch):
    from api.schedules_store import list_schedules

    monkeypatch.setattr("api.schedules_store.ensure_schedule_runtime", lambda: None)
    original_import = builtins.__import__

    def missing_cron(name, *args, **kwargs):
        if name == "cron.jobs":
            error = ModuleNotFoundError("No module named 'cron'")
            error.name = "cron"
            raise error
        return original_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", missing_cron)

    assert list_schedules() == {"jobs": [], "cron_unavailable": True}


def test_internal_cron_import_bug_is_not_hidden(monkeypatch):
    import pytest

    from api.schedules_store import list_schedules

    monkeypatch.setattr("api.schedules_store.ensure_schedule_runtime", lambda: None)
    original_import = builtins.__import__

    def broken_dependency(name, *args, **kwargs):
        if name == "cron.jobs":
            error = ModuleNotFoundError("No module named 'cron_internal_dependency'")
            error.name = "cron_internal_dependency"
            raise error
        return original_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", broken_dependency)

    with pytest.raises(ModuleNotFoundError, match="cron_internal_dependency"):
        list_schedules()
