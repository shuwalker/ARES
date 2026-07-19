"""Modular FastAPI router registration."""

from fastapi import FastAPI

from .adapters import router as adapters_router
from .analytics import router as analytics_router
from .auth import router as auth_router
from .ares import router as ares_router
from .controls import router as controls_router
from .discovery import router as discovery_router
from .env import router as env_router
from .webhooks import router as webhooks_router
from .secrets import router as secrets_router
from .pairing import router as pairing_router
from .backends import router as backends_router
from .email import router as email_router
from .health import router as health_router
from .interactions import router as interactions_router
from .kanban import router as kanban_router
from .git import legacy_router as legacy_git_router, router as git_router
from .gateway import router as gateway_router
from .hatchery import router as hatchery_router
from .files import router as files_router
from .file_delivery import router as file_delivery_router
from .models import router as models_router
from .notes import router as notes_router
from .maintenance import router as maintenance_router
from .media import router as media_router
from .memory import router as memory_router
from .mcp import router as mcp_router
from .onboarding import router as onboarding_router
from .profiles import router as profiles_router
from .projects import router as projects_router
from .prompts import router as prompts_router
from .providers import router as providers_router
from .schedules import router as schedules_router
from .realtime import router as realtime_router
from .session import router as session_router
from .settings import router as settings_router
from .shares import router as shares_router
from .skills import router as skills_router
from .uploads import router as uploads_router
from .workspaces import router as workspaces_router
from .wiki import router as wiki_router
from .research import router as research_router
from .astronomy import router as astronomy_router
from .sam_conversation import router as sam_conversation_router
from .readiness import router as readiness_router
from .delegation import router as delegation_router

def install_core_routers(application: FastAPI) -> None:
    application.include_router(adapters_router)
    application.include_router(analytics_router)
    application.include_router(health_router)
    application.include_router(interactions_router)
    application.include_router(kanban_router)
    application.include_router(git_router)
    application.include_router(legacy_git_router)
    application.include_router(gateway_router)
    application.include_router(hatchery_router)
    application.include_router(files_router)
    application.include_router(file_delivery_router)
    application.include_router(models_router)
    application.include_router(notes_router)
    application.include_router(maintenance_router)
    application.include_router(media_router)
    application.include_router(memory_router)
    application.include_router(mcp_router)
    application.include_router(auth_router)
    application.include_router(controls_router)
    application.include_router(discovery_router)
    application.include_router(email_router)
    application.include_router(ares_router)
    application.include_router(secrets_router)
    application.include_router(onboarding_router)
    application.include_router(profiles_router)
    application.include_router(projects_router)
    application.include_router(prompts_router)
    application.include_router(providers_router)
    application.include_router(pairing_router)
    application.include_router(schedules_router)
    application.include_router(settings_router)
    application.include_router(env_router)
    application.include_router(shares_router)
    application.include_router(skills_router)
    application.include_router(uploads_router)
    application.include_router(session_router)
    application.include_router(webhooks_router)
    application.include_router(workspaces_router)
    application.include_router(wiki_router)
    application.include_router(backends_router)
    application.include_router(realtime_router)
    application.include_router(research_router)
    application.include_router(astronomy_router)
    application.include_router(sam_conversation_router)
    application.include_router(readiness_router)
    application.include_router(delegation_router)


__all__ = ["install_core_routers"]
