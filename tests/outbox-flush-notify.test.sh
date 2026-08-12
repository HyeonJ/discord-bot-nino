#!/usr/bin/env bash
# outbox-flush-notify.sh 계약 시험 — tmux·크론 안 씀(전부 env 주입)
#
# 🔑 이 스크립트가 하는 일은 «계기의 주어를 나에서 크론으로 옮기는 것»이다.
#   그래서 시험의 본체는 **「대기 중일 때 실제로 깨우나」**와 **「빈데 깨우지 않나」** 둘이다.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; BOT="$(cd "$DIR/.." && pwd)"
S="$BOT/scripts/outbox-flush-notify.sh"
pass=0; fail=0
ok(){ echo "  ✅ $1"; pass=$((pass+1)); }
bad(){ echo "  ❌ $1"; fail=$((fail+1)); [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/     /'; }
[[ -f "$S" ]] || { echo "❌ 대상 없음: $S"; exit 1; }
R="$(mktemp -d)"; trap 'rm -rf "$R"' EXIT
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/injected"\n' "$R" > "$R/inject"; chmod +x "$R/inject"

mk(){ printf '# 대기함\n\n## 대기 중\n%s\n' "$1" > "$R/outbox.md"; }
run(){ OUTBOX_FILE="$R/outbox.md" INJECT_CMD="$R/inject" FLUSH_LOG="$R/log" bash "$S"; }

echo "── ① 대기 중이면 깨운다 ──"
mk '- 룬드에게: census 결과'; : > "$R/injected"
run >/dev/null 2>&1
[[ -s "$R/injected" ]] && ok "항목이 있으면 주입한다" || bad "주입" "1건" "0건"
grep -q '놀이터' "$R/injected" 2>/dev/null && ok "주입문에 무엇을 하라는지가 들어 있다" \
  || bad "주입문 내용" "놀이터 언급" "$(cat "$R/injected" 2>/dev/null)"

echo "── ② 🔴 빈 상태는 조용하다 (확인된 빈 상태 ≠ 실패) ──"
mk '(비어 있음)'; : > "$R/injected"
run >/dev/null 2>&1
[[ ! -s "$R/injected" ]] && ok "플레이스홀더만 있으면 안 깨운다" || bad "빈데 깨움" "0건" "$(cat "$R/injected")"
mk ''; : > "$R/injected"
run >/dev/null 2>&1
[[ ! -s "$R/injected" ]] && ok "아예 비어도 안 깨운다" || bad "빈데 깨움" "0건" "$(cat "$R/injected")"

echo "── ③ 🔴 파일이 없으면 «조용히 성공»하면 안 된다 ──"
# 부재는 조용하다 — 대기함이 사라졌는데 아무 일도 안 일어나면 규칙이 통째로 죽는다.
: > "$R/injected"
OUTBOX_FILE="$R/no-such.md" INJECT_CMD="$R/inject" FLUSH_LOG="$R/log" bash "$S" >/dev/null 2>&1
rc=$?
[[ "$rc" -ne 0 ]] && ok "대기함 부재는 rc≠0 (판정 불가를 삼키지 않는다)" || bad "부재 무음" "rc≠0" "rc=$rc"

echo "── ④ 돌았다는 «흔적»이 남는다 (안 돈 것과 갈린다) ──"
mk '(비어 있음)'; : > "$R/log"
run >/dev/null 2>&1
grep -q 'pending=0' "$R/log" 2>/dev/null && ok "빈 회차도 로그에 남는다" \
  || bad "빈 회차 로그" "pending=0" "$(cat "$R/log" 2>/dev/null)"
mk '- 하나'; run >/dev/null 2>&1
grep -q 'pending=1' "$R/log" 2>/dev/null && ok "건수를 로그에 남긴다" \
  || bad "건수 로그" "pending=1" "$(cat "$R/log" 2>/dev/null)"

echo; echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
