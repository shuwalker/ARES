"""Parallel FastAPI application for the incremental ARES backend migration."""

from .main import create_app

__all__ = ["create_app"]
