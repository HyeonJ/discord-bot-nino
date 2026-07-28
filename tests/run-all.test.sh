#!/usr/bin/env bash
# run-all.sh 셔틀 계약 시험 — **인자를 실제로 넘기는가**가 본체다
#
# 🔑 왜 셔틀이 파일이어야 하나: 전에는 `package.json` 의 한 줄이었다. 문자열이라
#   ① CI 갈래를 나눌 수 없고 ② **넘기는 인자를 시험할 수 없었다.**
#   기능을 만들어도 호출부가 안 붙이면 아무 일도 안 일어나고 그 사실이 어디에도 안 뜬다
#   — cron 에서 안 도는 검사와 같은 클래스라, **붙이는 것 자체**를 여기서 잰다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHUTTLE="$ROOT/tests/run-all.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
[ -f "$SHUTTLE" ] || { echo "❌ 없음: $SHUTTLE"; exit 1; }

STUB_DIR="$(mktemp -d)"; trap 'rm -rf "$STUB_DIR"' EXIT
cat > "$STUB_DIR/stub.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${STUB_ARGV_OUT:?}"
STUB
chmod +x "$STUB_DIR/stub.sh"

# ⚠️ **호출 환경을 지우고 부른다** — `UNMEASURED_STATE`·`CI` 가 밖에서 설정돼 있으면
#    시험 내부의 셔틀 호출까지 상속돼 ②의 기대값(`*/state/*`)이 그 값으로 바뀐다.
#    실측(2026-07-28): `UNMEASURED_STATE=/tmp/elsewhere/x.tsv bash tests/run-all.test.sh`
#    → 7 pass · **1 fail**. 룬드가 자기 셔틀에서 먼저 밟았고(`assistant#23`) 내 것도 같았다.
#    🔑 *시험이 환경 따라 갈리면 초록도 빨강도 신뢰할 수 없다.* `-u` 로 지운 뒤,
#       그 갈래를 **일부러** 태우는 경우(④)만 인자로 다시 준다 — 나중 지정이 이긴다.
run_shuttle() {  # $1=argv 파일명, 나머지는 env
    local out="$STUB_DIR/$1"; shift
    env -u UNMEASURED_STATE -u CI "$@" \
        STUB_ARGV_OUT="$out" RUNNER="$STUB_DIR/stub.sh" bash "$SHUTTLE" >/dev/null 2>&1
    printf '%s' "$out"
}

echo "① 러너를 부르고 시험 목록을 넘긴다"
A="$(run_shuttle argv.txt)"
grep -qx -- '--shell-glob' "$A" && ok "--shell-glob 을 준다" || bad "--shell-glob" "있음" "없음"
grep -qx -- 'npx jest --runInBand' "$A" && ok "jest 를 준다" || bad "--cmd jest" "있음" "$(tr '\n' ' ' < "$A")"

echo "② 🔑 판정 불가 **추세를 실제로 켠다** — 안 붙이면 조용히 안 잰다 (코어 #91)"
st="$(grep -A1 -x -- '--unmeasured-state' "$A" 2>/dev/null | tail -1)"
[ -n "$st" ] && ok "--unmeasured-state 를 넘긴다" || bad "--unmeasured-state" "argv 에 있음" "없음"
case "$st" in
    */state/*) ok "  → gitignore 된 state/ 아래를 가리킨다" ;;
    *)         bad "상태 경로" "*/state/*" "${st:-없음}" ;;
esac

echo "③ CI 에서는 **안 붙인다** — 매번 새 컨테이너라 '첫 기록'이 상시가 되면 신호가 죽는다"
B="$(run_shuttle argv_ci.txt CI=1)"
grep -qx -- '--unmeasured-state' "$B" \
  && bad "CI 에서도 켠다" "CI 면 안 붙인다" "$(tr '\n' ' ' < "$B")" \
  || ok "CI 면 추세를 안 켠다"
# 🔑 갈래를 나누면서 **목록을 빠뜨리면 시험이 통째로 안 도는데 rc 만 보면 안 보인다**(룬드 #22).
grep -qx -- 'npx jest --runInBand' "$B" && ok "  → CI 에서도 목록은 그대로 넘어간다" \
  || bad "CI 목록" "jest 있음" "$(tr '\n' ' ' < "$B")"

echo "④ 🔑 상태 경로에 **공백이 있어도 한 토큰**으로 넘어간다"
# 🔴 `$ARGS` 를 안 감싸고 펼치면 공백에서 쪼개져 러너가 `모르는 인자` 로 죽는다(rc=2).
#    조용히 죽진 않지만 원인은 *공백* 인데 메시지는 *모르는 인자* 라 엉뚱한 데를 판다.
#    내가 룬드 `assistant#22` 에서 지적한 자리 — 내 코드에선 처음부터 잠근다.
C="$(run_shuttle argv_sp.txt UNMEASURED_STATE="$STUB_DIR/my state/unm.tsv")"
got="$(grep -A1 -x -- '--unmeasured-state' "$C" | tail -1)"
[ "$got" = "$STUB_DIR/my state/unm.tsv" ] && ok "공백 경로가 안 쪼개진다" \
  || bad "공백 경로" "$STUB_DIR/my state/unm.tsv" "$got"

echo "⑤ 러너 계약을 **여기서 다시 구현하지 않는다** — 그게 사본이다"
grep -qE 'unk=|pass=|판정 불가 [0-9]' "$SHUTTLE" \
  && bad "셔틀이 러너 계약을 재구현한다" "없어야 한다" "$(grep -nE 'unk=|pass=' "$SHUTTLE"|head -2)" \
  || ok "집계·판정은 러너에만 있다"

echo ""
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
