"""
Sprint 43 Tests: security fixes retained by the FastAPI/Uvicorn server.

Covers:
- gateway_watcher.py: MD5 uses usedforsecurity=False (B324)
- config.py: URL scheme validation before urlopen (B310)
- bootstrap.py: URL scheme validation in wait_for_health (B310)
- Uvicorn owns connection lifecycle; ARES preserves process hardening
- Logging: at least 5 modules add a module-level logger (B110 remediation)
- FastAPI session service redacts titles in /api/sessions responses
"""
import ast
import pathlib
import re
import sys
import unittest

REPO_ROOT = pathlib.Path(__file__).parent.parent
GATEWAY_WATCHER_PY = (REPO_ROOT / "api" / "gateway_watcher.py").read_text(encoding="utf-8")
CONFIG_PY = (REPO_ROOT / "api" / "config.py").read_text(encoding="utf-8")
BOOTSTRAP_PY = (REPO_ROOT / "bootstrap.py").read_text(encoding="utf-8")
FASTAPI_MAIN_PY = (REPO_ROOT / "fastapi_app" / "main.py").read_text(encoding="utf-8")
LIFECYCLE_PY = (REPO_ROOT / "fastapi_app" / "lifecycle.py").read_text(encoding="utf-8")
PROCESS_RUNTIME_PY = (REPO_ROOT / "api" / "process_runtime.py").read_text(encoding="utf-8")
SERVICES_PY = (REPO_ROOT / "fastapi_app" / "services.py").read_text(encoding="utf-8")
AUTH_PY = (REPO_ROOT / "api" / "auth.py").read_text(encoding="utf-8")
PROFILES_PY = (REPO_ROOT / "api" / "profiles.py").read_text(encoding="utf-8")
STREAMING_PY = (REPO_ROOT / "api" / "streaming.py").read_text(encoding="utf-8")
WORKSPACE_PY = (REPO_ROOT / "api" / "workspace.py").read_text(encoding="utf-8")
STATE_SYNC_PY = (REPO_ROOT / "api" / "state_sync.py").read_text(encoding="utf-8")


# ── B324: MD5 usedforsecurity=False ─────────────────────────────────────────

class TestMD5SecurityFix(unittest.TestCase):
    """B324: hashlib.md5 must use usedforsecurity=False for non-crypto hashes."""

    def test_gateway_watcher_md5_usedforsecurity_false(self):
        """_snapshot_hash must pass usedforsecurity=False to hashlib.md5 (PR #354)."""
        self.assertIn(
            "usedforsecurity=False",
            GATEWAY_WATCHER_PY,
            "gateway_watcher.py: MD5 must use usedforsecurity=False (B324)",
        )

    def test_gateway_watcher_md5_pattern(self):
        """Exact pattern: hashlib.md5(..., usedforsecurity=False)."""
        # Use re.search with DOTALL since the arg may span parens internally
        import re
        self.assertIsNotNone(
            re.search(r"hashlib\.md5\(.*?usedforsecurity=False\)", GATEWAY_WATCHER_PY, re.DOTALL),
            "MD5 call must include usedforsecurity=False kwarg",
        )


# ── B310: URL scheme validation ──────────────────────────────────────────────

class TestUrlSchemeValidation(unittest.TestCase):
    """B310: urllib.request.urlopen must not be called with arbitrary schemes."""

    def test_config_scheme_validation_present(self):
        """config.py must validate URL scheme before urlopen (B310 fix)."""
        self.assertIn(
            "parsed_url.scheme",
            CONFIG_PY,
            "config.py: URL scheme validation missing (B310)",
        )
        # Must check against allowed schemes
        self.assertRegex(
            CONFIG_PY,
            r'parsed_url\.scheme\s+not\s+in\s+\(',
            "config.py: scheme check must use 'not in (...)' pattern",
        )

    def test_config_urlopen_has_nosec(self):
        """The urlopen call in config.py must have a # nosec B310 comment."""
        self.assertIn(
            "nosec B310",
            CONFIG_PY,
            "config.py: urlopen must have # nosec B310 after scheme validation",
        )

    def test_bootstrap_scheme_validation_present(self):
        """bootstrap.py wait_for_health must validate URL scheme before urlopen."""
        self.assertIn(
            "Invalid health check URL",
            BOOTSTRAP_PY,
            "bootstrap.py: URL scheme validation missing in wait_for_health (B310)",
        )
        self.assertRegex(
            BOOTSTRAP_PY,
            r'url\.startswith\([^)]+http',
            "bootstrap.py: must check url starts with http:// or https://",
        )

    def test_bootstrap_urlopen_has_nosec(self):
        """The urlopen call in bootstrap.py must have a # nosec B310 comment."""
        self.assertIn(
            "nosec B310",
            BOOTSTRAP_PY,
            "bootstrap.py: urlopen must have # nosec B310 after scheme validation",
        )

    def test_config_allows_http_and_https(self):
        """config.py scheme check must permit both http and https."""
        self.assertIn('"http"', CONFIG_PY, "config.py: http must be in allowed schemes")
        self.assertIn('"https"', CONFIG_PY, "config.py: https must be in allowed schemes")


