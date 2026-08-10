#!/usr/bin/env bash
# portability.test.sh — **모든 시험 파일**이 GNU/BSD 공용인지 한 자리에서 잰다.
#
# 🔴 왜 파일 하나로 모았나 (2026-07-31):
#   같은 가드를 `nino-watchdog.test.sh` **안에** 두고 있었다. 그러면 새 시험 파일은
#   **가드를 그냥 안 쓰는 것으로 통과**한다 — 그리고 안 쓰는 것은 조용하다.
#   실제로 그 형태로 샜다: `scripts/lib/timeshift.sh` 머리말에 *"사본 금지, 정본은 이 파일 하나"*
#   가 적혀 있는데도 `nino-watchdog.test.sh` 가 source 를 안 해 룬드 맥에서 4 fail 이 났다.
#   🔑 **안 쓰는 것이 조용한 한, 정본은 권고일 뿐이다.** 여기서 시끄럽게 만든다.
#
# 🔸 범위 — **세 층**이다(2026-08-05 개정, `#149`):
#   ① `tests/*.sh`                  — 판정
#   ② 그 시험들이 **호출하는** `scripts/*.sh` — 판정(면제 원장에 적힌 것만 제외)
#   ③ 나머지 `scripts/*.sh`         — 세어서 **보고만**
#   🔴 ②는 원래 없었고 그게 이 시험의 결함이었다. 지키려는 명제는 *"룬드 맥에서 `tests/` 가
#     통과한다"* 인데 ①만 보면 **시험 파일은 깨끗한데 호출된 스크립트가 죽는** 경로가 열린다.
#     실물: `scripts/darren-sleep.sh` 가 GNU `date -d` 로 죽어 맥 6 fail — **이 시험은 초록이었다.**
#   🔑 **판정 분모는 「무엇을 보나」가 아니라 「무슨 명제를 지키나」로 정한다.**
#   ⚠️ ③은 조용히 좁힌 게 아니라 **적어두고** 좁혔다. 아래에서 세어 보고한다.
#
# 🔴 숫자를 여기 적지 않는다 (2026-07-31). 전엔 *"세 곳(`vault-audit.sh:76,82` …)"* 이라고
#   박아뒀는데 **두 번 낡았다**: ① `#94` 가 명령 축(`sed -i`·`grep -P`)을 추가해 늘었고,
#   ② 같은 명령이 **체크아웃마다 다른 수를 낸다** — 워크트리엔 추적 안 되는 스크립트가 없어서
#      main 체크아웃 8곳이 워크트리에선 5곳으로 보인다.
#   🔑 세는 자리는 하나(아래 시험)여야 한다. 주석에 사본을 두면 **부분 정정**이 남는다.
#   🔸 부수 관측: `vault-ingest.sh`·`wiki-register-memory.sh` 는 **git 에 없다**(untracked).
#      추적 밖이라 리뷰도 이 시험도 영원히 안 닿는다 — 별건으로 남긴다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/portability-guard.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "🔴 이식성 — 모든 시험 파일이 상대 봇(macOS·BSD) 기계에서 돌아야 한다:"
VIOL="$(portability_scan "$REPO"/tests/*.sh)"
if [ -z "$VIOL" ]; then
    ok "tests/ 에 정본 밖 GNU/BSD 전용 시각 도구가 없다"
else
    bad "이식성 위반" "<없음>" "$(printf '%s' "$VIOL" | sed 's|'"$REPO"/'||')"
fi

# 🧪 [양성 대조군] 검사기가 **일을 하는가** — 없으면 위 초록은 "규칙이 없다"와 구별이 안 된다.
#   네 형태를 다 심는다. 하나만 심으면 나머지 규칙이 죽어도 초록이다.
cat > "$WORK/probe.sh" <<'PROBE'
#!/bin/bash
touch -d '@100' "$f"
stat -c %Y "$f"
date -u -d '@1' +%s
X=$(stat -f %m "$f")
PROBE
PROBE_OUT="$(portability_scan "$WORK/probe.sh")"
PROBE_N="$(printf '%s' "$PROBE_OUT" | grep -c . || true)"
[ "${PROBE_N:-0}" -eq 4 ] \
  && ok "🧪 [양성 대조군] 심어둔 네 형태를 전부 잡는다 (touch -d · stat -c · date -d · stat -f)" \
  || bad "🧪 [양성 대조군] 검출 개수" "4건" "${PROBE_N:-0}건 — $PROBE_OUT"

