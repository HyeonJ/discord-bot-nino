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

echo "── ①-c 🔴 «실사용 형식»(불렛 항목)을 센다 — 픽스처가 제목형 뿐이라 이 축이 통째로 안 재졌다 ──"
# 🔑 실물 2026-08-14: 실사용 파일엔 항목이 `- **제목**` 불렛으로 쌓이는데 좌변이 `### ` 뿐이라
#   items=0 → body>0 → **항상 1**. 3건이 `pending=1` 로 나왔고 «조용했다».
#   그리고 outbox 머리말은 `###` 를 «쓰지 말라»고 한다(08-13, 하위 제목이 별도 항목으로 세어져서)
#   ⇒ 두 규칙이 서로를 무효화하고 있었다. 좌변은 「최상위 항목이냐」여야 한다.
printf '# 대기함\n\n## 대기 중\n\n- **첫 건**\n  - 본문 하나\n  - 본문 둘\n\n- **둘째 건**\n  - 본문 하나\n\n- **셋째 건**\n  - 본문 하나\n' > "$R/outbox.md"
: > "$R/injected"; : > "$R/log"
run >/dev/null 2>&1
grep -q 'pending=3' "$R/log" 2>/dev/null && ok "불렛 항목 셋 → pending=3 (하위 불렛은 본문)" \
  || bad "실사용 형식 항목 수" "pending=3" "$(tail -1 "$R/log" 2>/dev/null)"

echo "── ①-d 🔴 두 형식이 섞이면 «구별 불가»다 — 접되 «시끄럽게» ──"
# 🔑 제목형 문서에서는 «제목 아래 본문»도 들여쓰지 않은 `- ` 로 쓴다 ⇒ 「항목 불렛」과
#   「본문 불렛」이 같은 모양이라 **원리적으로 못 가른다**. 그래서 문서 단위로 접는데,
#   조용히 접으면 그게 바로 이 버그(항상 1)의 재발이다 ⇒ 로그에 표지를 남긴다.
printf '# 대기함\n\n## 대기 중\n\n### 옛 형식 건\n- 본문\n\n- **새 형식 건**\n  - 본문\n' > "$R/outbox.md"
: > "$R/log"
run >/dev/null 2>&1
grep -q 'MIXED-FORMAT' "$R/log" 2>/dev/null && ok "섞이면 로그에 MIXED-FORMAT 표지가 남는다" \
  || bad "혼합 감지" "MIXED-FORMAT 표지" "$(tail -1 "$R/log" 2>/dev/null)"

echo "── ①-e 대조군: 안 섞였으면 표지가 «없다» ──"
printf '# 대기함\n\n## 대기 중\n\n- **첫 건**\n  - 본문\n' > "$R/outbox.md"
: > "$R/log"
run >/dev/null 2>&1
grep -q 'MIXED-FORMAT' "$R/log" 2>/dev/null && bad "표지 오탐" "표지 없음" "$(tail -1 "$R/log" 2>/dev/null)" \
  || ok "불렛형만 있으면 표지가 안 붙는다 (표지가 항진명제가 아니다)"

echo "── ①-f 🔴 «절 밖»에 쌓인 항목이 조용히 사라지면 안 된다 (ORPHAN) ──"
# 🔑 실물 2026-08-15 13:00: 큐에 7건이 있는데 `pending=0` 이 나왔다 — `cat >>` 로 쌓느라
#   항목들이 `## ⑰`…`## ㉓` 같은 «자기 제목» 아래 앉았고, 계수기는 `## 대기 중` 절 밖을
#   «한 줄도» 안 본다. 0 은 「없다」가 아니라 「못 봤다」였는데 **화면이 같았다**.
# 🔴 좌변을 「무엇이 항목처럼 생겼나」로 잡지 않는다 — 머리말·보낸 기록에도 최상위 불렛이
#   산다(오탐 확정). 좌변은 «절 이름»이고 **아는 절의 열거**다: `대기 중` · `보낸 기록`.
#   모르는 절에 실질 내용이 있으면 표지를 남긴다(열거 밖은 «시끄러운 쪽»으로 실패한다).
printf '# 대기함\n\n## 대기 중\n\n(비어 있음)\n\n## ⑰ 룬드에게\n\n- 무언가\n' > "$R/outbox.md"
: > "$R/log"; : > "$R/injected"
run >/dev/null 2>&1
grep -q 'ORPHAN=1' "$R/log" 2>/dev/null && ok "모르는 절에 내용이 있으면 로그에 ORPHAN=1" \
  || bad "고아 감지" "ORPHAN=1" "$(tail -1 "$R/log" 2>/dev/null)"
