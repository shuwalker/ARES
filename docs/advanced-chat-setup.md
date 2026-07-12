# Advanced Chat Setup

This page covers operator-only chat routing options for self-hosted ARES Web UI deployments.

## Hermes Gateway Chat Backend

By default, ARES Web UI runs Hermes Agent in-process. Operators who already run a separate Hermes Gateway can route chat through that gateway instead:

```bash
HERMES_WEBUI_CHAT_BACKEND=gateway
HERMES_API_URL=http://127.0.0.1:8642
HERMES_API_KEY=<shared gateway key>
```

The `gateway_chat` health payload is an operator diagnostic. It is intended for logs, support bundles, and explicit status inspection, and is not currently rendered as a user-facing health banner.

Use this mode when you deliberately manage the agent process separately from the Web UI process. For ordinary single-machine installs, leave the chat backend unset and use the default in-process runtime.

## Approval Runs API

Gateway approval runs are opt-in. Enable them only when your gateway supports the approval-runs endpoints and the Web UI and gateway share the same trust boundary:

```bash
HERMES_WEBUI_GATEWAY_USE_RUNS_API=1
```

Keep the gateway bound to localhost unless it is behind authenticated, private networking such as Tailscale or a reverse proxy you control.
