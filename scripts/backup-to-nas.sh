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
CDM_SRC="${BACKUP_CDM_SRC:-$HOME/discord-bot-nino/of/cdm}"
AGE_BIN="${BACKUP_AGE_BIN:-$HOME/.local/bin/age}"
AGE_PUBKEY="${BACKUP_AGE_PUBKEY:-age1zx3fzyhgk3ysv9nxnhvrw3wezzpkj9ktchdclzdz9k7td5zkjdnqgd3pkl}"
CRONTAB_CMD="${BACKUP_CRONTAB_CMD:-crontab -l}"
HOUR="${BACKUP_FORCE_HOUR:-$(date +%H)}"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

RC=0
fail() { log "ERROR: $*"; RC=1; }

RSYNC_OPTS=(-r --no-perms --no-owner --no-group --delete)

# yaksu-history DB 스냅샷.
#
# ⚠️ **외부 `sqlite3` CLI 를 쓰지 않는다.** 이 컴에 미설치인데 `set -e` 와 겹쳐서
#   4개월간(3/23~7/27) 매일 03시 이 지점에서 죽고, **완료 로그도 실패 로그도 안 남았다**.
#   피해: 스냅샷 0개 + 뒤에 있던 .env 암호화 백업까지 동반 미실행(env.age 가 7/27 에 처음 생성).
#   교훈은 "설치하면 된다"가 아니라 **시스템 패키지 의존 자체가 조용한 단일 실패점**이라는 것.
#
# python3 내장 sqlite3 의 `Connection.backup` 은 `.backup` 명령과 같은 **온라인 백업 API** 라
# relay 가 DB에 쓰는 중에도 일관된 사본을 만든다. 원본은 `mode=ro` 로 열어 절대 변형하지 않는다.
#
# ⚠️ **`.partial` 에 쓰고 성공 시 `mv` 한다** (룬드 리뷰). 최종 경로에 직접 쓰면:
#   파일명이 날짜 기반이라 같은 날 두 번 돌면 경로가 같다 → 1회차 성공 → 2회차 실패 →
#   실패 정리(`rm -f`)가 **1회차 정상 사본을 파괴**한다. retention 을 성공 분기에 둔 이유
#   ("실패가 상태를 악화시켜선 안 된다")와 같은 논리인데 여기서만 반대로 갔던 자리다.
#   `.partial` 이면 실패해도 기존 사본 무사 + 껍데기도 안 남고 + 교체가 원자적이다.
snapshot_db() {
    local src="$1" dst="$2" tmp="$2.partial"
    rm -f "$tmp" "$tmp-wal" "$tmp-shm"
    if python3 - "$src" "$tmp" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
source = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
try:
    target = sqlite3.connect(dst)
    try:
        with target:
            source.backup(target)
        # backup() 은 원본의 journal_mode 까지 물려준다 — 원본이 WAL 이라 사본도 WAL 이 되고,
        # 그러면 사본은 **자기완결 파일이 아니다**(읽기만 해도 -wal/-shm 이 생기고, 본체만
        # mv 하면 짝이 안 맞는 sidecar 가 남는다). 백업 산출물은 단일 파일이어야 하므로
        # 체크포인트로 WAL 내용을 본체에 밀어넣고 journal_mode 를 DELETE 로 되돌린다.
        # 두 PRAGMA 는 트랜잭션 밖에서 실행해야 한다(그래서 with 블록 뒤).
        target.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        mode = target.execute("PRAGMA journal_mode=DELETE").fetchone()[0]
        if mode.lower() != "delete":
            raise RuntimeError(f"journal_mode 전환 실패: {mode}")
    finally:
        target.close()
finally:
    source.close()
PY
    then
        mv -f "$tmp" "$dst"
        # 이전 스냅샷(WAL 시절)이 남긴 sidecar 정리 — 옛 DB의 것이 새 본체 옆에 남으면
        # sqlite 가 짝이 안 맞는 wal 을 적용하려 들 수 있다. mv 는 본체 하나만 옮기므로
        # "교체를 원자적으로"의 단위가 파일 하나가 아니었던 자리다.
        rm -f "$dst-wal" "$dst-shm"
        return 0
    fi
    rm -f "$tmp" "$tmp-wal" "$tmp-shm"
    return 1
}

