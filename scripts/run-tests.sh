#!/usr/bin/env bash
# run-tests.sh — 이 레포의 **모든** 시험을 한 종료코드로 모은다 (양봇 공용 본체)
#
# 왜 생겼나 (2026-07-28, 룬드 M:jcic 와 합의):
#   `npm test`/`bun test` 가 그 레포의 시험을 **대표하지 않는다**. 두 방향으로 확인됐다:
#     · 룬드 쪽 — JS 시험이 0개인데 jest 가 기본 러너라 하위 별도 레포를 긁어 **상시 rc=1**.
#       아무도 그 종료코드를 안 읽어서 몇 달간 아무 일도 안 났다.
#     · 니노 쪽 — `npm test`(jest) 는 94개를 돌리는데 `tests/*.test.sh` **16개가 안 돈다**.
#       코어도 같다: CI 가 `bun test` 만 불러서 `tests/mutate.test.sh` 등이 한 번도 안 돌았다.
#   ⇒ 러너를 **하나** 두고, 무엇을 돌릴지는 **레포가 인자로** 준다(목록은 레포마다 다르다).
#
# 🔑 계약 — 세 상태를 접지 않는다:
#   0  전부 통과
#   1  하나 이상 실패
#   2  판정 불가 — 돌린 것이 0개이거나 도구가 없어 **못 쟀다**. 통과로도 실패로도 접지 않는다
#
# ⚠️ **초록불의 개수**를 찍는다. "빨간불이 없다" 는 건강 신호가 아니다 — 아무것도 안 돌아도
#    빨간불은 없다. 그래서 개수를 못 읽으면 그 사실(`건수 미상`)도 찍는다.
#
# 사용법:
#   scripts/run-tests.sh [--shell-glob <glob>]... [--cmd <명령>]... [--root <경로>]
#     --shell-glob   bash 로 돌릴 시험 파일 glob (반복 가능). 예: 'tests/*.test.sh'
#     --cmd          그대로 실행할 명령 (반복 가능). 예: 'bun test' · 'npx jest --runInBand'
#     --root         기준 디렉터리 (기본: 이 스크립트의 상위)
#
# 예시:
#   scripts/run-tests.sh --shell-glob 'tests/*.test.sh' --cmd 'bun test'
set -uo pipefail

ROOT=""
GLOBS=""     # 개행 구분 문자열 — bash 3.2 에서 빈 배열 확장이 set -u 와 부딪히므로 배열을 안 쓴다
CMDS=""

die_usage() { echo "⛔ 판정 불가 — $1"; echo "   사용법은 --help"; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --shell-glob) [ $# -ge 2 ] || die_usage "--shell-glob 뒤에 glob 이 없다"
                      GLOBS="$GLOBS$2
"; shift 2 ;;
        --cmd)        [ $# -ge 2 ] || die_usage "--cmd 뒤에 명령이 없다"
                      CMDS="$CMDS$2
"; shift 2 ;;
        --root)       [ $# -ge 2 ] || die_usage "--root 뒤에 경로가 없다"
                      ROOT="$2"; shift 2 ;;
        -h|--help)    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            die_usage "모르는 인자: $1" ;;
    esac
done

if [ -z "$ROOT" ]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$ROOT" || { echo "⛔ 판정 불가 — 루트로 못 갔다: $ROOT"; exit 2; }

if [ -z "$GLOBS" ] && [ -z "$CMDS" ]; then
    die_usage "돌릴 것을 하나도 안 줬다(--shell-glob / --cmd). 목록은 레포가 준다"
fi

pass=0; fail=0; unk=0
failed=""; unmeasured=""

