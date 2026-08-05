#!/usr/bin/env bash
# capture-rc.test.sh — `hf_verdict` 이 「검사기가 죽은 것」을 «위반 0건»과 가르는지 잰다.
#
# 🔴 왜 생겼나 (2026-08-02, 룬드 `#140` 리뷰 ②):
#   `#140` 에서 `VAR=$(python3 … << )` 를 `python3 … << > tmp` + `VAR=$(cat tmp)` 로 바꿨다.
#   형태는 고쳤는데 **rc 를 아무도 안 본다** — 파이썬이 죽으면 tmp 가 비고 `viol=""` 가 되어
#   **«위반 0건» 초록**이 난다. 원래 형태도 같았으니 회귀는 아니지만,
#   `heredoc-form.test.sh` 에서 「검사기가 죽으면 판정 불가」를 세운 그 손으로
#   여섯 곳에 **같은 구멍을 형태만 바꿔 옮긴** 자리다.
#
#   🔑 그리고 **파일 경유가 그 자리를 열어줬다**(룬드 지적) — `$( … )` 일 땐 rc 가 대입에 묻혀
#     **잴 수가 없었고**, 지금은 독립 명령이라 다음 줄에서 `$?` 로 잰다.
#     ⇒ 형태 제거의 부수 효과가 **관측 가능성을 늘린 것**이라, 별건이 아니라 연장선이다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/capture-rc.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

echo "🔴 hf_verdict — 「검사기가 죽었다」와 「위반이 없다」를 가른다:"

# ① rc=0 — 조용하고 0
out="$(hf_verdict 0 이식성)"; rc=$?
[ "$rc" -eq 0 ] && ok "rc=0 → 0 을 돌려준다" || bad "rc=0 인데 0 이 아니다" "0" "$rc"
[ -z "$out" ]   && ok "rc=0 → 아무것도 안 낸다" || bad "rc=0 인데 출력이 있다" "<빈 출력>" "«${out}»"

# ② rc≠0 — 시끄럽고 1
out="$(hf_verdict 2 이식성)"; rc=$?
[ "$rc" -eq 1 ] && ok "rc≠0 → 1 을 돌려준다" || bad "rc≠0 인데 1 이 아니다" "1" "$rc"
case "$out" in
    *"판정 불가"*) ok "rc≠0 → 사유에 «판정 불가» 가 있다" ;;
    *)             bad "사유가 판정 불가라고 말하지 않는다" "«판정 불가» 포함" "«${out}»" ;;
esac
case "$out" in
    *"rc=2"*) ok "rc≠0 → 실제 rc 값을 싣는다" ;;
    *)        bad "rc 값이 사유에 없다" "rc=2 포함" "«${out}»" ;;
esac
case "$out" in
    *이식성*) ok "rc≠0 → 어느 검사인지 싣는다" ;;
    *)        bad "라벨이 사유에 없다" "«이식성» 포함" "«${out}»" ;;
esac

# ③ 🔑 rc 인자를 «안 주면» 통과가 아니라 실패다 — 배선을 빠뜨린 자리가 조용하면 안 된다.
#   `$?` 를 못 잡은 site 는 빈 문자열을 넘기게 되는데, 그게 0 으로 읽히면
#   **이 헬퍼를 붙였다는 사실 자체가 초록의 근거**가 되어버린다.
out="$(hf_verdict "" 이식성)"; rc=$?
[ "$rc" -eq 1 ] && ok "rc 를 안 넘기면 실패로 친다(배선 누락이 조용하지 않다)" \
                || bad "rc 없이 불렀는데 통과했다" "1" "$rc"

# ④ 🧪 [양성 대조군] 실제 죽는 명령으로 끝까지 돌려본다 — 「위반 0건」이 안 나와야 한다.
_t="$(mktemp)"
python3 -c 'import sys; sys.exit(3)' > "$_t" 2>/dev/null
_rc=$?
val="$(cat "$_t")"; rm -f "$_t"
if msg="$(hf_verdict "$_rc" 대조군)"; then
    bad "죽은 검사기가 통과했다" "판정 불가" "출력 «${val}» rc=${_rc}"
else
    [ -z "$val" ] && ok "[대조군] 출력은 비었지만 «위반 0건»으로 안 읽힌다 (rc=${_rc})" \
                  || bad "대조군 출력이 비어야 한다" "<빈 출력>" "«${val}»"
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