# ── B110: Bare except/pass → logger.debug() ─────────────────────────────────

class TestBareExceptLogging(unittest.TestCase):
    """B110: bare except/pass blocks must be replaced with logger.debug()."""

    MODULES_REQUIRING_LOGGER = [
        ("api/auth.py", AUTH_PY),
        ("api/config.py", CONFIG_PY),
        ("api/gateway_watcher.py", GATEWAY_WATCHER_PY),
        ("api/profiles.py", PROFILES_PY),
        ("api/streaming.py", STREAMING_PY),
        ("api/workspace.py", WORKSPACE_PY),
        ("api/state_sync.py", STATE_SYNC_PY),
        ("fastapi_app/lifecycle.py", LIFECYCLE_PY),
    ]

    def test_module_level_loggers_present(self):
        """All fixed modules must have a module-level logger = logging.getLogger(__name__)."""
        for name, src in self.MODULES_REQUIRING_LOGGER:
            with self.subTest(module=name):
                self.assertIn(
                    "logger = logging.getLogger(__name__)",
                    src,
                    f"{name}: module-level logger missing (B110 fix requires logger)",
                )

    def test_gateway_watcher_no_bare_pass_in_except(self):
        """gateway_watcher.py critical except blocks must not use bare pass."""
        # The poll loop except block that previously had 'pass' must now use logger
        self.assertIn(
            "logger.debug",
            GATEWAY_WATCHER_PY,
            "gateway_watcher.py: must use logger.debug not bare pass (B110)",
        )

    def test_profiles_reload_dotenv_logs_on_error(self):
        """profiles.py _reload_dotenv except must log + reset _loaded_profile_env_keys."""
        # Both the reset and the debug log should be present in the except block
        self.assertIn(
            "_loaded_profile_env_keys = set()",
            PROFILES_PY,
            "profiles.py: _reload_dotenv except must reset _loaded_profile_env_keys",
        )
        self.assertIn(
            "Failed to reload dotenv",
            PROFILES_PY,
            "profiles.py: _reload_dotenv except must log a warning",
        )


# ── ASGI process lifecycle ──────────────────────────────────────────────────

class TestAsgiProcessLifecycle(unittest.TestCase):
    """Uvicorn owns sockets while ARES retains its process guarantees."""

    def test_fastapi_application_factory_is_the_server_boundary(self):
        self.assertIn("def create_app(", FASTAPI_MAIN_PY)
        self.assertIn("ares_lifespan", FASTAPI_MAIN_PY)

    def test_sigpipe_is_ignored_at_process_startup(self):
        self.assertIn("SIGPIPE", PROCESS_RUNTIME_PY)
        self.assertIn("ignore_sigpipe()", PROCESS_RUNTIME_PY)

    def test_shutdown_runs_from_lifespan_finally(self):
        self.assertIn("finally:", LIFECYCLE_PY)
        self.assertIn("await shutdown_runtime()", LIFECYCLE_PY)


# ── Session title redaction in /api/sessions ────────────────────────────────

class TestSessionTitleRedaction(unittest.TestCase):
    """The FastAPI session service redacts session-list output."""

    def test_session_list_uses_canonical_redaction_helper(self):
        self.assertIn("from api.helpers import redact_session_rows", SERVICES_PY)
        self.assertIn("rows = redact_session_rows(rows)", SERVICES_PY)
