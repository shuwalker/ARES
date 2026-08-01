"""SI calibration preference keys — defaults, validation, persistence."""

from __future__ import annotations

from api.config import _SETTINGS_DEFAULTS, _SETTINGS_ENUM_VALUES, load_settings, save_settings


def test_si_calibration_defaults_exist():
    assert _SETTINGS_DEFAULTS["si_cal_verbosity"] == "balanced"
    assert _SETTINGS_DEFAULTS["si_cal_tone"] == "balanced"
    assert _SETTINGS_DEFAULTS["si_cal_support"] == "balanced"
    assert _SETTINGS_DEFAULTS["si_cal_initiative"] == "balanced"
    assert _SETTINGS_DEFAULTS["si_cal_notes"] == ""


def test_si_calibration_enum_values():
    assert _SETTINGS_ENUM_VALUES["si_cal_verbosity"] == {"concise", "balanced", "explanatory"}
    assert _SETTINGS_ENUM_VALUES["si_cal_tone"] == {"direct", "balanced", "conversational"}
    assert _SETTINGS_ENUM_VALUES["si_cal_support"] == {"supportive", "balanced", "challenging"}
    assert _SETTINGS_ENUM_VALUES["si_cal_initiative"] == {"reactive", "balanced", "proactive"}


def test_si_calibration_persists_valid_values(tmp_path, monkeypatch):
    settings_file = tmp_path / "settings.json"
    monkeypatch.setattr("api.config.SETTINGS_FILE", settings_file)

    saved = save_settings(
        {
            "si_cal_verbosity": "concise",
            "si_cal_tone": "direct",
            "si_cal_support": "challenging",
            "si_cal_initiative": "proactive",
            "si_cal_notes": "Give me the result first, then details.",
        }
    )
    assert saved["si_cal_verbosity"] == "concise"
    assert saved["si_cal_tone"] == "direct"
    assert saved["si_cal_support"] == "challenging"
    assert saved["si_cal_initiative"] == "proactive"
    assert saved["si_cal_notes"] == "Give me the result first, then details."

    reloaded = load_settings()
    assert reloaded["si_cal_verbosity"] == "concise"
    assert reloaded["si_cal_tone"] == "direct"
    assert reloaded["si_cal_notes"] == "Give me the result first, then details."


def test_si_calibration_rejects_invalid_enum(tmp_path, monkeypatch):
    settings_file = tmp_path / "settings.json"
    monkeypatch.setattr("api.config.SETTINGS_FILE", settings_file)
    save_settings({"si_cal_verbosity": "concise"})
    # Invalid enum is ignored — previous valid value remains.
    saved = save_settings({"si_cal_verbosity": "not-a-real-value"})
    assert saved["si_cal_verbosity"] == "concise"


def test_si_calibration_notes_max_length(tmp_path, monkeypatch):
    settings_file = tmp_path / "settings.json"
    monkeypatch.setattr("api.config.SETTINGS_FILE", settings_file)
    save_settings({"si_cal_notes": "ok"})
    too_long = "x" * 2001
    saved = save_settings({"si_cal_notes": too_long})
    assert saved["si_cal_notes"] == "ok"
