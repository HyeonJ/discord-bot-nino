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

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

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
DEFERRED_WHY='of/ 처분 Darren 대기 — 레포가 public 이라 of/cdm/(PEM 개인키)·record-drm-* 를 추적 밖에 둔 상태'

looks_like()     { ls -1 "$1/tests" 2>/dev/null | grep -E '(^test_.*\.(py|ts)$|\.test\.(sh|js|ts|py)$|\.obsolete$|^conftest\.py$|^__init__\.py$)' || true; }
runner_covered() { ls -1 "$1/tests" 2>/dev/null | grep -E '\.test\.(sh|js)$' | grep -v '\.obsolete$' || true; }
git_tracked()    { git -C "$1" ls-files 'tests/*' 2>/dev/null | sed 's|^tests/||' || true; }
# 🔴 「git 이 모른다」와 「여기 git 이 없다」는 다르다 — 뒤엣것은 **판정 불가**지 추적 밖이 아니다.
#    안 가르면 비-git 디렉터리에서 **전부 추적 밖**으로 읽혀 오탐이 난다(대조군이 잡아준 자리).
is_git_repo()    { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

echo "🔴 러너 분모 — 시험처럼 생긴 파일이 분모 밖에 있나  (root=${GUARD_ROOT})"

# 러너가 무엇을 도는지 **선언에서** 읽는다 (하드코딩하면 러너가 바뀔 때 조용히 낡는다)
RUNNER_DECL="$(grep -oE "\-\-shell-glob '[^']+'" "$GUARD_ROOT/tests/run-all.sh" 2>/dev/null)"
if [ -z "$RUNNER_DECL" ]; then
    bad "판정 불가 — run-all.sh 에서 글롭 선언을 못 읽었다" "--shell-glob '…'" "«없음»"
else
    ok "러너 글롭 선언을 읽었다: ${RUNNER_DECL}"
fi

LOOKS="$(looks_like "$GUARD_ROOT")"
COVERED="$(runner_covered "$GUARD_ROOT")"
if is_git_repo "$GUARD_ROOT"; then
    TRACK_MEASURABLE=1; TRACKED="$(git_tracked "$GUARD_ROOT")"
else
    TRACK_MEASURABLE=0; TRACKED=""
fi

is_deferred() { printf '%s\n' "$DEFERRED_NAMES" | grep -qxF "$1"; }

ORPHAN_GLOB=""; ORPHAN_TRACK=""; DEFERRED_STALE=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$f" | grep -qE "$EXCLUDE_RE" && continue
    _og=1; printf '%s\n' "$COVERED" | grep -qxF "$f" && _og=0
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

if [ "$TRACK_MEASURABLE" -eq 0 ]; then
    echo "  ⛔ ⓑ 추적 축 **판정 불가** — ${GUARD_ROOT} 는 git 레포가 아니다"
    echo "     (「추적 밖 0개」로 접지 않는다. 못 잰 것을 잰 척하지 않는다)"
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
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
