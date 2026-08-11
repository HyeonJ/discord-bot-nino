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
# ⚠️ **한계를 먼저 적는다**: 여기서 벽시계를 «진짜로» 못 바꾼다(러너 시계를 못 만진다).
#   그래서 **상속된 새벽 epoch** 으로 대신 잰다.
#   ⇒ 이 시험이 잡는 것: *「하위 시험이 자기 시각을 안 박아 바깥 값에 끌려간다」*.
#   근거는 **변이**다 — 핀 한 줄을 지우면 3시에서 빨강(27/16), 14시는 초록.
#
# 🔴 **처음엔 근거를 «동어반복»으로 적었다가 룬드가 잡았다(2026-08-11).**
#   내가 댄 것: *「벽시계 01:47 과 주입 03:30 이 똑같이 27/16 을 냈으니 같은 자리다」*.
#   ⛔ 안 선다 — **두 조건이 «같은 답»을 요구한다.** 둘 다 취침 창(1~7시) 안이라,
#   주입이 **완전히 다른 경로로 들어가도, 아예 무시돼도** 벽시계가 그 시각이라 같은 숫자가 나온다.
#   ⇒ 그 관측은 「주입이 벽시계와 같은 자리를 건드린다」와 「주입이 무시됐다」를 **구별하지 않는다.**
#
# ✅ **갈라주는 형태는 「두 조건이 «다른» 답을 요구하게 만드는 것」이다** — 아래 ② 절.
#   🔑 **양방향 둘 다** 봐야 한다. 한 방향만 보면 *「주입이 무시됐는데 우연히 벽시계가 그 답」*이
#     통과한다 — 그게 정확히 위에서 내가 밟은 갈래다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     $2"; fail=$((fail + 1)); }

# KST 자정으로 정규화 — 러너 TZ 가 UTC 라 리터럴 epoch 은 「몇 시인가」가 갈린다
_B=1786000000
KST_MIDNIGHT=$(( _B - (_B + 32400) % 86400 ))
kst() { echo $(( KST_MIDNIGHT + $1 * 3600 + 1800 )); }

# 🔑 **대상 목록을 여기 «적는다»** — 전 시험 자동 순회로 만들면 시간이 N배가 되고,
#   시각을 «일부러» 좌변으로 쓰는 시험(취침 시간대 자체를 재는 것)까지 끌려온다.
#   ⚠️ 목록이 낡으면 새 시험이 이 검사 밖에 산다. 좁아지는 쪽 실패라 결함은 아니지만,
#     새 시험이 시각을 읽으면 **여기 등재하는 것이 수리**다.
TARGETS="darren-mention-guard"

# 새벽(취침 창 안)과 낮(밖) — 이 둘에서 결과가 같아야 한다
HOURS="3 14"

for t in $TARGETS; do
  f="$SCRIPT_DIR/$t.test.sh"
  if [ ! -f "$f" ]; then
    echo "  ⛔ 판정 불가 — $t.test.sh 가 없다(이름이 바뀌었나)"
    fail=$((fail + 1))
    continue
  fi

  first=""
  for h in $HOURS; do
    out="$(DARREN_NOW_EPOCH="$(kst "$h")" bash "$f" 2>&1)"
    rc=$?
    line="$(printf '%s\n' "$out" | grep -E '^결과:' | tail -1)"

    if [ "$rc" -ne 0 ]; then
      bad "$t — KST ${h}시에 빨강 (rc=$rc)" "${line:-결과 줄을 못 찾았다}"
      continue
    fi
    # 🔑 **rc 만 보면 부족하다** — 통과 «수»가 갈리면 시각이 시험 개수를 바꾼 것이고,
    #   그건 rc=0 인 채로도 「다른 시험을 돌렸다」는 뜻이다.
    if [ -z "$first" ]; then
      first="$line"
      ok "$t — KST ${h}시 초록 ($line)"
    elif [ "$line" = "$first" ]; then
      ok "$t — KST ${h}시가 ${first:+같은} 결과 ($line)"
    else
      bad "$t — 시각에 따라 «결과가 갈린다»" "3시: $first / ${h}시: $line"
    fi
  done
done


# ② **우선권 — 주입이 벽시계를 «이기나».** ①의 전제가 여기서 서거나 무너진다.
#   좌변을 「두 조건이 «다른» 답을 요구하는가」로 잡는다(룬드, 2026-08-11).
#   훅을 직접 찌른다 — ①의 하위 시험은 이제 자기 시각을 «박아서» 우선권을 못 잰다.
#
#   멘션 없는 발신 하나로 두 상태가 갈린다:
#     깨어 있음 → **차단(rc=2)**   ·   취침 창 안 → **무음 통과(rc=0)**
#
# 🔑 **처음엔 「한쪽은 언제나 판정 불가」로 뒀다가 고쳤다 — 그러면 판불이 «영구히» +1 이다.**
#   우리 원장은 「판정 불가가 직전 행보다 안 늘었다」를 정상 모드 조건으로 쓰는데,
#   **줄어들 수 없는 판불**은 그 축을 영구 동결로 밀고 **동결 출구(판불 감소)도 막는다.**
#   ⇒ 구조적으로 안 줄어드는 판정 불가는 «정직»이 아니라 **설계 실수**다.
# ✅ **시계를 못 옮기면 «창»을 옮긴다** — `DARREN_SLEEP_FROM/TO` 로 창을 지금 시각 위에 얹으면
#   벽시계가 «창 안»이 된다. 같은 좌변을 반대편에서 만든 것이고, **두 방향이 둘 다 지금 측정된다.**
#   🔸 TZ 로는 못 속인다 — 훅이 `date +%s`(TZ 무관) + 에폭 산술로 시를 낸다.
echo ""
echo "② 우선권 — 주입이 벽시계를 이기는가 (두 조건이 다른 답을 요구하게 만든다)"

