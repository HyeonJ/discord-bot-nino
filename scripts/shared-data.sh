#!/usr/bin/env bash
set -euo pipefail

SHARED_DATA_DIR="${SHARED_DATA_DIR:-/home/bpx27/yaksu-shared-data}"
command="${1:-}"
file="${2:-}"

usage() {
  echo "Usage:" >&2
  echo "  $0 read <todo-list.md|shopping-list.md|pantry.md|purchase-history.md>" >&2
  echo "  $0 write <file> <content> [commit message]" >&2
  echo "  $0 append <file> <content> [commit message]" >&2
}

validate_file() {
  case "$file" in
    todo-list.md|shopping-list.md|pantry.md|purchase-history.md)
      ;;
    *)
      echo "[shared-data] unsupported file: $file" >&2
      usage
      exit 2
      ;;
  esac
}

require_repo() {
  if [[ ! -d "$SHARED_DATA_DIR/.git" ]]; then
    echo "[shared-data] not a git repo: $SHARED_DATA_DIR" >&2
    exit 1
  fi
}

sync_before() {
  git -C "$SHARED_DATA_DIR" pull --rebase
}

commit_and_push() {
  local message="${1:-Update $file}"
  git -C "$SHARED_DATA_DIR" add -- "$file"
  if git -C "$SHARED_DATA_DIR" diff --cached --quiet -- "$file"; then
    echo "[shared-data] no changes for $file"
    return 0
  fi
  git -C "$SHARED_DATA_DIR" commit -m "$message"
  git -C "$SHARED_DATA_DIR" push
}

if [[ -z "$command" || -z "$file" ]]; then
  usage
  exit 2
fi

validate_file
require_repo
sync_before

target="$SHARED_DATA_DIR/$file"

case "$command" in
  read)
    cat "$target"
    ;;
  write)
    content="${3:-}"
    message="${4:-Update $file}"
    printf '%s\n' "$content" > "$target"
    commit_and_push "$message"
    ;;
  append)
    content="${3:-}"
    message="${4:-Update $file}"
    printf '%s\n' "$content" >> "$target"
    commit_and_push "$message"
    ;;
  *)
    usage
    exit 2
    ;;
esac
