#!/bin/bash
# check-core-drift.sh — 코어 뒤처짐 + **받았을 때의 영향**을 함께 본다
#
# 🔴 **2026-08-01 정정: 머리말이 「초안 · 미배선」이라고 적혀 있었으나 실제로는 배선돼 있다.**
#    `crontab: 15 * * * * scripts/core-drift-cron.sh` → 이 파일을 **매시** 부른다.
#    적힌 것과 실재가 **반대**였다(오늘 「적혀 있는데 없는 것」 계열의 뒤집힌 판). 읽는 사람이
#    *"안 도니까 고쳐도 된다"* 로 갈 수 있어 위험한 방향의 거짓이다.
#    ⚠️ 감시 대상은 `CORE_REPO=~/yaksu-bot-core-live`(prod) **하나뿐**이다 — dev 클론은 안 본다.
#
# 왜 두 개를 같이 내나: "5커밋 뒤처짐" 은 행동을 못 정한다.
# "5커밋 뒤처짐 · 받으면 임계값 미달" 은 정한다(먼저 .env 를 올리고 받아라).
#
# 설계 근거(2026-07-28 룬드와 합의):
#   - 요건표를 따로 선언하지 않는다. 요건은 코어 코드에 있으므로(2000+PREFIX_MAX)
#     선언하면 **두 번째 소스**가 된다 → 대신 **입력 트리의 판정 코드를 dry-run** 한다.
#   - 플래그로 값을 넘기지 않는다. `.env` 를 source 해서 process.env 로 넘긴다.
#     명시 전달은 **내가 아는 값만** 검사하게 만들어, 코어에 검사가 추가돼도 안 덮인다.
#   - 🔑 종료코드 계약 (2026-07-28 양봇 합의 — 코어 run-tests 계열로 통일):
#       0 정상 · **1 위반(조치 있음)** · **2 판정 불가** · 그 외(126·127·128+) ⇒ 판정 불가로 접는다
#     ⚠️ "판정 불가" 를 "미달" 로 보고하지 않는다 — 없는 경고는 pull 을 미루게 해
#        오히려 위험(옛 코드로 계속 돎)을 늘린다.
#     🔴 **이전엔 1·2 가 반대였다**(0=충족 · 2=요건 미달 · 그 외=실행 실패). 같은 레포의
#        check-runner-drift.sh 는 이미 `2=판정 불가` 였다 — 한 디렉터리에 두 규약이 있었고,
#        둘 다 자기 헤더에 "계약대로" 라고 적혀 있어서 각 파일만 읽으면 충돌이 안 보였다.
#     🔑 옛 형태가 갖고 있던 건 **"그 외" 뭉치**다(126·127 을 삼킴). 숫자는 다수파로 가되
#        그 뭉치는 계약 마지막 항으로 남긴다 — 버리면 셸이 내는 코드가 갈래 밖으로 샌다.
set -uo pipefail

# 🤝 자동 발신엔 `[감시]` 를 붙인다 — 셔틀이 이 변수를 보고 «모든» 전송에 태그한다.
#    호출 자리마다 붙이지 않는 이유: 새 전송을 추가해도 자동으로 태그되게(환경에 건다).
export NINO_AUTOSEND=1

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
  [ -e "$f" ] || { echo "ERROR: 없음 — $f"; exit 2; }
done

