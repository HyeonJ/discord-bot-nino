#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/start-nino.sh"

echo "[keepalive] holding WSL open for Nino"
exec tail -f /dev/null
