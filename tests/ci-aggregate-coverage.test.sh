#!/bin/bash
# .github/workflows/ci.yml — «러너 집계»가 CI 의 시험 스텝을 다 덮나
#
# 🔴 왜 이 시험이 필요한가: 원장의 세 수(실패집합 · 판정 불가 · platform)는 **러너 집계 위에**
#   정의된다. 집계가 안 덮는 CI 스텝은 실패도 통과도 아니라 «부재»고, 부재는 조용하다.
#
# 🔑 실물 (2026-08-15, 코어): 시험 스텝이 셋인데 집계가 하나만 덮어서 판정 불가 2 였다.
#   그 값으로 원장 첫 행이 «동결»로 착지해 APPROVED 인 PR 넷이 통째로 잠겼다.
#   🔑 그때 아무 경보도 없었다 — 세 수를 «만드는» 쪽의 결함이라 세 수로는 안 보인다.
#
# 🔑 잠그는 축은 «둘»이고 성질이 다르다:
#   ① 집계 스텝이 «정본 집계 명령»을 실제로 부르나 — 회귀 잠금(바꾸면 빨강)
#   ② 워크플로의 «모든» run 스텝이 «집계» 또는 «등재된 면제» 중 하나인가 — 분모 잠금(새 스텝이면 빨강)
#   ①만 두면 **새로 생긴 스텝이 통째로 안 보인다** — 그게 이 시험이 막으려는 바로 그 고장이다.
#
# 🔴 면제 목록을 «이 파일 안»에 두지 않는다 — `.github/aggregate-exempt.tsv` 가 정본이다.
#   왜: 원장의 「집계 밖 등재」 칸이 **그 파일의 행 수**라, 목록이 시험 소스 안에 있으면
#   원장이 세려면 시험 소스를 파싱해야 한다. 데이터는 데이터 파일에 둔다(platform baseline 과 같은 꼴).
#   🔑 그리고 사본이 하나뿐이라 «한쪽만 고치는» 경로가 아예 없다.
#
# 🔴 이 시험이 «못 보는» 축 — 초록을 「집계가 옳다」로 읽지 않기 위해 적어둔다:
#   ⓐ 앵커는 «문자열»이다. 표기를 바꾸면 ②에서 빨개진다(거짓 양성) ⇒ tsv 도 같이 고친다.
#   ⓑ 「집계에 넣었다」가 「그 명령이 초록이다」를 뜻하지 않는다 — 초록 여부는 러너가 잰다.
#   ⓒ 스텝이 «여러 명령을 담은 블록»이면 앵커 하나로 그 블록 «전체»를 면제한다.
#      즉 블록 «안»에 새 명령이 들어오는 것은 이 시험이 못 본다. 알려진 좁음이다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_FILE:-$SCRIPT_DIR/../.github/workflows/ci.yml}"
EXEMPT_FILE="${EXEMPT_FILE:-$SCRIPT_DIR/../.github/aggregate-exempt.tsv}"

# 🔑 집계 스텝을 가르는 «정본 명령». 여기를 바꾸면 ci.yml 도 같이 바뀌어야 한다.
AGG_ANCHOR="npm run test:all"
VERDICT_ANCHOR="scripts/ci-verdict.sh"

pass=0; fail=0; unknown=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$CI" ] || { echo "⛔ 판정 불가 — 워크플로가 없다: $CI"; exit 2; }
command -v python3 >/dev/null || { echo "⛔ 판정 불가 — python3 이 없다"; exit 2; }

# 🔴 면제 파일 «부재»를 0건으로 접지 않는다 — 그러면 「등재 0」과 「목록이 없다」가 같아진다.
#    이 파일은 항상 있어야 한다(머리말만 있어도 된다). 없으면 그건 분기가 아니라 결함이다.
[ -f "$EXEMPT_FILE" ] || {
  echo "⛔ 판정 불가 — 면제 목록이 없다: $EXEMPT_FILE"
  echo "     🔑 「등재 0건」이 «측정»이 되려면 셀 파일이 있어야 한다. 머리말만 둔 채로 만든다."
  exit 2
}

echo "  워크플로: $CI"
echo "  면제 목록: $EXEMPT_FILE"
echo

# ── ① 회귀 잠금 — 집계 스텝이 정본 명령을 부르나 ──────────────────────────
# 🔴 **주석을 먼저 걷어낸다.** 안 걷으면 ci.yml 주석이 그 명령을 «언급»만 해도 ①이 참이 되고,
#    그건 «구조적 상시 참»이라 게이트 입력으로 못 쓴다. 실측(이 파일 개발 중): 배선을
#    `없는판정기.sh` 로 바꿨는데 ①이 초록이었다 — 위 주석 블록이 `scripts/ci-verdict.sh` 를
#    적어둔 탓이다. 🔑 변이를 안 돌렸으면 «항진인 시험»을 초록으로 보고 넣을 뻔했다.
CI_BODY="$(awk '{ line = $0; sub(/^[ \t]+/, "", line); if (line ~ /^#/) next; print }' "$CI")"
for a in "$AGG_ANCHOR" "$VERDICT_ANCHOR"; do
  case "$CI_BODY" in
    *"$a"*) ok "① 집계 스텝이 부른다 — $a" ;;
    *)      bad "① 집계 스텝이 부른다 — $a" "ci.yml 안에 이 명령" \
                "없다 — 집계가 사라지면 원장의 세 수가 «만들어지지» 않는다" ;;
  esac
