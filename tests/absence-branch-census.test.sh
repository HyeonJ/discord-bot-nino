#!/usr/bin/env bash
# absence-branch-census.test.sh — 「부재가 «떨어지는 가지»에 ok 가 있나」 검사기가 실제로 «본다»
#
# 🔴 왜 생겼나 (2026-08-11):
#   `flock` 없는 호스트를 흉내내려 PATH 를 줄여 다른 시험을 돌렸더니 `sed`·`grep` 도 같이 빠졌고,
#   그 시험의 ④ 가 **한 부재에서 두 방향으로** 틀렸다 —
#     ·`elif … grep -q …` → rc=127 → 조건 거짓 → `else` 로 흘러 **«거짓 초록»**
#     ·`grep -q … && ! grep -q …` → 같은 이유로 거짓 → **«거짓 빨강»**
#   ⇒ 「빨강이면 안전」이 그 자리의 `if/elif/else` 배치에 매여 있다. 이 도구는 그 «자리»를 센다.
#
# 🔑 좌변은 **부재가 떨어지는 가지에 `ok` 가 있나**다 — «조건의 부호»가 아니다.
#   첫 판을 「부정 조건」으로 뒀더니 0건이 나왔는데 **정작 찾던 실물이 부정이 아니었다.**
#   ⇒ 그 좌변이 다시 좁아지는 것을 ③ 이 막는다.
#
# 🔸 픽스처에 **«걸리면 안 되는» 표본**을 같이 둔다(룬드↔니노 합의 2026-08-11):
#   양성 대조군의 «반대»다. 없으면 「보고 통과했다」와 「아예 안 봤다」가 **둘 다 0건**이라 안 갈린다.
set -uo pipefail

