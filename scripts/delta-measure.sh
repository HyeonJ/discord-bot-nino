#!/usr/bin/env bash
# delta-measure.sh — base↔head 델타를 **«같은 온도»에서** 잰다
#
# 🔴 왜 있나 (2026-08-14, 룬드 `dazebug/assistant#75` 리뷰 재현):
#   자기지시 예외 조건 ③(「실패집합·판정 불가·platform 등재를 안 늘린다」)을 재현하려고
#   base·head 를 «각각 한 번씩» 돌렸더니 base 29/4/0 · head 32/1/0 이 나왔다.
#   그대로 비교했으면 **「실패 4 → 1, 이 PR 이 개선했다」**를 approve 본문에 적었을 것이다.
#   첫 회차가 `uv` 가상환경을 만드느라 셋이 같이 죽은 **순서 효과**였고, base 를 다시 돌리니 32/1/0.
#
#   ⚠️ **방향이 비대칭이다** — base 를 먼저 돌리는 «흔한 순서»가 head 를 좋아 보이게 한다
#      = **거짓 초록이라 조용하다.** 반대 순서는 시끄러워서 잡힌다.
#   🔑 잡아준 것은 도구가 아니라 *「문서 두 줄이 파이썬 시험을 고칠 리 없다」*는 **감각**이었다.
#      감각은 다음엔 안 걸린다 ⇒ 도구로 옮긴다.
#
# 🔑 왜 «계약 한 줄»이 아니라 도구인가: 같은 날 우리 둘이 **네 번** 밟은 병이
#    *「안 적었다」가 아니라 «적힌 것이 그 순간에 안 열린다»* 였다. 또 적으면 또 안 열린다.
#
# 🔸 이 도구가 «판정하지 않는 것»: 머지해도 되나 · 그 실패가 정당한가. 그건 리뷰와 원장이 한다.
#    여기서 내는 것은 **「이 diff 가 세 축을 늘렸나」** 하나뿐이다.
#    ⚠️ **그리고 「델타 0 인 회차의 흔들림」도 판정하지 않는다** — 델타가 0 이면 재측정을 «안 하므로»
#       「양쪽이 안정적으로 같다」와 「둘 다 우연히 같았다」를 못 가른다. 🔑 온도(⑦)는 «1회차가 더 나쁘다»는
#       단조 방향이 있어 수렴으로 닫히는데 **흔들림은 방향이 없어서** 유한 회차로는 못 닫는다.
#       ⇒ 못 막으니 **여기 적고 그 질문을 이 도구에 안 던진다**(룬드 `#218` 리뷰 ④).
#
# 사용법:
#   scripts/delta-measure.sh --base <ref> --head <ref> --cmd '<러너 명령>'
#     --base <ref>          좌변 ref (필수)
#     --head <ref>          우변 ref (필수)
#     --cmd '<명령>'        돌릴 러너 명령 (필수) — 무엇을 돌릴지 이 도구는 «유도하지 않는다»
#     --platform-base <N>   좌변의 platform 등재 수 (러너 «밖» 축이라 따로 받는다)
#     --platform-head <N>   우변의 platform 등재 수
#     --repo-dir <경로>     레포 경로 (기본: 현재 디렉터리)
#     --no-checkout         git checkout 을 «안» 한다 (시험·이미 체크아웃된 트리용)
#     -h, --help            이 도움말 (범위는 손이 아니라 «파일»이 정한다)
#
#   ⚠️ checkout 모드는 **깨끗한 트리**를 요구하고, 끝나거나 죽으면 **원래 ref 로 되돌린다**.
#      되돌리기가 예의가 아니라 안전인 이유: 크론·서비스가 작업트리 파일을 직접 가리키면
#      ref 를 옮기는 동안 **운영이 같이 옮겨 다닌다**(2026-08-14 실물).
#
# rc: 0 안 늘었다 · 1 늘었다 · 2 판정 불가(0 으로 안 접는다)
# 표지: 마지막 두 줄에 `DELTA_SCOPE=ref|no-checkout` 과 `DELTA_VERDICT=clean|real|warm-contaminated|flaky-head`
#   — 판정은 «산문»이 아니라 여기서 읽는다
#   🔑 `flaky-head` = head 두 회차가 «달랐다». 이 diff 의 효과와 흔들림을 못 가르므로 **판정하지 않는다**(rc=2).
#   🔴 **`DELTA_SCOPE` 가 «따로» 있는 이유 — `--no-checkout` 이면 base·head 가 «같은 트리»에서 돌아
#      델타가 «항상» 0 이다.** 그때의 `clean` 은 「안 늘었다」가 아니라 **「안 갈랐다」**인데,
#      한 필드에 접으면 그 둘이 구별되지 않는다(플래그 하나가 빨강을 초록으로 뒤집는데 표지가 침묵).
#      🔑 이건 이 파일 아래 *「요약 줄이 없으면 0 이 아니라 판정 불가다」*와 **같은 병**이고,
#         룬드가 `#218` 리뷰 ①에서 «심어서» 실증했다(ⓐ checkout=real rc=1 / ⓑ no-checkout=clean rc=0).
#      ⇒ 처방은 «막는 것»이 아니라 **말하게 하는 것**이다 — 한 필드는 한 축에만 답한다.
set -uo pipefail

