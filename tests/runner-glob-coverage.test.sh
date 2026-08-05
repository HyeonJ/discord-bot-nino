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
# ⚠️ 경로는 **레포 상대경로**(`tests/…`)다 — basename 이 아니다(룬드 리뷰 ②·③).
EXCLUDE_RE='(^|/)(__init__\.py|conftest\.py)$|\.obsolete$'

# 🔸 유예 — 「고칠 것」이지 「안 고칠 것」이 아니다. **이름 + 사유**로 적고 사유가 풀리면 뺀다.
#   ⚠️ 여기 적힌 파일이 «분모 안이 되면» 이 시험이 「목록에서 빼라」로 빨개진다
#      (종료 조건을 아무도 기억하지 않아도 되게 — 룬드 baseline 과 같은 형태).
DEFERRED_NAMES='tests/test_of_drm.py
tests/test_of_extractor.py
tests/test_of_markdown.py
tests/test_of_migrate.py
tests/test_of_page.py
tests/test_of_state.py
tests/test_of_text.py'
# 🔴 사유는 «빚이 보이게» 하는 것이 목적이지 «경로를 공개»하는 게 아니다 (룬드 리뷰 ④).
#   이 레포는 public 이다 — 파일 자체는 추적 밖이라 유출은 아니지만, *「저기에 무엇이 있다」* 는
#   **포인터가 공개된다.** 상세는 비공개 쪽(`memory/current-tasks.md` · inbox)에 둔다.
DEFERRED_WHY='Darren 처분 대기 — 미추적 자산 관련(상세는 비공개 기록)'

# 🔴 **재귀로 본다** (룬드 리뷰 ②). 초판은 `ls -1 tests` 라 **비재귀**였고, `tests/unit/orphan.test.sh`
#   같은 한 층 아래 고아를 **「글롭 밖 0개 — 다 돈다」로 승인**했다. `git_tracked` 는 재귀로 잡는데
#   `looks_like` 목록에 없으니 ⓑ 도 조용해서 **두 축이 같이 못 봤다.**
#   🔑 **부재가 아니라 «거짓 초록»이라 등급이 다르다** — 이 가드의 존재 목적이 「러너가 안 도는 시험
#     찾기」인데, 한 층 아래면 오히려 「다 돈다」고 말한다. `tests/unit/` 은 평범한 다음 수순이다.
looks_like() {
    find "$1/tests" -type f 2>/dev/null | sed "s|^$1/||" \
        | grep -E '(^|/)(test_.*\.(py|ts)|.*\.test\.(sh|js|ts|py))$|\.obsolete$|(^|/)(conftest|__init__)\.py$' || true
}
git_tracked()    { git -C "$1" ls-files 'tests/*' 2>/dev/null || true; }
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

# ② bun — `bun test <파일…>`. 파일이 **명시**돼 있어 그대로 읽힌다(레포 상대경로 그대로).
BUN_FILES="$(grep -oE "bun test [^']*" "$RUN_ALL" 2>/dev/null | sed 's/^bun test //' \
             | tr ' ' '\n' | sed '/^$/d' || true)"

