#!/usr/bin/env bash
# `grep -c` 뒤에 `|| echo <기본값>` 을 덧대는 형태를 막는다.
#
# 왜: `grep -c` 는 **0 을 «출력하면서» rc=1** 을 낸다. 그래서 `|| echo 0` 을 붙이면
#   기본값이 «덧대져» 값이 `0\n0` 두 줄이 된다. 산술 비교에 넣으면 에러가 나거나
#   조용히 틀린 답이 나오고, **한 줄일 때는 멀쩡해서** 표본이 빌 때만 문다.
#   ⇒ `|| true` 로 rc 만 삼키고 출력은 grep 것을 쓴다(+ `${var:-0}` 로 «진짜 실패»를 덮는다).
#
# 🔑 왜 코어 `lint-bash-pitfalls.sh` 를 통째로 안 걸었나 — **오탐이 배선을 막는다.**
#   실측 2026-08-11, 내 레포 `.sh` 117개: 16건 중 **13건(81%)이 오탐**이었다.
#   · 주석 안의 백틱 9건 (`tests/runner-glob-coverage.test.sh` — 함정을 «설명한» 줄)
#   · `<<'PY'` heredoc 안의 파이썬 4건 (`check-auth`·`check-usage-alert`·`check-shared-contracts`×2)
#   그 오탐은 전부 **백틱 규칙**에서 났고, **`grep -c` 규칙은 3/3 전부 진짜**였다.
#   ⇒ 규칙 단위로 좁히면 **오늘 이 레포에서 오탐 0** 이라 «지금» 배선할 수 있다.
#      통째 배선은 백틱 규칙의 오탐 처리가 선행이고, 그건 코어 쪽 몫이다.
#
# ⚠️ 🔴 **줄머리 `#` 제외만으로는 «부족했다» — 초판이 자기 픽스처 둘과 내 «꼬리» 주석을 물었다.**
#   함정을 «설명한» 줄과 «시험하는» 줄은 그 함정의 문자열을 반드시 가진다(룬드 08-11 지적의 내 판).
#   ⇒ 코어 `lint-bash-pitfalls.sh` 의 규약을 그대로 쓴다: 그 줄 주석에 `lint-pitfalls:allow`.
#   🔑 **면제 «수»를 같이 출력한다 — 조용한 제외 금지.** 0 이 아니면 리뷰가 그 줄을 본다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BOT_DIR"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/     /'; }

# 좌변 = **추적되는** `.sh` 전부. 추적 밖은 CI 체크아웃에 없어서 잴 수 없다.
# ⚠️ `mapfile`/`readarray` 는 **bash 4+** 라 쓰지 않는다 — 룬드 맥이 bash 3.2 다.
#    빈 배열의 `${#a[@]}` 도 3.2 의 `set -u` 에서 터지므로 **배열 자체를 안 쓴다**.
FILE_LIST="$(git ls-files '*.sh')"
FILE_N="$(printf '%s' "$FILE_LIST" | grep -c . || true)"; FILE_N="${FILE_N:-0}"

scan() {
    printf '%s\n' "$FILE_LIST" | while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        grep -nE 'grep[[:space:]]+(-[a-zA-Z]*c[a-zA-Z]*[[:space:]]).*\|\|[[:space:]]*echo' "$f" \
            | grep -vE '^[0-9]+:[[:space:]]*#' \
            | grep -v 'lint-pitfalls:allow' \
            | sed "s#^#${f}:#"
    done
}

# 면제된 줄 — 조용히 빼지 않는다
exempt() {
    printf '%s\n' "$FILE_LIST" | while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        grep -nE 'grep[[:space:]]+(-[a-zA-Z]*c[a-zA-Z]*[[:space:]]).*\|\|[[:space:]]*echo' "$f" \
            | grep -vE '^[0-9]+:[[:space:]]*#' \
            | grep 'lint-pitfalls:allow' \
            | sed "s#^#${f}:#"
    done
}

echo "== grep -c 뒤 기본값 덧대기 =="

_hits="$(scan || true)"
_n="$(printf '%s' "$_hits" | grep -c . || true)"
_n="${_n:-0}"

_ex="$(exempt || true)"
_xn="$(printf '%s' "$_ex" | grep -c . || true)"; _xn="${_xn:-0}"
[ "$_xn" -eq 0 ] || { echo "  🔸 면제 ${_xn}건 (lint-pitfalls:allow)"; printf '%s\n' "$_ex" | sed 's/^/     /'; }

if [ "$_n" -eq 0 ]; then
    ok "추적 .sh ${FILE_N}개 — 위반 0건 · 면제 ${_xn}건"
else
    bad "위반 ${_n}건 — \`|| echo\` 대신 \`|| true\` + \`\${var:-0}\` 을 쓸 것" "$_hits"
fi

# ── [대조군] 검사식이 «진짜로» 그 꼴을 잡는다 (항진명제 아님)
_t="$(mktemp -d)"
printf '%s\n' 'n=$(grep -c . f.txt || echo 0)' > "$_t/bad.sh"   # lint-pitfalls:allow — 픽스처다
if grep -qE 'grep[[:space:]]+(-[a-zA-Z]*c[a-zA-Z]*[[:space:]]).*\|\|[[:space:]]*echo' "$_t/bad.sh"; then
    ok "[대조군] 위반 꼴을 실제로 잡는다"
else
    bad "[대조군] 위반 꼴을 못 잡는다 — 위 초록은 아무 뜻이 없다"
fi

# ── [대조군] 고친 꼴은 «안» 잡는다 (거짓 양성으로 수리를 되돌리지 않는다)
printf '%s\n' 'n=$(grep -c . f.txt || true)' 'n=${n:-0}' > "$_t/good.sh"
if grep -qE 'grep[[:space:]]+(-[a-zA-Z]*c[a-zA-Z]*[[:space:]]).*\|\|[[:space:]]*echo' "$_t/good.sh"; then
    bad "[대조군] 고친 꼴까지 잡는다 — 오탐이라 배선하면 안 된다"
else
    ok "[대조군] 고친 꼴은 안 잡는다"
fi

# ── [대조군] 주석 제외가 «실제로» 동작한다 (설명 줄이 자기를 물지 않는다)
printf '%s\n' '# n=$(grep -c . f.txt || echo 0)  ← 이건 설명이다' > "$_t/cmt.sh"   # lint-pitfalls:allow — 픽스처다
_c="$(grep -nE 'grep[[:space:]]+(-[a-zA-Z]*c[a-zA-Z]*[[:space:]]).*\|\|[[:space:]]*echo' "$_t/cmt.sh" \
      | grep -vE '^[0-9]+:[[:space:]]*#' | grep -c . || true)"
if [ "${_c:-0}" -eq 0 ]; then
    ok "[대조군] 주석 줄은 제외된다"
else
    bad "[대조군] 주석을 문다 — 함정을 «설명한» 줄이 함정으로 세어진다"
fi
rm -rf "$_t"

echo ""
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