# 🔴 그리고 «깨운다» — pending=0 이라고 조용히 나가면 그게 정확히 이 버그다.
[[ -s "$R/injected" ]] && ok "pending=0 이어도 고아가 있으면 깨운다 (0 이 「못 봤다」일 수 있다)" \
  || bad "고아인데 무음" "주입 1건" "0건"

echo "── ①-g 대조군: 아는 절만 있으면 표지가 «없다» ──"
# 머리말 불렛·보낸 기록 항목이 고아로 잡히면 표지가 항진명제가 된다.
printf '# 대기함\n\n- **발신 시각**: 09:00\n- **비우는 법**: 묶어서 보낸다\n\n## 대기 중\n\n- **첫 건**\n  - 본문\n\n## 보낸 기록\n\n- **2026-08-14 23:0x — 4건 발송**\n  - 항목 하나\n' > "$R/outbox.md"
: > "$R/log"
run >/dev/null 2>&1
grep -q 'ORPHAN=' "$R/log" 2>/dev/null && bad "고아 오탐" "표지 없음" "$(tail -1 "$R/log" 2>/dev/null)" \
  || ok "머리말·보낸 기록은 고아가 아니다"
grep -q 'pending=1' "$R/log" 2>/dev/null && ok "대조군의 건수도 맞다 (보낸 기록을 안 센다)" \
  || bad "건수" "pending=1" "$(tail -1 "$R/log" 2>/dev/null)"

echo "── ①-h 🔴 «대기 중» 절 자체가 없으면 0 이 아니라 판정 불가다 ──"
# 🔑 계수기의 좌변이 통째로 없는데 「0건」을 내면, 그건 측정이 아니라 **측정의 부재**다.
#   ③(파일 부재)과 같은 자리 — 부재를 0 으로 접으면 규칙이 죽는데 조용하다.
printf '# 대기함\n\n## ⑰ 룬드에게\n\n- 무언가\n' > "$R/outbox.md"
: > "$R/log"; : > "$R/injected"
run >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 ]] && ok "절이 없으면 rc≠0 (rc=$rc)" || bad "절 부재 무음" "rc≠0" "rc=$rc"
grep -q 'no-section' "$R/log" 2>/dev/null && ok "로그에 사유가 남는다 (no-section)" \
  || bad "절 부재 로그" "no-section" "$(tail -1 "$R/log" 2>/dev/null)"

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

echo "── ⑥ 🔴 주입이 «실패»하면 조용하면 안 된다 (룬드 4425734 좌변) ──"
# 이 도구의 존재 이유가 「안 울렸다 ↔ 안 돌았다」를 가르는 것인데, 마지막 단계가
#   `2>/dev/null` 로 실패를 삼키면 그 구별이 정확히 거기서 사라진다.
printf '#!/usr/bin/env bash\nexit 3\n' > "$R/inject-fail"; chmod +x "$R/inject-fail"
mk '- 하나'; : > "$R/log"
OUTBOX_FILE="$R/outbox.md" INJECT_CMD="$R/inject-fail" FLUSH_LOG="$R/log" bash "$S" >/dev/null 2>&1
rc=$?
grep -q 'INJECT-FAIL' "$R/log" 2>/dev/null && ok "주입 실패가 로그에 남는다" \
  || bad "주입 실패 무음" "INJECT-FAIL rc=3" "$(cat "$R/log" 2>/dev/null)"
