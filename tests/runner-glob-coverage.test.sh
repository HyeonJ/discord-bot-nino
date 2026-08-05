#!/usr/bin/env bash
# runner-glob-coverage.test.sh — 시험처럼 생긴 파일이 «분모 밖»에 있으면 빨강.
#
# 🔴 왜 생겼나 (2026-08-02, 룬드 `M:lqpv` 왕복에서 내 쪽 구멍이 드러났다):
#   러너는 `tests/*.test.sh` 글롭 + jest + bun 을 돈다. 그런데 `tests/test_of_*.py` 7개는
#   **어느 쪽에도 안 걸려서 한 번도 안 돌고 있었다.** 그 사이 원장에 적힌 「통과 N」은
#   그 7개를 **분모에서 뺀 값**이었고, 실제로 그 안에 실패가 **1건** 숨어 있었다.
#
# 🔑 이 시험이 잠그는 것은 「지금 글롭이 맞나」가 아니라 **「분모가 낡는 것」**이다.
#   글롭은 쓸 당시엔 정확했다 — `.py` 시험이 **나중에** 들어오며 분모 밖으로 떨어졌다.
#   ⇒ 한 번 고치는 것으로는 안 닫힌다. 다음 `.py`·`.ts` 에서 같은 자리가 다시 열린다.
#
# 🔴 축이 **둘**이다 (2026-08-02 18:4x 실측에서 갈렸다):
#   ⓐ 글롭 밖  — 파일은 있는데 **러너가 안 돈다**
#   ⓑ 추적 밖  — 파일은 있는데 **git 이 모른다** ⇒ CI 체크아웃엔 아예 없다
#   둘을 한 칸으로 접으면 안 된다. **처방이 다르고**(ⓐ=러너 배선 / ⓑ=커밋),
#   ⓑ 는 「로컬 초록」이 「CI 초록」을 대변 못 하는 상태다.
#
#   실측: 같은 스크립트가 **워크트리 rc=0 · main 작업트리 rc=1**. 추적 밖 파일이 한쪽에만
#   있기 때문이다. 축을 안 가르면 이 차이가 「글롭이 고쳐졌다」로 잘못 읽힌다.
#
# 🔑 형태: **적힌 것 + 벗어나면 시끄럽다.** 새 확장자를 들이려면 러너에 배선하거나
#   아래 «의도적 제외»/«유예» 에 **이름과 이유**를 적어야 한다. 둘 다 안 하면 빨개진다.
#   ⚠️ 유예는 **이름으로** 적는다(건수 아님) — 건수면 「A 빠지고 B 유입」이 통과한다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 🔑 주입구를 두고 **이 시험이 직접 쓴다.** 주입구만 만들고 안 쓰면 없는 것과 같다
#   (룬드 실물: `alarm-tool`·`watchdog-rund` 가 정확히 그 꼴이었다 — 주입구가 있는데 시험이 안 썼다).
GUARD_ROOT="${GUARD_ROOT:-$ROOT}"

pass=0; fail=0; unknown=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
# 🔴 **못 잰 것은 실패도 통과도 아니다** — 코어 계약의 `2`. 초판은 ⓐ 쪽 판정 불가를 `bad`(실패)로,
#   ⓑ 쪽은 **아무 칸에도** 안 세서 **같은 성질이 두 갈래로 흩어져 있었다**(룬드 리뷰 ②).
#   ⇒ 칸을 하나 만들어 양쪽이 여기로 온다. 요약이 「빨강 0 · 판정 불가 0」과 「빨강 0 · 판정 불가 8」을
#     같은 문장으로 내면, 「다 쟀다」와 「거의 못 쟀다」가 구별되지 않는다.
unk() { echo "  ⛔ $1"; [ -n "${2:-}" ] && echo "     $2"; unknown=$((unknown + 1)); }

