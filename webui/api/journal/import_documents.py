"""
ARES Journal — Document scanner.

Scans directories for planning, evaluation, and architecture documents (.md, .txt, .json, .yaml)
and imports them into the journal for unified search.

Uses platform-agnostic path discovery from paths.py. No hardcoded user directories.
"""

import os
import re
import time
from pathlib import Path
from typing import Optional

from .paths import document_scan_dirs
from .schema import get_db, init_db

# File patterns to scan
SCAN_EXTENSIONS = {".md", ".txt", ".json", ".yaml", ".yml", ".toml"}

# Directories to skip (noise, not planning docs)
SKIP_DIRS = {
    "node_modules", ".venv", "venv", "__pycache__", ".git", ".build",
    "dist", ".pytest_cache", ".next", "attic", "trash", "archive",
    ".codex", ".claude",  # conversation data, handled by conversation importers
}

# Maximum file size to import (1MB text)
MAX_FILE_SIZE = 1_000_000


def _extract_title(content: str, file_path: str) -> str:
    """Extract title from first heading or filename."""
    # Try first markdown heading
    for line in content.split("\n")[:10]:
        line = line.strip()
        if line.startswith("# "):
            return line[2:].strip()
        if line.startswith("## "):
            return line[3:].strip()

    # Fall back to filename without extension
    return Path(file_path).stem


def _detect_source(file_path: str) -> str:
    """Guess which AI tool produced this document based on its location."""
    fp = str(file_path)
    if ".hermes" in fp or "plans" in fp:
        return "hermes"
    if ".claude" in fp:
        return "claude"
    if ".gemini" in fp or "antigravity" in fp:
        return "gemini"
    if ".codex" in fp:
        return "codex"
    if "CLAUDE.md" in fp or "AGENTS.md" in fp or "DESIGN.md" in fp or "ROADMAP.md" in fp:
        return "claude"
    if "docs/" in fp or "README" in fp:
        return "repo"
    return "manual"


def scan_documents(scan_paths: Optional[list[Path]] = None, source: Optional[str] = None) -> dict:
    """
    Scan directories for documents and import them into the journal.

    Args:
        scan_paths: Directories to scan. If None, uses document_scan_dirs() + ARES_REPO/docs.
        source: Only import documents from this source. If None, import all.

    Returns:
        Dict with import statistics.
    """
    if scan_paths is None:
        scan_paths = document_scan_dirs()

    db = init_db()
    docs_imported = 0
    docs_skipped = 0
    docs_errored = 0

    for scan_dir in scan_paths:
        if not scan_dir.exists():
            continue

        for root, dirs, files in os.walk(scan_dir):
            # Skip noise directories
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]

            for filename in files:
                file_path = Path(root) / filename
                ext = file_path.suffix.lower()

                if ext not in SCAN_EXTENSIONS:
                    continue

                # Skip large files
                try:
                    if file_path.stat().st_size > MAX_FILE_SIZE:
                        docs_skipped += 1
                        continue
                except OSError:
                    continue

                # Detect source
                doc_source = _detect_source(str(file_path))
                if source and doc_source != source:
                    continue

                # Read content
                try:
                    content = file_path.read_text(errors="replace")
                except Exception:
                    docs_errored += 1
                    continue

                title = _extract_title(content, str(file_path))
                mtime = file_path.stat().st_mtime

                # Upsert into documents table
                try:
                    db.execute(
                        """INSERT OR REPLACE INTO documents
                           (source, title, file_path, content, file_type, created_at, imported_at, metadata)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            doc_source,
                            title,
                            str(file_path),
                            content[:500000],  # Cap at 500KB per doc
                            ext.lstrip("."),
                            mtime,
                            time.time(),
                            "{}",
                        ),
                    )
                    docs_imported += 1
                except Exception:
                    docs_errored += 1

    db.commit()
    return {
        "imported": docs_imported,
        "skipped": docs_skipped,
        "errored": docs_errored,
    }