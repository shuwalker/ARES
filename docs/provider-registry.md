# External provider registry

ARES owns its WebUI listener and no provider ports. External runtimes such as
Hermes, JaegerAI, OpenClaw, Ollama, and cloud APIs remain independently managed.
ARES connects to them only after an operator explicitly configures or selects
them.

The runtime registry is stored at `~/.ares/providers.json`. Override the path
with `ARES_PROVIDER_REGISTRY_PATH`. A clean installation starts with:

```json
{
  "schema_version": 1,
  "providers": {}
}
```

Each provider entry may contain:

- `enabled`: whether ARES may use the connection.
- `kind`: connection category, normally `runtime`.
- `endpoint`: a complete provider-owned HTTP(S) or WebSocket URL.
- `credential_env`: the name of the environment or keychain-backed credential.
- `capabilities`: operator-visible capabilities.
- `metadata`: non-secret descriptive information.

Secret values are not accepted into the normalized registry. Providers are
available through `/api/ares/providers`; authenticated mutation requests can
create, update, or remove entries. Selecting a healthy runtime through the UI
marks that provider enabled. Selecting “Organizer only” clears the runtime
election.

Provider discovery may report installed software, but discovery does not elect
it. First-run ARES remains `unassigned` until the operator chooses a provider.
