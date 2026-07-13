"""Tests for ARES Tool Adapter and Runtime Context.

These modules let ARES register callable tools and inject live state
into either Hermes or JROS without forking either backend.

RED phase: all tests should FAIL until implementation is written.
"""

from __future__ import annotations

import json
import os
from unittest.mock import MagicMock, patch

import pytest


# ── ARES Runtime Context ──────────────────────────────────────────

class TestRuntimeContext:
    """ares_runtime_context.py: builds a live state packet every turn."""

    def test_module_exports_build_context(self):
        """Module exports build_runtime_context()."""
        from api.ares_runtime_context import build_runtime_context

        assert callable(build_runtime_context)

    def test_build_context_returns_dict(self):
        """build_runtime_context() returns a dict with required keys."""
        from api.ares_runtime_context import build_runtime_context

        ctx = build_runtime_context()
        assert isinstance(ctx, dict)
        # Required keys for ARES operating state
        assert "identity_projection" in ctx
        assert "active_backend" in ctx
        assert "capabilities" in ctx

    def test_identity_is_backend_projection(self):
        """Identity is a backend projection, not an ARES-owned canonical soul."""
        from api.ares_runtime_context import build_runtime_context

        ctx = build_runtime_context()
        assert isinstance(ctx["identity_projection"], dict)
        assert "name" in ctx["identity_projection"]

    def test_backend_hermes_when_jros_down(self):
        """When JROS is unavailable, backend defaults to hermes."""
        from api.ares_runtime_context import build_runtime_context

        with patch(
            "api.ares_runtime_context.is_jros_available",
            return_value=False,
        ):
            ctx = build_runtime_context(backend="hermes")
            assert ctx["active_backend"] == "hermes"
            assert ctx["capabilities"]["jros"]["available"] is False

    def test_backend_hybrid_when_jros_up(self):
        """When JROS is available and backend is hybrid, both show capabilities."""
        from api.ares_runtime_context import build_runtime_context

        with patch(
            "api.ares_runtime_context.is_jros_available",
            return_value=True,
        ):
            ctx = build_runtime_context(backend="hybrid")
            assert ctx["active_backend"] == "hybrid"
            assert ctx["capabilities"]["hermes"]["available"] is True
            assert ctx["capabilities"]["jros"]["available"] is True

    def test_render_context_prompt_compact(self):
        """render_context_prompt() produces a compact text block for injection."""
        from api.ares_runtime_context import (
            build_runtime_context,
            render_context_prompt,
        )

        ctx = build_runtime_context(backend="hermes")
        prompt = render_context_prompt(ctx)
        assert isinstance(prompt, str)
        assert "Projected identity" in prompt
        assert len(prompt) > 0
        # Must be compact — under 500 chars for injection
        assert len(prompt) < 500


# ── ARES Tool Adapter ────────────────────────────────────────────

class TestToolAdapter:
    """ares_tool_adapter.py: registers ARES tools into Hermes or JROS."""

    def test_module_exports_register_ares_tools(self):
        """Module exports register_ares_tools()."""
        from api.ares_tool_adapter import register_ares_tools

        assert callable(register_ares_tools)

    def test_module_exports_ares_tool_definitions(self):
        """Module exports ARES_TOOL_DEFS — the tool catalog."""
        from api.ares_tool_adapter import ARES_TOOL_DEFS

        assert isinstance(ARES_TOOL_DEFS, list)
        assert len(ARES_TOOL_DEFS) > 0

    def test_tool_defs_have_required_fields(self):
        """Each tool def has name, description, args_model, fn."""
        from api.ares_tool_adapter import ARES_TOOL_DEFS

        for tdef in ARES_TOOL_DEFS:
            assert "name" in tdef, f"Tool missing name: {tdef}"
            assert "description" in tdef, f"Tool missing description: {tdef}"
            assert "fn" in tdef, f"Tool missing fn: {tdef}"

    def test_register_into_hermes_mcp_format(self):
        """register_ares_tools produces MCP-compatible tool schemas for Hermes."""
        from api.ares_tool_adapter import register_ares_tools

        schemas = register_ares_tools(target="hermes")
        assert isinstance(schemas, list)
        for schema in schemas:
            assert "name" in schema
            assert "description" in schema
            assert "inputSchema" in schema

    def test_register_into_jros_tooldef_format(self):
        """register_ares_tools produces JROS ToolDef-compatible dicts for JROS."""
        from api.ares_tool_adapter import register_ares_tools

        tooldefs = register_ares_tools(target="jros")
        assert isinstance(tooldefs, list)
        for td in tooldefs:
            assert "name" in td
            assert "description" in td
            assert "args_model" in td
            assert "fn" in td

    def test_unknown_target_raises(self):
        """register_ares_tools raises ValueError for unknown backend target."""
        from api.ares_tool_adapter import register_ares_tools

        with pytest.raises(ValueError, match="Unknown target"):
            register_ares_tools(target="unknown_backend")


