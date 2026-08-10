#!/usr/bin/env bash
# merge-mode-gate.test.sh — 머지 모드 게이트가 «부재를 통과로 접지 않는가» + 원장이 «한 벌인가».
#
# 🔑 여기 넣은 것은 **CI 러너에서 실제로 잴 수 있는 것뿐**이다.
#   파생 도구(`ledger-mode.sh`)는 «코어 레포»에 살아 러너엔 없다. 「도구가 원장을 받아준다」는
#   여기서 못 재고, 그건 머지 직전에 게이트를 손으로 돌려 잰다.
#   ⚠️ 못 재는 것을 시험에 넣으면 **상시 판정 불가**가 되고, 그 판불이 원장에 실려
#      다음 PR 을 막는다. 「판불은 줄여야 통과」라 스스로 잠그는 형태다.
#
# 🔑 그래서 이 파일이 잠그는 것은 둘뿐이다:
#   ① 도구·원장이 «없을 때» 게이트가 조용히 0 을 내지 않는다 (부재 ≠ 정상)
#   ② 원장 표가 «한 벌»이다 — 여덟 벌로 흩어져 있던 게 이 원장이 생긴 이유다
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/derive-merge-mode.sh"
pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: ${2}"; [ -n "${3:-}" ] && echo "     got:  ${3}"; fail=$((fail + 1)); }

[ -f "$GATE" ] || { echo "⛔ 판정 불가 — 게이트가 없다: $GATE"; exit 2; }

echo "🚪 머지 모드 게이트 — 부재를 통과로 접지 않는가"

# ── 배선: 원장 경로를 «소스에서 뽑아» 실재를 확인한다. 값을 시험에 또 적으면 사본이 셋이 된다.
#   `bash -uc` — 선행 변수를 못 뽑으면 빈 문자열로 접히는 대신 «죽는다»(#153 M6 과 같은 축).
LEDGER="$(env -u LEDGER -u MERGE_LEDGER -u ROOT bash -uc "
    ROOT='$ROOT'
    $(grep -m1 -E '^LEDGER=' "$GATE")
    printf '%s' \"\${LEDGER}\"" 2>/dev/null)"
if [ -z "$LEDGER" ]; then
    echo "⛔ 판정 불가 — 게이트에서 원장 경로 대입문을 못 찾았다. 변수 이름이 바뀌었을 수 있다"
    exit 2
fi
ok "게이트가 가리키는 원장: ${LEDGER#"$ROOT/"}"
[ -f "$LEDGER" ] && ok "그 원장이 실재한다" \
  || bad "게이트가 «없는 파일»을 가리킨다" "$LEDGER 존재" "없음"

# ── ① 부재 → 판정 불가. 🔴 rc=0 이면 게이트를 통과했다고 읽힌다.
out="$(LEDGER_MODE_SH=/nonexistent/ledger-mode.sh bash "$GATE" 2>&1)"; rc=$?
{ [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '판정 불가'; } \
  && ok "파생 도구가 없으면 rc=2 «판정 불가» (0 으로 안 접는다)" \
  || bad "도구 부재가 조용히 넘어간다" "rc=2 + '판정 불가'" "rc=${rc} + ${out}"

_t="$(mktemp -d)"; trap 'rm -rf "$_t"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$_t/fake-tool.sh"
out="$(LEDGER_MODE_SH="$_t/fake-tool.sh" MERGE_LEDGER=/nonexistent/ledger.md bash "$GATE" 2>&1)"; rc=$?
{ [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '판정 불가'; } \
  && ok "원장이 없으면 rc=2 «판정 불가»" \
  || bad "원장 부재가 조용히 넘어간다" "rc=2 + '판정 불가'" "rc=${rc} + ${out}"

# 🧪 대조군 — 위 rc=2 둘이 «부재를 잡아서»인지 «게이트가 늘 2 를 내서»인지 가른다.
#   이게 없으면 게이트를 `exit 2` 한 줄로 바꿔도 초록이다.
out="$(LEDGER_MODE_SH="$_t/fake-tool.sh" bash "$GATE" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "[대조군] 둘 다 있으면 통과한다 (늘 2 를 내는 게 아니다)" \
  || bad "[대조군] 도구·원장이 다 있는데도 안 통과한다 — 위 rc=2 는 못 믿는다" "rc=0" "rc=${rc} + ${out}"

# ── ② 원장 표가 «한 벌»인가. 표의 경계는 내용이 아니라 «모양»이라,
#   빈 줄로 끊긴 행은 어느 표에도 안 붙어 파서가 아예 안 본다(`#148` 실물).
echo
echo "📒 원장 — 표가 한 벌인가"
if [ ! -f "$LEDGER" ]; then
    echo "⛔ 판정 불가 — 원장이 없어 표를 못 센다"
    exit 2
fi
nh="$(grep -c '^| 레포 |' "$LEDGER" || true)"
[ "${nh:-0}" -eq 1 ] && ok "머리글이 «한 벌»이다 (여덟 벌로 흩어져 있던 것을 합쳤다)" \
  || bad "원장 머리글이 한 벌이 아니다 — 「마지막 행」이 어느 표의 것인지 안 정해진다" "1벌" "${nh}벌"

# 고아 행 — 데이터 행 «사이»에 빈 줄이 끼면 그 아래는 다른 표다.
orphan="$(awk '
    /^\| 레포 \|/ {intbl=1; next}
    intbl && /^\|/ {last=NR; next}
    intbl && !/^\|/ {intbl=0; next}
    /^\| *니노 *\|/ && !intbl {print NR}
' "$LEDGER" | tr '\n' ' ')"
[ -z "$orphan" ] && ok "표 밖에 떠 있는 데이터 행이 없다" \
  || bad "고아 행이 있다 — 앞에 빈 줄이 끼면 파서가 그 행을 안 본다" "0줄" "L${orphan}"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
