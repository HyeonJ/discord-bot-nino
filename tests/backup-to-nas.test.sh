#!/usr/bin/env bash
# backup-to-nas.sh 계약 테스트 (실제 NAS·실제 원격 안 씀 — 전부 임시 루트)
#
# 왜: 니노 memory 디렉토리가 **두 곳**인데 한쪽(auto-memory)만 백업되고 있었다.
#   `~/discord-bot-nino/memory/`(WAL·알람·리서치)는 NAS·git 어디에도 없었고,
#   auto-memory는 백업 레포가 있는데 **자동 push가 없어** 5일치 21개가 미커밋으로 방치됐다.
#   (룬드도 같은 클래스를 자기 쪽에서 밟음 — `~/.claude`만 대상, `~/Assistant`는 밖)
#   백업은 **실패해도 알려줄 주체가 없으므로** 배선을 테스트로 고정한다.
#
# 설계: 스크립트가 경로·시각을 env로 받는다(기본값은 프로덕션). 그래야 부작용 없이 검증 가능.
#   [[feedback_vault_script_test_isolation]] — 실제 봇 트리·NAS를 건드리면 격리가 깨진다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT_DIR/scripts/backup-to-nas.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/     /'; }

[[ -f "$SCRIPT" ]] || { echo "❌ 대상 스크립트 없음: $SCRIPT"; exit 1; }

ROOT=""
setup() {
  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/nas" "$ROOT/auto-memory" "$ROOT/bot-memory" "$ROOT/logs"
  echo "auto" > "$ROOT/auto-memory/MEMORY.md"
  echo "wal"  > "$ROOT/bot-memory/current-tasks.md"
  mkdir -p "$ROOT/bot-memory/alarms"
  echo "alarm" > "$ROOT/bot-memory/alarms/a.md"
  # 경계 확인용: memory/ 밖(코드 위치) 파일 — 절대 백업되면 안 됨
  mkdir -p "$ROOT/outside-src"
  echo "code" > "$ROOT/outside-src/relay.js"
}
teardown() { [[ -n "$ROOT" && -d "$ROOT" ]] && rm -rf "$ROOT"; ROOT=""; }

# auto-memory를 git 레포로 만들고 bare 원격을 붙인다 (push 실측용)
init_git_repo() {
  git -C "$ROOT/auto-memory" init -q -b main
  git -C "$ROOT/auto-memory" config user.email "t@t"
  git -C "$ROOT/auto-memory" config user.name "t"
  git -C "$ROOT/auto-memory" add -A
  git -C "$ROOT/auto-memory" commit -qm init
  # bare 원격도 -b main — 기본 HEAD가 master면 `git log`가 빈 값을 반환해
  # "푸시 실패"로 오판한다(실제로 한 번 밟음: 배관 버그를 구현 버그로 읽을 자리)
  git init -q --bare -b main "$ROOT/remote.git"
  git -C "$ROOT/auto-memory" remote add origin "$ROOT/remote.git"
  # -u 로 upstream 설정 — 프로덕션(origin/main 추적)과 같은 모양이어야 미푸시 카운트 경로가 검증된다
  git -C "$ROOT/auto-memory" push -qu origin main
}

run_backup() {
  env \
    BACKUP_NAS_DIR="$ROOT/nas" \
    BACKUP_NAS_ROOT="$ROOT" \
    BACKUP_MEMORY_SRC="$ROOT/auto-memory" \
    BACKUP_BOT_MEMORY_SRC="$ROOT/bot-memory" \
    BACKUP_HISTORY_DB="$ROOT/nonexistent.db" \
    BACKUP_ENV_FILE="$ROOT/nonexistent.env" \
    BACKUP_LOG_FILE="$ROOT/logs/backup.log" \
    "$@" bash "$SCRIPT" 2>&1
}
logtext() { cat "$ROOT/logs/backup.log" 2>/dev/null; }

echo "=== backup-to-nas.sh 계약 ==="

# ① 봇 memory/ 가 NAS로 간다 (이번 PR의 본체)
setup
run_backup >/dev/null
[[ -f "$ROOT/nas/bot-memory/current-tasks.md" && -f "$ROOT/nas/bot-memory/alarms/a.md" ]] \
  && ok "봇 memory/ rsync (WAL·하위 디렉토리 포함)" \
  || bad "봇 memory/ 가 NAS에 없음" "$(find "$ROOT/nas" -type f | sed "s|$ROOT||")"

# ② 기존 auto-memory 백업 회귀 없음
[[ -f "$ROOT/nas/memory/MEMORY.md" ]] \
  && ok "auto-memory rsync 유지(회귀 없음)" \
  || bad "auto-memory 백업이 깨졌다"

