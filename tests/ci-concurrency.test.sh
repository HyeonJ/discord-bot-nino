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

# ────────────────────────────────────────────────────────────────────────────
# 🔴 «두 번째 축» — group. `cancel-in-progress: false` 만으로는 안 막힌다.
#
#   #145 가 고친 것은 **취소 축 하나뿐**이었다. 그런데 한 concurrency 그룹의
#   **대기 자리는 하나**라, main 커밋이 전부 같은 그룹에 들어가면 새 대기가
#   **앞 대기를 밀어낸다** — `cancel-in-progress` 와 «무관»하게 죽는다.
#   룬드 실측 증거: 취소 시각 = 다음 런의 «생성» 시각(같은 초). `523097f` 런이
#   `57e4f24` 생성과 동시에 cancelled.
#
# 🔑 **내 취소 건수 0 은 이 축에 대해 아무 말도 안 했다** — `#145` 이후 main 런 2건,
#   간격 2시간 8분, 10분 내 연속 0건. 「수리됐다」가 아니라 **「한 번도 안 밟혔다」**다.
#   *「이 값이 두 상태를 갈라주나?」* 아니오 — 갈라준 건 취소 수가 아니라 **런 간격**이었다.
#   ⇒ 발현은 **일이 몰릴 때**만 난다. 시험이 없으면 몰리는 날 조용히 밟는다.
grp() { sed -n '/^concurrency:/,/^[^ #]/p' "$WF" | sed -n 's/^[[:space:]]*group:[[:space:]]*//p' | head -1; }

GVAL="$(grp)"
if [ -z "$GVAL" ]; then
    bad "판정 불가 — concurrency 블록에서 group 을 못 읽었다" "값 한 줄" "«없음»"
elif printf '%s\n' "$GVAL" | grep -q 'github\.sha'; then
    ok "group 이 sha 로 갈린다 (main 커밋마다 «자기 그룹»)"

    # 🔑 sha 가 «참» 가지에 있어야 한다. 붙여넣기로 옮기면 여기가 조용히 뒤집힌다:
    #    ①`!=` 로 뒤집기  ②`==` 는 그대로 두고 값만 맞바꾸기 — 둘 다 이 칸이 잡는다.
    #    문자열 통째 대조가 아니라 «삼항의 참 가지»를 뽑아서 본다(동치 표현을 안 막으려고).
    COND="$(printf '%s\n' "$GVAL" | sed -n 's/.*{{\([^{}]*\)&&.*/\1/p')"
    TRUE_ARM="$(printf '%s\n' "$GVAL" | sed -n 's/.*&&\([^|]*\)||.*/\1/p')"
    if [ -z "$COND" ] || [ -z "$TRUE_ARM" ]; then
        bad "group 에 sha 는 있는데 «조건부»가 아니다 — PR 까지 sha 로 갈리면 연속 푸시가 안 취소된다" \
            "COND && github.sha || 'shared'" "«${GVAL}»"
    elif ! printf '%s\n' "$COND" | grep -q "==" || ! printf '%s\n' "$COND" | grep -q 'refs/heads/main'; then
        bad "조건이 «main 일 때»가 아니다 — 뒤집히면 PR 이 sha 로 갈리고 main 이 한 그룹이 된다" \
            "github.ref == 'refs/heads/main'" "«${COND}»"
    elif ! printf '%s\n' "$TRUE_ARM" | grep -q 'github\.sha'; then
        bad "sha 가 «거짓» 가지에 있다 — 값이 맞바뀌었다" \
            "&& 뒤가 github.sha" "«${TRUE_ARM}»"
    else
        ok "sha 가 «참»(main) 가지에 있다"
    fi
else
    bad "group 이 ref 로만 갈린다 — main 커밋 전부가 «한 그룹»이고 대기 자리는 하나다" \
        "group 에 github.sha (main 일 때)" "«${GVAL}»"
    echo "  ⛔ 판정 불가 — 위가 깨져서 «sha 가 어느 가지인가»는 못 쟀다 (분모는 4 유지)"
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