pass=0; fail=0; skip=0
ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()  { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
note() { echo "  ⛔ $1"; skip=$((skip + 1)); }

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$_HERE/../tools/absence-branch-census.py"
_T="$(mktemp -d)"
trap 'rm -rf "$_T"' EXIT

if [ ! -f "$TOOL" ]; then
    note "도구가 없다 ($TOOL) — 이 시험 전체를 못 쟀다"
    echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"; exit 0
fi
if ! command -v python3 > /dev/null 2>&1; then
    note "python3 이 없다 — 이 시험 전체를 못 쟀다 (판정기 자신이 안 돈다)"
    echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"; exit 0
fi

# ── 픽스처: 가지 «꼴»마다 한 파일. 목록이 아니라 «파일»이라 다음 사람이 실제로 넣는다 ──
# ⓐ 위험 — 부재가 말단 else 로 떨어지고 거기에 ok 가 있다
cat > "$_T/danger-elif.sh" <<'FIX'
if [ -z "$_body" ]; then
    bad "본문 없음"
elif printf '%s' "$_body" | command grep -qE 'X'; then
    bad "걸렸다"
else
    ok "안 걸렸다"
fi
FIX
# ⓑ 위험 — 부정 조건이라 부재가 «then» 으로 떨어지고 거기에 ok 가 있다
cat > "$_T/danger-negated.sh" <<'FIX'
if ! command grep -qE 'X' "$f"; then
    ok "없다"
else
    bad "있다"
fi
FIX
# ⓒ 🔸 **걸리면 «안» 되는 표본** — 부재가 bad 로 떨어진다(엄격한 쪽으로 실패)
cat > "$_T/safe-positive.sh" <<'FIX'
if printf '%s' "$_body" | command grep -qE 'X'; then
    ok "기대값이 있다"
else
    bad "기대값이 없다"
fi
FIX
# ⓓ 분모 «밖» — 조건에 그 도구가 아예 안 나온다
cat > "$_T/outside.sh" <<'FIX'
if [ "$n" -eq 0 ]; then
    ok "0이다"
else
    bad "0이 아니다"
fi
FIX
# ⓔ 한 줄 꼴 — 파서가 놓치는 알려진 한계 2. 두 수가 «갈려야» 한다
cat > "$_T/oneline.sh" <<'FIX'
if [ "$x" = 1 ]; then Y=0
elif command grep -q 'X' "$f"; then Y=1
else Y=0; fi
FIX

run() { python3 "$TOOL" "$1" "${@:2}" 2>&1; }

echo "① 🔴 위험한 두 꼴을 «잡는다» — 잡는 게 없으면 이 시험 전체가 무의미하다"
_o="$(run '(grep|sed)' "$_T/danger-elif.sh" "$_T/danger-negated.sh")"
_n="$(printf '%s\n' "$_o" | sed -n 's/^🔴 위험(부재 → ok 가지): \([0-9]*\)건$/\1/p')"
if [ "${_n:-x}" = 2 ]; then
    ok "말단else 꼴·부정 꼴 둘 다 잡힌다 (2건)"
else
    bad "두 꼴을 다 못 잡는다" "2건" "${_n:-파싱 실패}"
    printf '%s\n' "$_o" | sed 's/^/       /'
fi

echo
echo "② 🔸 «걸리면 안 되는» 표본이 «분모 안»에 있고 «히트 밖»에 있다"
# 🔑 두 축을 따로 잰다 — 히트 0 만 보면 「보고 통과」와 「아예 안 봄」이 같은 화면이다.
_o2="$(run '(grep|sed)' "$_T/safe-positive.sh" --list-denominator)"
_hit="$(printf '%s\n' "$_o2" | sed -n 's/^🔴 위험(부재 → ok 가지): \([0-9]*\)건$/\1/p')"
if printf '%s\n' "$_o2" | command grep -q 'safe-positive\.sh'; then
    if [ "${_hit:-x}" = 0 ]; then
        ok "분모 «안»에 있고 히트는 0 — 「봐서 통과」가 「안 봄」과 갈린다"
    else
        bad "안전한 꼴이 위험으로 잡혔다(거짓 양성)" "0건" "${_hit}건"
    fi
else
    bad "안전한 꼴이 «분모 밖»이다 — 히트 0 이 「안 봤다」를 뜻한다" "분모에 등장" "없음"
fi

echo
echo "③ 🔑 좌변이 «부호»로 좁아지면 죽는다 — 부정 아닌 위험 꼴이 혼자 잡히나"
# ⚠️ 이 단언이 없으면 좌변을 「부정 조건」으로 되돌려도 ① 이 여전히 «1건»으로 초록일 수 있다.
_o3="$(run '(grep|sed)' "$_T/danger-elif.sh")"
_n3="$(printf '%s\n' "$_o3" | sed -n 's/^🔴 위험(부재 → ok 가지): \([0-9]*\)건$/\1/p')"
if [ "${_n3:-x}" = 1 ]; then
    ok "부정이 «아닌» 위험 꼴도 단독으로 잡힌다"
else
    bad "좌변이 부호에 묶여 있다 — 말단else 꼴을 놓친다" "1건" "${_n3:-파싱 실패}"
fi

echo
echo "④ 🔴 분모와 «생 조건줄»이 갈리면 «기본 출력»에서 신고한다 (플래그 없이)"
# 🔑 「옆에 둔다」로는 안 잡힌다 — 같은 출력에 나란히 있어야 «안 맞을 때 그냥 보인다».
#   실물: 손으로 센 3 과 도구가 낸 2 를 같은 날 손에 쥐고도 안 맞춰봤다.
_o4="$(run '(grep|sed)' "$_T/oneline.sh")"
if printf '%s\n' "$_o4" | command grep -q '^🔴 분모 .*갈렸다'; then
    ok "한 줄 꼴에서 두 수가 갈리고, 플래그 없이 신고한다"
else
    bad "갈렸는데 조용하다 — 「안 본 것」이 「위험 0건」과 같은 화면이 된다" "🔴 … 갈렸다" "$(printf '%s\n' "$_o4" | head -1)"
fi

echo
echo "⑤ 🔸 안 갈릴 땐 ✅ 로 낸다 — ④ 가 «항상 빨강»이면 신호가 아니다"
_o5="$(run '(grep|sed)' "$_T/danger-elif.sh" "$_T/safe-positive.sh" "$_T/outside.sh")"
if printf '%s\n' "$_o5" | command grep -q '^✅ 분모 '; then
    ok "정상 꼴에서는 두 수가 같다 (④ 의 대조군)"
else
    bad "안 갈리는 입력에도 갈렸다고 한다" "✅ 분모 …" "$(printf '%s\n' "$_o5" | head -1)"
fi

echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ] || exit 1
