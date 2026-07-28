#!/bin/bash
# check-core-drift.sh — 코어 뒤처짐 + **받았을 때의 영향**을 함께 본다 (초안 · 미배선)
#
# 왜 두 개를 같이 내나: "5커밋 뒤처짐" 은 행동을 못 정한다.
# "5커밋 뒤처짐 · 받으면 임계값 미달" 은 정한다(먼저 .env 를 올리고 받아라).
#
# 설계 근거(2026-07-28 룬드와 합의):
#   - 요건표를 따로 선언하지 않는다. 요건은 코어 코드에 있으므로(2000+PREFIX_MAX)
#     선언하면 **두 번째 소스**가 된다 → 대신 **입력 트리의 판정 코드를 dry-run** 한다.
#   - 플래그로 값을 넘기지 않는다. `.env` 를 source 해서 process.env 로 넘긴다.
#     명시 전달은 **내가 아는 값만** 검사하게 만들어, 코어에 검사가 추가돼도 안 덮인다.
#   - 종료코드 계약(코어 PR #67): 0=충족 · 2=요건 미달 · 그 외=실행 실패(판정 불가)
#     ⚠️ "판정 불가" 를 "미달" 로 보고하지 않는다 — 없는 경고는 pull 을 미루게 해
#        오히려 위험(옛 코드로 계속 돎)을 늘린다.
set -uo pipefail

# 🔴 cron 에서 돌 때 `systemctl --user` 는 이게 없으면 실패한다:
#    "Failed to connect to bus: No medium found" (2026-07-28 실측)
#    그러면 MainPID 를 못 구하고 process_behind 가 `?` 가 된다 — 실제로 첫 실전 발동에서 그랬다.
#    로그인 셸에는 있고 cron 에는 없는 값이라, **손으로 돌리면 되고 cron 에서만 깨진다**.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

CORE_REPO="${CORE_REPO:-$HOME/yaksu-bot-core-live}"
BOT_ENV="${BOT_ENV:-$HOME/discord-bot-nino/.env}"
RELAY_UNIT="${RELAY_UNIT:-nino-relay.service}"
CHECK_REL="relay/check-config.js"

