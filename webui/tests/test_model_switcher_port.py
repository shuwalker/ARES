from pathlib import Path


WEBUI_ROOT = Path(__file__).resolve().parents[1]


def test_chat_model_switcher_uses_hermes_mobile_lifecycle():
    ui = (WEBUI_ROOT / "static" / "ui.js").read_text(encoding="utf-8")

    assert "let _modelDropdownHome=null;" in ui
    assert "document.body.appendChild(dd)" in ui
    assert "window.visualViewport" in ui
    assert "_restoreModelDropdownHome();" in ui


def test_chat_model_switcher_has_open_close_motion_and_reduced_motion_fallback():
    css = (WEBUI_ROOT / "static" / "style.css").read_text(encoding="utf-8")

    assert ".model-dropdown.open{opacity:1;visibility:visible" in css
    assert "transform:translateY(8px) scale(.985)" in css
    assert "@media(prefers-reduced-motion:reduce)" in css
    assert ".model-dropdown.model-dropdown--floating" in css