# ③ 경계: memory/ 밖(코드)은 백업되지 않는다
#    "memory가 백업되는가"만 보면 코드까지 딸려가도 통과한다 → 제외 대상을 심어 확인(룬드 방식)
#    ⚠️ **선행 조건을 먼저 확인**: 백업이 아무것도 안 했으면 이 케이스는 공허하게 통과한다
#       (구현 전 red에서 실제로 그렇게 통과했다 — 통과 케이스를 의심하라)
if [[ ! -f "$ROOT/nas/bot-memory/current-tasks.md" ]]; then
  bad "경계 검사 불가 — 백업 자체가 안 돌아 판정 무의미(공허한 통과 방지)"
elif grep -rq "code" "$ROOT/nas" 2>/dev/null; then
  bad "memory/ 밖 파일이 백업됐다(경계 붕괴)" "$(grep -rl code "$ROOT/nas")"
else
  ok "경계 유지 — memory/ 밖은 백업 안 됨"
fi

# ④ 미러링: 원본에서 지운 파일은 백업에서도 사라진다
#    여기도 "지우기 전에 있었는가"를 먼저 봐야 판정이 성립한다
if [[ ! -f "$ROOT/nas/bot-memory/alarms/a.md" ]]; then
  bad "미러링 검사 불가 — 대상 파일이 애초에 백업되지 않았다(공허한 통과 방지)"
else
  rm "$ROOT/bot-memory/alarms/a.md"
  run_backup >/dev/null
  [[ ! -f "$ROOT/nas/bot-memory/alarms/a.md" ]] \
    && ok "--delete 미러링 동작" \
    || bad "삭제가 반영되지 않음"
fi
teardown

# ⑤ **시각과 무관하게** git 단계가 돈다 (2026-07-28 승인 ⑦ 로 계약 변경)
#    이전 계약: 03시에만. 그러면 최악 **23시간**의 작업이 두 번째 사본 없이 남는다 —
#    NAS 미러는 `--delete` 라서 실수 삭제를 복구 못 하고, 그 축을 덮는 게 git 축이다.
#    스크립트는 매시 돌고 변경이 없으면 커밋을 안 만드니(⑦) 시각 게이트는 노출만 늘렸다.
# ⚠️ "auto-memory" 로만 grep하면 1단계 rsync 로그("auto-memory synced")에 걸린다 —
#    실제로 한 번 오탐했다. git 단계 고유 문구(커밋/push)로 좁혀야 판정이 성립한다.
setup; init_git_repo
echo "변경" >> "$ROOT/auto-memory/MEMORY.md"
run_backup BACKUP_FORCE_HOUR=09 >/dev/null
if logtext | grep -qE "auto-memory (커밋|push|변경 없음)"; then
  ok "비-03시에도 git 단계가 돈다"
else
  bad "시각 게이트가 남아 있다 — 09시에 git 단계가 안 돌았다" "$(logtext)"
fi
REMOTE_09="$(git -C "$ROOT/remote.git" log --oneline -1 2>/dev/null || echo "")"
[[ "$REMOTE_09" != *"init"* && -n "$REMOTE_09" ]] \
  && ok "09시 커밋+push → 원격 도달 실측" \
  || bad "09시인데 원격에 도달 안 함" "remote=$REMOTE_09 / log=$(logtext)"

# ⑥ 03시에도 그대로 된다 (기존 동작 유지 — 넓힌 것이지 옮긴 게 아니다)
echo "변경-03" >> "$ROOT/auto-memory/MEMORY.md"
run_backup BACKUP_FORCE_HOUR=03 >/dev/null
REMOTE_MSG="$(git -C "$ROOT/remote.git" log --oneline -1 2>/dev/null || echo "")"
if [[ "$REMOTE_MSG" == *"init"* || -z "$REMOTE_MSG" ]]; then
  bad "원격에 새 커밋이 도달하지 않았다" "remote=$REMOTE_MSG / log=$(logtext)"
else
  ok "03시 커밋+push → 원격 도달 실측"
fi

# ⑦ 변경이 없으면 조용히 통과 (빈 커밋 만들지 않음)
BEFORE="$(git -C "$ROOT/remote.git" rev-parse HEAD)"
run_backup BACKUP_FORCE_HOUR=03 >/dev/null
AFTER="$(git -C "$ROOT/remote.git" rev-parse HEAD)"
[[ "$BEFORE" == "$AFTER" ]] \
  && ok "변경 없으면 빈 커밋 안 만듦" \
  || bad "변경 없는데 커밋이 생겼다"
teardown

# ⑧ push 실패는 CI(백업) 결과를 덮지 않지만 **조용하지도 않다**
#    로그에 미커밋/실패가 남아야 한다 — 알림 경로가 죽은 걸 알려줄 주체가 없기 때문
setup; init_git_repo
git -C "$ROOT/auto-memory" remote set-url origin "$ROOT/does-not-exist.git"
echo "변경2" >> "$ROOT/auto-memory/MEMORY.md"
run_backup BACKUP_FORCE_HOUR=03 >/dev/null; RC=$?
if [[ $RC -ne 0 ]]; then
  bad "push 실패가 스크립트 전체를 실패시켰다(rc=$RC) — 백업 결과를 덮어쓰면 안 됨"
