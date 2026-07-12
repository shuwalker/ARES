# CLAUDE.md — Web UI Specific Rules

This file applies to all work inside the `webui/` directory.

## Server Entry Point

- The main server is `webui/server.py`.
- It must remain self-contained and runnable after `pip install -r requirements.txt`.

## Dependencies

- Keep `requirements.txt` minimal.
- Optional dependencies (edge-tts, psutil, etc.) must stay optional and clearly documented.
- Do not add heavy ML/model dependencies directly to the WebUI shell. Prefer adapter boundaries to full frameworks (Hermes/JROS) or explicit ARES-native services.

## Onboarding & Setup Flow

- The onboarding wizard lives in `webui/static/onboarding.js`.
- All onboarding changes must support public, portable installs. Runtime-specific paths, network values, and framework locations must be detected, configured through environment variables/settings, or user-selected.
- Never hardcode maintainer-specific paths or clone layouts in WebUI source. For JROS, use `ARES_JROS_DIR` for source-checkout features and `ARES_JAEGER_HOME` / `JAEGER_HOME` for installed runtime discovery. `~/GitHub/...`, maintainer usernames, private volumes, and real Tailscale IPs are not allowed in production code.
- New steps must be added thoughtfully and tested against a fresh clone scenario.

## API Development

- All new routes go in `webui/api/`.
- Every new endpoint must include proper owner-scope and authentication checks.
- Follow the existing patterns in `routes.py` and other api files.

## Frontend Rules

- Use the existing CSS variables and styling system.
- Do not introduce new major frameworks without discussion.
- All new JavaScript must be compatible with the current hot-reload setup.

## Testing

- New features should include at least basic test coverage in `webui/tests/`.
- Onboarding changes must be verified against the public portability test (`test_ares_onboarding_public_portability.py`).

## Hot Reload

- Preserve and improve the behavior when `ARES_WEBUI_RELOAD=1` is set.
- Changes to Python files should trigger automatic restart within ~2 seconds.

## Framework, Provider & Model Handling

- Hermes and JROS are peer full agentic frameworks behind ARES. Do not describe Hermes as the real backend or JROS as merely the body/accessory.
- Backend mode (`hermes`, `jros`, `hybrid`, or future ARES-native modes) is runtime/framework selection. Model/provider selection is separate and must stay real-provider based; never add fake `model="jros"` or `model_provider="jros"`.
- ARES WebUI is the UX/product layer: natural human request → ARES maps intent to framework/provider/tool calls → UI presents the result.
- Hybrid is first-class. A turn may use Hermes, JROS, and ARES-native automation together when that best satisfies the user intent.
- New provider integrations must follow the existing endpoint resolver/provider-sync pattern and remain portable.
- Before claiming a WebUI backend/provider change is done, run a changed-file scan for `/Users/`, `~/GitHub`, private volume names, real Tailscale IPs, and Matthew-specific strings. Explicit regression tests may contain forbidden examples; production code may not.

Do not modify anything outside `webui/` unless explicitly instructed.