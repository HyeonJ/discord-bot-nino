#!/bin/bash
# NAS 백업 스크립트 — memory 2곳 + yaksu-history + .env
# cron: 0 * * * * bash ~/discord-bot-nino/scripts/backup-to-nas.sh
#
# 니노 memory는 **두 곳**이고 성격이 달라 합칠 수 없다(ref_claude_memory_schema):
#   auto-memory  하네스가 매 세션 자동 로드(경로 고정)  → 자체 git 레포 + NAS
#   봇 memory/   온디맨드 서가(WAL·알람·리서치)         → NAS
# 2026-07-26까지 **봇 memory/ 는 어디에도 백업되지 않았고**, auto-memory는 레포가 있어도
# 자동 push가 없어 5일치 21개가 미커밋으로 방치됐다. 백업은 실패해도 알려줄 주체가 없어
# 조용히 죽으므로 배선을 tests/backup-to-nas.test.sh 로 고정한다.
#
# 경로·시각을 env로 받는 이유: 테스트가 실제 NAS·실제 원격을 건드리지 않기 위함(기본값=프로덕션).
set -euo pipefail

NAS_DIR="${BACKUP_NAS_DIR:-/mnt/d/Darren/backup/nino}"
NAS_ROOT="${BACKUP_NAS_ROOT:-/mnt/d/}"
MEMORY_SRC="${BACKUP_MEMORY_SRC:-$HOME/.claude/projects/-home-bpx27-discord-bot-nino/memory}"
BOT_MEMORY_SRC="${BACKUP_BOT_MEMORY_SRC:-$HOME/discord-bot-nino/memory}"
HISTORY_DB="${BACKUP_HISTORY_DB:-$HOME/.local/share/yaksu-history/messages.db}"
ENV_FILE="${BACKUP_ENV_FILE:-$HOME/discord-bot-nino/.env}"
LOG_FILE="${BACKUP_LOG_FILE:-$HOME/discord-bot-nino/logs/backup.log}"
HOUR="${BACKUP_FORCE_HOUR:-$(date +%H)}"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# NAS 접근 확인 (D:\ = yaksu-storage, WSL에서 /mnt/d/)
# 없으면 exit 1 — 조용한 skip이면 백업이 멈춘 걸 아무도 모른다
if [ ! -d "$NAS_ROOT" ]; then
    log "ERROR: NAS not accessible ($NAS_ROOT not found)"
    exit 1
fi

mkdir -p "$NAS_DIR/memory" "$NAS_DIR/bot-memory" "$NAS_DIR/yaksu-history"

RSYNC_OPTS=(-r --no-perms --no-owner --no-group --delete)

# 1. auto-memory rsync (매시간)
rsync "${RSYNC_OPTS[@]}" "$MEMORY_SRC/" "$NAS_DIR/memory/"
log "OK: auto-memory synced ($(find "$MEMORY_SRC" -type f | wc -l) files)"

# 2. 봇 memory/ rsync (매시간) — WAL·알람·리서치.
#    대상은 memory/ 뿐이다: 코드는 브랜치→PR 리뷰 게이트를 지나야 하므로 자동 백업 대상이 아니다.
if [ -d "$BOT_MEMORY_SRC" ]; then
    rsync "${RSYNC_OPTS[@]}" "$BOT_MEMORY_SRC/" "$NAS_DIR/bot-memory/"
    log "OK: bot memory synced ($(find "$BOT_MEMORY_SRC" -type f | wc -l) files)"
else
    log "WARN: bot memory source not found ($BOT_MEMORY_SRC)"
fi

# 3. auto-memory git push (매일 03시) — NAS 미러 외 두 번째 사본.
#    NAS는 삭제까지 미러링(--delete)하므로 실수 삭제는 복구가 안 된다. git이 그 축을 덮는다.
#    실패해도 rc를 올리지 않는다(백업 결과를 덮어쓰면 안 됨) — 대신 **조용히 넘기지도** 않는다.
if [ "$HOUR" = "03" ] && [ -d "$MEMORY_SRC/.git" ]; then
    PENDING="$(git -C "$MEMORY_SRC" status --porcelain | wc -l)"
    if [ "$PENDING" -eq 0 ]; then
        log "OK: auto-memory 변경 없음 (커밋 생략)"
    else
        git -C "$MEMORY_SRC" add -A
        if git -C "$MEMORY_SRC" commit -qm "backup: auto-memory 정기 백업 $(date '+%Y-%m-%d %H:%M')"; then
            log "OK: auto-memory 커밋 ($PENDING 파일)"
        else
            log "WARN: auto-memory 커밋 실패 ($PENDING 파일 미커밋 상태로 남음)"
        fi
    fi
    # 커밋이 없어도 이전 주기의 미푸시분이 남아 있을 수 있어 push는 항상 시도
    UNPUSHED="$(git -C "$MEMORY_SRC" rev-list --count '@{u}..HEAD' 2>/dev/null || echo "unknown")"
    if [ "$UNPUSHED" != "0" ]; then
        if git -C "$MEMORY_SRC" push -q origin main 2>/dev/null; then
            log "OK: auto-memory push 완료 ($UNPUSHED 커밋)"
        else
            log "WARN: auto-memory push 실패 — 로컬 커밋은 보존됨, 미푸시 ${UNPUSHED}건 (원격/인증 확인 필요)"
        fi
    fi
fi

# 4. yaksu-history DB (매일 새벽 3시에만 스냅샷)
if [ "$HOUR" = "03" ] && [ -f "$HISTORY_DB" ]; then
    SNAP="$NAS_DIR/yaksu-history/messages-$(date +%Y%m%d).db"
    sqlite3 "$HISTORY_DB" ".backup '$SNAP'"
    # 14일 이상 된 스냅샷 삭제
    find "$NAS_DIR/yaksu-history/" -name "messages-*.db" -mtime +14 -delete
    log "OK: yaksu-history snapshot created"
fi

# 5. .env 암호화 백업 (매일 새벽 3시에만)
AGE_BIN="$HOME/.local/bin/age"
AGE_PUBKEY="age1zx3fzyhgk3ysv9nxnhvrw3wezzpkj9ktchdclzdz9k7td5zkjdnqgd3pkl"
if [ "$HOUR" = "03" ] && [ -f "$ENV_FILE" ] && [ -x "$AGE_BIN" ]; then
    "$AGE_BIN" -r "$AGE_PUBKEY" -o "$NAS_DIR/env.age" "$ENV_FILE"
    log "OK: .env encrypted backup created"
fi

log "OK: backup complete"
