#!/bin/bash
# NAS 백업 스크립트 — memory + yaksu-history
# cron: 0 * * * * bash ~/discord-bot-nino/backup-to-nas.sh

set -euo pipefail

NAS_DIR="/mnt/d/Darren/backup/nino"
MEMORY_SRC="$HOME/.claude/projects/-home-bpx27-discord-bot-nino/memory"
HISTORY_DB="$HOME/.local/share/yaksu-history/messages.db"
LOG_FILE="$HOME/discord-bot-nino/logs/backup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# NAS 접근 확인 (D:\ = yaksu-storage, WSL에서 /mnt/d/)
if [ ! -d "/mnt/d/" ]; then
    log "ERROR: NAS not accessible (/mnt/d/ not found)"
    exit 1
fi

mkdir -p "$NAS_DIR/memory" "$NAS_DIR/yaksu-history"

# 1. memory/ rsync (매시간)
rsync -r --no-perms --no-owner --no-group --delete "$MEMORY_SRC/" "$NAS_DIR/memory/"
log "OK: memory synced ($(find "$MEMORY_SRC" -type f | wc -l) files)"

# 2. yaksu-history DB (매일 새벽 3시에만 스냅샷)
HOUR=$(date +%H)
if [ "$HOUR" = "03" ] && [ -f "$HISTORY_DB" ]; then
    SNAP="$NAS_DIR/yaksu-history/messages-$(date +%Y%m%d).db"
    sqlite3 "$HISTORY_DB" ".backup '$SNAP'"
    # 14일 이상 된 스냅샷 삭제
    find "$NAS_DIR/yaksu-history/" -name "messages-*.db" -mtime +14 -delete
    log "OK: yaksu-history snapshot created"
fi

log "OK: backup complete"
