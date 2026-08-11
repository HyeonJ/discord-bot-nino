#!/usr/bin/env bash
# 시각 독립성 — **시험이 「몇 시에 도는가」로 답이 갈리면 안 된다.**
#
# 왜 이 파일이 생겼나 (2026-08-11):
#   `#173` 의 CI 가 빨갛게 났는데 **그 PR 의 diff 에 원인이 없었다.** 러너가 16:47 UTC
#   = **01:47 KST** 에 돌았고, `#152` 가 넣은 「기본 취침 시간대 1~7시」가 발동해
#   `darren-mention-guard` 의 앞 블록이 통째로 뒤집혔다(**27 pass · 16 fail**).
#   그 블록만 `DARREN_NOW_EPOCH` 를 안 박아서 **혼자 벽시계로 돌고 있었다.**
#
#   🔴 **이 꼴의 나쁨은 「빨강」이 아니라 「분모 밖」이다** — 원장의 「실패 0」 이력은
#     *그 창에 안 돌았다*는 뜻이지 *쟀다*는 뜻이 아니다. 하루 24분의 6이 미측정이었다.
#   🔑 주석으로 *「새 블록엔 시각을 박아라」*라고 적는 건 **규칙이지 가드가 아니다.**
#     다음 사람은 주석을 안 읽고, 안 읽어도 초록이 나온다 — 그 시각에 안 돌면.
#
# 🔴 **첫 판은 «항진명제»였다 (룬드 `#175` 리뷰 ①).** 하위 시험을 시각 둘로 돌려 결과를
#   비교했는데, 그 시험 머리가 `export DARREN_NOW_EPOCH="$(kst 14)"` 라 **바깥 값이 즉시 죽었다.**
#   두 회차가 **둘 다 14시로** 돌았고, 「결과가 같다」는 「시각 독립」이 아니라 **「주입이 안 먹힌다」**였다.
#   ⇒ 하위 시험 쪽을 `:-` 로 고치고(밖에서 줄 때만 진다), **여기서는 그 비교를 «없앴다»** —
#     `:-` 를 넣으면 하위 시험은 주입받은 시각으로 정직하게 갈리므로 「같아야 한다」가 애초에 틀린 좌변이다.
#
# 🔴 **처음엔 근거를 «동어반복»으로도 적었다** — *「벽시계 01:47 과 주입 03:30 이 똑같이
#   27/16 을 냈으니 같은 자리다」*. 안 선다: **두 조건이 «같은 답»을 요구한다**(둘 다 취침 창 안).
#   주입이 완전히 다른 경로로 들어가도, 아예 무시돼도 같은 숫자가 나온다.
#   ⇒ **갈라주는 형태는 「두 조건이 «다른» 답을 요구하게 만드는 것」**이고, **양방향 둘 다** 봐야 한다.
#
# 이 파일이 세우는 셋:
#   ① **양성 대조군** — 시각을 «안 박은» 최소 픽스처는 시각에 따라 «반드시 갈린다».
#      안 갈리면 이 검사기 자체가 죽은 것이다(초록이 아무 뜻도 없어진다).
#   ② **우선권** — 주입이 벽시계를 이긴다(양방향).
#   ③ **전수** — 훅을 부르면서 시각을 안 박은 시험 파일이 «없다». 목록이 아니라 **파일을 읽어서** 센다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../claude-config/hooks/darren-mention-guard.sh"

pass=0; fail=0; unk=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     $2"; fail=$((fail + 1)); }
unknown() { echo "  ⛔ 판정 불가 — $1"; unk=$((unk + 1)); }

# KST 자정으로 정규화 — 러너 TZ 가 UTC 라 리터럴 epoch 은 「몇 시인가」가 갈린다.
# 🔸 `_B` 가 «무슨 날»인지는 상관없다 — 아래 `KST_MIDNIGHT` 정규화가 날짜를 흡수하고
#   남는 것은 「자정 + N시간」뿐이다. 리터럴에 의미를 찾지 말 것.
_B=1786000000
KST_MIDNIGHT=$(( _B - (_B + 32400) % 86400 ))
kst() { echo $(( KST_MIDNIGHT + $1 * 3600 + 1800 )); }

