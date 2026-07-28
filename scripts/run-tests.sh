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
#     --unmeasured-state <파일>
#                    판정 불가 **이름 집합**을 남겨 직전과 비교한다(env `UNMEASURED_STATE` 도 됨).
#                    새로 깨진 것 🔴 · 고쳐진 것 ✅ · 오래된 것 ⏳N일째 를 찍는다.
#                    안 주면 추세를 안 잰다 — CI 는 매번 새 컨테이너라 직전 값이 없다.
#                    ⚠️ rc 는 안 바뀐다. 못 잰 건 새것이든 오래된 것이든 rc=2 다.
#
# 예시:
#   scripts/run-tests.sh --shell-glob 'tests/*.test.sh' --cmd 'bun test'
#   scripts/run-tests.sh --cmd 'bun test' --unmeasured-state state/unmeasured.tsv
set -uo pipefail

ROOT=""
# 판정 불가 이름 집합을 남길 파일. 안 주면 추세를 안 잰다(CI 는 매번 새 컨테이너라 직전 값이 없다).
UNMEASURED_STATE="${UNMEASURED_STATE:-}"
GLOBS=""     # 개행 구분 문자열 — bash 3.2 에서 빈 배열 확장이 set -u 와 부딪히므로 배열을 안 쓴다
CMDS=""
# 실패 시 보여줄 표식 줄 수. 넘치면 **몇 줄 잘랐는지 반드시 찍는다**(조용한 절단 금지).
# ⚠️ env 로 여는 건 설정 기능이 아니라 **검증 가능성** 때문이다 — 값이 6 으로 고정이면
#    안내의 `%s` 를 6 으로 하드코딩하는 변이가 **등가라서 안 잡힌다**(실측: 변이 H 살아남음).
#    한도가 바뀌는 순간 그 하드코딩은 거짓말이 되는데, 그때는 아무도 안 보고 있다.
MARK_LINES="${MARK_LINES:-6}"

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
        --unmeasured-state)
                      [ $# -ge 2 ] || die_usage "--unmeasured-state 뒤에 경로가 없다"
                      UNMEASURED_STATE="$2"; shift 2 ;;
        -h|--help)    sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
