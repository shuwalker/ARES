#!/bin/bash
# Fix ARES → Hermes connection
# This sets up the HTTP bridge and configures ARES to use it

set -e

echo "🔧 ARES Connection Fixer"
echo ""

# Check if Hermes CLI is available
if ! command -v hermes &> /dev/null; then
    echo "❌ Error: 'hermes' CLI not found."
    echo "   Make sure Hermes is installed and available in PATH."
    exit 1
fi

echo "✓ Hermes CLI found: $(which hermes)"
echo ""

# Create ~/.ares directory structure
echo "📁 Creating ~/.ares directories..."
mkdir -p ~/.ares/config
mkdir -p ~/.ares/logs
echo "✓ Done"
echo ""

# Write config pointing to the bridge
echo "⚙️  Writing ARES config to point to Hermes bridge..."
cat > ~/.ares/config/ares.toml << 'EOF'
# ARES Configuration
# Hermes is accessed via a local HTTP bridge (ares_bridge_minimal.py)
# which wraps the Hermes CLI

[agent]
backend = "hermes"

[agent.hermes]
# Points to ares_bridge_minimal.py running on localhost
api_url = "http://localhost:9876"
api_key = ""

[agent.lilith]
zmq_host = "127.0.0.1"
input_port = 5571
output_port = 5572

[agent.local]
model = "gemma3:12b"
ollama_url = "http://localhost:11434"

[face]
default_style = "blackfire"
intensity = 0.60

[gateway]
host = "127.0.0.1"
port = 7860
EOF
echo "✓ Config written: ~/.ares/config/ares.toml"
echo ""

# Test Hermes CLI
echo "🧪 Testing Hermes CLI..."
if hermes -z "test" &> /dev/null; then
    echo "✓ Hermes CLI responds"
else
    echo "⚠️  Hermes CLI returned an error (may be expected)"
fi
echo ""

# Start the bridge
echo "🌉 Starting Hermes HTTP bridge..."
echo "   (Port: 9876)"
python3 ares/runtime/ares_bridge_minimal.py > ~/.ares/logs/bridge.log 2>&1 &
BRIDGE_PID=$!
echo "✓ Bridge started (PID: $BRIDGE_PID)"
echo ""

# Wait for bridge to start
sleep 2

# Test the bridge
echo "🧪 Testing bridge health..."
if curl -s http://localhost:9876/health | grep -q '"status"'; then
    echo "✓ Bridge is responding at http://localhost:9876"
else
    echo "⚠️  Bridge health check failed"
    echo "   Check logs: tail ~/.ares/logs/bridge.log"
fi
echo ""

# Test ARES
echo "🧪 Testing ARES doctor..."
ares doctor || true
echo ""

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Start ARES daemon: ares start"
echo "  2. Give ARES a goal: ares goal 'show me your status'"
echo "  3. Check logs: ares log -f"
echo ""
echo "⚠️  Important:"
echo "  - The Hermes bridge runs in background (PID: $BRIDGE_PID)"
echo "  - Keep this script running or create a launchd service"
echo "  - See CONNECTION_ISSUES.md for permanent setup"