# 개수 추출 — 🔴 **형식이 러너마다 다르고, 레포를 건너가면 한 겹 더 다르다.**
#   jest    "Tests: 94 passed, 94 total"     → `94 passed`
#   pytest  "61 passed in 0.4s"              → `61 passed`
#   룬드 셸  "pass=125 fail=0"                → `pass=125`
#   니노 셸  "  통과 23 · 실패 0"              → `통과 23`      ← 한글. 영어 패턴만 쓰면 조용히 빈칸
#   bun     "465 pass"                        → `465 pass`
# 한 형태만 보면 개수가 **조용히 빈칸**이 된다(2026-07-28 실측: 룬드 러너가 니노 시험 16개를
# 전부 `건수 미상` 으로 읽었다 — 형식 차이를 막으려고 만든 코드가 그 차이에 걸렸다).
extract_count() {
    printf '%s\n' "$1" \
        | grep -oE '(pass|passed)=?[0-9]+|[0-9]+ (pass|passed)|통과 ?[0-9]+' \
        | tail -1
}

run_one() {  # $1=표시이름 $2...=명령
    local name="$1"; shift
    local out rc n
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
        pass=$((pass + 1))
        n="$(extract_count "$out")"
        printf '  ✅ %-38s %s\n' "$name" "${n:-⚠️건수 미상}"
    elif [ "$rc" -eq 2 ]; then
        # 하위 시험도 세 상태 계약을 쓴다(양봇 규칙) — 그 2를 실패로 접으면 헛빨간불이 되고,
        # 통과로 접으면 못 쟀다가 초록이 된다. 그대로 올린다.
        unk=$((unk + 1)); unmeasured="$unmeasured $name"
        printf '  ⛔ %-38s rc=2 판정 불가\n' "$name"
        printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
    else
        fail=$((fail + 1)); failed="$failed $name"
        printf '  🔴 %-38s rc=%s\n' "$name" "$rc"
        printf '%s\n' "$out" | tail -8 | sed 's/^/       /'
    fi
}

if [ -n "$GLOBS" ]; then
    echo "== 셸 시험 =="
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        found=0
        for t in $g; do          # glob 확장 — 매치 없으면 패턴 그대로 오므로 -e 로 가른다
            [ -e "$t" ] || continue
            found=1
            run_one "$(basename "$t" .test.sh)" bash "$t"
        done
        [ "$found" -eq 1 ] || {
            unk=$((unk + 1)); unmeasured="$unmeasured $g(매치0)"
            echo "  ⛔ $g — 매치되는 파일이 0개다(경로·이름 규칙 확인)"
        }
    done <<EOF
$GLOBS
EOF
fi

if [ -n "$CMDS" ]; then
    echo
    echo "== 명령 =="
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        # 첫 토큰이 실행 가능한지 먼저 본다 — 없는 도구의 rc=127 을 "실패" 로 읽으면
        # "코드가 깨졌다" 로 오해한다. 없는 것은 **못 쟀다**(2).
        first="${c%% *}"
        if ! command -v "$first" >/dev/null 2>&1; then
            unk=$((unk + 1)); unmeasured="$unmeasured $first(부재)"
            echo "  ⛔ $c — '$first' 가 없다. 못 돌렸다(통과가 아니다)"
            continue
        fi
        run_one "$c" bash -c "$c"
    done <<EOF
$CMDS
EOF
fi

echo
echo "── 결과: 통과 $pass · 실패 $fail · 판정 불가 $unk"
[ -n "$failed" ]     && echo "   실패:$failed"
[ -n "$unmeasured" ] && echo "   판정 불가:$unmeasured"

# 🔴 **아무것도 안 돌았으면 통과가 아니다.** pass=0·fail=0 이면 아래 조건에 안 걸려 exit 0 으로
#    떨어지는데, 그건 이 러너가 없애려던 바로 그 상태(`npm test` 가 0개를 돌리고 초록이던 것)를
#    러너 자신이 새로 만드는 것이다. (2026-07-28 룬드 러너 리뷰에서 같은 자리를 찾았다)
if [ "$pass" -eq 0 ] && [ "$fail" -eq 0 ]; then
    echo "   🔴 시험이 **하나도 안 돌았다** — 대상을 못 찾았다"
    exit 2
fi
[ "$fail" -gt 0 ] && exit 1
[ "$unk" -gt 0 ] && exit 2
exit 0