failed=""
# 🔴 판정 불가 이름은 **개행 구분**이다(공백 구분이 아니라). 이름에 공백이 들어가기 때문이고,
#    이름은 **명령 전체**여야 한다 — 첫 단어만 쓰면 `zzq alpha` 와 `zzq beta` 가 같은 키가 되어
#    **교체를 못 본다**(니노 N3). 개수 대신 이름을 보려는 이 기능의 전제가 *이름이 구별된다* 이므로
#    키가 뭉개지면 같은 구멍이 한 층 아래로 내려올 뿐이다.
unmeasured=""
# ⚠️ 이름에서 **탭·개행을 없앤다**(니노 P1). 이 목록은 개행 구분이고 상태 파일은 TSV 라,
#    이름에 그 두 글자가 들어가면 구조가 깨진다 — `awk -F'\t' '$2==n'` 이 잘린 조각과
#    비교해 **영영 안 맞고, 매 실행 "새로 깨졌다" 오탐 + 나이가 절대 안 자란다**(N1 과 같은 모양).
#    ⇒ 키로 쓸 값은 **구분자를 포함할 수 없게** 만든다. 검사보다 정규화가 싸다.
add_unmeasured() {
    unk=$((unk + 1))
    unmeasured="$unmeasured$(printf '%s' "$1" | tr '\t\n' '  ')
"
}

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
    local out rc n marks
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
        pass=$((pass + 1))
        n="$(extract_count "$out")"
        printf '  ✅ %-38s %s\n' "$name" "${n:-⚠️건수 미상}"
    elif [ "$rc" -eq 2 ]; then
        # 하위 시험도 세 상태 계약을 쓴다(양봇 규칙) — 그 2를 실패로 접으면 헛빨간불이 되고,
        # 통과로 접으면 못 쟀다가 초록이 된다. 그대로 올린다.
        add_unmeasured "$name"
        printf '  ⛔ %-38s rc=2 판정 불가\n' "$name"
        printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
    else
        fail=$((fail + 1)); failed="$failed $name"
        printf '  🔴 %-38s rc=%s\n' "$name" "$rc"
        # 🔴 실패는 **꼬리가 아니라 표식 줄**을 먼저 보여준다(2026-07-28 니노 CI 실사고).
        #    `tail -8` 만 찍으면 마지막 8줄이 ⛔·요약으로 채워질 때 ❌ 줄이 **잘린다** —
        #    실제로 CI 에서 `backup-to-nas 3 fail` 이 떴는데 **무엇이 실패했는지 로그에 없었다.**
        #    "빨간불은 보이는데 왜인지는 안 보이는" 상태고, 그건 빨간불이 없는 것과 크게 다르지 않다.
        #    ⚠️ 이 규칙은 `.claude/rules/shell-scripts.md`(룬드) 에 *성공이면 꼬리, 실패면 머리* 로
        #       이미 적혀 있었다 — 적어두고 러너에선 안 지킨 자리다.
        #    ⚠️ 표식을 **못 찾은 경우를 빈칸으로 두지 않는다**(니노 사전 지적): 시험마다 표식이
        #       다르므로 이 grep 은 언제든 0건이 될 수 있고, 그때 꼬리까지 짧게 주면 **정보가
        #       전보다 줄어든다**(8줄 → 3줄). 못 찾았다고 말하고 **꼬리를 더 길게** 준다.
        #    ⚠️ 그리고 **자를 거면 잘랐다고 말한다**(2026-07-28 후속): 실패 3건이면 시험이
        #       `❌` + `want:` + `got:` 로 **건당 3줄**을 내므로 9줄이 되고, `head -6` 이
        #       **셋째 실패를 통째로 지운다.** 위에서 막으려던 *"빨간불은 보이는데 왜인지는
        #       안 보인다"* 가 **한 겹 위에서 그대로 재발**한다 — 게다가 이번엔 6줄이 보이니까
        #       **다 보여준 것처럼 읽힌다**(잘림은 흔적을 안 남긴다). 개수를 세서 알린다.
        marks_all="$(printf '%s\n' "$out" | grep -nE '❌|✗|FAIL|want:|got:|[Ee]rror|assert')"
        n_marks="$(printf '%s\n' "$marks_all" | grep -c .)"
        if [ "$n_marks" -gt 0 ]; then
            printf '%s\n' "$marks_all" | head -"$MARK_LINES" | sed 's/^/       /'
            if [ "$n_marks" -gt "$MARK_LINES" ]; then
                printf '       ⚠️ 표식 줄 %s개 중 %s개만 보인다 — **%s줄 잘랐다**(전부 보려면 이 시험을 로컬에서 직접 돌린다)\n' \
                    "$n_marks" "$MARK_LINES" "$((n_marks - MARK_LINES))"
            fi
            printf '%s\n' "$out" | tail -3 | sed 's/^/       … /'
        else
            printf '       (실패 표식 줄을 못 찾았다 — 꼬리 12줄)\n'
            printf '%s\n' "$out" | tail -12 | sed 's/^/       /'
        fi
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
            add_unmeasured "$g(매치0)"
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
            add_unmeasured "$c(부재: $first)"
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
if [ -n "$unmeasured" ]; then
    echo "   판정 불가:"
    printf '%s' "$unmeasured" | sed 's/^/     · /'
fi

