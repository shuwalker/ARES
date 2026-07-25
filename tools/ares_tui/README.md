# ARES TUI (Jaeger method)

Single-file Companion terminal client. Same idea as Jaeger’s `jros_client`:

| Jaeger | ARES TUI |
|--------|----------|
| One stdlib client file | `ares_tui.py` |
| Spawns `jaeger bridge` | Talks to existing WebUI controller (`:8787`) |
| `turn(text)` → reply | `AresClient.turn(text)` → Companion reply |
| No embedded LLM | SI + worker adapters live in the controller |

## Run

```bash
# from repo
python3 tools/ares_tui/ares_tui.py

# or via ares CLI
ares tui
ares tui --worker claude_local
ares tui -q "Who are you?"
```

Requires the ARES controller running (`com.ares.webui` / `./start.sh`).

## Commands in the TUI

- `/status` — health, SI flag, session  
- `/worker hermes_local` — switch adapter  
- `/session` — session id  
- `/quit` — exit  

## Roadmap

v1 = Jaeger-method bridge + chat.  
Later: full Fallout / Aliens CRT dashboard (panels, connections, logs).
