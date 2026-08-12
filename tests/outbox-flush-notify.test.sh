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

echo "── ①-b 🔴 «항목»을 센다 — 줄이 아니다 (첫 실사용에서 2건이 12로 나왔다) ──"
# 옛 픽스처는 전부 «한 줄짜리 항목»이라 줄 수와 항목 수가 같았다 ⇒ 이 축을 하나도 안 쟀다.
#   경계를 재는 픽스처가 없으면 좌변이 틀려도 초록이다(같은 날 check-auth 에서 밟은 그것).
printf '# 대기함\n\n## 대기 중\n\n### 1. 첫 건\n- 줄 하나\n- 줄 둘\n- 줄 셋\n\n### 2. 둘째 건\n- 줄 하나\n' > "$R/outbox.md"
: > "$R/injected"
run >/dev/null 2>&1
grep -q 'pending=2' "$R/log" 2>/dev/null && ok "여러 줄 항목 둘 → pending=2 (줄 수 8이 아니다)" \
  || bad "항목 수" "pending=2" "$(tail -1 "$R/log" 2>/dev/null)"
grep -q '2건' "$R/injected" 2>/dev/null && ok "주입문의 「N건」도 항목 수다" \
  || bad "주입문 건수" "2건" "$(cat "$R/injected" 2>/dev/null)"

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

echo "── ⑤ 🔴 «검증 실행»이 실물을 쏘면 안 된다 (--dry-run) ──"
# 실물: 09:53·09:54 에 이 스크립트를 «진짜 파일로 확인»하려고 돌렸더니 그대로 내 세션에 주입됐다.
#   그중 하나는 버그판이라 **틀린 수(12건)가 «지시»로 도착**했다. 확인이 계기를 만들면 안 된다.
# 🔑 그리고 dry 회차는 로그에서 «갈려야» 한다 — 안 그러면 이 로그의 본업(「안 울렸다 ↔ 안 돌았다」를
#   가르는 것)이 「내가 시험한 것 ↔ 크론이 돈 것」에서 다시 무너진다.
mk '- 하나'; : > "$R/injected"; : > "$R/log"
OUTBOX_FILE="$R/outbox.md" INJECT_CMD="$R/inject" FLUSH_LOG="$R/log" bash "$S" --dry-run >/dev/null 2>&1
rc=$?
[[ ! -s "$R/injected" ]] && ok "--dry-run 은 주입하지 않는다" || bad "dry 인데 주입" "0건" "$(cat "$R/injected")"
[[ "$rc" -eq 0 ]] && ok "--dry-run 은 rc=0 (확인은 실패가 아니다)" || bad "dry rc" "0" "rc=$rc"
grep -q 'pending=1 DRY' "$R/log" 2>/dev/null && ok "dry 회차는 로그에서 실회차와 갈린다" \
  || bad "dry 표지" "pending=1 DRY" "$(cat "$R/log" 2>/dev/null)"
# 대조군 — 같은 픽스처를 dry 없이 돌리면 주입되고 표지가 없다
: > "$R/injected"; : > "$R/log"; run >/dev/null 2>&1
[[ -s "$R/injected" ]] && ! grep -q 'DRY' "$R/log" && ok "대조군: dry 없으면 주입되고 표지도 없다" \
  || bad "대조군" "주입 있음 · DRY 없음" "$(cat "$R/log" 2>/dev/null)"

echo; echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