# ── ARES Tools (the actual callable tools) ────────────────────────

class TestAresTools:
    """ares_tools.py: the callable ARES-owned tool implementations."""

    def test_module_exports_all_tools(self):
        """Module exports the tool functions."""
        from api.ares_tools import (
            ares_get_runtime_context,
            ares_create_task,
            ares_self_audit,
        )

        assert callable(ares_get_runtime_context)
        assert callable(ares_create_task)
        assert callable(ares_self_audit)

    def test_get_runtime_context_returns_json(self):
        """ares_get_runtime_context returns valid JSON string."""
        from api.ares_tools import ares_get_runtime_context

        result = ares_get_runtime_context()
        parsed = json.loads(result)
        assert isinstance(parsed, dict)
        assert "identity_projection" in parsed

    def test_create_task_returns_confirmation(self):
        """ares_create_task creates a task and returns confirmation."""
        from api.ares_tools import ares_create_task

        result = ares_create_task(
            title="Test task",
            description="A test task",
            priority="medium",
        )
        parsed = json.loads(result)
        assert parsed["status"] == "created"
        assert parsed["title"] == "Test task"

    def test_self_audit_returns_result(self):
        """ares_self_audit returns a structured audit result."""
        from api.ares_tools import ares_self_audit

        result = ares_self_audit(turn_id="test-turn-001")
        parsed = json.loads(result)
        assert "status" in parsed
        assert "checks" in parsed


# ── Integration: Runtime Context injection into streaming ─────────

class TestStreamingIntegration:
    """Runtime context is injectable into the streaming path."""

    def test_context_injectable_into_hermes_prompt(self):
        """Runtime context can be rendered for Hermes ephemeral_system_prompt."""
        from api.ares_runtime_context import (
            build_runtime_context,
            render_context_prompt,
        )

        ctx = build_runtime_context(backend="hermes")
        prompt = render_context_prompt(ctx)
        # Must contain backend designation
        assert "hermes" in prompt.lower()

    def test_context_injectable_into_jros_prompt(self):
        """Runtime context can be rendered for JROS system_prompt."""
        from api.ares_runtime_context import (
            build_runtime_context,
            render_context_prompt,
        )

        ctx = build_runtime_context(backend="jros")
        prompt = render_context_prompt(ctx)
        # Must contain backend designation
        assert "jros" in prompt.lower()

    def test_context_prompt_includes_capabilities(self):
        """Context prompt includes capability summary for both backends."""
        from api.ares_runtime_context import (
            build_runtime_context,
            render_context_prompt,
        )

        # Hermetic: availability is a live JROS gateway health probe now,
        # so pin it instead of depending on the test machine's setup.
        with patch(
            "api.ares_runtime_context.is_jros_available",
            return_value=True,
        ):
            ctx = build_runtime_context(backend="hybrid")
        prompt = render_context_prompt(ctx)
        # In hybrid mode, prompt should mention JROS embodiment
        assert "jros" in prompt.lower()
        # The context dict should have both backends
        assert ctx["capabilities"]["hermes"]["available"] is True
        assert ctx["capabilities"]["jros"]["available"] is True


# ── Route Registration ────────────────────────────────────────────

class TestRouteRegistration:
    """ARES runtime-context and tools routes are registered in routes.py."""

    def test_runtime_context_route_is_registered(self):
        """/api/ares/runtime-context route exists in routes.py."""
        import api.routes as routes_mod
        source = open(routes_mod.__file__).read()
        assert "/api/ares/runtime-context" in source

    def test_tools_route_is_registered(self):
        """/api/ares/tools route exists in routes.py."""
        import api.routes as routes_mod
        source = open(routes_mod.__file__).read()
        assert "/api/ares/tools" in source


# ── Streaming Wiring ──────────────────────────────────────────────

class TestStreamingWiring:
    """Runtime context is wired into streaming.py alongside self-persistence."""

    def test_runtime_context_injection_in_streaming(self):
        """streaming.py imports and calls build_runtime_context."""
        import api.streaming as streaming_mod
        source = open(streaming_mod.__file__).read()
        assert "ares_runtime_context" in source
        assert "build_runtime_context" in source
        assert "render_context_prompt" in source

    def test_runtime_context_prompt_in_merge_order(self):
        """Runtime context is merged after self-persistence in _combined_prompt_parts."""
        import api.streaming as streaming_mod
        source = open(streaming_mod.__file__).read()
        # Self-persistence must come before runtime context
        sp_pos = source.find("_self_persistence_prompt")
        rc_pos = source.find("_runtime_context_prompt")
        assert sp_pos < rc_pos, "Self-persistence must be injected before runtime context"