# age 암호화 산출물도 **`.partial` + `mv`** 로 쓴다 (룬드 리뷰 PR #26).
# `age -o <최종경로>` 는 파일을 바로 열어 truncate 하므로, 실패하면 **어제의 정상 사본이
# 파괴되고 부분 파일이 남는다**. snapshot_db 가 이미 이 패턴을 쓰고 있었는데(같은 파일
# 100줄 위, 이유까지 주석에 있음) age 출력엔 안 붙어 있었다 — **같은 파일 안의 불일치**.
encrypt_to() {
    local dst="$1" src="$2" tmp="$1.partial"
    rm -f "$tmp"
    if "$AGE_BIN" -r "$AGE_PUBKEY" -o "$tmp" "$src"; then
        mv -f "$tmp" "$dst"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# 디렉토리 → tar → age. **파이프로 잇지 않는다** (룬드 리뷰의 핵심 지적).
#   `tar -cf - ... | age -o out` 에서 tar 가 중간에 죽으면 age 는 **그때까지 받은 부분
#   입력을 정상적으로 암호화하고 exit 0** 으로 끝날 수 있다. pipefail 이 rc 는 1로
#   만들어주지만 **파일은 남고, age 포맷으로 유효하고, 복호화도 된다** — 안이 잘려 있을 뿐.
#   즉 "포맷이 맞나 / 평문이 없나" 검사를 **전부 통과하는 손상 파일**이 만들어진다.
#   그리고 age 는 공개키로만 암호화하므로(개인키는 이 머신에 없음) **사후 내용 검증이 불가능**하다.
# → tar 를 먼저 완결시켜 파일로 만들고 `tar -tf` 로 **완전성을 확인한 뒤** 암호화한다.
#   임시 tar 는 평문 키를 담으므로 NAS(가 아니라) **로컬 + umask 077** 로 만들고 반드시 지운다
#   (원본이 이미 로컬 평문이라 노출 범위는 늘지 않는다).
archive_encrypt_to() {
    local dst="$1" src="$2" tar_tmp rc=1
    tar_tmp="$(umask 077; mktemp "${TMPDIR:-/tmp}/nino-arc.XXXXXX")" || return 1
    if tar -cf "$tar_tmp" -C "$(dirname "$src")" "$(basename "$src")" \
       && tar -tf "$tar_tmp" >/dev/null 2>&1; then
        encrypt_to "$dst" "$tar_tmp" && rc=0
    fi
    rm -f "$tar_tmp"
    return "$rc"
}

# 소스 → NAS 한 대상. 한 대상이 실패해도 rc만 올리고 **다음 대상을 계속** 처리한다.
# 소스 부재는 조용한 WARN이 아니라 ERROR다 — "백업이 아무것도 못 덮고 있다"는 뜻이고,
# 그게 이 스크립트가 없애려던 상태다(봇 memory/가 어디에도 백업되지 않던 6주).
# 단, 부재일 때 rsync 하면 --delete 로 **남아 있던 백업까지 날아가므로** 건너뛴다.
sync_dir() {
    local label="$1" src="$2" dst="$3"
    if [ ! -d "$src" ]; then
        fail "$label source not found ($src) — 기존 백업은 보존, rsync 건너뜀"
        return
    fi
    mkdir -p "$dst"
    # 🔸 안전형 — bash 3.2 + set -u 는 «빈» 배열의 맨 확장에서 unbound 로 죽는다.
    if rsync "${RSYNC_OPTS[@]+"${RSYNC_OPTS[@]}"}" "$src/" "$dst/"; then
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

# ── 축 2: auto-memory git 원격 (**매시** — 2026-07-28 승인 ⑦ 로 03시에서 넓힘) ──
# NAS 미러 외 두 번째 사본. NAS는 삭제까지 미러링(--delete)하므로 실수 삭제는 복구가 안 된다.
# git이 그 축을 덮는다 — 그래서 **NAS 상태를 조건에 넣지 않는다**(넣으면 두 축이 같이 죽는다).
# push 실패는 rc를 올리지 않는다(NAS 백업 성공 결과를 덮어쓰면 안 됨) — 대신 조용히 넘기지도 않는다.
#
# 왜 시각 게이트를 뺐나: 03시에만 돌면 최악 **23시간**치가 두 번째 사본 없이 남는다.
#   게이트가 줄여주는 건 커밋 수인데, 아래에서 **변경이 없으면 커밋을 안 만들므로**
#   게이트 없이도 커밋 수는 실제 작업량에 비례한다. 즉 게이트는 비용을 안 줄이고 노출만 늘렸다.
if [ -d "$MEMORY_SRC/.git" ]; then
    PENDING="$(git -C "$MEMORY_SRC" status --porcelain | wc -l)"
    if [ "$PENDING" -eq 0 ]; then
        log "OK: auto-memory 변경 없음 (커밋 생략)"
    else
        git -C "$MEMORY_SRC" add -A
        # 🔴 **이 커밋은 «내 손 편집»을 쓸어담는다 — 그러면 장부가 거짓이 된다.**
        #   `add -A` 는 편집 중인 것까지 구분 없이 가져가고, 내 변경이 「정기 백업」이라는
        #   **남의 메시지 밑**으로 들어간다. 내용 유실은 없지만 나중에 `log -S` 로 유래를
        #   찾으면 **커밋 메시지가 아무것도 안 말한다.**
        #   실물: `5603d67`「backup: auto-memory 정기 백업 2026-08-11 08:00」이 그 세션 편집
        #   **5건**(신규 파일 하나 포함)을 통째로 삼켰다.
        # 🔑 **닫는 방향을 「안 삼킨다」로 잡으면 백업이 죽는다** — 데몬이 안 담으면 그 시간 동안
        #   두 번째 사본이 없다. ⇒ **담되 «저자를 참칭하지 않는다»**: 무엇이 들어갔는지
        #   본문에 열거하고, 저자가 미상이라고 «적는다».
        # 🔑 목록은 `add -A` **뒤**에 `--cached` 로 뽑는다 — 앞에서 뽑으면 그 사이 바뀐 파일이
        #   목록에 없는 채 커밋된다(메시지가 커밋 내용보다 낡는다).
        # 🔴 `core.quotepath` 기본값이 **비ASCII 파일명을 8진 이스케이프**로 낸다
        #   (`"\354\203\210…"`). 그러면 목록이 있어도 **사람이 못 읽고 `log -S` 로도 안 걸린다**
        #   — 열거의 목적이 통째로 죽는다. 내 `memory/` 엔 한글 파일명이 산다.
        #   🔑 시험이 이걸 잡았다: 「신규 파일이 `A` 상태로 잡히나」를 한글 이름으로 물었더니 빨강.
        _staged="$(git -C "$MEMORY_SRC" -c core.quotepath=false diff --cached --name-status)"
        _n="$(printf '%s\n' "$_staged" | grep -c . || true)"
        _msgfile="$(mktemp)"
        {
            printf 'backup: auto-memory 정기 백업 %s (데몬 자동 · 저자 미상 %s건)\n\n' \
                   "$(date '+%Y-%m-%d %H:%M')" "$_n"
            printf '⚠️ 이 커밋은 «데몬이 쓸어담은» 것이라 저자를 말하지 않는다.\n'
            printf '   아래 변경은 사람/세션이 만든 것일 수 있고, 이 메시지는 그 유래가 아니다.\n\n'
            printf '%s\n' "$_staged"
        } > "$_msgfile"
        if git -C "$MEMORY_SRC" commit -q -F "$_msgfile"; then
            log "OK: auto-memory 커밋 ($PENDING 파일, 목록 동봉 ${_n}건)"
        else
            log "WARN: auto-memory 커밋 실패 ($PENDING 파일 미커밋 상태로 남음)"
        fi
        rm -f "$_msgfile"
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
            # `wc -c <` 로 크기를 읽는다 — `stat -c%s` 는 GNU 전용이라 코어(macOS)로 옮길 때 깨진다
            log "OK: yaksu-history snapshot created ($(wc -c < "$SNAP" | tr -d ' ') bytes)"
        else
            # 정리는 snapshot_db 가 `.partial` 만 지운다 — 최종 경로를 건드리면
            # 같은 날 1회차 성공분을 2회차 실패가 파괴한다(룬드 리뷰)
            fail "yaksu-history 스냅샷 실패 ($HISTORY_DB) — python3/DB 상태 확인"
        fi
    fi

    # ⚠️ `[ -x "$AGE_BIN" ]` 를 조건에 함께 두면 **age 가 사라진 날 백업이 조용히 skip 된다**
    #    (sqlite3 4개월 사고와 같은 클래스 — 의존 부재는 항상 조용하다). 그래서 도구 부재는
    #    스킵 사유가 아니라 **실패**로 올린다. 백업할 대상이 있는데 도구가 없는 건 사고다.
    if [ -f "$ENV_FILE" ] || [ -d "$CDM_SRC" ]; then
        if [ ! -x "$AGE_BIN" ]; then
            fail "age 바이너리 없음 ($AGE_BIN) — .env·cdm 암호화 백업 전부 미실행"
        else
            if [ -f "$ENV_FILE" ]; then
                if encrypt_to "$NAS_DIR/env.age" "$ENV_FILE"; then
                    log "OK: .env encrypted backup created ($(wc -c < "$NAS_DIR/env.age" | tr -d ' ') bytes)"
                else
                    fail ".env 암호화 백업 실패 — 기존 사본은 보존됨"
                fi
            fi

            # DRM 디바이스 키. **재발급이 불가능해 복구 비용이 가장 크다** — 특정 Android SDK
            # 빌드에서 추출한 디바이스 바인딩 키라 잃으면 추출 과정을 처음부터 밟아야 한다.
            # 16K 짜리가 15M 짜리보다 비싸다(우선순위는 크기가 아니라 복구 비용으로 매긴다).
            #
            # 보안상 git 제외 대상(.gitignore "절대 커밋 금지")이라 **제외가 곧 무보호**였다.
            # 같은 .gitignore 안에 성질이 정반대인 두 종류가 섞여 있었다:
            #   코드   = "다른 데(git)에 있다"      → 제외해도 보호됨
            #   cdm    = "여기 있으면 안 된다"      → 제외하면 어디에도 없음  ← 이 축은 소실 대비 필수
            # 평문으로 NAS 에 둘 수 없으니 .env 와 같은 age 경로에 태운다(새 배선 아님).
            if [ -d "$CDM_SRC" ]; then
                if archive_encrypt_to "$NAS_DIR/cdm.age" "$CDM_SRC"; then
                    log "OK: cdm encrypted backup created ($(wc -c < "$NAS_DIR/cdm.age" | tr -d ' ') bytes)"
                else
                    fail "cdm 암호화 백업 실패 ($CDM_SRC)"
                fi
            else
                # cdm 부재는 ERROR 가 아니다 — memory/ 부재와 성질이 다르다.
                # memory/ 는 항상 있어야 하지만 cdm 은 **DRM 도구 미설치면 정상적으로 없다**.
                # 다만 조용히 넘기지는 않는다(없다는 사실 자체는 로그에 남긴다).
                log "INFO: cdm 소스 없음 ($CDM_SRC) — DRM 도구 미설치로 간주, 백업 대상 아님"
            fi
        fi
    fi

    # 잡 정의 백업. 잃으면 봇 자동시작·백업·알람·헬스체크 스케줄이 **전부 조용히** 사라진다.
    # 자기참조 주의: stale 감지 규약이 감시 목록을 crontab 에서 유도하므로, crontab 유실은
    # ①감지기가 감시 대상을 잃고 ②잡이 안 도니 마커도 없고 ③목록이 비었으니 missing=stale 도
    # 안 걸려서 **양방향 감지가 동시에 무력해진다**. 백업은 되돌려주고, 감지는 "목록 0개 = 감시
    # 실패" 검사가 알려준다 — 둘은 별개 축이라 둘 다 필요하다(룬드와 규약 10번으로 합의).
    # 민감정보가 없어 평문 텍스트로 둔다.
    CRON_OUT="$($CRONTAB_CMD 2>/dev/null)"
    if [ -n "$CRON_OUT" ]; then
        printf '%s\n' "$CRON_OUT" > "$NAS_DIR/crontab.txt"
        log "OK: crontab backed up ($(printf '%s\n' "$CRON_OUT" | grep -cE '^[^#[:space:]]') 잡)"
    else
        fail "crontab 이 비었거나 읽지 못했다 ($CRONTAB_CMD) — 잡 정의 백업 미실행"
    fi
fi

if [ "$RC" -eq 0 ]; then
    log "OK: backup complete"
else
    log "ERROR: backup completed with failures (rc=$RC) — 위 ERROR 줄 확인"
fi
exit "$RC"