# 🔴 **bash 3.2 축 양성 대조군** (2026-08-10 이사와 함께 신설).
#   이 넷은 원래 다른 파일에 «분모 1~2개»로 살았다. 옮겨오면서 **대조군도 같이 세운다** —
#   안 세우면 「위반 0건」이 「없다」인지 「판별식이 눈이 멀었다」인지 안 갈린다.
#   🔑 픽스처를 «리터럴로 안 적는다»: 이 파일은 CANON 이라 스캔에서 빠지지만,
#      그 면제에 기대면 면제가 사라지는 날 조용히 자기를 세기 시작한다.
cat > "$WORK/b32.sh" <<'B32'
set -u
mapfile -t arr < <(printf 'a\n')
declare -A m
echo "${name^^}"
for x in "${arr[@]}"; do echo "$x"; done
echo "${arr[@]+"${arr[@]}"}"
B32
B32_OUT="$(portability_scan "$WORK/b32.sh")"
B32_N="$(printf '%s' "$B32_OUT" | grep -c . || true)"
# 3건: mapfile · declare -A · ${name^^}  (+ 맨 ${arr[@]} 1건 = 4건)
# 🔸 `$VAR»` 축은 여기 없다 — `tests/lib/nonascii-scan.py` 가 레포 전수로 소유한다.
# 🔑 안전형 `${arr[@]+…}` 과 중괄호 `${ok}»` 는 **안 잡혀야** 한다 — 그 둘이 처방이다.
[ "${B32_N:-0}" -eq 4 ] \
  && ok "🧪 [양성 대조군] bash 3.2/4 축 넷만 잡는다 (안전형은 안 잡는다)" \
  || bad "bash 3.2 축 검출" "정확히 4건" "${B32_N:-0}건 — $B32_OUT"
case "$B32_OUT" in
  *'[@]+'*)  bad "안전형 \${a[@]+\"\${a[@]}\"} 를 잡는다 (오탐) — 올바른 형태를 벌하면 다음 사람이 되돌린다" "0건" "$B32_OUT" ;;
  *)         ok "  → 안전형 배열 확장은 «안» 잡는다 = 처방을 벌하지 않는다" ;;
esac
# 🔴 출력 형식 축 — **같은 명령인데 출력 모양이 갈리는 자리**
#   BSD `wc -l` 은 우측정렬로 패딩한다(GNU `[2]` vs BSD `[       2]`).
#   ⇒ 문자열 비교는 맥에서 **항상 거짓**. 산술 비교(`-eq`)는 앞공백을 무시하니 안전하다.
#   🔸 룬드가 자기 맥에서 발견(`check-auth` 4 fail)하고, 내가 패딩 흉내로 재현했다.
cat > "$WORK/wc.sh" <<'WCP'
[ "$(wc -l < "$F")" = 1 ] && echo ok
[ "$(wc -l < "$F")" -eq 1 ] && echo ok
[[ "$(wc -l < "$F")" != 2 ]] && echo ok
n=$(wc -l < "$F"); [ "$n" = 1 ] && echo ok
WCP
WC_OUT="$(portability_scan "$WORK/wc.sh")"
WC_N="$(printf '%s' "$WC_OUT" | grep -c . || true)"
# 🔑 개수를 단언한다 — "하나라도 잡혔다" 로는 **`-eq` 를 오탐하는지** 못 가른다.
[ "${WC_N:-0}" -eq 2 ] \
  && ok "🧪 [양성 대조군] wc -l 문자열 비교 2건만 잡는다 (-eq 는 안 잡는다)" \
  || bad "wc 축 검출" "정확히 2건" "${WC_N:-0}건 — $WC_OUT"
# 🔸 4행(변수 경유)은 **일부러 안 잡는다** — 자료흐름은 이 도구 몫이 아니다.
#   그 한계를 여기 단언으로 박아, 나중에 잡히게 되면 **한계 문서가 낡았다**는 신호가 되게 한다.
case "$WC_OUT" in
    *":4 "*) bad "한계 문서" "4행은 안 잡힌다고 적혀 있다" "잡혔다 — 헤더의 '못 보는 것' 문단을 고쳐야 한다" ;;
    *) ok "  → 변수 경유(4행)는 안 잡는다 = 헤더에 적어둔 한계와 일치한다" ;;
