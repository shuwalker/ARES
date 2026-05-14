"""ARES runtime — lifecycle, config, brain backends, and service management.

Modules:
    lifecycle       — Process lifecycle (prepare, bring_up, teardown)
    config          — TOML config loading + AresConfig
    hermes_backend  — Hermes Agent API backend (default brain)
    lilith_backend  — Lilith ZMQ bus backend (stub)
    local_backend   — Direct Ollama backend (air-gapped fallback)
    bootstrap       — Idempotent first-run setup
    session_store   — Volatile session/turn storage
    agent_stack     — Product manifest definition
"""