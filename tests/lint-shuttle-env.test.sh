#!/usr/bin/env bash
# lint-nino-memory.sh 셔틀이 정본에 **무슨 값을 넘기는지** 재는 시험
#
# 🔴 이 시험이 생긴 이유 (2026-08-02):
#   bot-core #129 로 `WIKI_ORPHAN_EXCLUDES` 장치를 넣고 「고아 5건 해결」이라 부를 뻔했다.
#   그런데 그 장치의 **기본값은 비어 있다**(일부러 그렇게 만들었다 — 안 쓰는 봇은 안 바뀌게).
#   ⇒ 정본에 코드가 들어간 것과 **내 볼트에서 실제로 빠지는 것**은 다르다.
#      값을 주는 쪽은 셔틀이고, 셔틀이 안 주면 머지해도 **아무것도 안 바뀐다.**
#
#   🔑 그래서 이 시험은 정본을 부르지 않는다. `LINT_MEMORY_CANONICAL` 로 **가짜 정본**을
#      꽂아 「셔틀이 넘긴 환경」만 본다. 정본의 동작은 bot-core 시험의 몫이고,
#      여기서 겹쳐 재면 정본이 바뀔 때마다 이 시험이 같이 빨개진다(사본이 따로 늙는다).
#
# ⚠️ 부작용 격리: 셔틀은 실행되면 진짜 볼트·메모리를 훑는다. 가짜 정본이 그걸 막는다.
#    (같은 이유로 HOME 은 안 건드린다 — 셔틀의 기본값 해석 자체가 검사 대상이라서)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SHUTTLE="$REPO/scripts/lint-nino-memory.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$SHUTTLE" ] || { echo "❌ 없음: $SHUTTLE"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# 가짜 정본 — 넘어온 환경을 그대로 뱉는다
STUB="$WORK/fake-canonical.sh"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
for v in WIKI_ORPHAN_EXCLUDES SIZE_BASELINE MEMORY_WIKI_DIR MEMORY_AUTO_DIR MEMORY_SHARED_DIR; do
  printf '%s=%s\n' "$v" "${!v-«unset»}"
done
SH
chmod +x "$STUB"

run_shuttle() { LINT_MEMORY_CANONICAL="$STUB" bash "$SHUTTLE" 2>&1; }
val_of() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

echo "① 🔑 계측기를 먼저 먹인다 — 가짜 정본이 정말 환경을 받아 찍는가"
out="$(WIKI_ORPHAN_EXCLUDES='PROBE-XYZ' run_shuttle)"; rc=$?
[ "$rc" -eq 0 ] && ok "셔틀이 가짜 정본을 exec 한다 (rc=0)" || bad "rc" "0" "$rc"
[ "$(val_of "$out" WIKI_ORPHAN_EXCLUDES)" = "PROBE-XYZ" ] \
  && ok "  → 넘긴 값이 그대로 보인다(이게 없으면 아래 초록이 무의미하다)" \
  || bad "계측기" "PROBE-XYZ" "$out"

echo "② 🔑 셔틀이 WIKI_ORPHAN_EXCLUDES 를 **준다** — 정본 기본값은 비어 있어서 안 주면 안 바뀐다"
out2="$(run_shuttle)"
got2="$(val_of "$out2" WIKI_ORPHAN_EXCLUDES)"
case "$got2" in
  ''|'«unset»') bad "셔틀이 값을 안 넘긴다 — 볼트 고아 5건이 그대로 뜬다" "darren 포함" "«${got2}»" ;;
  *darren*)     ok "darren/ 이 제외 목록에 들어 있다 (Darren 이 고른 ⓑ)" ;;
  *)            bad "제외 목록에 darren 이 없다" "darren 포함" "«${got2}»" ;;
esac