elif logtext | grep -qE "WARN.*push"; then
  ok "push 실패를 WARN으로 남기고 rc는 0 유지"
else
  bad "push 실패가 조용히 묻혔다" "$(logtext)"
fi
teardown

# ⑨ NAS 접근 불가 → rc는 1로 알리되 **git 축은 계속 돈다** (축 독립성)
#    ⚠️ "NAS 불가 → exit 1"만 보면 **현재 구현을 명세로 굳혀** 결함을 승인해버린다(룬드 지적).
#    이 PR의 명제가 "NAS는 --delete 미러라 실수 삭제를 복구 못 하니 git이 그 축을 덮는다"인데,
#    NAS 장애로 git 축이 같이 멈추면 두 축은 독립이 아니고 명제가 성립하지 않는다.
#    한 축을 죽였을 때 다른 축이 사는지를 봐야 독립이 증명된다.
setup; init_git_repo
echo "변경3" >> "$ROOT/auto-memory/MEMORY.md"
BEFORE="$(git -C "$ROOT/remote.git" rev-parse HEAD)"
OUT="$(env BACKUP_NAS_ROOT="$ROOT/no-such-mount" \
  BACKUP_NAS_DIR="$ROOT/nas" BACKUP_MEMORY_SRC="$ROOT/auto-memory" \
  BACKUP_BOT_MEMORY_SRC="$ROOT/bot-memory" BACKUP_LOG_FILE="$ROOT/logs/backup.log" \
  BACKUP_FORCE_HOUR=03 bash "$SCRIPT" 2>&1)"; RC=$?
AFTER="$(git -C "$ROOT/remote.git" rev-parse HEAD)"
if [[ $RC -eq 0 ]]; then
  bad "NAS 없는데 성공으로 끝났다(조용한 skip)" "$OUT"
elif [[ "$BEFORE" == "$AFTER" ]]; then
  bad "NAS 장애가 git 축까지 멈췄다 — 두 축이 독립이 아님" "$(logtext)"
else
  ok "NAS 불가 → rc=$RC 로 알리면서 git 축은 계속 수행(축 독립)"
fi

# ⑩ 역방향: git 축이 죽어도 NAS 축은 살아야 한다
git -C "$ROOT/auto-memory" remote set-url origin "$ROOT/gone.git"
echo "변경4" >> "$ROOT/bot-memory/current-tasks.md"
run_backup BACKUP_FORCE_HOUR=03 >/dev/null; RC=$?
if ! grep -q "변경4" "$ROOT/nas/bot-memory/current-tasks.md" 2>/dev/null; then
  bad "push 실패가 NAS 축까지 멈췄다 — 역방향 독립 깨짐" "$(logtext)"
else
  ok "git push 실패 → NAS 축은 정상 수행(역방향 독립)"
fi
teardown

# ⑪ 백업 소스가 사라지면 조용한 WARN이 아니라 rc로 알린다 + **기존 백업을 지우지 않는다**
#    소스 부재는 "백업이 아무것도 못 덮고 있다"는 뜻 = 이 PR이 없애려던 상태 그대로다.
#    동시에 --delete 로 rsync 하면 남아 있던 백업까지 날아가므로 rsync는 건너뛴다.
setup
run_backup >/dev/null   # 정상 1회로 백업 적재
rm -rf "$ROOT/bot-memory"
run_backup >/dev/null; RC=$?
if [[ $RC -eq 0 ]]; then
  bad "봇 memory 소스가 사라졌는데 rc=0 (조용한 통과)" "$(logtext)"
elif [[ ! -f "$ROOT/nas/bot-memory/current-tasks.md" ]]; then
  bad "소스 부재인데 기존 백업이 삭제됐다(--delete 로 날아감)" "$(logtext)"
else
  ok "소스 부재 → rc=$RC 로 알리고 기존 백업은 보존"
fi
teardown

# ── yaksu-history 스냅샷 ────────────────────────────────────────
# 왜: `sqlite3` CLI 가 이 컴에 **미설치**라 4개월간 매일 03시 그 지점에서 죽고 있었다.
#   set -e 였던 동안엔 완료·실패 로그가 **둘 다** 안 남아 아무 신호가 없었다.
#   증거: 스냅샷 0개(폴더는 3/23 생성) / env.age 가 2026-07-27 에 처음 생성 /
#   03시 로그가 전부 `OK: memory synced` 한 줄에서 끝남.
#   → python3 내장 sqlite3(Connection.backup, 온라인 백업 API)로 전환해 외부 CLI 의존을 없앤다.
#   테스트는 **CLI 유무와 무관하게** 통과해야 한다(그게 전환의 목적).

