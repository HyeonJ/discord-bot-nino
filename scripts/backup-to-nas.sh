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
#
# ⚠️ `set -e` 를 쓰지 않는다(룬드 리뷰 반영). 위 명제("NAS는 --delete 미러라 실수 삭제를
#   복구 못 하니 git이 그 축을 덮는다")가 성립하려면 두 축이 **독립**이어야 한다.
#   -e + 직렬이면 NAS 마운트 유실·rsync 실패가 git 단계를 건너뛰게 만들어, NAS가 며칠 죽은
#   동안 git 백업도 0이 된다. 그런데 로그엔 `ERROR: NAS not accessible` 만 남아서
#   **git 축이 같이 멈춘 건 보이지도 않는다** — 이 스크립트가 없애려던 상태(미커밋 방치)의 재현.
#   그래서 축마다 독립 실행 + 실패는 rc에 누적해서 마지막에 한 번 반환한다.
set -uo pipefail

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

RC=0
fail() { log "ERROR: $*"; RC=1; }

RSYNC_OPTS=(-r --no-perms --no-owner --no-group --delete)

# 소스 → NAS 한 대상. 한 대상이 실패해도 rc만 올리고 **다음 대상을 계속** 처리한다.
# 소스 부재는 조용한 WARN이 아니라 ERROR다 — "백업이 아무것도 못 덮고 있다"는 뜻이고,
# 그게 이 스크립트가 없애려던 상태다(봇 memory/가 어디에도 백업되지 않던 6주).
# 단, 부재일 때 rsync 하면 --delete 로 **남아 있던 백업까지 날아가므로** 건너뛴다.
# yaksu-history DB 스냅샷.
#
# ⚠️ **외부 `sqlite3` CLI 를 쓰지 않는다.** 이 컴에 미설치인데 `set -e` 와 겹쳐서
#   4개월간(3/23~7/27) 매일 03시 이 지점에서 죽고, **완료 로그도 실패 로그도 안 남았다**.
#   피해: 스냅샷 0개 + 뒤에 있던 .env 암호화 백업까지 동반 미실행(env.age 가 7/27 에 처음 생성).
#   교훈은 "설치하면 된다"가 아니라 **시스템 패키지 의존 자체가 조용한 단일 실패점**이라는 것.
#
# python3 내장 sqlite3 의 `Connection.backup` 은 `.backup` 명령과 같은 **온라인 백업 API** 라
# relay 가 DB에 쓰는 중에도 일관된 사본을 만든다. 원본은 `mode=ro` 로 열어 절대 변형하지 않는다.
snapshot_db() {
    python3 - "$1" "$2" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
source = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
try:
    target = sqlite3.connect(dst)
    try:
        with target:
            source.backup(target)
    finally:
        target.close()
finally:
    source.close()
PY
}

sync_dir() {
    local label="$1" src="$2" dst="$3"
    if [ ! -d "$src" ]; then
        fail "$label source not found ($src) — 기존 백업은 보존, rsync 건너뜀"
        return
    fi
    mkdir -p "$dst"
    if rsync "${RSYNC_OPTS[@]}" "$src/" "$dst/"; then
        log "OK: $label synced ($(find "$src" -type f | wc -l) files)"
    else
        fail "$label rsync 실패 (디스크 full·권한·I/O 확인)"
    fi
}

# ── 축 1: NAS 미러 ──────────────────────────────────────────────
# NAS 접근 불가면 rc=1로 알리되 **여기서 종료하지 않는다** — git 축은 NAS와 무관하다.
# (D:\ = yaksu-storage, WSL에서 /mnt/d/)
NAS_OK=1
if [ ! -d "$NAS_ROOT" ]; then
    NAS_OK=0
    fail "NAS not accessible ($NAS_ROOT not found) — NAS 축 전체 skip, git 축은 계속"
else
    # 대상은 memory/ 뿐이다: 코드는 브랜치→PR 리뷰 게이트를 지나야 하므로 자동 백업 대상이 아니다.
    sync_dir "auto-memory" "$MEMORY_SRC" "$NAS_DIR/memory"
    sync_dir "bot memory" "$BOT_MEMORY_SRC" "$NAS_DIR/bot-memory"
fi

# ── 축 2: auto-memory git 원격 (매일 03시) ───────────────────────
# NAS 미러 외 두 번째 사본. NAS는 삭제까지 미러링(--delete)하므로 실수 삭제는 복구가 안 된다.
# git이 그 축을 덮는다 — 그래서 **NAS 상태를 조건에 넣지 않는다**(넣으면 두 축이 같이 죽는다).
# push 실패는 rc를 올리지 않는다(NAS 백업 성공 결과를 덮어쓰면 안 됨) — 대신 조용히 넘기지도 않는다.
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

# ── 축 1 계속: NAS에 쓰는 03시 스냅샷들 ─────────────────────────
# NAS_OK 게이트가 필요하다 — 이들은 NAS_DIR에 쓰므로 마운트 없이 실행하면
# WSL 로컬 디스크에 유령 디렉토리를 만들고 "OK"를 남긴다(백업된 줄 알게 되는 최악).
if [ "$NAS_OK" = "1" ] && [ "$HOUR" = "03" ]; then
    if [ -f "$HISTORY_DB" ]; then
        mkdir -p "$NAS_DIR/yaksu-history"
        SNAP="$NAS_DIR/yaksu-history/messages-$(date +%Y%m%d).db"
        if snapshot_db "$HISTORY_DB" "$SNAP"; then
            # retention 은 **성공 분기 안에** 둔다 — 스냅샷이 실패한 날 옛 스냅샷을 지우면
            # 마지막 정상 사본까지 날아간다(백업 없는 상태로 수렴).
            find "$NAS_DIR/yaksu-history/" -name "messages-*.db" -mtime +14 -delete
            log "OK: yaksu-history snapshot created ($(stat -c%s "$SNAP" 2>/dev/null || echo '?') bytes)"
        else
            # 부분 생성된 껍데기를 남기면 "파일 있음"으로 백업된 줄 오독된다
            rm -f "$SNAP"
            fail "yaksu-history 스냅샷 실패 ($HISTORY_DB) — python3/DB 상태 확인"
        fi
    fi

    AGE_BIN="$HOME/.local/bin/age"
    AGE_PUBKEY="age1zx3fzyhgk3ysv9nxnhvrw3wezzpkj9ktchdclzdz9k7td5zkjdnqgd3pkl"
    if [ -f "$ENV_FILE" ] && [ -x "$AGE_BIN" ]; then
        if "$AGE_BIN" -r "$AGE_PUBKEY" -o "$NAS_DIR/env.age" "$ENV_FILE"; then
            log "OK: .env encrypted backup created"
        else
            fail ".env 암호화 백업 실패"
        fi
    fi
fi

if [ "$RC" -eq 0 ]; then
    log "OK: backup complete"
else
    log "ERROR: backup completed with failures (rc=$RC) — 위 ERROR 줄 확인"
fi
exit "$RC"