esac

# 🔴 명령 축 — **양쪽이 서로 반대**라 한쪽에 맞추면 다른 쪽이 깨지는 자리
#   ① `sed -i`  BSD 는 `sed -i '' …`, GNU 는 `sed -i …`. **정반대다**(룬드 맥 실측).
#   ③ `grep -P` BSD 에 없다 — `grep: invalid option -- P`.
#   🔑 룬드가 ③에서 하마터면 틀릴 뻔했다: 대화형 셸에선 `ugrep` 이 가려서 **되는 것처럼 보였고**,
#     `bash -c` 로 껍데기를 벗기고서야 갈렸다. ⇒ *부재 증명은 `bash -c` 로 한다*(새벽 규칙)의 실전.
#   ⚠️ ② `sort` 로케일은 **일부러 뺐다** — 갈리긴 하는데 BSD/GNU 축이 아니라 **로케일 축**이라
#     양쪽 다 로케일 따라 갈린다. 결정성 가드는 다른 물건이다(룬드 측정·동의).
cat > "$WORK/cmd.sh" <<'CMDP'
#!/bin/bash
sed -i 's/a/X/' "$f"
sed -i '' 's/a/X/' "$f"
grep -P 'a\w+' "$f"
while read -r x; do :; done < <(grep -oP '\[\[\K[^]]+' "$f")
CLAUDE_PID=$(pgrep -P "$PANE_PID" -f "claude" | head -1)
sed -e 's/a/X/' "$f" > "$t" && mv "$t" "$f"
CMDP
CMD_OUT="$(portability_scan "$WORK/cmd.sh")"
CMD_N="$(printf '%s' "$CMD_OUT" | grep -c . || true)"
[ "${CMD_N:-0}" -eq 4 ] \
  && ok "🧪 [양성 대조군] sed -i 2건 · grep -P 2건만 잡는다" \
  || bad "명령 축 검출" "정확히 4건" "${CMD_N:-0}건 — $CMD_OUT"
# 🔑 **이 두 줄이 이 절의 본론이다.** 규칙을 넣기 전에 이미 오탐 후보가 레포에 있었다 —
#   `nino-watchdog.sh:95` 의 `pgrep -P`(부모 PID). 이름이 `grep` 으로 끝나서 순진한 패턴에 걸린다.
#   룬드: *"미탐은 다음 사례가 알려주지만 오탐은 가드 자체를 죽인다."*
case "$CMD_OUT" in
    *":6 "*) bad "오탐" "pgrep -P 는 grep 이 아니다" "잡혔다 — 명령 경계가 무너졌다" ;;
    *) ok "  🔑 pgrep -P 를 grep -P 로 오인하지 않는다 (실재하는 오탐 후보)" ;;
esac
case "$CMD_OUT" in
    *":7 "*) bad "오탐" "-i 없는 sed 는 위반이 아니다" "잡혔다" ;;
    *) ok "  → 임시파일+mv(-i 없는 sed)는 안 잡는다 = 권장 형태를 벌하지 않는다" ;;
esac

# 🧪 [양성 대조군] **오탐이 없는가.** 면제 셋이 실제로 동작하나 —
#   ① 주석 ② 가까운 폴백(두 줄로 갈려도) ③ 문자열 속(설명 문구·가드 자신의 패턴)
cat > "$WORK/clean.sh" <<'CLEAN'
#!/bin/bash
# touch -d '@100' 은 GNU 전용이다 — 이 줄은 주석이라 위반이 아니다
file_mtime() {
  m="$(date -r "$1" +%s 2>/dev/null)" || m=""
  [[ "$m" =~ ^[0-9]+$ ]] || m="$(stat -f %m "$1" 2>/dev/null)"
}
DET=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "")
ok "GNU date -d 는 정본 안에만 있다"
CLEAN
CLEAN_OUT="$(portability_scan "$WORK/clean.sh")"
[ -z "$CLEAN_OUT" ] \
  && ok "🧪 [양성 대조군] 주석·갈린 폴백·문자열 속은 오탐 없이 통과한다" \
  || bad "오탐" "<없음>" "$CLEAN_OUT"