# 실제 DB 픽스처 — 행 수를 세서 "빈 파일이 아니라 진짜 사본"인지 볼 수 있게 만든다
# ⚠️ 픽스처는 **WAL 모드**로 만든다 — 프로덕션 messages.db 가 WAL 이고,
#    `backup()` 이 journal_mode 까지 물려주기 때문에 이게 사본의 자기완결성을 가른다.
#    기본(delete) 모드로 픽스처를 만들면 sidecar 문제가 재현되지 않아 테스트가 무의미해진다.
make_db() {
  python3 - "$1" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("PRAGMA journal_mode=WAL")
c.execute("CREATE TABLE messages (id INTEGER PRIMARY KEY, body TEXT)")
c.executemany("INSERT INTO messages (body) VALUES (?)", [(f"msg{i}",) for i in range(37)])
c.commit(); c.close()
PY
}
journal_mode() {
  python3 - "$1" <<'PY' 2>/dev/null || echo "?"
import sqlite3, sys
c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
print(c.execute("PRAGMA journal_mode").fetchone()[0]); c.close()
PY
}
count_rows() {
  python3 - "$1" <<'PY' 2>/dev/null || echo -1
import sqlite3, sys
c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
print(c.execute("SELECT count(*) FROM messages").fetchone()[0])
PY
}

# ⑫ 03시에 스냅샷이 생기고 **내용이 실제로 복사**된다 (sqlite3 CLI 없이)
setup
make_db "$ROOT/msgs.db"
run_backup BACKUP_FORCE_HOUR=03 BACKUP_HISTORY_DB="$ROOT/msgs.db" >/dev/null; RC=$?
SNAP="$(find "$ROOT/nas/yaksu-history" -name 'messages-*.db' 2>/dev/null | head -1)"
if [[ -z "$SNAP" ]]; then
  bad "03시인데 스냅샷이 생성되지 않았다" "$(logtext)"
elif [[ "$(count_rows "$SNAP")" != "37" ]]; then
  # 파일 존재만 보면 0바이트 껍데기도 통과한다 — 행 수까지 봐야 "사본"이 증명된다
  bad "스냅샷이 유효한 사본이 아니다 (행 수 $(count_rows "$SNAP") ≠ 37)" "$(ls -la "$SNAP")"
elif [[ $RC -ne 0 ]]; then
  bad "스냅샷은 만들었는데 rc=$RC" "$(logtext)"
else
  ok "03시 스냅샷 생성 + 행 수 37 일치 (외부 sqlite3 CLI 불필요)"
fi

# ⑬ 비-03시엔 스냅샷을 만들지 않는다 (매시간 6.8MB 복사 방지)
rm -f "$ROOT/nas/yaksu-history"/messages-*.db
run_backup BACKUP_FORCE_HOUR=09 BACKUP_HISTORY_DB="$ROOT/msgs.db" >/dev/null
[[ -z "$(find "$ROOT/nas/yaksu-history" -name 'messages-*.db' 2>/dev/null)" ]] \
  && ok "비-03시엔 스냅샷 미생성" \
  || bad "03시가 아닌데 스냅샷이 생겼다"
teardown

# ⑭ 스냅샷 실패는 **조용히 넘어가지 않는다** (rc=1 + ERROR 로그)
#    이번 사고의 본체가 "실패했는데 아무 신호가 없었다"는 것이라 이 케이스가 회귀 가드다.
setup
echo "이건 sqlite DB가 아니다" > "$ROOT/broken.db"
run_backup BACKUP_FORCE_HOUR=03 BACKUP_HISTORY_DB="$ROOT/broken.db" >/dev/null; RC=$?
if [[ $RC -eq 0 ]]; then
  bad "DB가 깨졌는데 rc=0 (조용한 실패 — 4개월 사고의 형태)" "$(logtext)"
elif ! logtext | grep -qE "ERROR.*(history|스냅샷)"; then
  bad "스냅샷 실패가 로그에 안 남았다" "$(logtext)"
else
  ok "스냅샷 실패 → rc=$RC + ERROR 로그"
fi

# ⑮ 실패해도 **다른 축은 계속** — 스냅샷 실패가 NAS rsync 결과를 덮지 않는다
[[ -f "$ROOT/nas/bot-memory/current-tasks.md" ]] \
  && ok "스냅샷 실패에도 memory rsync 는 수행됨(축 독립 유지)" \
  || bad "스냅샷 실패가 앞 단계까지 무효화했다" "$(logtext)"
teardown

