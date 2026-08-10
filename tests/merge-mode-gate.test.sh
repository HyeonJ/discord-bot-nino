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

# 라벨도 «소스에서» 뽑는다 — 시험에 「니노」를 또 적으면 사본이 둘이 돼 따로 낡는다.
REPO_LABEL="$(env -u REPO_LABEL -u MERGE_REPO_LABEL bash -uc "
    $(grep -m1 -E '^REPO_LABEL=' "$GATE")
    printf '%s' \"\${REPO_LABEL}\"" 2>/dev/null)"
if [ -z "$REPO_LABEL" ]; then
    echo "⛔ 판정 불가 — 게이트에서 레포 라벨 대입문을 못 찾았다. 변수 이름이 바뀌었을 수 있다"
    exit 2
fi
[ -f "$LEDGER" ] && ok "그 원장이 실재한다" \
  || bad "게이트가 «없는 파일»을 가리킨다" "$LEDGER 존재" "없음"

# ── ① 부재 → 판정 불가. 🔴 rc=0 이면 게이트를 통과했다고 읽힌다.
out="$(LEDGER_MODE_SH=/nonexistent/ledger-mode.sh bash "$GATE" 2>&1)"; rc=$?
{ [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '판정 불가'; } \
  && ok "파생 도구가 없으면 rc=2 «판정 불가» (0 으로 안 접는다)" \
  || bad "도구 부재가 조용히 넘어간다" "rc=2 + '판정 불가'" "rc=${rc} + ${out}"

_t="$(mktemp -d)"; trap 'rm -rf "$_t"' EXIT
# 🔑 가짜 도구는 «받은 인자를 적는다». 이게 없으면 래퍼가 `--ledger`·`--repo-label`·`"$@"` 를
#   통째로 안 넘겨도 전부 초록이다 — ①② 는 `exec` «앞»의 검사고, 대조군은 rc 만 본다.
#   래퍼의 존재 이유가 그 두 값을 박아두는 것뿐이라, 안 넘기면 래퍼는 빈 껍데기다.
cat > "$_t/fake-tool.sh" <<EOF
#!/bin/sh
: > "$_t/args"
for a in "\$@"; do printf '%s\n' "\$a" >> "$_t/args"; done
exit 0
EOF
out="$(LEDGER_MODE_SH="$_t/fake-tool.sh" MERGE_LEDGER=/nonexistent/ledger.md bash "$GATE" 2>&1)"; rc=$?
{ [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '판정 불가'; } \
  && ok "원장이 없으면 rc=2 «판정 불가»" \
  || bad "원장 부재가 조용히 넘어간다" "rc=2 + '판정 불가'" "rc=${rc} + ${out}"

# 🧪 대조군 — 위 rc=2 둘이 «부재를 잡아서»인지 «게이트가 늘 2 를 내서»인지 가른다.
#   이게 없으면 게이트를 `exit 2` 한 줄로 바꿔도 초록이다.
out="$(LEDGER_MODE_SH="$_t/fake-tool.sh" bash "$GATE" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "[대조군] 둘 다 있으면 통과한다 (늘 2 를 내는 게 아니다)" \
  || bad "[대조군] 도구·원장이 다 있는데도 안 통과한다 — 위 rc=2 는 못 믿는다" "rc=0" "rc=${rc} + ${out}"

# ── ③ 래퍼가 두 값을 «실제로» 넘기나 (위 rc=0 은 이걸 못 가른다).
argv_at() { awk -v k="$1" '$0==k {if (getline > 0) print; exit}' "$_t/args"; }
if [ ! -f "$_t/args" ]; then
    bad "가짜 도구가 실행되지 않았다 — 인자 검사는 판정 불가" "인자 기록" "없음"
else
    got="$(argv_at --ledger)"
    [ "$got" = "$LEDGER" ] && ok "래퍼가 --ledger 를 원장 경로로 넘긴다" \
      || bad "래퍼가 --ledger 를 안 넘긴다(또는 다른 값)" "$LEDGER" "${got:-없음}"
    got="$(argv_at --repo-label)"
    [ "$got" = "$REPO_LABEL" ] && ok "래퍼가 --repo-label 을 넘긴다: $got" \
      || bad "래퍼가 --repo-label 을 안 넘긴다(또는 다른 값)" "$REPO_LABEL" "${got:-없음}"
    # 🔑 좌변을 «원장»에 둔다 — 라벨을 소스에서 뽑아 소스와 대보면 항진명제라, 라벨이
    #   조용히 딴 레포로 바뀌어도 둘이 같이 움직여 초록이다. 실제로 물어야 할 것은
    #   「그 라벨로 읽을 행이 이 원장에 «있나»」다.
    nrow="$(grep -c "^| *${got} *|" "$LEDGER" || true)"
    [ "${nrow:-0}" -ge 1 ] && ok "그 라벨로 읽을 행이 원장에 ${nrow}개 있다" \
      || bad "래퍼가 «이 원장에 없는» 라벨을 넘긴다 — 늘 빈 원장을 읽는다" "행 ≥1" "${got:-없음} 0행"
fi

# ── ④ 손으로 준 인자가 «그대로» 도구까지 가나 (`"$@"` 를 떨구면 게이트가 조회 전용이 된다).
out="$(LEDGER_MODE_SH="$_t/fake-tool.sh" bash "$GATE" --unknown 11 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    bad "인자를 주면 게이트가 죽는다 — 통과 검사가 판정 불가" "rc=0" "rc=${rc} + ${out}"
elif [ "$(argv_at --unknown)" = "11" ]; then
    ok "게이트에 준 인자가 도구까지 그대로 간다"
else
    bad "게이트가 뒤에 붙인 인자를 떨군다 — 조회만 되고 «기록»이 안 된다" "--unknown 11" "$(tr '\n' ' ' < "$_t/args")"
fi

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
# 🔑 좌변을 «니노 라벨»에 걸지 않는다 — 라벨을 박아두면 오타 난 라벨·남의 라벨로 떨어진 행이
#   고아여도 안 보인다. 표 밖에 뜬 «파이프로 시작하는 줄» 전부가 좌변이다.
#   (코드펜스 안은 뺀다 — 거긴 마크다운 표가 아니라 본문이다.)
orphan="$(awk '
    /^```/ {fence = !fence; next}
    fence {next}
    /^\| 레포 \|/ {intbl=1; next}
    intbl && /^\|/ {next}
    intbl {intbl=0}
    /^\|/ {print NR}
' "$LEDGER" | tr '\n' ' ')"
[ -z "$orphan" ] && ok "표 밖에 떠 있는 데이터 행이 없다" \
  || bad "고아 행이 있다 — 앞에 빈 줄이 끼면 파서가 그 행을 안 본다" "0줄" "L${orphan}"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