HOOK="$SCRIPT_DIR/../claude-config/hooks/darren-mention-guard.sh"
unk=0

# $1=주입할 epoch(빈 문자열이면 주입 없음 = 벽시계) → 훅의 rc
# 🔑 빈 값을 «주입 안 함»으로 다뤄야 대조군이 선다 — `DARREN_NOW_EPOCH=""` 를 그대로 넘기면
#   훅의 `${DARREN_NOW_EPOCH:-$(date +%s)}` 가 «빈 값도 미설정»으로 접어주긴 하지만,
#   그건 훅의 기본값 문법에 기대는 것이라 여기서 «명시적으로» 뺀다.
probe_win() {   # 창을 인자로 받는 판(WIN_FROM/WIN_TO 환경변수)
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
  echo "  ⛔ 판정 불가 — 훅이 없다: $HOOK"
  unk=$((unk + 1))
else
  WALL_H="$(( ( ($(date +%s) + 32400) / 3600 ) % 24 ))"   # 훅과 «같은» 산술로 낸다
  echo "  · 지금 벽시계 KST ${WALL_H}시"

  # ── 방향 A: 벽시계 «밖» + 주입 «안» → 답이 「취침」이면 주입이 이긴 것 ──
  # 🔑 창을 기본값(1~7)으로 두고 벽시계가 그 밖일 때만 성립한다.
  if [ "$WALL_H" -ge 1 ] && [ "$WALL_H" -le 6 ]; then
    echo "  ⛔ 판정 불가 — 방향 A 는 벽시계가 창 «밖»이라야 하는데 지금 안이다(KST ${WALL_H}시)"
    unk=$((unk + 1))
  else
    base_a="$(probe "")"                       # 대조군: 주입 없이 = 벽시계 그대로
    got_a="$(probe "$(kst 3)")"
    if [ "$base_a" = "$got_a" ]; then
      echo "  ⛔ 판정 불가 — 방향 A 의 두 조건이 «같은 답»을 요구한다(둘 다 rc=$base_a). 가르지 못한다"
      unk=$((unk + 1))
    elif [ "$got_a" = "0" ]; then
      ok "방향 A — 벽시계 밖(rc=$base_a) + 주입 03시 → «취침» 답(rc=0). 주입이 이긴다"
    else
      bad "방향 A — 주입이 무시됐다" "rc=$got_a (기대 0, 대조군 $base_a)"
    fi
  fi

  # ── 방향 B: 벽시계 «안» + 주입 «밖» → 답이 「깨어있음」이면 주입이 이긴 것 ──
  # 🔑 **시계를 못 옮기면 «창»을 옮긴다.** 훅은 epoch 산술로 시를 내므로 TZ 로는 못 속인다
  #   (`date +%s` 는 TZ 무관). 대신 `DARREN_SLEEP_FROM/TO` 로 **창을 지금 시각 위에 얹으면**
  #   벽시계가 «창 안»이 된다 — 같은 좌변을 반대편에서 만든 것이고, 이러면 두 방향이
  #   **둘 다 지금 측정된다**(한쪽을 영구 판정 불가로 두지 않는다).
  INJ_B=$(( (WALL_H + 5) % 24 ))              # 옮긴 창(한 시간짜리) 밖이 되게
  base_b="$(WIN_FROM="$WALL_H" WIN_TO=$((WALL_H + 1)) probe_win "")"
  got_b="$(WIN_FROM="$WALL_H" WIN_TO=$((WALL_H + 1)) probe_win "$(kst "$INJ_B")")"
  if [ "$base_b" = "$got_b" ]; then
    echo "  ⛔ 판정 불가 — 방향 B 의 두 조건이 «같은 답»을 요구한다(둘 다 rc=$base_b). 가르지 못한다"
    unk=$((unk + 1))
  elif [ "$got_b" = "2" ]; then
    ok "방향 B — 창을 ${WALL_H}시에 얹어 벽시계를 «안»으로(rc=$base_b) + 주입 ${INJ_B}시 → «깨어있음»(rc=2). 주입이 이긴다"
  else
    bad "방향 B — 주입이 무시됐다" "rc=$got_b (기대 2, 대조군 $base_b)"
  fi
fi

echo ""
echo "결과: $pass pass, $fail fail, 판정 불가 $unk"
# 🔑 판정 불가를 rc=0 으로 접지 않는다 — 러너가 0/1/**2** 를 구분한다.
[[ $fail -eq 0 ]] || exit 1
[[ $unk -eq 0 ]] || exit 2
