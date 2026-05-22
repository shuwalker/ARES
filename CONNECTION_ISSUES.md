# ARES Connection Issues — Analysis & Fixes

## Issues Found & Fixed

### ✅ Fixed
1. **cli.py:168** — `cfg.llm.cloud_api_key` doesn't exist
   - Removed invalid config reference, using `ANTHROPIC_API_KEY` env var instead
   
2. **cli.py:811** — `ares_base` undefined variable  
   - Fixed to use `paths["socket"]` from config

### 🔴 Remaining Issues

#### 1. **Architecture Mismatch: SSH vs HTTP API**
   - **Original hermes-desktop**: Connects via SSH to remote Hermes hosts
   - **Your ARES**: Configured to use HTTP API on `localhost:8321`
   
   **Impact**: ARES cannot connect to original hermes-desktop infrastructure
   
   **Solution Options**:
   ```
   Option A: Run the Hermes HTTP bridge locally
   - ARES has ares_bridge_minimal.py that wraps Hermes CLI as HTTP
   - This allows ARES HTTP client → Hermes CLI calls
   - Bridge runs on port 9876 or 8321 (adjust config)
   
   Option B: Diverge completely from hermes-desktop
   - Keep ARES as standalone (already partially done)
   - Use Hermes as a backend service, not integrate with desktop app
   - Update config defaults to match your actual Hermes setup
   ```

#### 2. **Missing Hermes Service Dependency**
   - CLAUDE.md says "Hermes is one reasoning engine inside ARES"
   - Config defaults to `http://localhost:8321` (Hermes API)
   - But no instructions for starting Hermes in that mode
   
   **Current setup**:
   - Hermes lives in `~/.hermes/` (separate repo)
   - Runs as CLI: `hermes -z "message"`
   - No native HTTP API (needs the bridge)
   
   **Fix**: 
   ```toml
   # Update ~/.ares/config/ares.toml
   [agent]
   backend = "hermes"
   
   [agent.hermes]
   api_url = "http://localhost:9876"  # ares_bridge_minimal.py
   api_key = ""
   ```

#### 3. **Config Defaults Point to Non-Existent Services**
   - MCP server URLs defined but no services described:
     - `mcp_perception_url = "http://localhost:9512"`
     - `mcp_voice_url = "http://localhost:9513"`
     - `mcp_avatar_url = "http://localhost:9514"`
     - `mcp_mac_url = "http://localhost:9501"`
   
   **Impact**: ARES will fail silently when trying to use these features
   
   **Fix**: Document which are implemented vs. planned

#### 4. **No Setup Instructions for Bridge**
   - `ares_bridge_minimal.py` exists but isn't automatically started
   - No launchd service for the bridge
   - No documentation on how to wire it up
   
   **Fix**: Create `ares_bridge.plist` for launchd auto-start

---

## Recommended Next Steps

### **Immediate** (to unblock basic functionality)
1. Start the Hermes bridge: 
   ```bash
   python3 ares/runtime/ares_bridge_minimal.py &
   ```
   
2. Update config to point to bridge:
   ```bash
   cat > ~/.ares/config/ares.toml << 'EOF'
   [agent]
   backend = "hermes"
   
   [agent.hermes]
   api_url = "http://localhost:9876"
   api_key = ""
   EOF
   ```

3. Test: `ares doctor` should now show Hermes as connected

### **Soon** (for production use)
1. Create `com.ares.hermes-bridge.plist` for launchd auto-start
2. Update CLAUDE.md to clarify Hermes is wrapped, not integrated
3. Document MCP server expectations (which are real vs. future)
4. Create setup guide explaining the architecture

### **Later** (architectural decisions)
1. Decide: Keep Hermes as external service, or bake it in?
2. Implement actual MCP servers for perception/voice/avatar
3. Remove hermes-desktop integration (or formalize it)

---

## Current Architecture

```
ARES (Python daemon)
  └─ HermesBackend (HTTP client)
       └─ ares_bridge_minimal.py (HTTP server)
            └─ hermes CLI (actual reasoning)
```

This is **different** from hermes-desktop (which uses SSH), but it works for local ARES.
