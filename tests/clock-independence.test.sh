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
#   그래서 **상속된 새벽 epoch** 으로 대신 잰다. 훅 입장에서 두 경로는 같은 자리로
#   들어오고(주입 없으면 벽시계, 있으면 그 값), **실측이 그걸 뒷받침한다** —
#   수리 전 기준 「벽시계 01:47」과 「주입 03:30」이 **똑같이 27/16** 을 냈다.
#   ⇒ 이 시험이 잡는 것: *「하위 시험이 자기 시각을 안 박아 바깥 값에 끌려간다」*.
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

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