# 🔸 의도적 제외 — 시험처럼 생겼지만 러너가 돌 «대상이 아닌» 것
EXCLUDE_RE='^(__init__\.py|conftest\.py|.*\.obsolete)$'

# 🔸 유예 — 「고칠 것」이지 「안 고칠 것」이 아니다. **이름 + 사유**로 적고 사유가 풀리면 뺀다.
#   ⚠️ 여기 적힌 파일이 «분모 안이 되면» 이 시험이 「목록에서 빼라」로 빨개진다
#      (종료 조건을 아무도 기억하지 않아도 되게 — 룬드 baseline 과 같은 형태).
DEFERRED_NAMES='test_of_drm.py
test_of_extractor.py
test_of_markdown.py
test_of_migrate.py
test_of_page.py
test_of_state.py
test_of_text.py'
# 🔴 사유는 «빚이 보이게» 하는 것이 목적이지 «경로를 공개»하는 게 아니다 (룬드 리뷰 ④).
#   이 레포는 public 이다 — 파일 자체는 추적 밖이라 유출은 아니지만, *「저기에 무엇이 있다」* 는
#   **포인터가 공개된다.** 상세는 비공개 쪽(`memory/current-tasks.md` · inbox)에 둔다.
DEFERRED_WHY='Darren 처분 대기 — 미추적 자산 관련(상세는 비공개 기록)'

looks_like()     { ls -1 "$1/tests" 2>/dev/null | grep -E '(^test_.*\.(py|ts)$|\.test\.(sh|js|ts|py)$|\.obsolete$|^conftest\.py$|^__init__\.py$)' || true; }
git_tracked()    { git -C "$1" ls-files 'tests/*' 2>/dev/null | sed 's|^tests/||' || true; }
# 🔴 「git 이 모른다」와 「여기 git 이 없다」는 다르다 — 뒤엣것은 **판정 불가**지 추적 밖이 아니다.
#    안 가르면 비-git 디렉터리에서 **전부 추적 밖**으로 읽혀 오탐이 난다(대조군이 잡아준 자리).
is_git_repo()    { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

echo "🔴 러너 분모 — 시험처럼 생긴 파일이 분모 밖에 있나  (root=${GUARD_ROOT})"

# 🔴 러너가 무엇을 도는지 **선언에서 읽고, 그 값으로 «판정한다».**
#   초판은 선언을 읽어 **출력만** 하고 판정은 하드코딩 패턴으로 했다(룬드 리뷰 ①).
#   🔑 그러면 **분모가 낡는 것을 잠그는 시험 자신이 같은 방식으로 낡는다** — 헤더의
#     *「한 번 고치는 것으로는 안 닫힌다」* 가 이 파일에도 걸린다.
#   ⚠️ 그리고 하드코딩이 선언보다 **넓었다**(`.js` 까지). 셋(shell·jest·bun)의 커버리지를
#     손으로 합친 값이라 **셋 중 어느 하나가 바뀌어도 안 걸렸다.**
RUN_ALL="$GUARD_ROOT/tests/run-all.sh"

# ① shell — `--shell-glob '<glob>'`. 선언이 **정확히 하나**여야 뜻이 하나다.
_sg_all="$(grep -oE "\-\-shell-glob '[^']+'" "$RUN_ALL" 2>/dev/null || true)"
_sg_n="$(printf '%s' "$_sg_all" | grep -c . || true)"
SHELL_GLOB=""
if [ "${_sg_n:-0}" -eq 1 ]; then
    SHELL_GLOB="$(printf '%s' "$_sg_all" | sed "s/.*'\(.*\)'/\1/")"
    ok "shell 글롭 선언을 읽었다: '${SHELL_GLOB}'"
else
    unk "shell 글롭 선언을 못 읽었다 (${_sg_n:-0}건 — 하나여야 한다)" \
        "run-all.sh 의 --shell-glob 를 확인할 것. 「글롭 밖 0개」로 접지 않는다"
fi

