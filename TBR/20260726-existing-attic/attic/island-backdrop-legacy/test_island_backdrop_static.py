from pathlib import Path


WEBUI_ROOT = Path(__file__).resolve().parents[1]


def test_island_backdrop_is_optional_and_enabled_by_default():
    index = (WEBUI_ROOT / "static" / "index.html").read_text(encoding="utf-8")
    script = (WEBUI_ROOT / "static" / "background_manager.js").read_text(
        encoding="utf-8"
    )
    styles = (WEBUI_ROOT / "static" / "custom_backgrounds.css").read_text(
        encoding="utf-8"
    )
    main_styles = (WEBUI_ROOT / "static" / "style.css").read_text(encoding="utf-8")

    assert 'id="islandBackdropEnabled" checked' in index
    assert "islandBackdropSection" in index
    assert "ares-island-backdrop" in script
    assert "enabled:true" in script or "enabled: true" in script
    assert "island-backdrop-enabled" in styles
    assert 'url("assets/ares-island-wide.png")' in styles
    # Chat watermark path must be relative to /static/style.css
    assert 'url("assets/ares-island-wide.png")' in main_styles
    assert 'url("static/assets/ares-island-wide.png")' not in main_styles


def test_island_backdrop_beats_opaque_skins_and_covers_shell():
    styles = (WEBUI_ROOT / "static" / "custom_backgrounds.css").read_text(
        encoding="utf-8"
    )

    # Higher specificity than :root[data-skin=…] .main
    assert "html body.island-backdrop-enabled" in styles
    # Fixed layer so the art is not painted only on body under opaque children
    assert "position: fixed" in styles or "position:fixed" in styles
    # Major shell surfaces used by every tab
    for selector_fragment in (
        ".main",
        ".main-view",
        ".sidebar",
        ".rail",
        ".composer-wrap",
        "#mainChat",
    ):
        assert selector_fragment in styles


def test_island_backdrop_does_not_force_a_background_on_every_element():
    styles = (WEBUI_ROOT / "static" / "custom_backgrounds.css").read_text(
        encoding="utf-8"
    )

    assert "body *" not in styles
    assert "div[class*=" not in styles


def test_island_early_boot_script_present():
    index = (WEBUI_ROOT / "static" / "index.html").read_text(encoding="utf-8")
    assert "ares-island-backdrop" in index
    assert "island-backdrop-enabled" in index
    assert "island-backdrop-pending" in index
