#!/usr/bin/env bash
# catchup-hint.sh 계약 테스트
#
# 왜 별 스크립트로 뽑았나:
#   "놓친 대화 따라잡기" 지시문이 start-nino.sh와 restart-nino.sh에 **각각 복사**돼 있었다.
#   같은 규칙의 사본 두 벌은 갈린다(discord-send 문법·yaksu-history 버전이 4개월씩 갈린 형태).
#
# 🔴 핵심 계약 두 개:
#   ① 중단 시각을 모를 때 "0분"이나 "전체"로 넘어가지 않는다 — 기본 창을 쓰고 **모른다는 사실을 남긴다.**
#      조용한 기본값은 실제 중단 시간처럼 읽힌다.
#   ② 오차는 **창이 넓어지는 방향으로만** 난다. 좁아지는 방향이 유일하게 유실이 나는 방향이다.
#
# 🔴 픽스처가 앵커를 직접 심지 않는다 (룬드 리뷰 M:vsdg의 본체):
#   1차 구현은 restart-nino.sh가 쓰는 logs/last-stop-utc를 앵커로 썼고, 테스트가 그 파일을
#   직접 채웠다. 그래서 20개가 통과했는데 **실물은 창이 항상 5분에 고정**돼 있었다 —
#   restart가 맨 위에서 now를 쓰고 7초 뒤 읽었기 때문이다. 파일을 채우는 주체가 시험 밖이었다.
#   → 이제 앵커는 DB(니노 마지막 발화)이고, 맨 아래에 **restart-nino.sh를 실제로 태우는
#     통합 케이스**를 둬서 생산자-소비자 계약을 잰다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
HINT="$REPO/scripts/catchup-hint.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     want: $2"; echo "     got:  $3"; fail=$((fail + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/logs" "$WORK/bin" "$WORK/memory/discord-history"
DB="$WORK/messages.db"

# CLI 스텁 (있음/없음을 시험에서 갈아끼운다)
make_cli() { printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/yaksu-history"; chmod +x "$WORK/bin/yaksu-history"; }
drop_cli() { rm -f "$WORK/bin/yaksu-history"; }

# 실물 스키마의 NOT NULL 컬럼만 추린 픽스처. seed_db <분전> [작성자] [분전] [작성자] ...
seed_db() {
  rm -f "$DB"
  python3 - "$DB" "$@" <<'PY'
import sqlite3, sys, datetime as dt
db, args = sys.argv[1], sys.argv[2:]
c = sqlite3.connect(db)
c.execute("""CREATE TABLE messages (
    message_id TEXT PRIMARY KEY, type TEXT NOT NULL, channel_id TEXT NOT NULL,
    channel_name TEXT, author_id TEXT NOT NULL, author_name TEXT NOT NULL,
    content TEXT, timestamp TEXT NOT NULL)""")
now = dt.datetime.now(dt.timezone.utc)
for i in range(0, len(args), 2):
    mins, who = int(args[i]), args[i + 1]
    ts = (now - dt.timedelta(minutes=mins)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    c.execute("INSERT INTO messages VALUES (?,?,?,?,?,?,?,?)",
              (f"id{i}", "message", "1", "충재-다용도", "a1", who, "x", ts))
c.commit()
PY
}

env_run() { CATCHUP_BOT_DIR="$WORK" CATCHUP_CLI="$WORK/bin/yaksu-history" YAKSU_HISTORY_DB="$DB" bash "$HINT" "$@" 2>&1; }

# $1=설명 $2=기대 정규식 $3.. = 추가 인자
run() {
  local desc="$1" want="$2"; shift 2
  local got; got=$(env_run "$@")
  if printf '%s' "$got" | grep -qE "$want"; then ok "$desc"; else bad "$desc" "$want" "$got"; fi
}
run_not() {
  local desc="$1" unwanted="$2"; shift 2
  local got; got=$(env_run "$@")
  if printf '%s' "$got" | grep -qE "$unwanted"; then bad "$desc" "NOT $unwanted" "$got"; else ok "$desc"; fi
}

echo "앵커 = 니노 마지막 발화 → 경과 분으로 창을 잡는다:"
make_cli
seed_db 90 니노
run "90분 전 발화 → --after 9[0-9]m"        'yaksu-history --after 9[0-9]m'
run_not "정확히 알 때는 '못 구해서' 문구 없음" '못 구해서'
seed_db 180 니노
run "3시간 전 발화 → 18[0-9]m"              'yaksu-history --after 18[0-9]m'

echo ""
echo "🔴 앵커가 '니노' 발화여야 한다 (전체 MAX면 안 되는 이유):"
# restart는 relay를 먼저 살리고 5초 뒤 지시문을 만든다. 그 5초에 남의 메시지 한 건만 와도
# MAX(timestamp) 전체는 "방금"이 되고 창이 5분으로 좁아진다 — 유실 나는 방향.
seed_db 90 니노 1 Tim
run "남의 메시지가 1분 전이어도 창은 9[0-9]m" 'yaksu-history --after 9[0-9]m'
run_not "전체 MAX에 끌려가 5m로 좁아지지 않는다" 'after (5|[1-9])m'
seed_db 30 Tim 45 룬드
run "니노 발화가 아예 없으면 기본 창 + 명시"  '못 구해서'

echo ""
echo "경계 — 너무 짧거나 너무 긴 값은 클램프:"
seed_db 0 니노
run "방금 발화(0분) → 최소 5m 이상"           'yaksu-history --after (5|[6-9]|1[0-9])m'
seed_db 14400 니노
run "10일 전 → 48시간(2880m)으로 클램프"      'yaksu-history --after 2880m'
run "클램프하면 그 사실을 지시문에 남긴다"     '(잘랐|클램프|48시간)'

echo ""
echo "🔴 앵커를 못 구할 때 — 기본 창 + 모른다는 사실 명시:"
rm -f "$DB"
run "DB 파일 없음 → 기본 창으로"              'yaksu-history --after [0-9]+m'
run "모른다는 사실을 지시문에 남긴다"          '못 구해서'
printf 'garbage\n' > "$DB"
run "DB가 깨졌어도 기본 창 + 명시"            '못 구해서'
run_not "깨진 DB로 0분/빈 창을 만들지 않는다"  'after (0m|m )'

echo ""
echo "CLI가 없을 때 — jsonl 폴백 (조용히 실패하지 않는다):"
seed_db 90 니노; drop_cli
TODAY=$(TZ=Asia/Seoul date +%Y-%m-%d); : > "$WORK/memory/discord-history/$TODAY.jsonl"
run "CLI 부재 → jsonl 경로 지시"              "memory/discord-history/$TODAY.jsonl"
run_not "CLI 부재면 CLI 명령을 주지 않는다"     'yaksu-history --after'
run "CLI가 왜 없는지도 확인하라고 한다"        '(CLI 부재|조회 정본)'

rm -f "$WORK/memory/discord-history/"*.jsonl
run "CLI도 jsonl도 없으면 current-tasks 폴백"  'current-tasks.md'

echo ""
echo "--reboot 변형:"
make_cli; seed_db 30 니노
run "--reboot → 재부팅 문구"                  '재부팅'                --reboot
run "--reboot여도 따라잡기 명령은 그대로"      'yaksu-history --after'  --reboot
: > "$WORK/logs/pending-restart-notify.txt"
run "--reboot + 알림파일 → 처리 지시 포함"     'pending-restart-notify' --reboot
rm -f "$WORK/logs/pending-restart-notify.txt"
run_not "알림파일 없으면 그 문구 없음"         'pending-restart-notify' --reboot
run_not "플래그 없으면 재부팅 문구 없음"       '재부팅'

echo ""
echo "🟡 --no-head — 호출부가 앞머리를 가질 때 문장이 겹치지 않는다 (룬드 리뷰 ②):"
run_not "--no-head면 '재시작됐어' 없음"        '재시작됐어'             --no-head
run_not "--no-head는 --reboot보다 우선"        '재부팅'                 --no-head --reboot
run "--no-head여도 따라잡기 명령은 그대로"     'yaksu-history --after'  --no-head

echo ""
echo "출력 형태:"
run "UTC 표기를 알려준다(KST 오해 방지)"       '(UTC|\+9)'
lines=$(env_run | wc -l)
[[ "$lines" -eq 1 ]] && ok "정확히 1줄(tmux send-keys에 그대로 들어감)" || bad "정확히 1줄" "1" "$lines"

echo ""
echo "🔴 통합 — restart-nino.sh를 실제로 태워서 생산자-소비자 계약을 잰다:"
# 1차 구현이 여기서 무너졌다. 픽스처가 앵커를 직접 심으면 restart가 앵커를 어떻게 만드는지는
# 아무도 검사하지 않는다. tmux/systemctl/sleep을 스텁으로 갈아끼우고 스크립트를 그대로 돌린다.
STUB="$WORK/stub"; mkdir -p "$STUB"
cat > "$STUB/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  has-session) exit 0 ;;                                   # 세션 있음 = 재시작 경로
  send-keys)   printf '%s\n' "$4" >> "$SENT_FILE"; exit 0 ;;  # -t <세션> <문자열> C-m
esac
exit 0
EOF
cat > "$STUB/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$STUB/sleep"   # 7초 대기 생략
chmod +x "$STUB/tmux" "$STUB/systemctl" "$STUB/sleep"

RWORK="$WORK/restart"; mkdir -p "$RWORK/scripts" "$RWORK/logs"
cp "$REPO/scripts/restart-nino.sh" "$REPO/scripts/catchup-hint.sh" "$RWORK/scripts/"
make_cli; seed_db 90 니노
SENT="$RWORK/sent.txt"; : > "$SENT"
PATH="$STUB:$PATH" SENT_FILE="$SENT" CATCHUP_BOT_DIR="$WORK" \
  CATCHUP_CLI="$WORK/bin/yaksu-history" YAKSU_HISTORY_DB="$DB" \
  bash "$RWORK/scripts/restart-nino.sh" >/dev/null 2>&1
sent="$(cat "$SENT")"

if printf '%s' "$sent" | grep -qE 'yaksu-history --after 9[0-9]m'; then
  ok "restart 경로에서도 90분 창이 나온다"
else
  bad "restart 경로에서도 90분 창이 나온다" '--after 9[0-9]m' "$sent"
fi
# 이 한 줄이 룬드가 잡은 결함의 가드다. 창이 5분으로 고정되면 여기서 빨개진다.
if printf '%s' "$sent" | grep -qE 'yaksu-history --after 5m'; then
  bad "창이 최소값에 고정되지 않는다" 'NOT --after 5m' "$sent"
else
  ok "창이 최소값(5m)에 고정되지 않는다"
fi
if [[ -f "$RWORK/logs/last-stop-utc" || -f "$WORK/logs/last-stop-utc" ]]; then
  bad "restart는 last-stop-utc를 더 쓰지 않는다" "파일 없음" "생성됨"
else
  ok "restart는 last-stop-utc를 더 쓰지 않는다(읽기 직전에 덮어쓰던 자리)"
fi

echo ""
echo "🟡 배선 — 호출부가 인자를 넘기는지 (테스트가 함수만 직접 부르면 배선은 검사 밖):"
# 룬드가 오늘 두 번 겪은 형태라 첫 일치만 보지 않고 **호출부 전부**를 센다.
# 주석 줄은 뺀다 — 첫 판에 주석의 "catchup-hint.sh 한 곳에서" 문구까지 호출부로 세서 헛빨강이 났다.
mapfile -t calls < <(grep -vE '^[[:space:]]*#' "$REPO/scripts/start-nino.sh" \
  | grep -oE '\$SCRIPT_DIR/catchup-hint\.sh"?( --[a-z-]+)*')
if [[ ${#calls[@]} -eq 0 ]]; then
  bad "start-nino가 catchup-hint를 부른다" "1건 이상" "0건"
else
  ok "start-nino의 catchup-hint 호출부 ${#calls[@]}건 확인"
  missing=0
  for c in "${calls[@]}"; do [[ "$c" == *--no-head* ]] || missing=$((missing + 1)); done
  [[ $missing -eq 0 ]] && ok "호출부 전부가 --no-head를 넘긴다" \
    || bad "호출부 전부가 --no-head를 넘긴다" "0건 누락" "${missing}건 누락: ${calls[*]}"
fi

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