# 훅을 한 번 찌른다. 멘션 없는 발신 하나로 두 상태가 갈린다:
#   깨어 있음 → **차단(rc=2)**   ·   취침 창 안 → **무음 통과(rc=0)**
# $1=주입할 epoch(빈 문자열이면 «주입 없음» = 벽시계) / WIN_FROM·WIN_TO 로 창을 옮긴다
probe_win() {
  local epoch="$1" json
  json="$(printf '%s' 'discord-send 현인-업무 "보고"' | python3 -c '
import json,sys
print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))
')"
  if [ -n "$epoch" ]; then
    printf '%s' "$json" | env -u DARREN_SLEEP_FLAG \
      DARREN_SLEEP_FROM="${WIN_FROM:-1}" DARREN_SLEEP_TO="${WIN_TO:-7}" \
      DARREN_NOW_EPOCH="$epoch" bash "$HOOK" >/dev/null 2>&1
  else
    printf '%s' "$json" | env -u DARREN_SLEEP_FLAG -u DARREN_NOW_EPOCH \
      DARREN_SLEEP_FROM="${WIN_FROM:-1}" DARREN_SLEEP_TO="${WIN_TO:-7}" \
      bash "$HOOK" >/dev/null 2>&1
  fi
  echo $?
}
probe() { probe_win "$1"; }   # 기본 창(1~7)

if [ ! -f "$HOOK" ]; then
  echo "⛔ 판정 불가 — 훅이 없다: $HOOK"
  echo ""
  echo "결과: 0 pass, 0 fail, 판정 불가 1"
  exit 2
fi

# ── ① 양성 대조군 — 「안 박으면 갈린다」가 참이라야 이 검사기가 산다 ──────────────
# 🔑 **이게 없으면 ②③ 의 초록이 「우연히 안 걸렸다」와 구별이 안 된다.**
#   변이를 매번 손으로 심는 대신 **상시 대조군**으로 박는다 — 다음 사람이 이 파일을
#   리팩터링하다 주입 경로를 끊으면 **그 자리에서 빨개진다**(룬드 `#175` 리뷰 ②).
echo "① 양성 대조군 — 시각을 «안 박은» 호출은 시각에 따라 갈리는가"
CTL_A="$(probe "$(kst 3)")"    # 취침 창 «안»
CTL_B="$(probe "$(kst 14)")"   # 취침 창 «밖»
if [ "$CTL_A" = "$CTL_B" ]; then
  bad "안 갈렸다 — 이 검사기는 갈림을 «못 본다»(②③ 의 초록이 무의미해진다)" \
      "3시 rc=$CTL_A · 14시 rc=$CTL_B (기대: 0 ↔ 2)"
elif [ "$CTL_A" = "0" ] && [ "$CTL_B" = "2" ]; then
  ok "3시 rc=0(취침) ↔ 14시 rc=2(깨어있음) — 갈림을 본다"
else
  bad "갈리긴 하는데 방향이 다르다 — 훅의 계약이 바뀌었나" "3시 rc=$CTL_A · 14시 rc=$CTL_B"
fi

# ── ② 우선권 — 주입이 벽시계를 «이기나» (두 조건이 다른 답을 요구하게 만든다) ─────
echo ""
echo "② 우선권 — 주입이 벽시계를 이기는가"
WALL_H="$(( ( ($(date +%s) + 32400) / 3600 ) % 24 ))"   # 훅과 «같은» 산술로 낸다
echo "  · 지금 벽시계 KST ${WALL_H}시"

# 방향 A: 벽시계 «밖» + 주입 «안» → 답이 「취침」이면 주입이 이긴 것
if [ "$WALL_H" -ge 1 ] && [ "$WALL_H" -le 6 ]; then
  unknown "방향 A 는 벽시계가 창 «밖»이라야 하는데 지금 안이다(KST ${WALL_H}시)"
else
  base_a="$(probe "")"
  got_a="$(probe "$(kst 3)")"
  if [ "$base_a" = "$got_a" ]; then
    unknown "방향 A 의 두 조건이 «같은 답»을 요구한다(둘 다 rc=$base_a). 가르지 못한다"
  elif [ "$got_a" = "0" ]; then
    ok "방향 A — 벽시계 밖(rc=$base_a) + 주입 03시 → «취침»(rc=0). 주입이 이긴다"
  else
    bad "방향 A — 주입이 무시됐다" "rc=$got_a (기대 0, 대조군 $base_a)"
  fi
fi

# 방향 B: 벽시계 «안» + 주입 «밖» → 답이 「깨어있음」이면 주입이 이긴 것
# 🔑 **시계를 못 옮기면 «창»을 옮긴다.** 훅은 `date +%s`(TZ 무관) + 에폭 산술로 시를 내므로
#   TZ 로는 못 속인다. 대신 창을 지금 시각 위에 얹으면 벽시계가 «창 안»이 된다.
#   ⇒ 한쪽을 «영구 판정 불가»로 두지 않는다 — 줄어들 수 없는 판불은 원장을 영구 동결로 민다.
INJ_B=$(( (WALL_H + 5) % 24 ))
base_b="$(WIN_FROM="$WALL_H" WIN_TO=$((WALL_H + 1)) probe_win "")"
got_b="$(WIN_FROM="$WALL_H" WIN_TO=$((WALL_H + 1)) probe_win "$(kst "$INJ_B")")"
if [ "$base_b" = "$got_b" ]; then
  unknown "방향 B 의 두 조건이 «같은 답»을 요구한다(둘 다 rc=$base_b). 가르지 못한다"