# ⑯ 🔴 같은 날 2회차 실패가 **1회차 정상 사본을 파괴하지 않는다** (룬드 리뷰)
#    파일명이 날짜 기반이라 같은 날 두 번 돌면 경로가 같다. 실패 정리로 최종 경로를 지우면
#    1회차 성공분이 날아간다 — 실패가 상태를 악화시키는 방향(retention 을 성공 분기에
#    둔 것과 같은 논리인데 여기서만 반대로 갔던 자리).
#    ⚠️ 발견 당시 프로덕션에 8163행 사본이 이미 있었으므로 **실재하는 위험**이었다.
setup
make_db "$ROOT/msgs.db"
run_backup BACKUP_FORCE_HOUR=03 BACKUP_HISTORY_DB="$ROOT/msgs.db" >/dev/null
SNAP1="$(find "$ROOT/nas/yaksu-history" -name 'messages-*.db' | head -1)"
if [[ -z "$SNAP1" || "$(count_rows "$SNAP1")" != "37" ]]; then
  bad "선행 조건 실패 — 1회차 사본이 없어 파괴 검사가 무의미(공허한 통과 방지)"
else
  echo "이건 sqlite DB가 아니다" > "$ROOT/broken.db"
  run_backup BACKUP_FORCE_HOUR=03 BACKUP_HISTORY_DB="$ROOT/broken.db" >/dev/null; RC=$?
  if [[ ! -f "$SNAP1" ]]; then
    bad "2회차 실패가 1회차 정상 사본을 삭제했다" "$(ls -la "$ROOT/nas/yaksu-history/")"
  elif [[ "$(count_rows "$SNAP1")" != "37" ]]; then
    bad "1회차 사본이 덮여 손상됐다 (행 수 $(count_rows "$SNAP1"))" "$(logtext)"
  elif [[ -n "$(find "$ROOT/nas/yaksu-history" -name '*.partial' 2>/dev/null)" ]]; then
    bad ".partial 껍데기가 남았다" "$(ls -la "$ROOT/nas/yaksu-history/")"
  elif [[ $RC -eq 0 ]]; then
    bad "2회차가 실패했는데 rc=0"
  else
    ok "같은 날 2회차 실패 → 1회차 사본 무사(37행) + .partial 잔재 없음 + rc=$RC"
  fi
fi
teardown

# ⑰ 🔴 스냅샷은 **자기완결 단일 파일**이어야 한다 (sidecar 잔재 금지)
#    `backup()` 은 원본의 journal_mode 를 물려준다. 프로덕션 원본이 WAL 이라 사본도 WAL 이 되고,
#    그러면 읽기만 해도 -wal/-shm 이 생기며 `mv` 는 본체 하나만 옮긴다
#    → **옛 DB의 sidecar 가 새 본체 옆에 남아** sqlite 가 짝이 안 맞는 wal 을 적용할 수 있다.
#    "교체를 원자적으로"의 단위가 파일 하나가 아니었던 자리(룬드 .partial 지적의 한 겹 아래).
setup
make_db "$ROOT/msgs.db"
[[ "$(journal_mode "$ROOT/msgs.db")" == "wal" ]] \
  || bad "선행 조건 실패 — 픽스처가 WAL 이 아니어서 sidecar 문제가 재현되지 않는다(공허한 통과 방지)"
# 옛 WAL 시절 sidecar 를 심어둔다 — 정리되는지 봐야 한다
mkdir -p "$ROOT/nas/yaksu-history"
touch "$ROOT/nas/yaksu-history/messages-$(date +%Y%m%d).db-wal" \
      "$ROOT/nas/yaksu-history/messages-$(date +%Y%m%d).db-shm"
run_backup BACKUP_FORCE_HOUR=03 BACKUP_HISTORY_DB="$ROOT/msgs.db" >/dev/null
SNAP="$(find "$ROOT/nas/yaksu-history" -name 'messages-*.db' | head -1)"
SIDE="$(find "$ROOT/nas/yaksu-history" \( -name '*-wal' -o -name '*-shm' -o -name '*.partial*' \) | wc -l)"
if [[ -z "$SNAP" ]]; then
  bad "스냅샷이 없어 판정 불가"
elif [[ "$(journal_mode "$SNAP")" == "wal" ]]; then
  bad "사본이 WAL 모드 — 자기완결 파일이 아니다(원본 모드를 물려받았다)"
elif [[ "$SIDE" -ne 0 ]]; then
  bad "sidecar/partial 잔재 $SIDE 건" "$(ls -la "$ROOT/nas/yaksu-history/")"
elif [[ "$(count_rows "$SNAP")" != "37" ]]; then
  # journal_mode 를 바꾸면서 데이터가 날아가지 않았는지 — 체크포인트가 본체에 반영됐어야 한다
  bad "모드 전환 과정에서 데이터가 유실됐다 (행 수 $(count_rows "$SNAP"))"
else
  ok "사본이 자기완결(journal_mode=$(journal_mode "$SNAP")) + sidecar 잔재 0 + 37행 보존"
fi
teardown