# ③ jest — `npx jest` 자체는 무엇을 도는지 **말하지 않는다.** `package.json` 의 `testMatch` 가
#   있으면 그것이 선언이고, **없으면 기본값에 기댄다**(실측 2026-08-05: 이 레포엔 없다).
#   🔑 기본값을 이 시험이 «안다고 가정»하면 jest 가 바뀔 때 조용히 낡는다 — **막으려는 병 그 자체**.
#     ⇒ 선언이 없으면 아는 척하지 않고 **판정 불가**로 내보낸다.
#   🔴 **선언이 «있으면» 반드시 매칭에 써야 한다**(룬드 리뷰 ①). 초판은 읽기만 하고 안 써서,
#     `testMatch` 를 선언하면 `.test.js` 가 어디에도 안 걸려 **실패**가 됐다 — 동결의 «출구»라던
#     수리가 오히려 **문을 잠갔다.** 읽은 값을 안 쓰면 읽은 것이 아니다.
JEST_DECL="$(grep -oE "npx jest[^']*" "$RUN_ALL" 2>/dev/null || true)"
# 🔸 도구 부재와 «선언 부재»를 가른다(룬드 리뷰 ③) — 방향은 안전해도 **판정 불가의 «사유»가
#   거짓**이 되면, 이 파일의 주제가 정확히 그 구별이라 스스로를 배반한다.
#   🔑 주입구를 두되 **아래 대조군이 실제로 쓴다** — 안 쓰면 없는 것과 같다(이 파일 헤더의 규칙).
#   🔴 **«존재»가 아니라 «동작»을 본다** (룬드 2차 ③): `command -v` 는 pyenv shim·brew 갱신 중·
#     권한 문제로 **있는데 죽는** python3 를 통과시킨다. 완전 부재만 잡히고 그 셋은 접혔다.
#     🔑 내가 세운 *「주입구만 만들면 없는 것과 같다」* 의 한 칸 더 — **대조군이 주입구를 재고
#       «실제 조건»을 안 쟀다.** ⇒ 실행 rc 로 판정한다.
if [ "${GUARD_NO_PYTHON:-0}" = 1 ]; then PY_OK=0
elif python3 -c 'pass' >/dev/null 2>&1; then PY_OK=1
else PY_OK=0; fi
JEST_MATCH=""
if [ "$PY_OK" -eq 1 ]; then
    # 🔸 `$GUARD_ROOT` 를 **보간하지 않는다** — 경로에 `'` 가 있으면 깨진다(룬드). `sys.argv` 로.
    JEST_MATCH="$(python3 -c '
import json, sys
try:
    m = json.load(open(sys.argv[1] + "/package.json")).get("jest", {}).get("testMatch") or []
except Exception:
    m = []
print("\n".join(m))
' "$GUARD_ROOT" 2>/dev/null || true)"
fi

# 🔑 **글롭을 «해석»하지 않고 «확장»한다.** 초판은 `${SHELL_GLOB##*/}` 로 basename 패턴을 떼서
#   `case` 에 물렸는데, `case` 의 `*` 는 **`/` 를 넘어가서** `tests/*.test.sh` 가
#   `tests/unit/x.test.sh` 에도 맞는다. 반대로 글롭이 `tests/unit/*.test.sh` 로 바뀌면
#   `*.test.sh` 로 눌려 **루트 파일을 covered 로 오판**한다 — **같은 병의 양방향**이다(룬드 ②).
#   ⇒ 셸에게 확장을 시킨다. **러너가 하는 것과 «같은 연산»**이라 대리값 거리가 그만큼 줄어든다.
_expand() { ( cd "$GUARD_ROOT" 2>/dev/null || exit 0; shopt -s nullglob; for p in $1; do printf '%s\n' "$p"; done ); }
SHELL_COVERED=""
[ -n "$SHELL_GLOB" ] && SHELL_COVERED="$(_expand "$SHELL_GLOB")"
# jest 는 `**` 를 쓰므로 `globstar` 가 필요하다. 선언이 있을 때만 확장한다.
# 🔴 **`globstar` 는 bash 3.2(맥 기본)에 «없다»** — 룬드 맥 실측 2026-08-05:
#   `shopt -s nullglob globstar` 는 nullglob 만 켜고 globstar 에서 죽는다. 그러면 `**` 가
#   그냥 `*` 라 **`/` 를 못 넘고**, `tests/unit/x.test.sh` 가 「글롭 밖」= **실패**로 나온다.
#   🔑 **jest 는 실제로 도는데 시험이 「안 돈다」고 빨강을 낸다 — 거짓 «빨강»**이다.
#   ⚠️ 내 리눅스와 CI 에선 영원히 안 보인다. 그리고 맥에서도 **파일이 1단계면 안 터진다** —
#     *「우연한 일치가 방법을 승인하지 않는다」*(㊲)의 실물이라, 깊이에 기대지 않는다.
#   ⇒ 계약대로 **못 펴면 «판정 불가»**다. 못 쟀는데 빨강을 내면 **「고칠 게 있다」는 거짓 정보**가 되고,
#     실제로 내 대조군이 그 거짓 정보를 냈다(「이 수리로는 동결이 안 풀린다」 ← 리눅스에선 풀린다).
GLOBSTAR_OK=0
if [ "${GUARD_NO_GLOBSTAR:-0}" != 1 ]; then
    ( shopt -s globstar ) >/dev/null 2>&1 && GLOBSTAR_OK=1
fi
JEST_UNEXPANDABLE=0
if [ -n "$JEST_MATCH" ] && [ "$GLOBSTAR_OK" -eq 0 ]; then
    case "$JEST_MATCH" in *'**'*) JEST_UNEXPANDABLE=1 ;; esac
fi

JEST_COVERED=""
if [ -n "$JEST_MATCH" ] && [ "$JEST_UNEXPANDABLE" -eq 0 ]; then
    JEST_COVERED="$( ( cd "$GUARD_ROOT" 2>/dev/null || exit 0
        shopt -s nullglob
        shopt -s globstar 2>/dev/null || true
        while IFS= read -r pat; do
            [ -n "$pat" ] || continue
            for p in $pat; do printf '%s\n' "$p"; done
        done <<< "$JEST_MATCH" ) | sort -u)"
fi

