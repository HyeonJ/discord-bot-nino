#!/usr/bin/env bash
# ci-concurrency.test.sh — main 의 런은 «취소되지 않아야 한다».
#
# 🔴 왜 생겼나 (2026-08-02, 룬드 실사고 → 그가 내 쪽도 같은 자리라고 알려줬다):
#   `concurrency: cancel-in-progress: true` + `group: …-${{ github.ref }}` 는
#   **PR 브랜치엔 맞는 설정**이다(연속 푸시 3커밋 = 3런을 끝까지 돌릴 이유가 없다).
#   그런데 **main 에서는 다음 머지가 «직전 머지 커밋의 런»을 취소한다.**
#
#   그 런이 곧 원장의 관측값이다. 취소되면 그 행의 값을 **다음 커밋 값으로 적게 된다** —
#   룬드 실물: `aa4a2fe` 의 첫 런이 다음 push 에 취소당했고, `gh run watch` 를 안 했으면
#   모르고 지나갔다. *「1줄 차이라 아마 맞았겠지만 그건 운이다」*.
#
# 🔑 **조용하다**: 실패가 아니라 `cancelled` 로 남을 뿐이라 아무도 안 본다.
#   「부재는 조용하다」의 실물이고, 시끄럽게 만드는 건 설정이 아니라 **칸**이다 —
#   ⇒ 취소된 런은 「실패 0」이 아니라 **«판정 불가»** 로 적는다(원장 쪽 조항).
#   이 시험은 그 앞단, **애초에 안 취소되게** 하는 자리를 잠근다.
#
# 🔑 계약을 «문자열 모양»이 아니라 **「main 이 예외인가」**로 적는다. 표현식을 통째로
#   못박으면 포맷 시험이 되고, `github.ref_name` 같은 동치 표현으로 바꿀 때 헛빨간불이 난다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="${CI_WORKFLOW:-$ROOT/.github/workflows/ci.yml}"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$WF" ] || { echo "⛔ 판정 불가 — 워크플로가 없다: $WF"; exit 2; }

# concurrency 블록의 cancel-in-progress 값만 뽑는다 (들여쓰기 2칸 기준)
cip() { sed -n '/^concurrency:/,/^[^ #]/p' "$WF" | sed -n 's/^[[:space:]]*cancel-in-progress:[[:space:]]*//p' | head -1; }

echo "🔴 CI concurrency — main 의 런이 취소되면 원장이 «남의 값»을 적는다"

VAL="$(cip)"
if [ -z "$VAL" ]; then
    bad "판정 불가 — concurrency 블록에서 cancel-in-progress 를 못 읽었다" "값 한 줄" "«없음»"
else
    ok "cancel-in-progress 를 읽었다: «${VAL}»"
fi

# ① 무조건 취소 금지
case "$VAL" in
    true) bad "main 에서도 무조건 취소한다 — 머지 커밋의 관측이 다음 push 에 죽는다" \
              "main 을 예외로 두는 조건식" "true" ;;
    "")   ;;   # 위에서 이미 판정 불가로 셌다
    *)    ok "무조건 true 가 아니다" ;;
esac

# ② main 이 «실제로» 예외인가 — 조건식이 main 을 언급해야 한다
if [ -n "$VAL" ]; then
    if printf '%s\n' "$VAL" | grep -q 'refs/heads/main\|main'; then
        ok "조건식이 main 을 예외로 든다"
    else
        bad "조건식이 있는데 main 을 안 가린다 — 다른 축으로 갈랐을 수 있다" \
            "main 을 언급하는 조건" "«${VAL}»"
    fi
fi

# ③ PR 쪽은 여전히 취소되어야 한다 — 「그냥 다 끄기」로 고치면 러너 시간이 샌다
if [ -n "$VAL" ] && [ "$VAL" != "false" ]; then
    ok "PR 브랜치의 취소는 살아 있다 (전면 해제가 아니다)"
elif [ "$VAL" = "false" ]; then
    bad "전면 해제했다 — PR 연속 푸시가 전부 끝까지 돈다(월 한도)" "main 만 예외" "false"
fi

# 🧪 [양성 대조군] 검사기를 실제로 태운다 — 같은 코드에, 위반 파일을 만들어서.
#   이게 없으면 위 초록이 「통과」인지 「안 봤다」인지 안 갈린다.
if [ "${CI_CONC_SELFTEST:-1}" = "1" ]; then
    echo
    echo "🧪 대조군 — 위반 워크플로를 만들어 같은 검사기를 태운다"
    _tmp="$(mktemp -d)"; trap 'rm -rf "$_tmp"' EXIT
    printf 'name: CI\n\nconcurrency:\n  group: x-${{ github.ref }}\n  cancel-in-progress: true\n\njobs:\n  a:\n    runs-on: ubuntu-latest\n' > "$_tmp/bad.yml"
    _o="$(CI_WORKFLOW="$_tmp/bad.yml" CI_CONC_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc=$?
    if [ "$_rc" -ne 0 ] && printf '%s\n' "$_o" | grep -q '무조건 취소한다'; then
        ok "[대조군] cancel-in-progress: true 를 잡고 빨강이 된다 (rc=${_rc})"
    else
        bad "[대조군] 위반 파일을 못 잡는다 — 위 판정은 못 믿는다" "rc≠0 + '무조건 취소한다'" "rc=${_rc}"
    fi
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
