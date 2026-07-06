# Docker deployment

ARES retains the upstream Hermes Web UI container definitions for users who need isolated deployments. Review the compose file before use and set password authentication before exposing a port beyond loopback.

## Production image security model

The production image performs startup preparation as `root`, then runs the WebUI as `hermeswebui`. It does not provide passwordless sudo to the application user. Treat this as a single-tenant application boundary, not a multi-tenant security sandbox.

## API base URL set to localhost fails from Docker

Inside a container, `localhost` means *that container*, not the Docker host. On Docker Desktop use `host.docker.internal`; Podman commonly provides `host.containers.internal`. Linux Docker may require an `extra_hosts` entry mapping `host.docker.internal` to `host-gateway`.

## Host paths and sudo

Running compose through `sudo` often changes `$HOME` to `/root`, so `${HERMES_HOME:-${HOME}/.hermes}` becomes `/root/.hermes`. Set `HERMES_HOME=/home/youruser/.hermes`, then inspect the resolved mounts with `docker compose config`.

## Upgrading the agent container

The `hermes-agent-src` volume caches the agent source. When upgrading the agent image, stop the stack and remove that volume before recreating it:

```bash
docker compose down
docker volume rm hermes-agent-src
docker compose up -d
```

## What the multi-container setup isolates

The multi-container deployment separates processes, networks, and resource limits. Shared bind mounts and named volumes mean it does not provide complete filesystem isolation.

## Related issues

Upstream background and diagnostics: #681, #858, #1389, #1399, #1416, #2453, #3006, and #3012. Podman 3.4 or unusual multi-architecture hosts can use the community `sunnysktsang/hermes-suite` image as an alternative.