_in_list() { [ -n "$2" ] && printf '%s\n' "$2" | grep -qxF "$1"; }
shell_covered() { _in_list "$1" "$SHELL_COVERED"; }
bun_covered()   { _in_list "$1" "$BUN_FILES"; }
jest_covered()  { _in_list "$1" "$JEST_COVERED"; }
# 🔴 jest 선언이 **없을 때만** 판정 불가로 보낸다. 선언이 있으면 위에서 확장돼 covered 로 잡힌다.
jest_unknown() {
    [ -n "$JEST_DECL" ] || return 1
    # 선언이 없거나(기본값 의존), 있어도 이 셸이 «못 편다»면 둘 다 「모른다」다.
    if [ -z "$JEST_MATCH" ] || [ "$JEST_UNEXPANDABLE" -eq 1 ]; then
        case "$1" in *.test.js) return 0 ;; esac
    fi
    return 1
}

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
    if jest_unknown "$f" && ! bun_covered "$f"; then
        UNKNOWN_GLOB="${UNKNOWN_GLOB}${f}"$'\n'; continue
    fi
    _og=1
    shell_covered "$f" && _og=0
    [ "$_og" -eq 1 ] && bun_covered  "$f" && _og=0
    [ "$_og" -eq 1 ] && jest_covered "$f" && _og=0
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
    # 🔴 **사유를 가른다** (룬드 리뷰 ③). 방향은 둘 다 안전하지만(판불로 접힘), 「선언이 없다」와
    #   「읽을 도구가 없다」를 같은 문장으로 내면 **판정 불가의 «사유»가 거짓**이 된다 —
    #   이 파일의 주제가 정확히 그 구별이라, 그러면 스스로를 배반한다.
    if [ "$PY_OK" -eq 0 ]; then
        unk "ⓐ 판정 불가 ${NU}개 — jest 선언을 «읽을 도구»가 없다(python3 부재). 선언 부재가 아니다" \
            "«$(_join "$UNKNOWN_GLOB")» — python3 를 두면 이 칸의 사유부터 갈린다"
    elif [ "$JEST_UNEXPANDABLE" -eq 1 ]; then
        unk "ⓐ 판정 불가 ${NU}개 — 선언은 «있는데» 이 셸에 globstar 가 없어 «**» 를 못 편다" \
            "«$(_join "$UNKNOWN_GLOB")» — bash 4+ 에서 재라(맥 기본 3.2 에는 없다). 선언 부재가 아니다"
    else
        unk "ⓐ 판정 불가 ${NU}개 — 러너 선언이 없어 «도는지 모른다»" \
            "«$(_join "$UNKNOWN_GLOB")» — jest 에 testMatch 를 선언하면 이 칸이 비워진다"
    fi
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
    # 🔸 `trap` 을 «갱신»한다 — 초판은 `_tmp` 만 걸려 있어 `_t2` 가 중간 실패 시 남았다(룬드 ④).
    trap 'rm -rf "$_tmp" "${_t2:-}"' EXIT
    mkdir -p "$_t2/tests"
    printf "%s\n" "--shell-glob 'tests/*.test.sh'" "npx jest --runInBand" > "$_t2/tests/run-all.sh"
    : > "$_t2/tests/alpha.test.sh"
    : > "$_t2/tests/ghost.test.js"      # jest 몫으로 «보이는데» 선언이 없다 → 판정 불가
    git -C "$_t2" init -q -b main >/dev/null 2>&1
    git -C "$_t2" add tests/ >/dev/null 2>&1
    _o2="$(GUARD_ROOT="$_t2" GUARD_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc2=$?
    # 🔴 여기서 `rm -rf "$_t2"` 를 하지 않는다 — 아래 「출구」 대조군이 **같은 트리를 다시 쓴다.**
    #   초판은 지웠고, 그러자 다음 대조군이 «빈 트리»를 재서 빨개졌다. 정리는 `trap` 몫이다.
    #   🔑 그때 빨강의 뜻은 「처방이 안 통한다」가 아니라 **「대조군이 안 섰다」**였다 —
    #     둘을 안 가르면 멀쩡한 수리를 되돌린다. `bad` 의 `got` 에 실측값을 붙여둬서 갈렸다.
    if [ "$_rc2" -eq 2 ] && printf '%s\n' "$_o2" | grep -q 'ghost.test.js'; then
        ok "[대조군] 실패 0 · 판정 불가 1 → **rc=2** (초록으로 접지 않는다)"
    else
        bad "[대조군] 판정 불가가 rc 로 안 나온다" "rc=2 + ghost.test.js" \
            "rc=${_rc2} — «$(printf '%s' "$_o2" | grep -E '통과 |⛔' | tr '\n' ' ')»"
    fi

    # 🧪 [대조군] **동결의 «출구»가 실제로 열리나** — jest 에 testMatch 를 «선언하면» 초록이어야 한다.
    #   🔴 초판은 여기서 **rc=1(실패 1)** 이 나왔다. 읽기만 하고 매칭에 안 썼기 때문이다(룬드 ①).
    #     그 상태로 넣었으면 동결 통과식에 대입해 **어떤 PR 도 못 들어간다** — 「출구」가 문을 잠갔다.
    #   🔑 처방을 시험하지 않으면 **처방이 있다는 것만 참**이 된다.
    printf '%s\n' '{"jest":{"testMatch":["**/tests/**/*.test.js"]}}' > "$_t2/package.json"
    _o3="$(GUARD_ROOT="$_t2" GUARD_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc3=$?
    if [ "$_rc3" -eq 0 ]; then
        ok "[대조군] jest testMatch 를 선언하면 **rc=0** — 동결의 출구가 실제로 열린다"
    else
        bad "[대조군] 출구가 안 열린다 — 이 수리로는 동결이 안 풀린다" "rc=0" \
            "rc=${_rc3} — «$(printf '%s' "$_o3" | grep -E '통과 |❌|⛔' | tr '\n' ' ')»"
    fi

    # 🧪 [대조군] **하위 디렉터리 고아를 잡나** (룬드 ②/③ — 초판은 여기서 「다 돈다」고 승인했다)
    _t3="$(mktemp -d)"
    trap 'rm -rf "$_tmp" "${_t2:-}" "${_t3:-}"' EXIT
    mkdir -p "$_t3/tests/unit"
    printf "%s\n" "--shell-glob 'tests/*.test.sh'" > "$_t3/tests/run-all.sh"
    : > "$_t3/tests/alpha.test.sh"
    : > "$_t3/tests/unit/orphan.test.sh"      # 한 층 아래 — 러너 글롭이 안 닿는다
    git -C "$_t3" init -q -b main >/dev/null 2>&1
    git -C "$_t3" add tests/ >/dev/null 2>&1
    _o4="$(GUARD_ROOT="$_t3" GUARD_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc4=$?
    if [ "$_rc4" -ne 0 ] && printf '%s\n' "$_o4" | grep -q 'tests/unit/orphan.test.sh'; then
        ok "[대조군] 하위 디렉터리 고아를 잡는다 (rc=${_rc4}) — 「다 돈다」로 승인하지 않는다"
    else
        bad "[대조군] 한 층 아래를 못 본다 — 거짓 초록" "rc≠0 + tests/unit/orphan.test.sh" \
            "rc=${_rc4} — «$(printf '%s' "$_o4" | grep -E 'ⓐ|통과 ' | tr '\n' ' ')»"
    fi

    # 🧪 [대조군] **판정 불가의 «사유»가 갈리나** — 도구 부재를 「선언 부재」로 말하면 거짓이다.
    #   🔑 여기서 재는 건 rc 가 아니라 **문장**이다. 방향(판불)은 어차피 같아서 rc 로는 안 갈린다.
    _o5="$(GUARD_ROOT="$_t2" GUARD_SELFTEST=0 GUARD_NO_PYTHON=1 bash "${BASH_SOURCE[0]}" 2>&1)"
    if printf '%s\n' "$_o5" | grep -q 'python3 부재'; then
        ok "[대조군] python3 가 없으면 사유가 «도구 부재»로 갈린다 (선언 부재와 안 섞인다)"
    else
        bad "[대조군] 도구 부재가 「선언 부재」로 읽힌다 — 판정 불가의 사유가 거짓" \
            "'python3 부재' 가 사유에" "«$(printf '%s' "$_o5" | grep '⛔' | tr '\n' ' ')»"
    fi

    # 🧪 [대조군] **globstar 가 없으면 «판정 불가»여야 한다** — 실패가 아니라.
    #   🔴 이 대조군은 **주입구(`GUARD_NO_GLOBSTAR`)를 잰다.** 실제 조건(bash 3.2)은 이 기계에서
    #     못 만든다 — **룬드 맥 실행이 그 축의 유일한 관측**이고, 그가 실측으로 이 결함을 냈다.
    #     ⚠️ 그래서 이 초록은 「맥에서 돈다」가 아니라 **「이 갈래가 배선돼 있다」**만 말한다.
    _o6="$(GUARD_ROOT="$_t2" GUARD_SELFTEST=0 GUARD_NO_GLOBSTAR=1 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc6=$?
    if [ "$_rc6" -eq 2 ] && printf '%s\n' "$_o6" | grep -q 'globstar'; then
        ok "[대조군] globstar 부재 → **rc=2 · 사유에 globstar** (거짓 빨강을 안 낸다)"
    else
        bad "[대조군] globstar 가 없을 때 «못 쟀다»가 아니라 빨강을 낸다" "rc=2 + 사유에 'globstar'" \
            "rc=${_rc6} — «$(printf '%s' "$_o6" | grep -E '❌|⛔' | tr '\n' ' ')»"
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