# ② bun — `bun test <파일…>`. 파일이 **명시**돼 있어 그대로 읽힌다.
BUN_FILES="$(grep -oE "bun test [^']*" "$RUN_ALL" 2>/dev/null | sed 's/^bun test //' \
             | tr ' ' '\n' | sed 's|^tests/||' | sed '/^$/d' || true)"

# ③ jest — 🔴 **선언에서 못 읽는다.** `npx jest` 는 무엇을 도는지 말하지 않고,
#   `package.json` 의 jest 키에도 `testMatch` 가 없어 **기본값에 기댄다**(실측 2026-08-05).
#   🔑 기본값을 이 시험이 «안다고 가정»하면 jest 가 바뀔 때 조용히 낡는다 — **이 시험이
#     막으려는 병 그 자체**다. ⇒ 아는 척하지 않고 **판정 불가**로 내보낸다.
JEST_DECL="$(grep -oE "npx jest[^']*" "$RUN_ALL" 2>/dev/null || true)"
JEST_MATCH="$(python3 -c "
import json,sys
try: print(json.load(open('$GUARD_ROOT/package.json')).get('jest',{}).get('testMatch') or '')
except Exception: print('')
" 2>/dev/null)"

# 🔑 covered 판정이 **선언에서** 나온다. 하드코딩 패턴은 없앴다.
shell_covered() {
    [ -n "$SHELL_GLOB" ] || return 1
    case "$1" in ${SHELL_GLOB##*/}) return 0 ;; esac
    return 1
}
bun_covered() { [ -n "$BUN_FILES" ] && printf '%s\n' "$BUN_FILES" | grep -qxF "$1"; }
# jest 가 «돌 수도 있는» 모양인가 — 도는지 «아닌지»를 여기서 정하지 않는다. 판정 불가로 보낼 뿐.
jest_shaped() { [ -n "$JEST_DECL" ] && [ -z "$JEST_MATCH" ] && case "$1" in *.test.js) return 0 ;; esac; return 1; }

LOOKS="$(looks_like "$GUARD_ROOT")"
if is_git_repo "$GUARD_ROOT"; then
    TRACK_MEASURABLE=1; TRACKED="$(git_tracked "$GUARD_ROOT")"
else
    TRACK_MEASURABLE=0; TRACKED=""
fi

is_deferred() { printf '%s\n' "$DEFERRED_NAMES" | grep -qxF "$1"; }

ORPHAN_GLOB=""; ORPHAN_TRACK=""; DEFERRED_STALE=""; UNKNOWN_GLOB=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$f" | grep -qE "$EXCLUDE_RE" && continue
    # 🔴 러너가 **선언에서 못 읽히는** 몫이면 「글롭 밖」이 아니라 «판정 불가»다.
    #    「안 걸렸다」로 두면 그 자리가 초록이 되고, 그게 정확히 이 시험이 막으려는 것이다.
    if jest_shaped "$f" && ! bun_covered "$f"; then
        UNKNOWN_GLOB="${UNKNOWN_GLOB}${f}"$'\n'; continue
    fi
    _og=1
    shell_covered "$f" && _og=0
    [ "$_og" -eq 1 ] && bun_covered "$f" && _og=0
    # 못 재는 자리에서는 «안 걸린다» 로 두지 않는다 — 아래에서 판정 불가로 따로 말한다
    if [ "$TRACK_MEASURABLE" -eq 1 ]; then
        _ot=1; printf '%s\n' "$TRACKED" | grep -qxF "$f" && _ot=0
    else
        _ot=0
    fi
    if [ "$_og" -eq 0 ] && [ "$_ot" -eq 0 ]; then
        # 분모 «안»이다. 유예에 적혀 있으면 그건 낡은 유예 — 빼라고 말한다
        is_deferred "$f" && DEFERRED_STALE="${DEFERRED_STALE}${f}"$'\n'
        continue
    fi
    is_deferred "$f" && continue
    [ "$_og" -eq 1 ] && ORPHAN_GLOB="${ORPHAN_GLOB}${f}"$'\n'
    [ "$_ot" -eq 1 ] && ORPHAN_TRACK="${ORPHAN_TRACK}${f}"$'\n'
done <<< "$LOOKS"

_join()  { printf '%s' "$1" | sed '/^$/d' | tr '\n' ' '; }
_count() { printf '%s' "$1" | sed '/^$/d' | grep -c . || true; }

NG="$(_count "$ORPHAN_GLOB")"; NT="$(_count "$ORPHAN_TRACK")"

if [ "$NG" -eq 0 ]; then
    ok "ⓐ 글롭 밖 0개 — 있는 시험을 러너가 다 돈다"
else
    bad "ⓐ 글롭 밖 ${NG}개 — 러너가 안 돈다(「통과 N」이 이만큼 좁다)" \
        "0개 (러너에 배선하거나 유예에 이름·사유를 적을 것)" "«$(_join "$ORPHAN_GLOB")»"
fi

NU="$(_count "$UNKNOWN_GLOB")"
if [ "$NU" -gt 0 ]; then
    unk "ⓐ 판정 불가 ${NU}개 — 러너 선언이 없어 «도는지 모른다»" \
        "«$(_join "$UNKNOWN_GLOB")» — jest 에 testMatch 를 선언하면 이 칸이 비워진다"
fi

if [ "$TRACK_MEASURABLE" -eq 0 ]; then
    unk "ⓑ 추적 축 판정 불가 — ${GUARD_ROOT} 는 git 레포가 아니다" \
        "(「추적 밖 0개」로 접지 않는다. 못 잰 것을 잰 척하지 않는다)"
elif [ "$NT" -eq 0 ]; then
    ok "ⓑ 추적 밖 0개 — 로컬 분모와 CI 분모가 같다"
else
    bad "ⓑ 추적 밖 ${NT}개 — CI 체크아웃엔 «없는» 파일이다(로컬 초록이 CI 를 대변 못 한다)" \
        "0개 (커밋하거나 유예에 이름·사유를 적을 것)" "«$(_join "$ORPHAN_TRACK")»"
fi

# 🔸 유예 현황 — 빚은 «보여야» 갚는다
ND="$(_count "$DEFERRED_NAMES")"
[ "$ND" -gt 0 ] && { echo "  ⏳ 유예 ${ND}건 — ${DEFERRED_WHY}"; echo "     «$(_join "$DEFERRED_NAMES")»"; }

NS="$(_count "$DEFERRED_STALE")"
if [ "$NS" -eq 0 ]; then
    ok "유예 목록에 «이미 해소된» 항목이 없다"
else
    bad "유예 ${NS}건이 이미 분모 안이다 — 목록에서 빼라(종료 조건)" "해소분 0" "«$(_join "$DEFERRED_STALE")»"
fi

# 🧪 [양성 대조군] 검사기를 **실제로 태운다** — 손으로 쓴 리터럴이 아니라 «같은 코드»에.
#   이게 없으면 위 초록이 「0개」인지 「안 셌다」인지 안 갈린다.
if [ "${GUARD_SELFTEST:-1}" = "1" ]; then
    echo
    echo "🧪 대조군 — 임시 트리를 만들어 같은 검사기를 태운다"
    _tmp="$(mktemp -d)"; trap 'rm -rf "$_tmp"' EXIT
    mkdir -p "$_tmp/tests"
    cp "$GUARD_ROOT/tests/run-all.sh" "$_tmp/tests/run-all.sh" 2>/dev/null \
        || echo "--shell-glob 'tests/*.test.sh'" > "$_tmp/tests/run-all.sh"
    : > "$_tmp/tests/alpha.test.sh"
    : > "$_tmp/tests/test_ghost.py"     # 글롭 밖 + 추적 밖, 유예에도 없다 → 둘 다 걸려야 한다
    # 🔑 대조군은 «진짜 git 레포»여야 한다. 아니면 ⓑ 가 판정 불가로 빠져 축이 안 갈린다.
    #    (첫 판이 그랬고 대조군이 그걸 잡았다 — 기대값 ⓑ=1 인데 실측 ⓑ=2 였다)
    git -C "$_tmp" init -q -b main >/dev/null 2>&1
    git -C "$_tmp" add tests/run-all.sh tests/alpha.test.sh >/dev/null 2>&1
    _o="$(GUARD_ROOT="$_tmp" GUARD_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc=$?
    if [ "$_rc" -ne 0 ] && printf '%s\n' "$_o" | grep -q 'test_ghost.py'; then
        ok "[대조군] 심어둔 test_ghost.py 를 잡고 빨강이 된다 (rc=${_rc})"
    else
        bad "[대조군] 검사기가 심어둔 파일을 못 잡는다 — 위 판정은 못 믿는다" "rc≠0 + test_ghost.py" "rc=${_rc}"
    fi
    # 🔑 «두 축이 따로 보고되는가» — 한 칸으로 접히면 처방이 갈리지 않는다
    if printf '%s\n' "$_o" | grep -q 'ⓐ 글롭 밖 1개' && printf '%s\n' "$_o" | grep -q 'ⓑ 추적 밖 1개'; then
        ok "[대조군] 두 축이 «따로» 보고된다"
    else
        bad "[대조군] 축이 갈리지 않는다" "ⓐ 1개 · ⓑ 1개 각각" "«$(printf '%s' "$_o" | grep -E 'ⓐ|ⓑ' | tr '\n' ' ')»"
    fi

    # 🧪 [대조군] **판정 불가 축은 «따로» 태운다** — 위 트리는 실패가 있어 rc=1 이라
    #   `2` 를 덮어쓴다. 실패 0 인 트리여야 「빨강 아닌데 0 도 아니다」가 보인다.
    #   🔑 새 축을 만들고 대조군을 안 붙이면, 그 축의 초록이 「0건」인지 「안 셌다」인지 안 갈린다.
    _t2="$(mktemp -d)"
    mkdir -p "$_t2/tests"
    printf "%s\n" "--shell-glob 'tests/*.test.sh'" "npx jest --runInBand" > "$_t2/tests/run-all.sh"
    : > "$_t2/tests/alpha.test.sh"
    : > "$_t2/tests/ghost.test.js"      # jest 몫으로 «보이는데» 선언이 없다 → 판정 불가
    git -C "$_t2" init -q -b main >/dev/null 2>&1
    git -C "$_t2" add tests/ >/dev/null 2>&1
    _o2="$(GUARD_ROOT="$_t2" GUARD_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc2=$?
    rm -rf "$_t2"
    if [ "$_rc2" -eq 2 ] && printf '%s\n' "$_o2" | grep -q 'ghost.test.js'; then
        ok "[대조군] 실패 0 · 판정 불가 1 → **rc=2** (초록으로 접지 않는다)"
    else
        bad "[대조군] 판정 불가가 rc 로 안 나온다" "rc=2 + ghost.test.js" \
            "rc=${_rc2} — «$(printf '%s' "$_o2" | grep -E '통과 |⛔' | tr '\n' ' ')»"
    fi
fi

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $unknown"
# 🔴 rc 계약: 1 = 빨강 · **2 = 못 쟀다(초록 아님)** · 0 = 다 재고 초록.
#   🔑 실패가 0 이어도 판정 불가가 있으면 **0 을 주지 않는다** — 그 0 은 「다 통과」로 읽히고,
#     「거의 못 쟀는데 걸린 게 없다」와 구별이 사라진다. `#146` 신규 조항의 코드 판이다.
[ "$fail" -gt 0 ] && exit 1
[ "$unknown" -gt 0 ] && exit 2
exit 0
