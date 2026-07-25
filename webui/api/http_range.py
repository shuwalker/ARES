"""Single-range HTTP byte serving helpers."""

from __future__ import annotations


def parse_range_header(range_header: str, file_size: int) -> tuple[int, int] | None:
    if not range_header or not range_header.startswith("bytes=") or file_size < 1:
        return None
    spec = range_header.split("=", 1)[1].strip()
    if "," in spec or "-" not in spec:
        return None
    start_text, end_text = spec.split("-", 1)
    try:
        if not start_text:
            suffix = int(end_text)
            if suffix <= 0:
                return None
            start, end = max(0, file_size - suffix), file_size - 1
        else:
            start = int(start_text)
            end = int(end_text) if end_text else file_size - 1
            if start < 0:
                return None
            end = min(end, file_size - 1)
        return (start, end) if start <= end and start < file_size else None
    except ValueError:
        return None


_parse_range_header = parse_range_header


__all__ = ["parse_range_header"]