# ⑱ retention: 14일 넘은 스냅샷만 삭제, 최근 것은 보존
setup
make_db "$ROOT/msgs.db"
mkdir -p "$ROOT/nas/yaksu-history"
# ⚠️ `touch -d` 는 GNU 전용 — 코어(macOS)로 옮기면 `touch -t` 로 바꿔야 한다(룬드 지적)
touch -d '30 days ago' "$ROOT/nas/yaksu-history/messages-20260101.db"
touch -d '3 days ago'  "$ROOT/nas/yaksu-history/messages-20260724.db"
run_backup BACKUP_FORCE_HOUR=03 BACKUP_HISTORY_DB="$ROOT/msgs.db" >/dev/null
OLD_GONE=$([[ -f "$ROOT/nas/yaksu-history/messages-20260101.db" ]] && echo NO || echo YES)
NEW_KEPT=$([[ -f "$ROOT/nas/yaksu-history/messages-20260724.db" ]] && echo YES || echo NO)
if [[ "$OLD_GONE" == "YES" && "$NEW_KEPT" == "YES" ]]; then
  ok "retention — 30일 전 삭제 / 3일 전 보존"
else
  bad "retention 오동작 (구파일삭제=$OLD_GONE 신파일보존=$NEW_KEPT)" "$(ls -la "$ROOT/nas/yaksu-history/")"
fi
teardown

# ── 커버리지 확장: cdm(재발급 불가) + crontab(잡 정의) ─────────
# 왜: 백업이 "무엇을 덮는가"만 보고 있어서 **무엇이 빠졌는가**를 안 셌다. 실측 결과 2건 누락:
#   of/cdm  16K  DRM 디바이스 키 — **재발급 불가**(추출 과정 재수행). 복구 비용이 가장 크다.
#                .gitignore "절대 커밋 금지" 대상이라 **제외가 곧 무보호**였다.
#   crontab  8잡  봇 자동시작·백업·알람 스케줄. git 0건 / NAS 0건.
# 판별 질문: 제외 근거가 "다른 데 있다"인가 "여기 있으면 안 된다"인가. 후자는 소실 대비 필수.
AGE_REAL="$HOME/.local/bin/age"

# ⑲ cdm 이 **암호화되어** 백업된다 (평문 노출 금지)
if [[ ! -x "$AGE_REAL" ]]; then
  bad "age 바이너리가 없어 cdm 검사 불가 — 건너뛰지 않고 실패로 표시(조용한 skip 금지)"
else
  setup
  mkdir -p "$ROOT/cdm"
  echo "SECRET-DEVICE-KEY-MATERIAL" > "$ROOT/cdm/device_private_key"
  run_backup BACKUP_FORCE_HOUR=03 BACKUP_CDM_SRC="$ROOT/cdm" \
             BACKUP_AGE_BIN="$AGE_REAL" >/dev/null; RC=$?
  if [[ ! -f "$ROOT/nas/cdm.age" ]]; then
    bad "cdm.age 가 생성되지 않았다" "$(logtext)"
  elif grep -qa "SECRET-DEVICE-KEY-MATERIAL" "$ROOT/nas/cdm.age"; then
    # 파일 존재만 보면 tar 만 하고 암호화가 빠져도 통과한다 → 평문이 없는지 직접 확인
    bad "🔴 cdm.age 안에 평문 키가 그대로 들어 있다(암호화 안 됨)"
  elif ! head -c 21 "$ROOT/nas/cdm.age" | grep -qa "age-encryption.org"; then
    bad "cdm.age 가 age 포맷이 아니다" "$(head -c 40 "$ROOT/nas/cdm.age" | tr -d '\0')"
  elif [[ $RC -ne 0 ]]; then
    bad "cdm 백업은 됐는데 rc=$RC" "$(logtext)"
  else
    ok "cdm 암호화 백업 — age 포맷 + 평문 미노출"
  fi
  teardown
fi

# ⑳ crontab 이 백업된다
#    ⚠️ 주입은 **실행 파일 경로**로 한다. `BACKUP_CRONTAB_CMD` 는 스크립트에서 비인용 확장
#    (`$CRONTAB_CMD`)이라 단어 분리에 의존하므로 **따옴표를 포함한 명령을 담을 수 없다**
#    (`printf '...'` 를 넣었더니 따옴표가 리터럴이 되어 깨졌다 — 실제로 한 번 밟음).
#    `eval` 로 풀면 임의 명령 주입면이 생기므로 쓰지 않는다. 기본값 `crontab -l` 처럼
#    **공백 구분 단순 인자**까지만 허용하는 계약이다.
setup
cat > "$ROOT/fake-crontab" <<'FAKE'
#!/bin/bash
printf '0 3 * * * a\n*/5 * * * * b\n'
FAKE
chmod +x "$ROOT/fake-crontab"
run_backup BACKUP_FORCE_HOUR=03 BACKUP_CRONTAB_CMD="$ROOT/fake-crontab" >/dev/null
if [[ ! -f "$ROOT/nas/crontab.txt" ]]; then
  bad "crontab.txt 가 없다" "$(logtext)"