# ⚠️ ③ 은 **② 가 초록이 된 뒤에만** 무언가를 가른다. 배선이 아예 없던 시점(TDD 빨간불)에도
#    통과했다 — 셔틀이 변수를 안 건드리면 값이 그냥 통과하기 때문. 즉 ③ 단독 초록은
#    「안 덮는다」가 아니라 「아무것도 안 한다」와 구별되지 않는다. ②와 짝으로만 읽는다.
echo "③ 🔑 밖에서 준 값은 안 덮는다 — DENSITY_EXCLUDES·SIZE_EXCLUDES 와 같은 관례"
out3="$(WIKI_ORPHAN_EXCLUDES='onlythis' run_shuttle)"
got3="$(val_of "$out3" WIKI_ORPHAN_EXCLUDES)"
[ "$got3" = "onlythis" ] \
  && ok "호출자가 준 값이 이긴다 (진단할 때 범위를 바꿔 볼 수 있다)" \
  || bad "덮어썼다" "onlythis" "«${got3}»"

echo "③-b 🔴 **빈 값으로 끌 수 있다** — 이걸 못 하면 대조군을 만들 수 없다"
# 실사고(2026-08-02): 처음엔 `${VAR:-darren}` 로 짰다. `:-` 는 **빈 값도 「안 준 것」으로 쳐서**
#   darren 을 도로 꽂는다. 그 판으로 델타를 재니 `WIKI_ORPHAN_EXCLUDES=''` 대조군이
#   실험군과 **글자까지 같은 출력**을 냈다 — 「제외가 안 듣는다」로 읽힐 뻔했다.
#   🔑 위 ③(비어있지 않은 값)은 이 결함을 **통과시킨다.** 대조군을 만드는 능력은 따로 잰다.
out3b="$(WIKI_ORPHAN_EXCLUDES='' run_shuttle)"
got3b="$(val_of "$out3b" WIKI_ORPHAN_EXCLUDES)"
[ -z "$got3b" ] \
  && ok '빈 값을 주면 빈 채로 간다 (콜론붙은 :- 였다면 darren 이 도로 꽂힌다)' \
  || bad "빈 값이 덮였다 — 대조군을 못 만든다" "빈 문자열" "«${got3b}»"

echo "④ 대조군 — 제외를 넣다가 원래 넘기던 3경로를 깨지 않았다"
for v in MEMORY_WIKI_DIR MEMORY_AUTO_DIR MEMORY_SHARED_DIR; do
  g="$(val_of "$out2" "$v")"
  case "$g" in
    ''|'«unset»') bad "$v 가 안 넘어간다" "경로" "«${g}»" ;;
    /*)           ok "  → $v 가 절대경로로 넘어간다" ;;
    *)            bad "$v 가 절대경로가 아니다" "/로 시작" "«${g}»" ;;
  esac
done

echo "⑤ 🔴 SIZE_BASELINE 도 **빈 값으로 끌 수 있다** — 같은 결함이 여기에도 있었다"
# 🔑 이 절은 룬드가 자기 셔틀의 SIZE_BASELINE 을 같은 이유로 고친 커밋(assistant `112177a`)을 보고
#   **내 분모를 훑어서** 찾았다. `:-` 를 하나 고친 걸로 「그 축은 닫혔다」고 읽으면 안 된다 —
#   같은 파일 안에 같은 기전이 하나 더 살아 있었다.
# 실측(고치기 전): SIZE_BASELINE='' 로 준 출력과 기본값 출력이 **225줄 내내 diff 0** 이었다.
#   면제 24건을 밖에서 끌 방법이 없어서, 「면제가 무엇을 가리고 있나」를 잴 수 없었다.
out5="$(SIZE_BASELINE='' run_shuttle)"
got5="$(val_of "$out5" SIZE_BASELINE)"
[ -z "$got5" ] \
  && ok "빈 값을 주면 빈 채로 간다 → 면제를 끄고 원래 위반을 볼 수 있다" \
  || bad "빈 값이 덮였다 — 면제를 못 꺼서 무엇을 가리는지 못 잰다" "빈 문자열" "«${got5}»"
got5b="$(val_of "$out2" SIZE_BASELINE)"
case "$got5b" in
  /*) ok "  → 기본값은 그대로 절대경로로 간다 (끄는 걸 만들다 켜는 걸 깨지 않았다)" ;;
  *)  bad "기본 SIZE_BASELINE 이 절대경로가 아니다" "/로 시작" "«${got5b}»" ;;
esac

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
