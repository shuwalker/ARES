#!/usr/bin/env python3
"""ARES Relay — direct LAN message bridge between ARES v1 (WSL) and Hermes (Mac)."""

import socket
import json
import sys
import os
import datetime

PORT = 9500
HOST = "0.0.0.0"
LOG_PATH = "/Users/matthewjenkins/ares_relay.log"

def log(msg):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")
    print(line, flush=True)

def handle(conn, addr):
    try:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\n" in data:
                break
        if not data:
            return

        payload = json.loads(data.decode("utf-8").strip())
        sender = payload.get("from", "unknown")
        body = payload.get("message", "")
        log(f"FROM {sender} ({addr[0]}): {body}")

        # ACK
        conn.sendall(json.dumps({"status": "received", "by": "Hermes Mac Studio"}).encode() + b"\n")

    except json.JSONDecodeError as e:
        log(f"BAD JSON from {addr}: {e}")
        conn.sendall(json.dumps({"status": "error", "reason": "invalid json"}).encode() + b"\n")
    except Exception as e:
        log(f"ERROR from {addr}: {e}")
    finally:
        conn.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen(5)
    log(f"ARES Relay listening on {HOST}:{PORT}")
    log(f"Log: {LOG_PATH}")

    while True:
        try:
            conn, addr = s.accept()
            handle(conn, addr)
        except KeyboardInterrupt:
            log("Shutting down.")
            break
        except Exception as e:
            log(f"Accept error: {e}")

if __name__ == "__main__":
    main()
