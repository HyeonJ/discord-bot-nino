#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_DIR="${BACKEND_STATUS_DIR:-$BOT_DIR/runtime/backend-status}"

command="${1:-}"
backend="${2:-}"
state="${3:-}"
reason="${4:-}"
until="${5:-}"

usage() {
  echo "Usage:" >&2
  echo "  commands: set|clear|show|list" >&2
  echo "  $0 set <backend> <quota_exhausted|cooldown|maintenance|disabled|ready> [reason] [until_iso]" >&2
  echo "  $0 clear <backend>" >&2
  echo "  $0 show <backend>" >&2
  echo "  $0 list" >&2
}

validate_state() {
  case "$state" in
    quota_exhausted|cooldown|maintenance|disabled|ready) ;;
    *)
      echo "[backend-status] unsupported state: $state" >&2
      usage
      exit 2
      ;;
  esac
}

status_file="$STATUS_DIR/$backend.json"

case "$command" in
  set)
    if [[ -z "$backend" || -z "$state" ]]; then
      usage
      exit 2
    fi
    validate_state
    mkdir -p "$STATUS_DIR"
    cat > "$status_file" <<JSON
{
  "backend": "$backend",
  "state": "$state",
  "reason": "$reason",
  "until": "$until",
  "updated_at": "$(date -Is)"
}
JSON
    echo "$status_file"
    ;;
  clear)
    if [[ -z "$backend" ]]; then
      usage
      exit 2
    fi
    rm -f "$status_file"
    ;;
  show)
    if [[ -z "$backend" ]]; then
      usage
      exit 2
    fi
    if [[ -f "$status_file" ]]; then
      cat "$status_file"
    else
      echo "{\"backend\":\"$backend\",\"state\":\"ready\"}"
    fi
    ;;
  list)
    mkdir -p "$STATUS_DIR"
    find "$STATUS_DIR" -maxdepth 1 -type f -name '*.json' -print | sort
    ;;
  *)
    usage
    exit 2
    ;;
esac