WORKTREE=""
cleanup() { [ -n "$WORKTREE" ] && git -C "$CORE_REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1; }
trap cleanup EXIT

for f in "$CORE_REPO/.git" "$BOT_ENV"; do
  [ -e "$f" ] || { echo "ERROR: 없음 — $f"; exit 1; }
done

# ⚠️ fetch 없이 @{u} 를 읽으면 **항상 0** 이 나온다(조용한 성공). 반드시 선행.
if ! git -C "$CORE_REPO" fetch -q origin 2>/dev/null; then
  echo "WARN: fetch 실패 — 뒤처짐 판정 불가(네트워크·인증)"; exit 1
fi

# ── 두 축을 **이름으로 갈라** 잰다 (2026-07-28 룬드 M:wy0a 로 발견한 구멍) ──
#   repo_behind    = origin 대비 레포가 뒤처짐        → **pull** 로 해소
#   process_behind = 레포 대비 실행 프로세스가 낡음   → **재시작** 으로 해소
# ⚠️ 초안은 repo_behind 만 봤다. 그래서 **pull 직후 재시작 전**에 repo_behind=0 이 되어
#    `OK: 코어 최신` 을 출력했다 — 정작 재시작이 필요한 순간에 조용해지는 구멍이었다.
#    같은 이름("N커밋 뒤처짐")으로 두 대상을 재면 두 행동이 뭉개진다.
# ⚠️ 프로세스는 패턴 검색으로 찾지 않는다(`pgrep -f` 는 자기 명령줄을 잡고, 실행기가
#    node 가 아니라 bun 일 수 있다) — **관리자에게 묻는다**.
process_behind() {
  local pid pstart
  pid="$(systemctl --user show -p MainPID --value "$RELAY_UNIT" 2>/dev/null)"
  [ -n "$pid" ] && [ "$pid" != "0" ] || { echo "?"; return; }
  pstart="$(date -d "$(ps -o lstart= -p "$pid" 2>/dev/null)" +%s 2>/dev/null)" || { echo "?"; return; }
  find "$CORE_REPO/relay" "$CORE_REPO/discord-send" -name '*.js' -newermt "@$pstart" 2>/dev/null | wc -l
}

BEHIND="$(git -C "$CORE_REPO" rev-list --count HEAD..@{u} 2>/dev/null)" || BEHIND=""
[ -n "$BEHIND" ] || { echo "WARN: @{u} 없음 — upstream 미설정"; exit 1; }
PBEHIND="$(process_behind)"

# 🔑 `?` 는 **0 도 N 도 아닌 세 번째 상태**다 — "못 쟀다".
#    이걸 STALE 로 접으면 *값이 없는데 조치(재시작)를 지시*하게 된다. 실제로 첫 실전 발동에서
#    `process_behind=?파일 — 재시작 안 됨` 이 나갔다: 판정은 우연히 맞았고 근거는 비어 있었다.
#    종료코드 계약대로 **1(판정 불가)** 로 낸다 — 2(미달)와 갈려야 래퍼가 다른 문장을 쓴다.
if [ "$PBEHIND" = "?" ]; then
  echo "WARN: process_behind 판정 불가 — $RELAY_UNIT 의 MainPID/시작시각을 못 구했다"
  echo "  repo_behind=${BEHIND}커밋 (이 값은 유효)"
  echo "  흔한 원인: cron 에 XDG_RUNTIME_DIR 이 없어 systemctl --user 가 버스에 못 붙음 · 유닛 미기동"
  exit 1
fi

if [ "$BEHIND" = "0" ]; then
  if [ "$PBEHIND" = "0" ]; then
    echo "OK: repo_behind=0 · process_behind=0 ($(git -C "$CORE_REPO" rev-parse --short HEAD))"
    exit 0
  fi
  # 레포는 최신인데 프로세스가 낡음 = pull 은 했고 재시작을 안 한 상태
  echo "STALE: repo_behind=0 · **process_behind=${PBEHIND}파일** — 코드는 받았고 **재시작 안 됨**"
  echo "  조치: systemctl --user restart $RELAY_UNIT (pull 불필요)"
  exit 2
fi

echo "DRIFT: repo_behind=${BEHIND}커밋 · process_behind=${PBEHIND}파일 ($(git -C "$CORE_REPO" rev-parse --short HEAD) → $(git -C "$CORE_REPO" rev-parse --short @{u}))"
git -C "$CORE_REPO" log --oneline HEAD..@{u} | sed 's/^/  /'

# 런타임 코드가 섞였는지 — lint/docs 만이면 급하지 않다
RUNTIME="$(git -C "$CORE_REPO" diff --name-only HEAD..@{u} | grep -cE '^(relay|discord-send)/')"
echo "  런타임 파일 변경: ${RUNTIME}건"

# ── 받았을 때의 영향: 입력 트리의 판정 코드를 내 설정에 대고 dry-run ──
WORKTREE="$(mktemp -d)"
if ! git -C "$CORE_REPO" worktree add -q --detach "$WORKTREE" @{u} 2>/dev/null; then
  echo "  ⚠️ 영향 판정 불가 — 워크트리 생성 실패"; exit 1
fi

if [ ! -f "$WORKTREE/$CHECK_REL" ]; then
  echo "  ⚠️ 영향 판정 불가 — 입력 트리에 $CHECK_REL 없음(코어 PR #67 이전 버전)"
  exit 1
fi

set -a; . "$BOT_ENV"; set +a
OUT="$(node "$WORKTREE/$CHECK_REL" 2>&1)"; RC=$?
case "$RC" in
  0) echo "  ✅ 받아도 설정 요건 충족" ;;
  2) echo "  🔴 받으면 설정 요건 미달 — **먼저 .env 를 고치고 받을 것**"
     echo "$OUT" | sed 's/^/     /' ;;
  *) echo "  ⚠️ 영향 판정 불가 — 검사 실행 실패(rc=$RC)"
     echo "$OUT" | sed 's/^/     /' ;;
esac
exit 0
