"""Regression test for #1312 / #1310 — _run_cron_tracked must import run_job.

The function runs inside a worker thread (threading.Thread), so any
names it references must be resolvable from that thread's scope.
Before the fix, run_job was only imported inside _handle_cron_run
(a local scope invisible to _run_cron_tracked), causing NameError.
"""
import ast
import inspect
from pathlib import Path

import pytest

SCHEDULES_PY = Path(__file__).resolve().parent.parent / "api" / "schedules_store.py"


def _get_function_source(func_name: str) -> str:
    """Extract a top-level function's source via AST for stability."""
    tree = ast.parse(SCHEDULES_PY.read_text(encoding="utf-8"))
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == func_name:
            lines = SCHEDULES_PY.read_text(encoding="utf-8").splitlines()
            return "\n".join(lines[node.lineno - 1 : node.end_lineno])
    pytest.fail(f"Function {func_name} not found in {SCHEDULES_PY}")


class TestRunCronTrackedImport:
    """_run_cron_tracked must be self-contained — it runs in a worker thread."""

    def test_run_job_imported_inside_function(self):
        """run_job must be imported inside the subprocess target, not relied on
        from a caller's local scope."""
        src = _get_function_source("_cron_job_subprocess_main")
        tree = ast.parse(src)
        names_used = set()

        class NameCollector(ast.NodeVisitor):
            def visit_Name(self, node):
                names_used.add(node.id)

        ImportCollector = type(
            "ImportCollector",
            (ast.NodeVisitor,),
            {
                "imports": set(),
                "visit_ImportFrom": lambda self, node: (
                    self.imports.add(a.name for a in node.names),
                ),
            },
        )

        # Collect all names referenced in the function body
        for node in ast.walk(tree):
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
                names_used.add(node.id)

        # Collect imports inside the function
        func_imports = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom):
                for alias in node.names:
                    func_imports.add(alias.name if alias.asname is None else alias.asname)
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    func_imports.add(alias.name if alias.asname is None else alias.asname)

        # run_job is referenced → must be imported inside the function
        if "run_job" in names_used:
            assert "run_job" in func_imports, (
                "_run_cron_tracked references run_job but does not import it locally. "
                "It runs in a worker thread and cannot rely on caller's local imports."
            )

    def test_fastapi_schedule_router_uses_schedule_service(self):
        """HTTP transport delegates execution instead of importing cron internals."""
        from fastapi_app.routers import schedules

        src = inspect.getsource(schedules.run)
        assert "from api.schedules_store import run_schedule" in src
        assert "from cron" not in src

    def test_run_cron_tracked_calls_run_job_helper(self):
        """Sanity: the function still delegates to the cron job runner."""
        src = _get_function_source("_run_cron_tracked")
        assert "_run_cron_job_in_profile_subprocess" in src

    def test_cron_subprocess_target_calls_run_job(self):
        """Sanity: the subprocess target still actually calls run_job."""
        src = _get_function_source("_cron_job_subprocess_main")
        assert "run_job" in src, "cron subprocess target should call run_job"