elif [[ "$(grep -c . "$ROOT/nas/crontab.txt")" != "2" ]]; then
  bad "crontab 내용이 온전하지 않다" "$(cat "$ROOT/nas/crontab.txt")"
else
  ok "crontab 백업 (2잡 온전)"
fi

# ㉑ crontab 이 비면 **조용히 넘기지 않는다** — 목록 유실은 stale 감지도 무력화한다
run_backup BACKUP_FORCE_HOUR=03 BACKUP_CRONTAB_CMD="true" >/dev/null; RC=$?
if [[ $RC -eq 0 ]]; then
  bad "crontab 이 비었는데 rc=0 (목록 유실이 조용히 통과)" "$(logtext)"
elif ! logtext | grep -qE "ERROR.*crontab"; then
  bad "crontab 유실이 로그에 안 남았다" "$(logtext)"
else
  ok "crontab 비었음 → rc=$RC + ERROR (감시 목록 유실 감지)"
fi
teardown

# ㉒ 🔴 age 부재는 **조용한 skip 이 아니라 실패**다
#    기존 코드가 `[ -f "$ENV_FILE" ] && [ -x "$AGE_BIN" ]` 였다 — age 가 사라진 날
#    .env 암호화 백업이 **아무 신호 없이** 안 돌았다. sqlite3 4개월 사고와 같은 클래스
#    (의존 부재는 항상 조용하다). 백업할 대상이 있는데 도구가 없는 건 사고다.
setup
echo "TOKEN=xxx" > "$ROOT/fake.env"
run_backup BACKUP_FORCE_HOUR=03 BACKUP_ENV_FILE="$ROOT/fake.env" \
           BACKUP_AGE_BIN="$ROOT/no-such-age" >/dev/null; RC=$?
if [[ $RC -eq 0 ]]; then
  bad "age 없는데 rc=0 (.env 백업이 조용히 skip 됐다)" "$(logtext)"
elif ! logtext | grep -qE "ERROR.*age"; then
  bad "age 부재가 로그에 안 남았다" "$(logtext)"
else
  ok "age 부재 → rc=$RC + ERROR (조용한 skip 아님)"
fi

# ㉓ age 부재가 **다른 축(NAS rsync)까지 죽이지 않는다**
[[ -f "$ROOT/nas/bot-memory/current-tasks.md" ]] \
  && ok "age 부재에도 memory rsync 는 수행됨(축 독립 유지)" \
  || bad "age 부재가 앞 단계까지 무효화했다" "$(logtext)"
teardown

# ⚠️ 판정은 **크기가 아니라 해시**로 한다. `tar` 는 10240바이트 블록으로 패딩하므로
#    작은 파일이 하나 빠져도 **크기가 동일하다**(실측: 1파일 tar = 2파일 tar = 10240 bytes).
#    처음에 크기로 비교했더니 수정 전 코드에서도 통과해 **공허한 테스트**였다.
side_hash() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || echo "none"; }

# ㉔ age 자체 실패가 기존 사본을 파괴하지 않는다 (회귀 가드)
#    ⚠️ 정직한 주석: 이 케이스는 **수정 전에도 통과한다**. 실측 결과 age 는 recipient 검증과
#    입력 파일 열기를 **출력 파일 생성보다 먼저** 하므로, 그 두 실패로는 최종 경로가 안 열린다.
#    즉 "`-o` 가 무조건 즉시 truncate 한다"는 전제는 age 에선 성립하지 않았다.
#    실제 파괴 경로는 ㉕(파이프 중간 실패)뿐이다. 이 케이스는 **age 구현이 바뀌면 깨지도록**
#    남기는 회귀 가드이고, 새 동작을 증명하는 테스트가 아니다.
if [[ ! -x "$AGE_REAL" ]]; then
  bad "age 없어 파괴 검사 불가 — 건너뛰지 않고 실패로 표시"