BASE=""; HEAD_REF=""; CMD=""; REPO_DIR="."; NO_CHECKOUT=0
PLAT_BASE=""; PLAT_HEAD=""
die() { echo "⛔ 판정 불가 — $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base)          BASE="${2:-}"; shift 2 ;;
    --head)          HEAD_REF="${2:-}"; shift 2 ;;
    --cmd)           CMD="${2:-}"; shift 2 ;;
    --repo-dir)      REPO_DIR="${2:-}"; shift 2 ;;
    --platform-base) PLAT_BASE="${2:-}"; shift 2 ;;
    --platform-head) PLAT_HEAD="${2:-}"; shift 2 ;;
    --no-checkout)   NO_CHECKOUT=1; shift ;;
    -h|--help)
      # 🔑 범위를 «손»(sed 1,30p)으로 정하면 머리말이 자랄 때 조용히 잘린다 — 파일이 정하게 둔다.
      awk 'NR==1{next}
           /^#/{if(b){printf "%s",b;b=""} sub(/^# ?/,""); print; next}
           /^[[:space:]]*$/{b=b"\n"; next}
           {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "모르는 옵션: $1 (사용법은 --help)" ;;
  esac
done
[ -n "$BASE" ]     || die "--base 가 없다"
[ -n "$HEAD_REF" ] || die "--head 가 없다"
[ -n "$CMD" ]      || die "--cmd 가 없다 — 무엇을 돌릴지 이 도구는 «유도하지 않는다»"

# 🔴 «범위»는 판정과 다른 축이다 — 여기서 한 번 정하고 표지·산문 양쪽이 같은 값을 쓴다.
if [ "$NO_CHECKOUT" -eq 1 ]; then SCOPE=no-checkout; else SCOPE=ref; fi

# ── 🔴 체크아웃 안전 (첫 실사용에서 둘 다 밟았다, 2026-08-14 `#219` 델타 측정) ──────────
# ① **원래 ref 를 안 되돌렸다** — 성공해도 head 에 detached 로 남고, 중단되면 «중간 ref»에 남는다.
#    ⚠️ 실물이 특히 나빴다: 내 크론이 `scripts/check-auth.sh` 를 **작업트리에서 직접** 읽어서,
#      이 도구가 ref 를 옮기는 동안 **운영이 같이 옮겨 다닌다.** 되돌리기는 예의가 아니라 안전이다.
# ② **더러운 트리를 안 봤다** — 수정된 tracked 파일이 있으면 checkout 이 덮거나 거부한다.
# 🔑 시험이 이 축을 통째로 못 봤다 — 전부 `--no-checkout` 으로 돌아서 **checkout 경로가 미검사**였다.
if [ "$NO_CHECKOUT" -eq 0 ]; then
    ORIG_REF="$( cd "$REPO_DIR" && git symbolic-ref -q --short HEAD || git -C "$REPO_DIR" rev-parse HEAD )"
    [ -n "$ORIG_REF" ] || die "원래 ref 를 못 읽었다 — 되돌릴 자리를 모르면 체크아웃을 시작하지 않는다"
    DIRTY="$( cd "$REPO_DIR" && git status --porcelain --untracked-files=no )"
    [ -z "$DIRTY" ] || die "작업트리에 «커밋 안 된 수정»이 있다 — checkout 이 그걸 덮거나 거부한다.
   커밋하거나 stash 한 뒤에 다시 부른다. (미추적 파일은 세지 않는다)
$(printf '%s\n' "$DIRTY" | head -5 | sed 's/^/     /')"
    restore_ref() { ( cd "$REPO_DIR" && git checkout -q "$ORIG_REF" ) 2>/dev/null || true; }
    trap restore_ref EXIT INT TERM
fi

# ── 한 회차 ────────────────────────────────────────────────────────────────
# 🔴 좌변은 코어 러너의 «정본 형식»이다: `── 결과: 통과 N · 실패 N · 판정 불가 N` + `   실패: a b c`
#   ⚠️ 요약 줄이 없으면 **0 이 아니라 판정 불가**다. 「없다」와 「0」을 접으면 이 도구가
#     막으려는 바로 그 병(거짓 초록)을 자기가 저지른다.
RUN_OUT=""
measure() {  # $1=라벨 → 전역 M_FAIL·M_UNK·M_SET
  local out
  if [ "$NO_CHECKOUT" -eq 0 ]; then
    ( cd "$REPO_DIR" && git checkout -q "$2" ) || die "checkout 실패: $2"
  fi
  out="$( cd "$REPO_DIR" && eval "$CMD" 2>&1 )"
  RUN_OUT="$out"
  local sum
  sum="$(printf '%s\n' "$out" | grep -E '── 결과: 통과 [0-9]+ · 실패 [0-9]+ · 판정 불가 [0-9]+' | tail -1)"
  [ -n "$sum" ] || die "「$1」 회차에 러너 요약 줄이 «없다» — 못 잰 것이지 0 이 아니다"
  M_FAIL="$(printf '%s\n' "$sum" | sed -E 's/.*실패 ([0-9]+).*/\1/')"
  M_UNK="$(printf '%s\n'  "$sum" | sed -E 's/.*판정 불가 ([0-9]+).*/\1/')"
  # 실패«집합» — 수가 같아도 항목이 바뀌면 다른 것이다(「A 빠지고 B 유입」이 수로는 안 보인다)
  # 🔴 요약 줄은 `tail -1`(마지막 회차)인데 집합만 «전부» 긁으면 둘이 «다른 회차»를 가리킨다 —
  #   그리고 이 도구의 판정 좌변이 바로 그 집합이다. `--cmd` 가 자유 문자열이라 러너가 두 번
  #   도는 명령(`a && b`·하위 러너)이 가능하고, `tail -1` 을 쓴 것 자체가 그 가능성을 인정한 것이다.
  #   ⇒ 범위를 맞춘다(룬드 `#218` 리뷰 ③).
  M_SET="$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*실패:[[:space:]]*//p' | tail -1 \
           | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ')"
  M_SET="${M_SET% }"
}

say_axes() { printf '   %-10s 실패 %s [%s] · 판불 %s\n' "$1" "$M_FAIL" "${M_SET:-없음}" "$M_UNK"; }

# 🔴 판정은 «두 줄»로 낸다 — 범위(무엇을 갈랐나)와 판정(늘었나)은 «다른 축»이다.
#   한 필드에 접으면 `--no-checkout` 의 `clean`(=안 갈랐다)이 진짜 `clean`(=안 늘었다)과 구별되지 않는다.
say_verdict() {
  echo "DELTA_SCOPE=$SCOPE"
  echo "DELTA_VERDICT=$1"
}

echo "🔬 델타 측정 — base=$BASE · head=$HEAD_REF"
# 🔴 사람이 읽는 쪽에도 «범위»를 말한다 — 표지만 고치면 산문을 읽는 사람은 여전히 속는다.
if [ "$NO_CHECKOUT" -eq 1 ]; then
  echo "   ⚠️ **범위 = no-checkout** — base·head 를 «같은 트리»에서 잰다. 이 모드의 「델타 0」은"
  echo "      「안 늘었다」가 «아니라» **「안 갈랐다」**다. ref 델타가 필요하면 이 플래그를 뺀다."
fi

measure "base(1회차)" "$BASE";     B1_F="$M_FAIL"; B1_U="$M_UNK"; B1_S="$M_SET"
M_FAIL="$B1_F" M_UNK="$B1_U" M_SET="$B1_S"; say_axes "base①"
measure "head" "$HEAD_REF";        H_F="$M_FAIL";  H_U="$M_UNK";  H_S="$M_SET"
M_FAIL="$H_F"  M_UNK="$H_U"  M_SET="$H_S";  say_axes "head "

# ── 온도 검사 ──────────────────────────────────────────────────────────────
# 🔑 델타가 «있어 보일 때만» base 를 다시 돌린다. 러너는 분 단위라 항상 3회는 비싸고,
#   델타 0 이면 오염이 있어도 결론이 안 바뀐다(양쪽이 같은 온도로 수렴한 것).
BL_F="$B1_F"; BL_U="$B1_U"; BL_S="$B1_S"; WARMED=0; CONTAMINATED=0; FLAKY_HEAD=0
if [ "$H_F" != "$B1_F" ] || [ "$H_U" != "$B1_U" ] || [ "$H_S" != "$B1_S" ]; then
    measure "base(2회차)" "$BASE";  B2_F="$M_FAIL"; B2_U="$M_UNK"; B2_S="$M_SET"
    M_FAIL="$B2_F" M_UNK="$B2_U" M_SET="$B2_S"; say_axes "base②"
    WARMED=1
    if [ "$B2_F" != "$B1_F" ] || [ "$B2_U" != "$B1_U" ] || [ "$B2_S" != "$B1_S" ]; then
        CONTAMINATED=1
        echo "🔴 **온도 오염** — 같은 ref 인데 base 두 회차가 «다르다»."
        echo "   1회차가 설치·캐시 비용을 냈다(uv 가상환경 · npm ci · 빌드 캐시 따위)."
        echo "   ⇒ **2회차를 좌변으로** 삼는다. 1회차와 비교했으면 이 diff 가 «개선»으로 읽혔다."
    fi
    BL_F="$B2_F"; BL_U="$B2_U"; BL_S="$B2_S"

    # 🔴 **head 도 두 번 잰다** — 첫 실사용에서 이 구멍을 밟았다(2026-08-14, `#219` 델타):
    #   head 가 «한 회차»에만 `mdweb-link-guard` 로 빨갰고 base 두 회차는 깨끗해서
    #   이 도구가 `DELTA_VERDICT=real` 을 냈다. head 를 두 번 더 재니 **둘 다 깨끗**했다
    #   — 원격 의존(live md-web)이 그 회차에만 흔들린 것이다.
    # 🔑 옛 판은 «base 가 차가웠나»만 물었다. 그건 대칭이 아니다 — **head 가 운이 나빴나**도
    #   같은 값으로 물어야 한다. 한쪽만 두 번 재면 나머지 한쪽의 흔들림이 «진짜»로 승격된다.
    # 🔴 갈리면 «real 도 clean 도 아니다 — 못 쟀다»(rc=2). 어느 쪽으로 접어도 거짓이 된다.
    measure "head(2회차)" "$HEAD_REF"; H2_F="$M_FAIL"; H2_U="$M_UNK"; H2_S="$M_SET"
    M_FAIL="$H2_F" M_UNK="$H2_U" M_SET="$H2_S"; say_axes "head②"
    if [ "$H2_F" != "$H_F" ] || [ "$H2_U" != "$H_U" ] || [ "$H2_S" != "$H_S" ]; then
        FLAKY_HEAD=1
        echo "🔴 **head 가 회차마다 다르다** — 이 diff 의 효과와 «흔들림»을 못 가른다."
        echo "   1회차 실패 [$H_S] · 2회차 실패 [$H2_S]"
        echo "   ⇒ 판정하지 않는다. 흔들리는 시험을 먼저 고정하거나, 그 항목을 빼고 다시 잰다."
    fi
fi

# ── 판정 ───────────────────────────────────────────────────────────────────
# 🔴 조건은 「안 «늘린다»」다 — 줄어드는 것은 막지 않는다(정직한 수리를 막으면 동결이 잠긴다).
RC=0; WHY=""
if [ "$H_S" != "$BL_S" ]; then
    ADDED="$(comm -13 <(printf '%s\n' $BL_S | LC_ALL=C sort -u) \
                      <(printf '%s\n' $H_S  | LC_ALL=C sort -u) | tr '\n' ' ')"
    ADDED="${ADDED% }"
    if [ -n "$ADDED" ]; then RC=1; WHY="${WHY}실패집합에 «새로» 들어온 것: ${ADDED}
"; fi
fi
[ "$H_U" -gt "$BL_U" ] && { RC=1; WHY="${WHY}판정 불가 ${BL_U} → ${H_U} (늘었다 — 「실패를 판불로 밀기」가 여기서 막힌다)
"; }
if [ -n "$PLAT_BASE" ] && [ -n "$PLAT_HEAD" ] && [ "$PLAT_HEAD" -gt "$PLAT_BASE" ]; then
    RC=1
    WHY="${WHY}platform 등재 ${PLAT_BASE} → ${PLAT_HEAD} (늘었다 — 이 축은 «영구·한 방향»이라 되돌아올 경로가 없다)
"
fi

echo
# 🔴 head 가 흔들리면 «판정을 안 한다» — ✅/❌ 어느 쪽으로 적어도 거짓이다.
#   이 가지를 안 두면 아래 ❌ 문구가 흔들림을 «회귀»라고 이름 붙인다(실물이 그랬다).
if [ "$FLAKY_HEAD" -eq 1 ]; then
    echo "⛔ **판정 불가** — head 두 회차가 달라 이 diff 의 효과를 못 가른다"
    echo "   차이가 난 항목만 따로 여러 번 돌려 «흔들리는지»부터 본다."
    say_verdict flaky-head
    exit 2
fi
if [ "$RC" -eq 0 ]; then
    echo "✅ **델타 0** — 실패집합·판정 불가·platform 등재 셋 다 안 늘었다"
    [ "$WARMED" -eq 1 ] && echo "   🔸 좌변은 base «2회차» 값이다(온도를 맞췄다)"
else
    echo "❌ **델타 있음** — 아래 축이 늘었다"
    printf '%s' "$WHY" | sed 's/^/   · /'
    [ "$WARMED" -eq 1 ] && echo "   🔸 base 두 회차가 «같았다» ⇒ 온도 오염이 아니라 «진짜» 변화다"
fi

# 🔴 **판정은 «산문»이 아니라 표지로 낸다.** 시험이 산문을 grep 하면 «부정된 자리»에 걸린다 —
#   실물 2026-08-14: 이 파일 첫 판이 *「온도 오염«이 아니라» 진짜 변화다」*를 찍었는데
#   시험의 `grep -q '온도 오염'` 이 **그 부정문에 걸려** 「오염으로 접었다」고 빨개졌다.
#   같은 회차에 *「«개선»으로 읽혔다」*라는 설명문도 `grep -q '개선'` 에 걸렸다.
#   🔑 둘 다 **도구가 옳고 시험의 좌변이 틀린** 경우다 — 산문은 «설명»을 담으므로 반대말이 섞인다.
#   ⇒ 기계가 읽는 자리를 따로 만든다. 사람용 산문은 위에 그대로 둔다(하나가 둘을 겸하면 또 샌다).
if   [ "$CONTAMINATED" -eq 1 ]; then say_verdict warm-contaminated
elif [ "$RC" -eq 0 ];            then say_verdict clean
else                                  say_verdict real
fi
exit "$RC"
