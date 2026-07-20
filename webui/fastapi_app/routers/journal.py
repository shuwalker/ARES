"""
ARES Journal API — conversation search and volume scanning endpoints.
"""

import os
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Query

from ..request_context import RequestIdentity, require_identity

router = APIRouter(prefix="/api/journal", tags=["journal"])


@router.get("/stats")
def journal_stats():
    """Get journal import statistics."""
    from .schema import stats
    return stats()


@router.get("/search")
def journal_search(
    q: str = Query(..., description="Search query"),
    source: Optional[str] = Query(None, description="Filter by source (hermes, claude_code, grok, codex, gemini, sam)"),
    limit: int = Query(20, ge=1, le=100),
):
    """Full-text search across all imported conversations."""
    from .schema import search
    results = search(q, source=source, limit=limit)
    return {"results": results, "count": len(results)}


@router.get("/conversations")
def journal_conversations(
    source: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
):
    """List conversations, most recently updated first."""
    from .schema import list_conversations
    return {"conversations": list_conversations(source=source, limit=limit)}


@router.get("/conversations/{conversation_id}")
def journal_conversation(conversation_id: int):
    """Get a conversation with all its messages."""
    from .schema import get_conversation
    result = get_conversation(conversation_id)
    if not result:
        from ..errors import CoreApiError
        raise CoreApiError(404, f"Conversation {conversation_id} not found")
    return result


@router.post("/import")
def journal_import(
    source: Optional[str] = Query(None, description="Specific source to import, or all if omitted"),
):
    """Run the conversation importer for one or all sources."""
    from .import_all import import_all
    results = import_all(sources=[source] if source else None)
    return {"results": results}


@router.get("/volumes")
def journal_volumes():
    """List all currently mounted volumes."""
    from .volume_scanner import list_volumes
    return {"volumes": list_volumes()}


@router.post("/volumes/mount")
def journal_mount_volume(
    server: str = Query(..., description="SMB server hostname or IP"),
    share: str = Query(..., description="Share name"),
    username: Optional[str] = Query(None),
):
    """Mount an SMB share."""
    from .volume_scanner import mount_smb
    return mount_smb(server, share, username=username)


@router.post("/volumes/unmount")
def journal_unmount_volume(
    path: str = Query(..., description="Volume mount path to unmount"),
):
    """Unmount a volume."""
    from .volume_scanner import unmount
    return unmount(path)


@router.get("/volumes/scan")
def journal_scan_volume(
    path: str = Query("/Volumes/Jenkins_Robotics", description="Volume path to scan"),
):
    """Scan a mounted volume for conversation data sources."""
    from .volume_scanner import scan_volume
    return scan_volume(path)