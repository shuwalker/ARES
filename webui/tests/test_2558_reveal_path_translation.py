"""Tests for issue #2558 -- container path translation for Reveal in File Manager.

Pins that _handle_file_reveal applies the same container_path_prefix /
host_path_prefix substitution used by _handle_file_open_vscode.
"""
from __future__ import annotations

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILE_OPERATIONS = ROOT / "api" / "file_operations.py"


class TestRevealPathTranslation:
    def test_handler_supports_path_prefix_mapping(self):
        """_handle_file_reveal must contain container_path_prefix / host_path_prefix
        so Docker users get the same path translation as _handle_file_open_vscode."""
        src = FILE_OPERATIONS.read_text(encoding="utf-8")
        m = re.search(
            r"def _translated_desktop_path\(.*?(?=\ndef )",
            src,
            re.DOTALL,
        )
        assert m, "_translated_desktop_path not found"
        body = m.group(0)
        assert "container_path_prefix" in body
        assert "host_path_prefix" in body

    def test_handler_uses_translated_path_in_subprocess(self):
        """The subprocess dispatch must use the translated string, not str(target)."""
        src = FILE_OPERATIONS.read_text(encoding="utf-8")
        m = re.search(
            r"def reveal_file\(.*?(?=\ndef )",
            src,
            re.DOTALL,
        )
        assert m
        body = m.group(0)
        assert "target_path, _vscode = _translated_desktop_path(target)" in body
        assert '["open", "-R", target_path]' in body
        assert '["explorer.exe", "/select," + target_path]' in body
