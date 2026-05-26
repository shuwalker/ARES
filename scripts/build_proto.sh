#!/usr/bin/env bash
# Regenerate Python protobuf bindings for the ARES IPC schema.
#
# Output: ares/ipc/ares_pb2.py (committed so the daemon runs without protoc).
# Run after editing ares/ipc/ares.proto.

set -euo pipefail

PROTO_DIR="$(cd "$(dirname "$0")/.." && pwd)/ares/ipc"
OUT_DIR="$PROTO_DIR"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not on PATH (install via 'brew install protobuf' or equivalent)" >&2
    exit 1
fi

protoc --proto_path="$PROTO_DIR" --python_out="$OUT_DIR" "$PROTO_DIR/ares.proto"

echo "wrote $OUT_DIR/ares_pb2.py"
