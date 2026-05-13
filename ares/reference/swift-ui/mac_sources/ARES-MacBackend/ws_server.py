#!/usr/bin/env python3
"""ARES WebSocket server — pushes state to iPad in real-time."""
import asyncio
import json
import logging
import time
from pathlib import Path
import websockets

HOME = Path.home()
LOG_DIR = HOME / "Library/Logs/ARES-Mac"
LOG_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_DIR / "websocket.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("ares.ws")

# Connected iPad clients
clients = set()

async def handler(websocket):
    """Handle a new iPad connection."""
    clients.add(websocket)
    logger.info(f"iPad connected ({len(clients)} total)")
    try:
        # Send initial state
        await websocket.send(json.dumps({
            "type": "state",
            "face": "idle",
            "expression": "calm",
            "style": "toon",
            "timestamp": time.time()
        }))
        
        # Listen for messages from iPad
        async for message in websocket:
            data = json.loads(message)
            msg_type = data.get("type")
            
            if msg_type == "ping":
                await websocket.send(json.dumps({"type": "pong"}))
            elif msg_type == "style_change":
                style = data.get("style", "toon")
                # Broadcast style change to all clients
                broadcast = json.dumps({
                    "type": "style_update",
                    "style": style,
                    "timestamp": time.time()
                })
                for client in clients.copy():
                    try:
                        await client.send(broadcast)
                    except:
                        clients.discard(client)
            elif msg_type == "command":
                text = data.get("text", "")
                logger.info(f"iPad command: {text}")
                # Route to Hermes via backend API
                import urllib.request
                req = urllib.request.Request(
                    "http://127.0.0.1:9876/think",
                    data=json.dumps({"text": text}).encode(),
                    headers={"Content-Type": "application/json"}
                )
                response = urllib.request.urlopen(req).read()
                resp_data = json.loads(response)
                
                # Send response back
                await websocket.send(json.dumps({
                    "type": "response",
                    "text": resp_data.get("text", ""),
                    "face": "speaking",
                    "audio": resp_data.get("audio", ""),
                    "timestamp": time.time()
                }))
    except websockets.exceptions.ConnectionClosed:
        logger.info("iPad disconnected")
    finally:
        clients.discard(websocket)

async def broadcast_state(state_data: dict):
    """Send state update to all connected iPads."""
    if not clients:
        return
    message = json.dumps({
        **state_data,
        "timestamp": time.time()
    })
    for client in clients.copy():
        try:
            await client.send(message)
        except:
            clients.discard(client)

async def main():
    # Read checkpoint for initial state
    cp_path = HOME / ".ares" / "consciousness" / "checkpoint.json"
    if cp_path.exists():
        try:
            cp = json.loads(cp_path.read_text())
            logger.info(f"Restored checkpoint: {cp.get('currentState', 'unknown')}")
        except:
            pass
    
    logger.info("WebSocket server starting on ws://0.0.0.0:9877")
    async with websockets.serve(handler, "0.0.0.0", 9877):
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    asyncio.run(main())
