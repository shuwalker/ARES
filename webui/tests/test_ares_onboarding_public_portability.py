from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PUBLIC_ONBOARDING_FILES = [
    ROOT / "webui" / "static" / "onboarding.js",
    ROOT / "tools" / "mcp-bootstrap" / "mcp_bootstrap.py",
    ROOT / "tools" / "mcp-bootstrap" / "README.md",
    ROOT / "tools" / "safari-mcp-bootstrap" / "safari_mcp_bootstrap.py",
    ROOT / "tools" / "safari-mcp-bootstrap" / "README.md",
    ROOT / "Sources" / "ARES" / "Views" / "SetupView.swift",
    ROOT / "ARES-Modules" / "Sources" / "ARESModules" / "Extractions" / "sam.md",
    ROOT / "ARES-Modules" / "Sources" / "ARESModules" / "Extractions" / "scarf.md",
    ROOT / "ARES-Modules" / "Sources" / "ARESModules" / "Extractions" / "hermes-desktop.md",
    ROOT / "ARES-Modules" / "Sources" / "ARESModules" / "KnowledgeGraph" / "KnowledgeGraph.swift",
]

FORBIDDEN_PUBLIC_ONBOARDING_STRINGS = [
    "/Users/matthewjenkins",
    "Jenkins_Robotics",
    "100.74.2.15",
    "100.78.245.49",
    "~/GitHub/ARES",
    "my tailnet",
    "my rack",
    "Matthew's setup",
    "Mac Studio",
    "MacStudio",
]


def test_public_onboarding_has_no_personal_hardware_or_path_leaks():
    offenders = []
    for path in PUBLIC_ONBOARDING_FILES:
        text = path.read_text(encoding="utf-8")
        for needle in FORBIDDEN_PUBLIC_ONBOARDING_STRINGS:
            if needle in text:
                offenders.append(f"{path.relative_to(ROOT)} contains {needle!r}")
    assert offenders == []


def test_mcp_filesystem_default_is_current_repo_not_desktop():
    text = (ROOT / "tools" / "mcp-bootstrap" / "mcp_bootstrap.py").read_text(encoding="utf-8")
    assert 'Path(__file__).resolve().parents[2]' in text
    assert 'str(HOME / "Desktop")' not in text


def test_backend_missing_guidance_includes_install_link():
    text = (ROOT / "tools" / "mcp-bootstrap" / "mcp_bootstrap.py").read_text(encoding="utf-8")
    assert "Hermes Agent backend not found" in text
    assert "https://hermes-agent.nousresearch.com/docs" in text
    assert "raw.githubusercontent.com/NousResearch/hermes-agent" in text


def test_web_onboarding_uses_relative_bootstrap_commands_and_backend_language():
    text = (ROOT / "webui" / "static" / "onboarding.js").read_text(encoding="utf-8")
    assert "python3 tools/mcp-bootstrap/mcp_bootstrap.py --catalog --plan" in text
    assert "https://hermes-agent.nousresearch.com/docs" in text
    assert "agent backend" in text
    assert "~/GitHub/ARES" not in text
