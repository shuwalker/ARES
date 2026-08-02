"""Contracts for the repository-wide agent and documentation entrypoints."""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[3]


def _read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_cross_agent_entrypoint_routes_canonical_context():
    entrypoint = _read("AGENTS.md")

    for required in (
        "docs/PRODUCT_SPEC.md",
        "docs/ARCHITECTURE.md",
        "docs/API.md",
        "docs/SECURITY.md",
        "docs/DEVELOPMENT.md",
        "docs/CURRENT_STATE.md",
        "docs/features/si-personalization.md",
    ):
        assert required in entrypoint
        assert (ROOT / required).exists()


def test_tool_specific_context_points_to_shared_entrypoint():
    assert "AGENTS.md" in _read("CLAUDE.md")
    assert "../AGENTS.md" in _read(".claude/FOUNDATION.md")
    assert "AGENTS.md" in _read("apps/macos/CLAUDE.md")
    assert "AGENTS.md" in _read("services/controller/CLAUDE.md")


def test_documentation_router_defines_ownership_and_freshness():
    router = _read("docs/README.md")

    for term in (
        "Canonical documents",
        "Task routing",
        "Feature specifications",
        "Decision records",
        "Freshness rules",
        "Last verified",
        "Source of truth",
    ):
        assert term in router


def test_si_feature_spec_is_actionable_and_honest():
    spec = _read("docs/features/si-personalization.md")

    for key in (
        "local_profile_character",
        "si_cal_verbosity",
        "si_cal_tone",
        "si_cal_support",
        "si_cal_initiative",
        "si_cal_notes",
    ):
        assert key in spec

    assert "partially implemented" in spec.lower()
    assert "Missing: calibration renderer" in spec
    assert "Control Center owns" in spec
    assert "Acceptance criteria" in spec
    assert "services/controller/api/streaming.py" in spec


def test_current_surface_contract_does_not_use_obsolete_foundation_navigation():
    entrypoint = _read("AGENTS.md")
    foundation = _read(".claude/FOUNDATION.md")

    assert "Agent | Engineering | Studio | Life | Library | Control Center" in entrypoint
    assert "Chat | Companion | Self | Workshop | Library | System" not in foundation
    assert "obsolete navigation model" in foundation


def test_agent_onboarding_documents_have_no_broken_relative_links():
    documents = [
        "AGENTS.md",
        "CLAUDE.md",
        "CONTRIBUTING.md",
        "docs/README.md",
        "docs/CURRENT_STATE.md",
        "docs/features/README.md",
        "docs/features/si-personalization.md",
        "apps/web/AGENTS.md",
        "apps/macos/AGENTS.md",
        "services/controller/AGENTS.md",
    ]

    broken: list[str] = []
    for relative in documents:
        document = ROOT / relative
        for raw_target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", document.read_text(encoding="utf-8")):
            target = raw_target.split("#", 1)[0]
            if not target or "://" in target or target.startswith("mailto:"):
                continue
            resolved = (document.parent / target).resolve()
            if not resolved.exists():
                broken.append(f"{relative} -> {raw_target}")

    assert broken == []