# 🔴 **판정 불가는 정직해서 안 아프다** (2026-07-28, 니노 `#53` 에서 나온 것).
#    rc=2 는 *조용한 실패* 를 없앴지만 **그 자리가 고쳐지게 만들지는 않는다** — 니노 cron 의
#    `node: command not found` 는 매 실행 정직하게 "판정 불가" 를 찍으면서 방치돼 있었다.
#    ⇒ 세 상태 계약의 2단계는 **판정 불가를 줄이는 것**이고, 줄고 있는지는 누가 봐야 한다.
#
# 🔑 **개수가 아니라 이름 집합을 비교한다.** `3 → 3` 은 "그대로" 로 보이지만 안에서
#    `{A,B,C} → {A,B,D}` 로 갈렸을 수 있다 — C 는 고쳐졌고 **D 가 새로 깨진 것**이다.
#    지표가 유지되는데 안에서 갈리는 건 오늘 여러 번 본 형태다(고침이 시험의 겨냥을 옮긴 그것).
#
# ⚠️ 그리고 *"그대로면 노랑"* 은 안 쓴다 — 환경 부재는 잘 안 변해서 **노랑이 상시가 되고,
#    상시 경고는 안 보인다.** 하트비트가 *조용한 게 정상이라 안 보인다* 였다면 이건
#    *시끄러운 게 정상이라 안 보인다* 로, 같은 병의 반대편이다. 대신 **나이**를 붙인다 —
#    시간이 갈수록 더 아프게. 고치는 힘은 정확한 보고가 아니라 아픔에서 나온다.
#
# 🔸 rc 는 바꾸지 않는다. 새로 깨졌든 오래됐든 **못 잰 것은 못 잰 것**이라 rc=2 그대로다.
#    여기서 rc=1 로 올리면 "실패"가 되어 이 러너가 지키는 세 상태 계약이 무너진다.
if [ -n "$UNMEASURED_STATE" ]; then
    # ⚠️ bash 문자열의 `\t` 는 **리터럴 두 글자**라 탭이 아니다. 변수에 담아 쓴다
    #    (실측: 이걸 놓쳐 상태 파일이 `1785239444\tzzq…` 로 저장됐고, awk -F'\t' 파싱이
    #     전부 빗나가 **새로 깨진 것도 고쳐진 것도 못 봤다** — 출력은 그럴듯했다).
    TAB="$(printf '\t')"
    now_epoch="$(date +%s 2>/dev/null)" || now_epoch=""
    if [ -z "$now_epoch" ]; then
        echo "   ⛔ 판정 불가 추세를 못 쟀다 — 현재 시각을 못 읽었다"
    else
        # ⚠️ 상위 디렉터리가 없으면 쓰기가 매번 실패해 **"첫 기록"이 영원히 반복**된다(니노 N2).
        #    `state/` 는 gitignore 자리라 **새 기계 첫 실행이 정확히 이 경로**다. 그리고 "첫 기록"은
        #    *잘 돌고 있다* 는 긍정 신호라 ⛔ 와 나란히 나오면 서로 상쇄돼 눈에 안 띈다.
        #    ⇒ 디렉터리를 만들고, **쓰기에 성공한 뒤에만** "첫 기록"을 말한다.
        mkdir -p "$(dirname "$UNMEASURED_STATE")" 2>/dev/null
        had_state=0; [ -f "$UNMEASURED_STATE" ] && had_state=1
        prev=""
        [ "$had_state" -eq 1 ] && prev="$(cat "$UNMEASURED_STATE" 2>/dev/null)"

        # 🔑 **어디서 쟀는지**를 같이 남긴다 (니노 발견 2026-07-28).
        #    같은 코드인데 실행 위치가 다르면 판정 불가 **이름 집합이 갈린다** — 실측:
        #      워크트리   판정 불가 1 (start-md-web: 유닛의 ExecStart 가 이 경로를 안 가리킨다)
        #      main       판정 불가 0
        #    ⇒ 위치를 오가면 `🔴 새로` 와 `✅ 벗어남` 이 번갈아 뜬다. **아무것도 안 변했는데.**
        #      이 기능은 *지표는 유지되는데 안에서 갈린다* 를 잡으려고 만들었는데, 그 거울상을
        #      같이 만든 셈이다.
        #    🔸 **비교를 건너뛰지는 않는다** — 언제 건너뛰는 게 맞는지 잴 데이터가 아직 없다.
        #      *말하기만* 한다. 실제로 섞이는 사례가 나오면 그때 붙인다(쓰는 데 없는 배선은 낡는다).
        #    🔸 그리고 이 값은 오탐 방지보다 **진단**에 더 쓰인다 — 나중에 "이 숫자가 어디서
        #      나온 거지" 를 물을 때, 안 적어두면 그때 못 답한다.
        ROOT_KEY="#root"
        prev_root="$(printf '%s\n' "$prev" | awk -F'\t' -v k="$ROOT_KEY" '$1==k {print $2; exit}')"
        if [ -n "$prev_root" ] && [ "$prev_root" != "$ROOT" ]; then
            echo "   ℹ️ 실행 위치가 바뀌었다($prev_root → $ROOT) — 이름 집합이 위치 따라 갈릴 수 있다"
        fi
        next="$ROOT_KEY$TAB$ROOT
