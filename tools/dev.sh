#!/usr/bin/env bash
# Run the split watcher and rojo serve together; Ctrl-C stops both.
set -euo pipefail
cd "$(dirname "$0")/.."

lune run tools/split -- --watch &
SPLIT_PID=$!
trap 'kill "$SPLIT_PID" 2>/dev/null' EXIT

rojo serve
