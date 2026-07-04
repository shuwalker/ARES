from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INDEX = (ROOT / "static" / "index.html").read_text(encoding="utf-8")
WORKSPACE_JS = (ROOT / "static" / "workspace.js").read_text(encoding="utf-8")
STYLE = (ROOT / "static" / "style.css").read_text(encoding="utf-8")


def _function_body(src: str, name: str) -> str:
    start = src.index(f"function {name}(")
    brace = src.index("{", start)
    depth = 0
    in_string = ""
    escape = False
    for idx in range(brace, len(src)):
        ch = src[idx]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == in_string:
                in_string = ""
            continue
        if ch in "'\"`":
            in_string = ch
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return src[start : idx + 1]
    raise AssertionError(f"{name} body did not close")


def test_preview_toolbar_has_copy_file_path_button():
    assert 'id="btnCopyPreviewPath"' in INDEX
    assert 'onclick="copyPreviewFilePath()"' in INDEX
    assert 'data-i18n="copy_file_path"' in INDEX
    assert "Copy file path" in INDEX


def test_preview_copy_file_path_uses_server_resolved_current_preview_path():
    body = _function_body(WORKSPACE_JS, "copyPreviewFilePath")
    assert "if(!_previewCurrentPath||!S.session) return;" in body
    assert "api('/api/file/path'" in body
    assert "session_id:S.session.session_id" in body
    assert "path:_previewCurrentPath" in body
    assert "const abs=(r&&r.path)||_previewCurrentPath" in body


def test_preview_copy_file_path_reuses_clipboard_fallback_and_toasts():
    body = _function_body(WORKSPACE_JS, "copyPreviewFilePath")
    assert "typeof _copyTextWithFallback==='function'" in body
    assert "_copyTextWithFallback(abs,t('path_copied'),t('path_copy_failed'))" in body
    assert "navigator.clipboard.writeText(abs)" in body
    assert "document.execCommand('copy')" in body
    assert "t('path_copied')" in body
    assert "t('path_copy_failed')" in body


def test_preview_toolbar_keeps_copy_button_from_shrinking_path_layout():
    assert ".preview-path #btnCopyPreviewPath" in STYLE
    selector_start = STYLE.index(".preview-path #btnCopyPreviewPath")
    selector_block = STYLE[selector_start : STYLE.index("}", selector_start) + 1]
    assert "flex-shrink:0" in selector_block
    assert "white-space:nowrap" in selector_block
