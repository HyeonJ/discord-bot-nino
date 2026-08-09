#!/usr/bin/env bash
# cascade-queue-wiring.test.sh — 생산자와 소비자가 «같은 파일»을 가리키는가.
#
# 🔴 왜 생겼나 (2026-08-10 실측):
#   훅  `hooks/cascade-queue.sh`      → $HOME/discord-bot-nino/memory/state/cascade-queue.md   (71줄, 실재)
#   린트 `scripts/lint-nino-memory.sh` → $MEMORY_AUTO_DIR/state/cascade-queue.md               (**없음**)
#   ⇒ 훅은 5일 넘게 큐를 쌓았고(검토 대상 65건), 린트는 **다른 파일**을 봤다.
#
# 🔑 린트는 이걸 «조용히» 넘기지 않았다 — `➖ 11: 검사 안 됨 (큐가 빈 게 아니라 «배선이 없다»)`.
#   부재를 0 으로 안 접은 덕에 **경고는 계속 떠 있었다.** 못 본 건 사람 쪽이다.
#   ⇒ 그래서 이 시험이 잠그는 것은 「큐가 비었나」가 아니라 **「두 자리가 같은 곳을 보나」**다.
#
# 🔑 값을 «맞춰 적었다»로 잠그지 않는다 — 양쪽 «소스에서 뽑아» 대조한다.
#   리터럴을 시험에 또 적으면 사본이 셋이 되고, 셋째가 따로 낡는다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/cascade-queue.sh"
LINT="$ROOT/scripts/lint-nino-memory.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

for f in "$HOOK" "$LINT"; do
    [ -f "$f" ] || { echo "⛔ 판정 불가 — 파일이 없다: $f"; exit 2; }
done

# 대입문 한 줄만 뽑아 «빈 환경»에서 평가한다. 소스 전체를 실행하면 훅/린트가 실제로 돈다.
#   env -u 로 상위 껍데기의 같은 이름 변수를 지운다 — 안 지우면 «내 환경»이 답을 정한다.
eval_assign() {
    local file="$1" pattern="$2" var="$3" line
    line=$(grep -m1 -E "$pattern" "$file" || true)
    [ -n "$line" ] || { echo ""; return 1; }
    env -u QUEUE -u CASCADE_QUEUE -u MEMORY_AUTO_DIR -u WIKI bash -c "
        $(grep -m1 -E '^(export )?MEMORY_AUTO_DIR=' "$file" || true)
        $(grep -m1 -E '^(export )?WIKI=' "$file" || true)
        $line
        printf '%s' \"\${$var}\""
}

echo "🔗 cascade 큐 배선 — 생산자(훅)와 소비자(린트)가 같은 파일을 보나"

HQ="$(eval_assign "$HOOK" '^(export )?QUEUE=' QUEUE)" || HQ=""
LQ="$(eval_assign "$LINT" '^(export )?CASCADE_QUEUE=' CASCADE_QUEUE)" || LQ=""

if [ -z "$HQ" ] || [ -z "$LQ" ]; then
    echo "⛔ 판정 불가 — 대입문을 못 찾았다 (훅=«${HQ}» 린트=«${LQ}»). 변수 이름이 바뀌었을 수 있다"
    exit 2
fi

ok "훅 큐 경로를 읽었다: $HQ"
ok "린트 큐 경로를 읽었다: $LQ"

if [ "$HQ" = "$LQ" ]; then
    ok "두 자리가 «같은 파일»을 가리킨다"
else
    bad "생산자와 소비자가 다른 파일을 본다 — 큐가 쌓여도 린트가 못 본다" "$HQ" "$LQ"
fi

# 🧪 [대조군] 시험이 «다름»을 실제로 잡는가. 이게 없으면 위 초록이 「같다」인지 「안 봤다」인지 안 갈린다.
if [ "${CASCADE_WIRING_SELFTEST:-1}" = "1" ]; then
    echo
    echo "🧪 대조군 — 훅 사본의 경로만 어긋내고 같은 검사기를 태운다"
    _t="$(mktemp -d)"; trap 'rm -rf "$_t"' EXIT
    mkdir -p "$_t/hooks" "$_t/scripts" "$_t/tests"
    sed 's#^QUEUE=.*#QUEUE="$HOME/somewhere-else/cascade-queue.md"#' "$HOOK" > "$_t/hooks/cascade-queue.sh"
    cp "$LINT" "$_t/scripts/"; cp "${BASH_SOURCE[0]}" "$_t/tests/"
    _o="$(CASCADE_WIRING_SELFTEST=0 bash "$_t/tests/$(basename "${BASH_SOURCE[0]}")" 2>&1)"; _rc=$?
    if [ "$_rc" -ne 0 ] && printf '%s\n' "$_o" | grep -q '다른 파일을 본다'; then
        ok "[대조군] 어긋난 배선을 잡고 빨강이 된다 (rc=${_rc})"
    else
        bad "[대조군] 어긋난 배선을 못 잡는다 — 위 판정은 못 믿는다" "rc≠0 + '다른 파일을 본다'" "rc=${_rc}"
    fi
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