# ⚠️ fetch 없이 @{u} 를 읽으면 **항상 0** 이 나온다(조용한 성공). 반드시 선행.
if ! git -C "$CORE_REPO" fetch -q origin 2>/dev/null; then
  echo "WARN: fetch 실패 — 뒤처짐 판정 불가(네트워크·인증)"; exit 2
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
  # 🔴 **`relay/discord-send/` 는 빼고 센다 — 그건 «부를 때마다 새 프로세스»인 CLI 라 재시작과 무관하다.**
  #   좌변은 「코어 안의 .js 가 새로운가」가 아니라 **「이 «프로세스»가 물고 있는 코드가 낡았나」**다.
  #   ⚠️ **경로에 주의** — 그 CLI 는 최상위 `discord-send/` 가 «아니라» `relay/discord-send/` 에 산다
  #     (최상위엔 그 디렉터리가 **없다**). 그래서 `find "$CORE_REPO/relay"` 로 좁히는 것만으로는
  #     **안 빠진다** — 내가 처음에 그렇게 고쳤다가 대조군(여전히 2건)에 걸렸다.
  #   실측 2026-08-15 (분모는 `relay/` **트리 전체**, 자기 참조 제외):
  #     `grep -rE "require\(|from ['\"]" relay --include='*.js' | grep -i discord-send` → **0건**
  #     유닛은 `bun relay/index.js` 하나만 띄우고(`systemctl show -p ExecStart`),
  #     그 파일이 무는 것은 `./core`·`./db`·`./tmux-bridge`·`./addon-loader`·`./mentions`·`./formatter` 뿐이다.
  #   🔑 **오탐의 대가가 컸다**: `relay/discord-send/{cli,parser}.js` 가 16:16·17:35 에 바뀌자
  #     18:15·19:15·20:15 **세 시간 동안 매시** 「재시작 안 됨」이 나갔다. 재시작해도 «아무것도
  #     안 바뀌는» 상태였다(그 CLI 는 이미 새 파일을 읽고 있었다). ⚠️ 이 알림은 `process_behind>0`
  #     이면 억제를 **끄는** 갈래라, **오탐이 곧 무제한 반복**이 된다.
  #   ⚠️ 그때 받은 처방이 「나이(첫 관측 이후 경과)를 붙이자」였는데, **그걸 먼저 넣었으면
  #     오탐에 나이가 붙어 «더 급해» 보였을 것이다** — 좌변이 틀린 채로 표현만 고치는 꼴이다.
  #   🔸 `discord-send` 가 바뀌어도 다음 «호출»이 새 코드를 쓴다 — 놓치는 것이 없다.
  find "$CORE_REPO/relay" -name '*.js' ! -path '*/discord-send/*' -newermt "@$pstart" 2>/dev/null | wc -l
}

BEHIND="$(git -C "$CORE_REPO" rev-list --count HEAD..@{u} 2>/dev/null)" || BEHIND=""
[ -n "$BEHIND" ] || { echo "WARN: @{u} 없음 — upstream 미설정"; exit 2; }
PBEHIND="$(process_behind)"

# 🔑 `?` 는 **0 도 N 도 아닌 세 번째 상태**다 — "못 쟀다".
#    이걸 STALE 로 접으면 *값이 없는데 조치(재시작)를 지시*하게 된다. 실제로 첫 실전 발동에서
#    `process_behind=?파일 — 재시작 안 됨` 이 나갔다: 판정은 우연히 맞았고 근거는 비어 있었다.
#    종료코드 계약대로 **2(판정 불가)** 로 낸다 — 1(위반)과 갈려야 래퍼가 다른 문장을 쓴다.
if [ "$PBEHIND" = "?" ]; then
  echo "WARN: process_behind 판정 불가 — $RELAY_UNIT 의 MainPID/시작시각을 못 구했다"
  echo "  repo_behind=${BEHIND}커밋 (이 값은 유효)"
  echo "  흔한 원인: cron 에 XDG_RUNTIME_DIR 이 없어 systemctl --user 가 버스에 못 붙음 · 유닛 미기동"
  exit 2
fi

if [ "$BEHIND" = "0" ]; then
  if [ "$PBEHIND" = "0" ]; then
    echo "OK: repo_behind=0 · process_behind=0 ($(git -C "$CORE_REPO" rev-parse --short HEAD))"
    exit 0
  fi
  # 레포는 최신인데 프로세스가 낡음 = pull 은 했고 재시작을 안 한 상태
  echo "STALE: repo_behind=0 · **process_behind=${PBEHIND}파일** — 코드는 받았고 **재시작 안 됨**"
  echo "  조치: systemctl --user restart $RELAY_UNIT (pull 불필요)"
  exit 1
fi

echo "DRIFT: repo_behind=${BEHIND}커밋 · process_behind=${PBEHIND}파일 ($(git -C "$CORE_REPO" rev-parse --short HEAD) → $(git -C "$CORE_REPO" rev-parse --short @{u}))"
git -C "$CORE_REPO" log --oneline HEAD..@{u} | sed 's/^/  /'

# 런타임 코드가 섞였는지 — lint/docs 만이면 급하지 않다
# 🔴 여기는 **포함 목록**이었고 라이브에서 거짓 초록을 냈다(2026-07-31): 코어가 `tmux-send.sh` 를
#    바꾼 뒤처짐에서 "런타임 파일 변경: 0건" 이 나갔다. 판정은 lib 한 곳으로 옮기고 **제외 목록**으로
#    뒤집었다 — 모르는 경로는 런타임으로 센다. 근거·두 번째 결함은 lib 헤더 참고.
# shellcheck source=lib/core-runtime-files.sh
. "$(dirname "$0")/lib/core-runtime-files.sh"
RUNTIME="$(git -C "$CORE_REPO" diff --name-only HEAD..@{u} | count_runtime_paths)"
echo "  런타임 파일 변경: ${RUNTIME}건"
if [ "$RUNTIME" -gt 0 ]; then
    git -C "$CORE_REPO" diff --name-only HEAD..@{u} | while IFS= read -r f; do
        core_is_runtime_path "$f" && echo "    · $f"
    done