done

# ── 면제 등재 수 — 원장 「집계 밖 등재」 칸의 좌변 ──────────────────────────
EXEMPT_N="$(awk 'BEGIN{n=0} /^[ \t]*#/ {next} /^[ \t]*$/ {next} {n++} END{print n}' "$EXEMPT_FILE")"
echo "  📊 집계 밖 등재: ${EXEMPT_N}건  ← 원장 칸의 좌변은 이 수다"
echo

# ── ② 분모 잠금 — 모든 run 스텝이 «집계» 또는 «등재된 면제» 중 하나인가 ────
read_misses() {
  python3 - "$CI" "$EXEMPT_FILE" "$AGG_ANCHOR" <<'PY'
import sys
ci_path, exempt_path, agg = sys.argv[1], sys.argv[2], sys.argv[3]
exempt = []
for ln in open(exempt_path):
    s = ln.rstrip("\n")
    if not s.strip() or s.lstrip().startswith("#"):
        continue
    exempt.append(s.split("\t", 1)[0].strip())

lines = open(ci_path).read().splitlines()
steps, i, cur_name, cur_line = [], 0, None, 0
while i < len(lines):
    ln = lines[i]; st = ln.strip()
    if st.startswith("#") or not st:
        i += 1; continue
    if st.startswith("- name:"):
        cur_name = st.split("name:", 1)[1].strip(); cur_line = i + 1
    elif st.startswith("- uses:") or st.startswith("uses:"):
        cur_name = None                      # uses 스텝은 run 이 없다 — 분모 밖
    elif st.startswith("- run:") or st.startswith("run:"):
        body = st.split("run:", 1)[1].strip()
        if st.startswith("- run:"):
            cur_name, cur_line = None, i + 1  # 이름 없는 스텝
        payload = []
        if body and body != "|":
            payload.append(body)
        else:
            ind = len(ln) - len(ln.lstrip())
            j = i + 1
            while j < len(lines):
                nxt = lines[j]
                if nxt.strip() and (len(nxt) - len(nxt.lstrip())) <= ind:
                    break
                if nxt.strip() and not nxt.strip().startswith("#"):
                    payload.append(nxt.strip())
                j += 1
            i = j - 1
        key = cur_name if cur_name else (payload[0] if payload else "")
        steps.append((cur_line or i + 1, key, "\n".join(payload)))
        cur_name = None
    i += 1

for lineno, key, payload in steps:
    hay = key + "\n" + payload
    if agg in hay or any(k and k in hay for k in exempt):
        continue
    print("%d:%s" % (lineno, key.split("#", 1)[0].strip() or "<이름 없는 스텝>"))
PY
}
MISSES="$(read_misses)"

if [ -z "$MISSES" ]; then
  ok "② 모든 run 스텝이 «집계» 또는 «등재된 면제» 중 하나다"
else
  n="$(printf '%s\n' "$MISSES" | grep -c .)"
  bad "② 모든 run 스텝이 두 칸 중 하나다" \
      "새 스텝이면 집계에 넣거나 $EXEMPT_FILE 에 «이유와 함께» 등재" \
      "${n}건이 어느 칸에도 없다 — 집계 밖이면 원장의 어느 수에도 안 뜬다"
  printf '%s\n' "$MISSES" | sed 's/^/       ci.yml:/'
fi

# ── ③ 등재에 이유가 붙어 있나 — 이유 없는 면제는 하수구가 된다 ─────────────
NO_REASON="$(awk -F'\t' '/^[ \t]*#/ {next} /^[ \t]*$/ {next} { r=$2; gsub(/^[ \t]+|[ \t]+$/, "", r); if (NF < 2 || r == "") print NR": "$1 }' "$EXEMPT_FILE")"
if [ -z "$NO_REASON" ]; then
  ok "③ 등재 ${EXEMPT_N}건 전부 «이유»가 붙어 있다"
else
  bad "③ 이유 없는 등재가 있다" "앵커<TAB>이유" "$(printf '%s' "$NO_REASON" | tr '\n' ' ')"
fi

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $unknown"
# 🔴 판정 불가를 «통과»로 접지 않는다 — 러너 계약과 같은 rc(2 = 못 쟀다).
[ "$fail" -eq 0 ] || exit 1
[ "$unknown" -eq 0 ] || exit 2
