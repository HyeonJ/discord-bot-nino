#!/usr/bin/env bash
# catchup-hint.sh 계약 테스트
#
# 왜 별 스크립트로 뽑았나:
#   "놓친 대화 따라잡기" 지시문이 start-nino.sh와 restart-nino.sh에 **각각 복사**돼 있었다.
#   오늘 종일 본 드리프트 형태(같은 규칙의 사본 두 벌)라, 한 곳에서 만들고 두 스크립트가 부르게 한다.
#
# 🔴 핵심 계약: 중단 시각을 모를 때 "0분"이나 "전체"로 넘어가지 않는다.
#   모르면 기본 창을 쓰고 **모른다는 사실을 지시문에 남긴다** — 조용한 기본값이 오늘 사고의 형태였다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HINT="$SCRIPT_DIR/../scripts/catchup-hint.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     want: $2"; echo "     got:  $3"; fail=$((fail + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/logs" "$WORK/bin" "$WORK/memory/discord-history"

# CLI 스텁 (있음/없음을 시험에서 갈아끼운다)
make_cli() { printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/yaksu-history"; chmod +x "$WORK/bin/yaksu-history"; }
drop_cli() { rm -f "$WORK/bin/yaksu-history"; }

# $1=설명 $2=기대 정규식 $3.. = 추가 인자
run() {
  local desc="$1" want="$2"; shift 2
  local got
  got=$(CATCHUP_BOT_DIR="$WORK" CATCHUP_CLI="$WORK/bin/yaksu-history" bash "$HINT" "$@" 2>&1)
  if printf '%s' "$got" | grep -qE "$want"; then ok "$desc"; else bad "$desc" "$want" "$got"; fi
}
run_not() {
  local desc="$1" unwanted="$2"; shift 2
  local got
  got=$(CATCHUP_BOT_DIR="$WORK" CATCHUP_CLI="$WORK/bin/yaksu-history" bash "$HINT" "$@" 2>&1)
  if printf '%s' "$got" | grep -qE "$unwanted"; then bad "$desc" "NOT $unwanted" "$got"; else ok "$desc"; fi
}

echo "중단 시각을 알 때 — 경과 분으로 창을 잡는다:"
make_cli
date -u -d '90 minutes ago' +%Y-%m-%dT%H:%M:%SZ > "$WORK/logs/last-stop-utc"
run "90분 전 중단 → --after 9[0-9]m"        'yaksu-history --after 9[0-9]m'
run_not "정확히 알 때는 '모른다' 문구 없음"  '중단 시각'

date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%SZ > "$WORK/logs/last-stop-utc"
run "3시간 전 중단 → 18[0-9]m"              'yaksu-history --after 18[0-9]m'

echo ""
echo "경계 — 너무 짧거나 너무 긴 값은 클램프:"
date -u +%Y-%m-%dT%H:%M:%SZ > "$WORK/logs/last-stop-utc"
run "방금 중단(0분) → 최소 5m 이상"          'yaksu-history --after (5|[6-9]|1[0-9])m'
date -u -d '10 days ago' +%Y-%m-%dT%H:%M:%SZ > "$WORK/logs/last-stop-utc"
run "10일 전 → 48시간(2880m)으로 클램프"     'yaksu-history --after 2880m'
run "클램프하면 그 사실을 지시문에 남긴다"    '(잘렸|클램프|48시간)'

echo ""
echo "🔴 중단 시각을 모를 때 — 기본 창 + 모른다는 사실 명시:"
rm -f "$WORK/logs/last-stop-utc"
run "state 파일 없음 → 기본 창으로"          'yaksu-history --after [0-9]+m'
run "모른다는 사실을 지시문에 남긴다"        '중단 시각'
printf 'garbage\n' > "$WORK/logs/last-stop-utc"
run "state 파일이 깨졌어도 기본 창 + 명시"   '중단 시각'
run_not "깨진 값을 그대로 쓰지 않는다"       'after garbage'

echo ""
echo "CLI가 없을 때 — jsonl 폴백 (조용히 실패하지 않는다):"
rm -f "$WORK/logs/last-stop-utc"; drop_cli
TODAY=$(TZ=Asia/Seoul date +%Y-%m-%d); : > "$WORK/memory/discord-history/$TODAY.jsonl"
run "CLI 부재 → jsonl 경로 지시"             "memory/discord-history/$TODAY.jsonl"
run_not "CLI 부재면 CLI 명령을 주지 않는다"   'yaksu-history --after'

rm -f "$WORK/memory/discord-history/"*.jsonl
run "CLI도 jsonl도 없으면 current-tasks 폴백" 'current-tasks.md'

echo ""
echo "--reboot 변형:"
make_cli
date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ > "$WORK/logs/last-stop-utc"
run "--reboot → 재부팅 문구"                 '재부팅'                --reboot
run "--reboot여도 따라잡기 명령은 그대로"     'yaksu-history --after'  --reboot
: > "$WORK/logs/pending-restart-notify.txt"
run "--reboot + 알림파일 → 처리 지시 포함"    'pending-restart-notify' --reboot
rm -f "$WORK/logs/pending-restart-notify.txt"
run_not "알림파일 없으면 그 문구 없음"        'pending-restart-notify' --reboot
run_not "플래그 없으면 재부팅 문구 없음"      '재부팅'

echo ""
echo "출력 형태:"
run "한 줄로 출력(tmux send-keys에 그대로 들어감)" '.'
lines=$(CATCHUP_BOT_DIR="$WORK" CATCHUP_CLI="$WORK/bin/yaksu-history" bash "$HINT" | wc -l)
[[ "$lines" -eq 1 ]] && ok "정확히 1줄" || bad "정확히 1줄" "1" "$lines"

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
