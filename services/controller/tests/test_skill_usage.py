"""Tests for api/skill_usage.py — .usage.json reader.

Covers:
  - read_skill_usage with various .usage.json states
  - GET /api/skills/usage route presence (read-only, agent writes the file)
"""

import json
import inspect

from api.skill_usage import read_skill_usage

class TestReadSkillUsage:
    def test_read_empty(self, tmp_path):
        """File does not exist -> returns {}."""
        assert read_skill_usage(tmp_path) == {}

    def test_read_valid(self, tmp_path):
        """Well-formed .usage.json with nested entries is returned as-is."""
        data = {
            "research-arxiv": {"use_count": 12, "view_count": 5},
            "ares-agent": {"use_count": 8, "view_count": 3},
        }
        (tmp_path / ".usage.json").write_text(json.dumps(data), encoding="utf-8")
        assert read_skill_usage(tmp_path) == data

    def test_read_agent_format(self, tmp_path):
        """Agent-side format (ISO timestamps) is accepted."""
        data = {
            "dev-workflow": {
                "use_count": 77,
                "view_count": 77,
                "last_used_at": "2024-04-05T20:54:38Z",
                "state": "active",
            },
        }
        (tmp_path / ".usage.json").write_text(json.dumps(data), encoding="utf-8")
        assert read_skill_usage(tmp_path) == data

    def test_read_corrupt_json(self, tmp_path):
        """Corrupt JSON returns {} without raising."""
        (tmp_path / ".usage.json").write_text("not json", encoding="utf-8")
        assert read_skill_usage(tmp_path) == {}

    def test_read_wrong_type(self, tmp_path):
        """Non-dict top-level value returns {}."""
        (tmp_path / ".usage.json").write_text("42", encoding="utf-8")
        assert read_skill_usage(tmp_path) == {}


class TestApiSkillsUsageRoute:
    def test_route_handler_present(self):
        """The modular FastAPI router exposes GET /api/skills/usage."""
        from fastapi_app.routers.skills import router

        routes = {(method, route.path) for route in router.routes for method in route.methods}
        assert ("GET", "/api/skills/usage") in routes

    def test_route_returns_usage_structure(self):
        """The route response shape includes usage/skill_names/total_invocations."""
        from api.skills_store import skill_usage

        block = inspect.getsource(skill_usage)
        assert '"usage"' in block and '"skill_names"' in block, "Missing usage or skill_names in response"
        assert '"total_invocations"' in block and '"unique_skills_used"' in block, "Missing total_invocations or unique_skills_used"