elif [ "$got_b" = "2" ]; then
  ok "방향 B — 창을 ${WALL_H}시에 얹어 벽시계를 «안»으로(rc=$base_b) + 주입 ${INJ_B}시 → «깨어있음»(rc=2). 주입이 이긴다"
else
  bad "방향 B — 주입이 무시됐다" "rc=$got_b (기대 2, 대조군 $base_b)"
fi

# ── ③ 전수 — 훅을 부르면서 시각을 «안 박은» 시험이 없다 ────────────────────────
# 🔴 **첫 판은 여기를 「대상 목록」으로 뒀는데, 그건 내가 이 파일에서 비판한 바로 그 꼴이다**
#   (룬드 리뷰 ③): *「목록이 낡으면 새 시험이 이 검사 밖에 산다」*는 **규칙이지 가드가 아니고,
#   미탐은 무음**이다. ⇒ 목록 대신 **파일을 읽어서 센다.**
# 🔑 시험을 «돌리는» 게 아니라 «읽는» 것이라 시간이 거의 안 든다.
#   새 시험이 훅을 부르면서 시각을 안 박으면 **그 자리에서 빨갛다.**
# ⚠️ 좌변은 문자열이라 하한이다 — 「훅을 부른다」를 파일명 언급으로 잡는다. 우회는 가능하고,
#   그 우회를 잡는 것은 ①의 대조군이 아니라 **사람**이다. 그래도 **무음보다 낫다.**
echo ""
echo "③ 전수 — 훅을 부르는 시험은 시각을 박는다"
HOOK_BASE="darren-mention-guard.sh"
EXEMPT="clock-independence.test.sh"   # 이 파일 자신은 «일부러» 안 박고 찌른다
MISSING=""
for f in "$SCRIPT_DIR"/*.test.sh; do
  b="$(basename "$f")"
  case " $EXEMPT " in *" $b "*) continue ;; esac
  grep -q "$HOOK_BASE" "$f" || continue

  # 🔴 **「파일 어딘가에 그 이름이 있나」로는 «안 잡힌다» — 변이로 확인했다.**
  #   머리 핀을 지워도 뒤 블록들이 각자 `DARREN_NOW_EPOCH=` 를 쓰므로 그 좌변은 여전히 참이다.
  #   ⇒ 좌변을 **«순서»**로 옮긴다: **첫 «훅 호출»보다 첫 «시각 박기»가 앞에 있나.**
  #   그게 정확히 사고의 자리다(머리 블록이 안 박힌 채 훅을 부른다).
  _inv="$(grep -n 'bash "\$HOOK"' "$f" | head -1 | cut -d: -f1)"
  # 🔴 **좌변이 「그 이름이 나오나」면 «주석»이 먼저 걸린다** — 실제로 걸렸다(이 파일 22행이
  #   그 함정을 «설명하는» 주석인데 변이가 그걸로 통과했다). ⇒ **줄머리 대입만** 센다.
  #   같은 병을 오늘 세 번째 본다(비ASCII 가드 오탐 · 룬드 픽스처 · 여기) — 축은 늘
  #   **「말하는 줄」과 「하는 줄」**이다.
  _pin="$(grep -nE '^[[:space:]]*(export[[:space:]]+)?DARREN_NOW_EPOCH=' "$f" | head -1 | cut -d: -f1)"
  [ -n "$_inv" ] || continue                       # 참조만 하고 안 부르면 대상 아님
  if [ -z "$_pin" ] || [ "$_pin" -gt "$_inv" ]; then
    MISSING="${MISSING}${b}(호출 ${_inv}행 · 박기 ${_pin:-없음}) "
  fi
done
if [ -z "$MISSING" ]; then
  ok "훅을 부르는 시험 전부가 «첫 호출보다 먼저» 시각을 박는다 (면제: $EXEMPT)"
else
  bad "첫 훅 호출 «앞»에 시각을 안 박은 시험이 있다 — 그 구간은 벽시계에 끌려간다" "$MISSING"
fi

echo ""
echo "결과: $pass pass, $fail fail, 판정 불가 $unk"
# 🔑 판정 불가를 rc=0 으로 접지 않는다 — 러너가 0/1/**2** 를 구분한다.
[[ $fail -eq 0 ]] || exit 1
[[ $unk -eq 0 ]] || exit 2
