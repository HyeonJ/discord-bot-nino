#!/usr/bin/env bash
# portability.test.sh — **모든 시험 파일**이 GNU/BSD 공용인지 한 자리에서 잰다.
#
# 🔴 왜 파일 하나로 모았나 (2026-07-31):
#   같은 가드를 `nino-watchdog.test.sh` **안에** 두고 있었다. 그러면 새 시험 파일은
#   **가드를 그냥 안 쓰는 것으로 통과**한다 — 그리고 안 쓰는 것은 조용하다.
#   실제로 그 형태로 샜다: `tests/lib/timeshift.sh` 머리말에 *"사본 금지, 정본은 이 파일 하나"*
#   가 적혀 있는데도 `nino-watchdog.test.sh` 가 source 를 안 해 룬드 맥에서 4 fail 이 났다.
#   🔑 **안 쓰는 것이 조용한 한, 정본은 권고일 뿐이다.** 여기서 시끄럽게 만든다.
#
# 🔸 범위 — `tests/` 만 본다. 근거:
#   시험은 **양쪽 기계에서 도는 것이 계약**이라(룬드가 내 PR 을 자기 맥에서 센다) 여기가 본체다.
#   `scripts/` 에도 세 곳이 남아 있지만(`check-core-drift.sh:59` · `vault-audit.sh:76,82`)
#   그건 니노 전용으로만 도는 것이라 **다른 판단이 필요하다** — 별건으로 남긴다.
#   ⚠️ 조용히 좁힌 게 아니라 **적어두고** 좁혔다. 아래 시험이 그 세 곳을 세어 보고한다.
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

# 🔸 범위 밖(scripts/)을 **세어서 보고**한다 — 좁힌 것을 조용히 두지 않는다.
S_VIOL="$(portability_scan "$REPO"/scripts/*.sh)"
S_N="$(printf '%s' "$S_VIOL" | grep -c . || true)"
echo "  🔸 범위 밖 scripts/ : ${S_N:-0}곳 (니노 전용 실행이라 별건 — 이 시험은 판정하지 않는다)"
[ "${S_N:-0}" -gt 0 ] && printf '%s\n' "$S_VIOL" | sed "s|$REPO/|       |"

echo
echo "  pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
