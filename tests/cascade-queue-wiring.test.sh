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
#
# 🔴 `bash -uc` 의 `-u` 가 이 검사기의 «뼈»다 (룬드 리뷰 #153, M6).
#   선행 대입문(`MEMORY_AUTO_DIR=`·`WIKI=`)을 못 뽑으면 그 변수는 «미설정»인데,
#   `-u` 가 없으면 셸이 그걸 **빈 문자열로 확장**해서 경로가 `/state/cascade-queue.md` 가 된다.
#   한쪽만 그러면 불일치로 잡히지만 **둘 다 그러면 값이 같아져 초록**이 뜬다.
#   🔑 그 초록불은 「같은 파일을 본다」가 아니라 **「두 문자열이 같다」**의 초록불이다.
#   ⚠️ 발동이 «흔한 편집 하나»다 — 경로를 공통 lib 으로 빼면 양쪽이 동시에 `^` 밖으로 나간다.
#      그때 훅·린트는 진짜 경로로 잘 돌고 **시험만 헛것을 대조하며 초록**을 낸다.
#   ⇒ `-u` 로 «빈 값이 경로를 만들 수 없게» 한다. 아래 [M6] 대조군이 이 칸을 지킨다.
#      🔸 «$HOME 접두 단언»으로도 막히지만 그건 리터럴 가정을 하나 더 만든다 — `-u` 는 안 늘린다.
eval_assign() {
    local file="$1" pattern="$2" var="$3" line
    line=$(grep -m1 -E "$pattern" "$file" || true)
    [ -n "$line" ] || { echo ""; return 1; }
    env -u QUEUE -u CASCADE_QUEUE -u MEMORY_AUTO_DIR -u WIKI bash -uc "
        $(grep -m1 -E '^(export )?MEMORY_AUTO_DIR=' "$file" || true)
        $(grep -m1 -E '^(export )?WIKI=' "$file" || true)
        $line
        printf '%s' \"\${$var}\"" 2>/dev/null
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
#   🔑 두 칸을 «따로» 지킨다 — 어긋남은 ❌(실패)로, 못 읽음은 ⛔(판정 불가)로 떨어져야 한다.
#      한 칸으로 합치면 「고쳤다」와 「눈을 감았다」가 같은 값이 된다.
if [ "${CASCADE_WIRING_SELFTEST:-1}" = "1" ]; then
    echo
    echo "🧪 대조군 — 사본을 어긋내고 같은 검사기를 태운다"
    _t="$(mktemp -d)"; trap 'rm -rf "$_t"' EXIT

    # 변이 하나를 태우고 «어느 칸으로 떨어지는가»를 본다. sed 식이 'b' 면 무변경.
    mutant() {
        local name="$1" want_rc="$2" want_msg="$3" hsed="$4" lsed="$5" d o rc
        d="$_t/$name"; mkdir -p "$d/hooks" "$d/scripts" "$d/tests"
        sed "$hsed" "$HOOK" > "$d/hooks/cascade-queue.sh"
        sed "$lsed" "$LINT" > "$d/scripts/lint-nino-memory.sh"
        cp "${BASH_SOURCE[0]}" "$d/tests/"
        o="$(CASCADE_WIRING_SELFTEST=0 bash "$d/tests/$(basename "${BASH_SOURCE[0]}")" 2>&1)"; rc=$?
        if [ "$rc" = "$want_rc" ] && printf '%s\n' "$o" | grep -q "$want_msg"; then
            # 🔴 «${want_msg}» — 중괄호 필수. bash 3.2(맥 기본)는 `»`(U+00BB = C2 BB)의 «앞 바이트»를
            #   식별자 문자로 먹어 변수명이 `want_msg\xC2` 가 된다. `set -u` 라 그 자리에서 죽는다.
            #   ⚠️ 리눅스 bash 5.x 에선 «안 죽는다» — CI 러너도 저자와 같은 편이라 이 축은
            #      실행으로는 안 잡힌다. 잡는 건 정적 검사뿐이다(`shared-contract-drift` 의 `$VAR»` 판별식).
            ok "[대조군 $name] rc=$rc «${want_msg}»"
        else
            bad "[대조군 $name] 이 칸을 못 지킨다 — 위 판정은 못 믿는다" \
                "rc=$want_rc + '$want_msg'" "rc=$rc + $(printf '%s' "$o" | tr '\n' ' ')"
        fi
    }

    # M1 — 훅만 다른 곳을 보게 한다. 어긋남은 «실패»여야 한다.
    mutant 어긋난배선 1 '다른 파일을 본다' \
        's#^QUEUE=.*#QUEUE="$HOME/somewhere-else/cascade-queue.md"#' 'b'

    # M6 — 양쪽 선행 대입문을 «동시에» 들여써서 `^` 밖으로 뺀다(공통 lib 리팩터링의 형태).
    #   `-u` 가 없으면 양쪽이 똑같이 «/state/cascade-queue.md» 로 접혀 **초록**이 뜬다.
    #   못 읽은 것은 실패가 아니라 «판정 불가»로 떨어져야 한다 — 변수명 변경(M3·M4)과 같은 칸이다.
    mutant 양쪽못읽음 2 '판정 불가' \
        's#^WIKI=#  WIKI=#' 's#^export MEMORY_AUTO_DIR=#  export MEMORY_AUTO_DIR=#'
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
