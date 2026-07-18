"""Coverage for French voices in the transport-neutral Edge allowlist."""

import sys
from types import SimpleNamespace

import pytest

from api.tts_service import TtsServiceError, generate_tts


FRENCH_VOICES = [
    "fr-CA-AntoineNeural",
    "fr-CA-JeanNeural",
    "fr-CA-SylvieNeural",
    "fr-CA-ThierryNeural",
    "fr-FR-DeniseNeural",
    "fr-FR-EloiseNeural",
    "fr-FR-HenriNeural",
]


@pytest.mark.parametrize("voice", FRENCH_VOICES)
def test_french_voice_in_allowlist_reaches_synthesis(monkeypatch, voice):
    captured = {}

    class FakeCommunicate:
        def __init__(self, text, selected_voice, **kwargs):
            captured.update(text=text, voice=selected_voice)

        def stream_sync(self):
            yield {"type": "audio", "data": b"abc"}

    monkeypatch.setitem(sys.modules, "edge_tts", SimpleNamespace(Communicate=FakeCommunicate))
    result = generate_tts({"text": "Bonjour", "voice": voice})
    assert result.content == b"abc"
    assert captured["voice"] == voice


def test_unlisted_french_locale_still_rejected():
    with pytest.raises(TtsServiceError, match="invalid voice") as raised:
        generate_tts({"text": "Bonjour", "voice": "fr-BE-CharlineNeural"})
    assert raised.value.status_code == 400
