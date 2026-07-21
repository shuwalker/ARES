# ARES Configuration
# Disable SI pipeline — use direct JROS backend for now

# Environment: set this before starting ARES
# export ARES_SI_ENABLED=false

# In settings.json, add:
# {
#   "si_enabled": false,
#   "default_backend": "jros_local"
# }

# SI Status: DISABLED
# - Keep all code in webui/api/si/ intact
# - Just don't route chat turns through it
# - Direct backend path: chat → JROSBackend → JaegerAI

# To re-enable SI later:
# 1. Set ARES_SI_ENABLED=true
# 2. Or set "si_enabled": true in settings.json
# 3. Restart ARES