# 🔴 못 읽는 파일을 **통과로 접지 않는다** — 검사기가 죽은 것과 깨끗한 것은 다르다.
MISS_OUT="$(portability_scan "$WORK/no-such-file.sh")"
case "$MISS_OUT" in
    *"못 읽었다"*) ok "읽을 수 없는 파일은 '못 읽었다'로 보고한다(조용히 통과 아님)" ;;
    *) bad "부재 처리" "'못 읽었다' 보고" "${MISS_OUT:-<조용함>} — 부재가 합격이 된다" ;;
esac

# 🔴 **판정 분모가 지키려는 명제와 어긋나 있었다** (2026-08-05, `#149` 룬드 맥 실측).
#   명제는 *"룬드가 자기 맥에서 `tests/` 를 돌리면 통과한다"* 인데, 위에서 `tests/*.sh` 만 판정했다.
#   ⇒ 시험이 **호출하는** 스크립트가 GNU 전용이면 시험 파일은 깨끗한데 **실행이 죽는다.**
#     실물: `scripts/darren-sleep.sh` 6곳이 「보고」 줄에만 있었고, 맥에서 6 fail 이 났다.
#     그때 이 시험은 **초록이었다** — 초록이 증명한 건 「`tests/` 에 GNU 토큰이 없다」뿐이다.
#   🔑 게이트를 **조회**하는 것으로는 부족하다. **분모끼리 대조**해야 한다(룬드).
#
#   🔸 목록을 손으로 적지 «않는다» — 낡으면 조용해진다. 시험 본문에서 **유도**한다.
CALLED="$(command grep -ho 'scripts/[A-Za-z0-9_-]*\.sh' "$REPO"/tests/*.sh | sort -u)"
# 🔸 이 PR 이전부터 있던 위반은 **이름으로 적어둔다**(줄 수가 아니라 파일). 새 파일은 자동으로
#   판정에 들어오고, 여기 있는 것은 «줄어드는 방향으로만» 지운다. 별건 안건 — 08-05 감사.
# ⚠️ **분모가 «주석»으로도 는다** — `CALLED` 는 tests/*.sh 를 grep 해 뽑으므로,
#   시험이 «설명으로만» 언급한 스크립트도 분모에 들어온다. 안전한 방향(과대추정)이지만
#   놀랍다: `#155` 의 새 시험이 주석에 `scripts/vault-audit-llm.sh` 를 적자
#   그 파일이 판정에 들어와 **스택 머지에서만** 빨개졌다(개별 CI 는 둘 다 초록).
#   🔑 이걸 「grep 을 정교하게」로 고치지 않는다 — 좁히면 «부르는데 안 잡히는» 쪽으로 샌다.
#   🔸 그 파일은 스스로 `:5` 에 **「Linux/bash 4+ 전용(GNU date·grep -P·mapfile)」**이라 적어뒀고
#      연관배열도 쓴다 — 이식성 «회귀»가 아니라 **선언된 범위 밖**이라 면제 원장에 넣는다.
#      (3.2 로 내리려면 별건 PR 이다. 여기서 같이 고치면 한 PR 이 두 가지가 된다)
LEGACY_DIRTY='morning-briefing.sh check-core-drift.sh vault-audit.sh vault-append.sh vault-audit-llm.sh'
CALLED_FILES=""
for rel in $CALLED; do
    base="${rel##*/}"
    case " $LEGACY_DIRTY " in *" $base "*) continue ;; esac
    [ -f "$REPO/$rel" ] && CALLED_FILES="$CALLED_FILES $REPO/$rel"
done
C_VIOL="$(portability_scan $CALLED_FILES)"
if [ -z "$C_VIOL" ]; then
    ok "시험이 «호출하는» scripts/ 도 GNU/BSD 공용이다 (면제 원장: $LEGACY_DIRTY)"
else
    bad "이식성 위반(시험이 호출하는 스크립트)" "<없음>" "$(printf '%s' "$C_VIOL" | sed "s|$REPO/||")"
fi

# 🔸 범위 밖(scripts/)을 **세어서 보고**한다 — 좁힌 것을 조용히 두지 않는다.
S_VIOL="$(portability_scan "$REPO"/scripts/*.sh)"
S_N="$(printf '%s' "$S_VIOL" | grep -c . || true)"
echo "  🔸 범위 밖 scripts/ : ${S_N:-0}곳 (니노 전용 실행이라 별건 — 이 시험은 판정하지 않는다)"
[ "${S_N:-0}" -gt 0 ] && printf '%s\n' "$S_VIOL" | sed "s|$REPO/|       |"

echo
echo "  pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