fi

# ── 받았을 때의 영향: 입력 트리의 판정 코드를 내 설정에 대고 dry-run ──
WORKTREE="$(mktemp -d)"
if ! git -C "$CORE_REPO" worktree add -q --detach "$WORKTREE" @{u} 2>/dev/null; then
  echo "  ⚠️ 영향 판정 불가 — 워크트리 생성 실패"; exit 2
fi

if [ ! -f "$WORKTREE/$CHECK_REL" ]; then
  echo "  ⚠️ 영향 판정 불가 — 입력 트리에 $CHECK_REL 없음(코어 PR #67 이전 버전)"
  exit 2
fi

set -a; . "$BOT_ENV"; set +a
# 🔴 맨 `node` 를 부르면 **cron 에서 매번 rc=127** 이다 — cron 의 PATH 는 `/usr/bin:/bin`
#    뿐이라 nvm·~/.local/bin 이 안 보인다.
#    ⚠️ 발견자는 **이 검사 자신**이다(2026-07-28 20:15 드리프트 알림이 스스로 rc=127 을 리포트).
#    룬드는 그 알림을 읽고 같은 클래스가 자기 쪽에 있는지 전수 확인했고 — 없었다.
#    판정 불가로 떨어지니 거짓말은 아니었지만 **이 검사가 cron 에서 한 번도 안 돌았다.**
#    *정직한 무능도 무능이다.* 해석은 scripts/lib/resolve-bin.sh 한 곳을 지난다.
. "$(dirname "$0")/lib/resolve-bin.sh"
if ! NODE="$(resolve_bin node "${NODE_BIN:-}")"; then
  echo "  ⚠️ 영향 판정 불가 — node 를 못 찾았다(cron PATH 는 /usr/bin:/bin)"
  echo "     NODE_BIN 으로 경로를 주거나 nvm/~/.local/bin 설치를 확인할 것"
  exit 2
fi
OUT="$("$NODE" "$WORKTREE/$CHECK_REL" 2>&1)"; RC=$?
case "$RC" in
  0) echo "  ✅ 받아도 설정 요건 충족" ;;
  2) echo "  🔴 받으면 설정 요건 미달 — **먼저 .env 를 고치고 받을 것**"
     echo "$OUT" | sed 's/^/     /' ;;
  *) echo "  ⚠️ 영향 판정 불가 — 검사 실행 실패(rc=$RC)"
     echo "$OUT" | sed 's/^/     /' ;;
esac

# 🔴 여기는 **DRIFT 갈래**다 — 조치(pull)가 있으므로 **1(위반)** 로 나간다.
#    2026-07-28 13:5x 까지 `exit 0` 이었고, 그래서 `core-drift-cron.sh:36`
#    (`[ "$RC" -eq 0 ] && exit 0`)이 알림 전에 빠져나갔다. 실제 로그:
#      12:08 rc=0 DRIFT: repo_behind=3커밋   ← 발견해놓고 조용
#      13:15 rc=0 DRIFT: repo_behind=4커밋
#    결과: 라이브 코어가 5커밋 뒤처진 채였고 lint 셔틀이 스테일 정본을 실행했다.
#    ⚠️ 래퍼 헤더엔 이미 *"없는 경고는 pull 을 미루게 해서 옛 코드로 계속 돌게 만든다"* 라고
#       적혀 있었다. **래퍼는 이 사고를 예상했는데 검사 쪽이 0을 내서 두 반쪽이 어긋났다** —
#       계약을 양쪽에 적어놓고 한쪽만 지킨 것이라, 문서가 아니라 시험으로 잠근다(⑤).
#    위 case 의 `2`(받으면 요건 미달)도 여기로 온다 — 그것도 조치가 필요한 상태다.
#    ⚠️ 저 `case` 가 읽는 건 **코어 쪽 node 검사기의 rc** 이고 그건 아직 옛 계약(0/2/그 외)이다.
#       코어 파일이라 이 PR 범위 밖 — 룬드 승인 후 별건. 여기서는 `*` 뭉치가 있어 안 샌다.
exit 1
