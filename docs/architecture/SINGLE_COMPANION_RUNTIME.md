# ARES single-Companion runtime contract

ARES is the product surface. JaegerAI is the sole Companion runtime. Hermes is
an optional managed task worker; it is not a peer conversational identity.

## Invariants

1. One configured Companion instance has at most one live JaegerAI runtime and
   one loaded model.
2. Every ARES surface connects to that runtime; a surface never starts another
   agent process.
3. JaegerAI owns identity, conversation, memory, persona, model, permissions,
   and the final response to the user.
4. Hermes may receive bounded tasks and return structured progress/results. It
   never silently receives the primary conversation.
5. A Web UI control is enabled only when its action is implemented by the
   active Companion runtime. A selector may not merely save display metadata.
6. Standalone JaegerAI and Hermes interfaces are diagnostics/development
   surfaces, not equal destinations in the normal ARES navigation.

## Migration compatibility

Existing `ares_backend: hermes|hybrid` and per-session backend values are read
as legacy data but normalize to `jros`. They must not change turn ownership.
The compatibility names remain temporarily so old sessions can load while the
peer-backend UI and write endpoints are removed.

## Runtime seam

The first migration slice removes process-spawning terminal tabs and fixes
turn ownership to JaegerAI. The next slice replaces WebUI-owned `jaeger bridge`
children with a supervised, attachable runtime service. Until that service is
ready, the cached local bridge is the only allowed owner of the Companion
process and other ARES surfaces must not start the same instance.