"
        while IFS= read -r u; do
            [ -n "$u" ] || continue
            # 🔸 여기선 헤더를 따로 안 거른다. 이름이 root 경로와 똑같아 헤더가 매치돼도
            #    `$1` 이 `#root` 라 아래 `case` 의 *비숫자* 갈래로 떨어져 같은 결과가 된다
            #    (실측: 거르는 판/안 거르는 판의 출력이 **완전히 동일**). 거르는 줄을 넣었다가
            #    **어떤 변이로도 안 갈려서** 뺐다 — 시험으로 구별 안 되는 방어는 낡기만 한다.
            #    아래 ✅ 루프는 다르다. 거기선 헤더가 곧바로 *이름*으로 읽혀 ⑩-d 가 잡는다.
            first="$(printf '%s\n' "$prev" | awk -F'\t' -v n="$u" '$2==n {print $1; exit}')"
            case "$first" in
                ''|*[!0-9]*)
                    [ "$had_state" -eq 1 ] && echo "   🔴 새로 못 재게 됐다: $u"
                    first="$now_epoch" ;;
                *)
                    # 🔴 **미래 시각은 신선한 게 아니라 시계가 어긋난 것**이다(니노 N1).
                    #    음수 나이는 `-ge 1` 이 거짓이라 조용하고, 그 미래 값을 **그대로 다시 쓰므로**
                    #    한 번의 어긋남이 나이를 그만큼 0으로 고정한다 — 그 사이 방치돼도 안 아프다.
                    #    ⚠️ 이건 내가 `heartbeat-status.sh` 리뷰에서 니노에게 지적한 것과 **같은
                    #       클래스인데 내 코드에선 반대로 판정**하고 있던 자리다.
                    if [ "$first" -gt "$now_epoch" ]; then
                        echo "   ⚠️ $u — 기록 시각이 미래다(시계 어긋남). 나이를 지금부터 다시 센다"
                        first="$now_epoch"
                    else
                        age_d=$(( (now_epoch - first) / 86400 ))
                        [ "$age_d" -ge 1 ] && echo "   ⏳ $u — **${age_d}일째** 판정 불가"
                    fi ;;
            esac
            next="$next$first$TAB$u
"
        done <<UNMEOF
$unmeasured
UNMEOF
        # ✅ 사라진 이름은 **고쳐진 것**이다. 이것도 말해야 줄고 있다는 게 보인다.
        if [ -n "$prev" ]; then
            while IFS= read -r pl; do
                case "$pl" in "$ROOT_KEY$TAB"*) continue ;; esac   # 헤더는 이름이 아니다
                pn="${pl#*	}"
                [ -n "$pn" ] && [ "$pn" != "$pl" ] || continue
                printf '%s' "$unmeasured" | grep -qxF "$pn" || echo "   ✅ 판정 불가에서 벗어났다: $pn"
            done <<PREVEOF
$prev
PREVEOF
        fi
        if printf '%s' "$next" > "$UNMEASURED_STATE" 2>/dev/null; then
            [ "$had_state" -eq 0 ] && [ -n "$unmeasured" ] \
                && echo "   ℹ️ 판정 불가 추세: **첫 기록** — 다음 실행부터 새로 생긴 것과 방치된 것을 가른다"
        else
            echo "   ⛔ 판정 불가 추세를 못 남겼다: $UNMEASURED_STATE"
        fi
    fi
fi

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