[[ "$rc" -ne 0 ]] && ok "주입 실패는 rc≠0 (크론이 알 수 있다)" || bad "주입 실패 rc" "≠0" "rc=$rc"
# 대조군 — 성공하면 그 표지가 «안» 뜬다
: > "$R/log"; run >/dev/null 2>&1
grep -q 'INJECT-FAIL' "$R/log" && bad "대조군" "표지 없음" "$(cat "$R/log")" \
  || ok "대조군: 주입 성공이면 실패 표지가 없다"

echo "── ⑦ 🔴 주입은 코어 «tmux-send.sh» 를 탄다 (raw send-keys 금지) ──"
# 실물 2026-08-12 18:00: raw `send-keys "$MSG" C-m` 이 rc=0 을 냈는데 텍스트가 입력창에
#   92분 앉아 있다가 다음 주입의 Enter 에 «붙어서» 제출됐다. rc 는 「tmux 에 넣었다」지
#   「컴포저가 삼켰다」가 아니다. 코어 래퍼는 C-m 을 따로 보내고 잔류를 검사한다.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/tsargv"\n' "$R" > "$R/tmux-send"
chmod +x "$R/tmux-send"
mk '- 하나'; : > "$R/log"; rm -f "$R/tsargv"
OUTBOX_FILE="$R/outbox.md" INJECT_CMD= TMUX_SEND="$R/tmux-send" TMUX_SESSION=testses \
  FLUSH_LOG="$R/log" bash "$S" >/dev/null 2>&1
rc=$?
[[ "$rc" -eq 0 ]] && [[ -s "$R/tsargv" ]] && ok "INJECT_CMD 없으면 tmux-send.sh 를 탄다" \
  || bad "래퍼 미사용" "tsargv 생성 · rc=0" "rc=$rc argv=$(cat "$R/tsargv" 2>/dev/null)"
# 🔑 `--pane` 을 «명시»해야 TMUX_SESSION 과 TMUX_SEND_PANE 이 서로를 오염시킬 경로가 없다
grep -qx -- '--pane' "$R/tsargv" 2>/dev/null && grep -qx -- 'testses:0.0' "$R/tsargv" 2>/dev/null \
  && ok "--pane 이 세션에서 «유도»돼 전달된다 (하드코딩 아님)" \
  || bad "--pane 누락" "--pane testses:0.0" "$(cat "$R/tsargv" 2>/dev/null)"

# 🔴 폴백으로 raw 를 두지 않는다 — 폴백이 곧 방금 «샌» 경로다. 없으면 «시끄럽게» 실패한다
: > "$R/log"
err="$(OUTBOX_FILE="$R/outbox.md" INJECT_CMD= TMUX_SEND="$R/no-such-injector" \
  FLUSH_LOG="$R/log" bash "$S" 2>&1 >/dev/null)"
rc=$?
[[ "$rc" -ne 0 ]] && grep -q 'INJECT-FAIL' "$R/log" && [[ -n "$err" ]] \
  && ok "주입기 부재 = rc≠0 + 로그 + stderr (조용한 폴백 없음)" \
  || bad "주입기 부재가 조용하다" "rc≠0 · INJECT-FAIL · stderr" "rc=$rc err=$err log=$(cat "$R/log")"

# 대조군 — INJECT_CMD 가 있으면 래퍼는 «안» 탄다 (시험이 진짜 tmux 를 못 때린다)
rm -f "$R/tsargv"; : > "$R/log"
OUTBOX_FILE="$R/outbox.md" INJECT_CMD="$R/inject" TMUX_SEND="$R/tmux-send" \
  FLUSH_LOG="$R/log" bash "$S" >/dev/null 2>&1
[[ ! -e "$R/tsargv" ]] && [[ -s "$R/injected" ]] && ok "대조군: INJECT_CMD 가 래퍼보다 우선한다" \
  || bad "우선순위" "래퍼 미호출 · INJECT_CMD 호출" "tsargv=$([[ -e "$R/tsargv" ]] && echo 있음 || echo 없음)"

echo; echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