else
  setup
  mkdir -p "$ROOT/cdm"; echo "SECRET-KEY" > "$ROOT/cdm/device_private_key"
  echo "TOKEN=xxx" > "$ROOT/fake.env"
  # 1회차 정상
  run_backup BACKUP_FORCE_HOUR=03 BACKUP_CDM_SRC="$ROOT/cdm" \
             BACKUP_ENV_FILE="$ROOT/fake.env" BACKUP_AGE_BIN="$AGE_REAL" >/dev/null
  SZ_CDM=$(wc -c < "$ROOT/nas/cdm.age" 2>/dev/null || echo 0)
  SZ_ENV=$(wc -c < "$ROOT/nas/env.age" 2>/dev/null || echo 0)
  if [[ "$SZ_CDM" -eq 0 || "$SZ_ENV" -eq 0 ]]; then
    bad "선행 조건 실패 — 1회차 사본이 없어 파괴 검사가 무의미(공허한 통과 방지)"
  else
    # 2회차: 잘못된 recipient 로 age 를 실패시킨다
    run_backup BACKUP_FORCE_HOUR=03 BACKUP_CDM_SRC="$ROOT/cdm" \
               BACKUP_ENV_FILE="$ROOT/fake.env" BACKUP_AGE_BIN="$AGE_REAL" \
               BACKUP_AGE_PUBKEY="age1invalid-recipient-xxx" >/dev/null; RC=$?
    NOW_CDM=$(wc -c < "$ROOT/nas/cdm.age" 2>/dev/null || echo 0)
    NOW_ENV=$(wc -c < "$ROOT/nas/env.age" 2>/dev/null || echo 0)
    LEFT=$(find "$ROOT/nas" -name '*.partial' 2>/dev/null | wc -l)
    if [[ $RC -eq 0 ]]; then
      bad "age 가 실패했는데 rc=0" "$(logtext)"
    elif [[ "$NOW_CDM" != "$SZ_CDM" || "$NOW_ENV" != "$SZ_ENV" ]]; then
      bad "age 실패가 기존 사본을 파괴했다 (cdm $SZ_CDM→$NOW_CDM, env $SZ_ENV→$NOW_ENV)" "$(logtext)"
    elif [[ "$LEFT" -ne 0 ]]; then
      bad ".partial 잔재 $LEFT 건" "$(ls -la "$ROOT/nas/")"
    else
      ok "age 실패 → 기존 cdm.age·env.age 무사 + .partial 잔재 0 + rc=$RC"
    fi
  fi
  teardown
fi

# ㉕ 🔴 tar 가 실패하면 **암호화 단계로 넘어가지 않는다**
#    파이프(`tar | age`)면 tar 가 중간에 죽어도 age 가 부분 입력을 정상 암호화하고 exit 0 →
#    **포맷·평문 검사를 전부 통과하는 손상 파일**이 남는다. age 는 공개키 전용이라
#    (개인키가 이 머신에 없어) **사후 내용 검증이 불가능**하므로 사전에 막아야 한다.
if [[ ! -x "$AGE_REAL" ]]; then
  bad "age 없어 tar 실패 검사 불가 — 건너뛰지 않고 실패로 표시"
else
  setup
  mkdir -p "$ROOT/cdm"; echo "SECRET-KEY" > "$ROOT/cdm/ok_file"
  run_backup BACKUP_FORCE_HOUR=03 BACKUP_CDM_SRC="$ROOT/cdm" BACKUP_AGE_BIN="$AGE_REAL" >/dev/null
  BASE="$(side_hash "$ROOT/nas/cdm.age")"
  # 읽을 수 없는 파일을 넣어 tar 를 실패시킨다 (root 가 아니어야 유효)
  echo "unreadable" > "$ROOT/cdm/locked"; chmod 000 "$ROOT/cdm/locked"
  if [[ "$BASE" == "none" ]]; then
    bad "선행 조건 실패 — 1회차 사본이 없어 덮어쓰기 검사가 무의미(공허한 통과 방지)"
  elif [[ -r "$ROOT/cdm/locked" ]]; then
    bad "tar 실패 유도 불가 — 권한 무시 환경(root?)이라 판정 무의미(공허한 통과 방지)"
  else
    run_backup BACKUP_FORCE_HOUR=03 BACKUP_CDM_SRC="$ROOT/cdm" BACKUP_AGE_BIN="$AGE_REAL" >/dev/null; RC=$?
    NOW="$(side_hash "$ROOT/nas/cdm.age")"
    LEFT=$(find "$ROOT/nas" -name '*.partial' 2>/dev/null | wc -l)
    if [[ $RC -eq 0 ]]; then
      bad "tar 가 실패했는데 rc=0 (손상 사본이 정상으로 통과)" "$(logtext)"
    elif [[ "$NOW" != "$BASE" ]]; then
      bad "🔴 tar 실패가 기존 사본을 덮었다 (해시 변경) — 손상 아카이브가 최종 경로에 남음" "$(logtext)"
    elif [[ "$LEFT" -ne 0 ]]; then
      bad ".partial 잔재 $LEFT 건" "$(ls -la "$ROOT/nas/")"
    else
      ok "tar 실패 → 암호화 미수행 + 기존 사본 무사(해시 동일) + rc=$RC"
    fi
  fi
  chmod 644 "$ROOT/cdm/locked" 2>/dev/null
  teardown
fi

echo
echo "=== 결과: $pass pass / $fail fail ==="
[[ $fail -eq 0 ]] || exit 1
