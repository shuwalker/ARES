"""Unit test configuration.

All tests collected under tests/unit/ are auto-marked with `unit` so they can
be selected via `pytest -m unit`. Unit tests must not require any ARES service
to be bound to a network port — keep them in-process.
"""

import pytest


def pytest_collection_modifyitems(config, items):
    for item in items:
        if "tests/unit/" in str(item.fspath).replace("\\", "/"):
            item.add_marker(pytest.mark.unit)
