#!/usr/bin/env bash
# catchup-hint.sh 계약 테스트
#
# 왜 별 스크립트로 뽑았나:
#   "놓친 대화 따라잡기" 지시문이 start-nino.sh와 restart-nino.sh에 **각각 복사**돼 있었다.
#   같은 규칙의 사본 두 벌은 갈린다(discord-send 문법·yaksu-history 버전이 4개월씩 갈린 형태).
#
# 🔴 핵심 계약 셋:
#   ① 기준 시각을 모를 때 "0분"이나 "전체"로 넘어가지 않는다 — 기본 창 + **모른다는 사실**을 남긴다.
#      조용한 기본값은 실제 중단 시간처럼 읽힌다.
#   ② 오차는 **창이 넓어지는 방향으로만** 난다. 좁아지는 방향이 유일하게 유실이 나는 방향이다.
#   ③ 실패의 층을 뭉개지 않는다: 명령 실패 / null / 파싱 실패 / 시각 해석 실패는 각각 다른 문구다.
#
# 🔴 픽스처가 앵커를 직접 심지 않는다 (룬드 리뷰 M:vsdg의 본체):
#   1차 구현은 restart-nino.sh가 쓰는 logs/last-stop-utc를 앵커로 썼고 테스트가 그 파일을 직접 채웠다.
#   20개가 통과했는데 **실물은 창이 항상 5분 고정**이었다 — 파일을 채우는 주체가 시험 밖이었다.
#   그래서 아래 두 층을 같이 둔다:
#     · 스텁 케이스   — 실패 층 분리(실물로는 재현이 어렵다)
#     · 실물 케이스   — **설치된 진짜 CLI + fixture DB**로 앵커→창 계약을 끝까지 태운다
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
HINT="$REPO/scripts/catchup-hint.sh"
REAL_CLI="$HOME/.local/bin/yaksu-history"

pass=0; fail=0; skip=0
ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()  { echo "  ❌ $1"; echo "     want: $2"; echo "     got:  $3"; fail=$((fail + 1)); }
skipt(){ echo "  ⏭️  $1 (사유: $2)"; skip=$((skip + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/logs" "$WORK/bin" "$WORK/memory/discord-history"
DB="$WORK/messages.db"

# CLI 스텁 — last-seen 응답을 케이스마다 갈아끼운다
make_cli() {
  cat > "$WORK/bin/yaksu-history" <<STUB
#!/bin/bash
[[ "\$1" == "last-seen" ]] && printf '%s\n' '$1'
exit 0
STUB
  chmod +x "$WORK/bin/yaksu-history"
}
make_cli_at() {   # $1 = 분 전 → 그 시각을 last_seen으로 돌려주는 스텁
  make_cli "{\"last_seen\": \"$(date -u -d "$1 minutes ago" +%Y-%m-%dT%H:%M:%S.000Z)\", \"count\": 3, \"author\": \"니노\"}"
}
make_cli_fail() { # 구버전: last-seen 자체가 없다 → argparse 에러로 종료코드 2
  printf '#!/bin/bash\necho "usage: yaksu-history ..." >&2\nexit 2\n' > "$WORK/bin/yaksu-history"
  chmod +x "$WORK/bin/yaksu-history"
}
drop_cli() { rm -f "$WORK/bin/yaksu-history"; }

# 실물 스키마의 NOT NULL 컬럼을 갖춘 픽스처 DB. seed_db <분전> <작성자> [<분전> <작성자> ...]
seed_db() {
  rm -f "$DB"
  python3 - "$DB" "$@" <<'PY'
import sqlite3, sys, datetime as dt
db, args = sys.argv[1], sys.argv[2:]
c = sqlite3.connect(db)
c.execute("""CREATE TABLE messages (
    message_id TEXT PRIMARY KEY, type TEXT NOT NULL, channel_id TEXT NOT NULL,
    channel_name TEXT, thread_id TEXT, thread_name TEXT, author_id TEXT NOT NULL,
    author_name TEXT NOT NULL, content TEXT, reply_to_id TEXT, root_message_id TEXT,
    attachments TEXT, timestamp TEXT NOT NULL, message_hash TEXT, thread_hash TEXT)""")
now = dt.datetime.now(dt.timezone.utc)
for i in range(0, len(args), 2):
    mins, who = int(args[i]), args[i + 1]
    ts = (now - dt.timedelta(minutes=mins)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    c.execute("INSERT INTO messages (message_id,type,channel_id,channel_name,author_id,"
              "author_name,content,timestamp) VALUES (?,?,?,?,?,?,?,?)",
              (f"id{i}", "guild", "1", "충재-다용도", "a1", who, "x", ts))
c.commit()
PY
}

env_run() {
  CATCHUP_BOT_DIR="$WORK" CATCHUP_CLI="${CLI_OVERRIDE:-$WORK/bin/yaksu-history}" \
  YAKSU_HISTORY_DB="${DB_OVERRIDE-}" bash "$HINT" "$@" 2>&1
}
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
# 🔴 **명령 부분만** 본다. 지시문은 명령 + 설명 산문이 한 줄에 같이 있어서,
#    전체를 grep하면 설명문이 걸린다 — 오늘 룬드가 밟고(`--limit` 언급) 내가 또 밟은 형태다:
#      "…--limit**도 없을 수 있으니**…"        → `--limit` 금지 가드가 헛빨강
#      "…내 발화 기록이 없어서**가 아니야**…"  → 부정문을 긍정으로 읽음
#    명령은 "돌려서" 앞까지다. 가드는 무엇을 보는가의 범위부터 좁힌다.
cmd_run_not() {
  local desc="$1" unwanted="$2"; shift 2
  local cmd; cmd=$(env_run "$@" | sed 's/ 돌려서.*//')
  if printf '%s' "$cmd" | grep -qE "$unwanted"; then bad "$desc" "명령부에 NOT $unwanted" "$cmd"; else ok "$desc"; fi
}

echo "앵커(내 마지막 발화) → 경과 분으로 창을 잡는다:"
make_cli_at 90
run "90분 전 발화 → --after 9[0-9]m"          'yaksu-history --after 9[0-9]m'
run "건수 상한(--limit)이 항상 붙는다"          '\-\-limit 200'
run_not "정상 경로엔 경고 문구가 없다"          '⚠️'
make_cli_at 180
run "3시간 전 발화 → 18[0-9]m"                'yaksu-history --after 18[0-9]m'

echo ""
echo "경계 — 너무 짧거나 너무 긴 값은 클램프:"
make_cli_at 0
run "방금 발화(0분) → 최소 5m 이상"            'yaksu-history --after (5|[6-9]|1[0-9])m'
make_cli_at 14400
run "10일 전 → 48시간(2880m)으로 클램프"       'yaksu-history --after 2880m'
run "클램프하면 그 사실을 지시문에 남긴다"      '(잘랐|클램프|48시간)'

echo ""
echo "🔴 실패의 층을 뭉개지 않는다 — 네 갈래가 각자 다른 문구를 갖는다:"
make_cli_fail
run "① 명령 실패 → 구버전일 수 있다고 말한다"   '(구버전|실행하지 못했)'
run_not "① 을 null 경로 문구로 말하지 않는다"   'last_seen이 null'
# ⚠️ 구버전이라고 판정한 자리에서 신규 옵션을 주면 그 명령 자체가 실패한다(룬드 M:w10f의 대칭)
cmd_run_not "🔴 ① 경로엔 --limit 을 주지 않는다" '\-\-limit'
run "① 에서도 따라잡기는 진행시킨다"            'yaksu-history --after [0-9]+m'

make_cli '{"last_seen": null, "count": 0, "author": "니노"}'
run "② null → 내 발화 기록이 없다고 말한다"     'null'
run "② 는 기본 창 + --limit"                   'after 120m --limit 200'

make_cli '{"lastSeen": "2026-07-26T09:30:00Z"}'
run "③ 필드명이 바뀌면 '해석하지 못했다'"        '(해석하지 못했|출력 형식)'
run_not "③ 을 '발화 기록 없음'으로 말하지 않는다" '발화 기록이 없어서'

make_cli '{"last_seen": "어제쯤", "count": 3}'
run "④ 시각을 못 읽으면 그렇게 말한다"           '해석하지 못'
make_cli '{"last_seen": "2026-07-27T00:00:00", "count": 3}'
run "④ tz 없는 시각을 UTC로 가정하지 않는다"     '해석하지 못'

echo ""
echo "CLI가 없을 때 — jsonl 폴백 (조용히 실패하지 않는다):"
drop_cli
TODAY=$(TZ=Asia/Seoul date +%Y-%m-%d); : > "$WORK/memory/discord-history/$TODAY.jsonl"
run "CLI 부재 → jsonl 경로 지시"               "memory/discord-history/$TODAY.jsonl"
run_not "CLI 부재면 CLI 명령을 주지 않는다"      'yaksu-history --after'
run "CLI가 왜 없는지도 확인하라고 한다"          '(CLI 부재|조회 정본)'
rm -f "$WORK/memory/discord-history/"*.jsonl
run "CLI도 jsonl도 없으면 current-tasks 폴백"   'current-tasks.md'

echo ""
echo "--reboot / --no-head 변형:"
make_cli_at 30
run "--reboot → 재부팅 문구"                   '재부팅'                --reboot
run "--reboot여도 따라잡기 명령은 그대로"       'yaksu-history --after'  --reboot
: > "$WORK/logs/pending-restart-notify.txt"
run "--reboot + 알림파일 → 처리 지시 포함"      'pending-restart-notify' --reboot
rm -f "$WORK/logs/pending-restart-notify.txt"
run_not "알림파일 없으면 그 문구 없음"          'pending-restart-notify' --reboot
run_not "플래그 없으면 재부팅 문구 없음"        '재부팅'
run_not "--no-head면 '재시작됐어' 없음"         '재시작됐어'             --no-head
run_not "--no-head는 --reboot보다 우선"         '재부팅'                 --no-head --reboot
run "--no-head여도 따라잡기 명령은 그대로"      'yaksu-history --after'  --no-head

echo ""
echo "출력 형태:"
run "UTC 표기를 알려준다(KST 오해 방지)"        '(UTC|\+9)'
lines=$(env_run | wc -l)
[[ "$lines" -eq 1 ]] && ok "정확히 1줄(tmux send-keys에 그대로 들어감)" || bad "정확히 1줄" "1" "$lines"

echo ""
echo "🔴 실물 — 설치된 진짜 CLI + fixture DB로 앵커→창을 끝까지 태운다:"
# 스텁은 "내가 기대한 출력"을 되돌려줄 뿐이라 CLI 쪽 계약이 바뀌면 통과한 채로 틀린다.
# (오늘 실측: `--db`를 서브커맨드 **앞**에 주면 조용히 무시되고 실 DB 답이 온다 — 이 케이스가 그걸 잡는다)
if [[ -x "$REAL_CLI" ]] && "$REAL_CLI" last-seen --help >/dev/null 2>&1; then
  seed_db 90 니노 1 Tim
  CLI_OVERRIDE="$REAL_CLI" DB_OVERRIDE="$DB" run "실물 CLI로도 90분 창이 나온다" 'yaksu-history --after 9[0-9]m'
  # 남의 메시지가 1분 전이어도 앵커는 내 발화여야 한다(전체 MAX면 창이 상시 0)
  CLI_OVERRIDE="$REAL_CLI" DB_OVERRIDE="$DB" run_not "남의 최신 메시지에 끌려가지 않는다" 'after (5|[1-9])m'
  seed_db 30 Tim 45 룬드
  CLI_OVERRIDE="$REAL_CLI" DB_OVERRIDE="$DB" run "내 발화가 없으면 null 경로로 떨어진다" 'null'
else
  skipt "실물 CLI 케이스 3건" "$REAL_CLI 없음 또는 last-seen 미지원(구버전)"
fi

echo ""
echo "🔴 통합 — restart-nino.sh를 실제로 태워서 생산자-소비자 계약을 잰다:"
# 1차 구현이 여기서 무너졌다: 픽스처가 앵커를 직접 심으면 restart가 앵커를 어떻게 만드는지 아무도 안 잰다.
STUB="$WORK/stub"; mkdir -p "$STUB"
cat > "$STUB/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  has-session) exit 0 ;;                                      # 세션 있음 = 재시작 경로
  send-keys)   printf '%s\n' "$4" >> "$SENT_FILE"; exit 0 ;;  # -t <세션> <문자열> C-m
esac
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$STUB/systemctl"
printf '#!/bin/bash\nexit 0\n' > "$STUB/sleep"   # 7초 대기 생략
chmod +x "$STUB/tmux" "$STUB/systemctl" "$STUB/sleep"

RWORK="$WORK/restart"; mkdir -p "$RWORK/scripts" "$RWORK/logs"
cp "$REPO/scripts/restart-nino.sh" "$REPO/scripts/catchup-hint.sh" "$RWORK/scripts/"
make_cli_at 90
SENT="$RWORK/sent.txt"; : > "$SENT"
PATH="$STUB:$PATH" SENT_FILE="$SENT" CATCHUP_BOT_DIR="$WORK" \
  CATCHUP_CLI="$WORK/bin/yaksu-history" \
  bash "$RWORK/scripts/restart-nino.sh" >/dev/null 2>&1
sent="$(cat "$SENT")"

if printf '%s' "$sent" | grep -qE 'yaksu-history --after 9[0-9]m'; then
  ok "restart 경로에서도 90분 창이 나온다"
else
  bad "restart 경로에서도 90분 창이 나온다" '--after 9[0-9]m' "$sent"
fi
# 룬드가 잡은 결함의 가드: 창이 최소값에 고정되면 여기서 빨개진다
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
echo "🔴 앵커 오염 — cron이 니노 이름으로 말해도 창이 좁아지지 않는다 (Tim M:uv86):"
# 실측된 형태: 룬드 실발화 2026-07-28T17:36:27Z인데 재시작 알림 03:25:47Z가 앵커가 돼
# 9시간 50분이 창 밖으로 밀렸다. 니노는 cron 7개가 같은 짓을 하므로 더 자주 난다.
HB="$WORK/logs/session-heartbeat-utc"
HOOK="$REPO/hooks/session-heartbeat.sh"
set_hb()  { date -u -d "$1 minutes ago" +%Y-%m-%dT%H:%M:%S.000Z > "$HB"; }
drop_hb() { rm -f "$HB"; }

# ① 쓰는 쪽을 실제로 태운다 — 픽스처만 심으면 "파일을 채우는 주체가 시험 밖"이 된다(위 1차 실패 그대로)
drop_hb
HEARTBEAT_BOT_DIR="$WORK" bash "$HOOK"
if [[ -s "$HB" ]] && grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$' "$HB"; then
  ok "훅이 파싱 가능한 ...Z 시각을 쓴다"
else
  bad "훅이 파싱 가능한 ...Z 시각을 쓴다" 'YYYY-MM-DDThh:mm:ss.mmmZ' "$(cat "$HB" 2>/dev/null || echo '파일 없음')"
fi
make_cli_at 2
run "훅 직후 + 발화도 최신 → 최소창" 'after 5m'

# ② 🔴 이 PR의 본체: 세션은 200분 전에 멈췄고 cron이 2분 전에 말했다
set_hb 200; make_cli_at 2
run     "cron 오염돼도 하트비트(200분)를 쓴다" 'after (19[5-9]|20[0-5])m'
run_not "cron이 낸 2분에 끌려가지 않는다"      'after 5m'
run     "왜 그 창인지 세션에게 말해준다"        '하트비트'

# ③ 반대 방향 — 세션은 도는데 조용했다: 더 오래된 쪽(발화 300분)이 이긴다
set_hb 1; make_cli_at 300
run     "하트비트가 최신이어도 더 오래된 발화를 쓴다" 'after (29[5-9]|30[0-5])m'
run_not "하트비트가 창을 좁히지 못한다"               'after 5m'

# ④ 대조군(음성) — 하트비트가 없으면 이 PR 이전과 똑같이 동작한다
drop_hb; make_cli_at 90
run     "하트비트 없으면 발화 앵커(90분) 그대로" 'after 9[0-9]m'
run_not "하트비트 없다고 기본창으로 떨어지지 않는다" 'after 120m'

# ⑤ 망가진 하트비트 → 조용히 쓰지 않고 CLI로 떨어진다
printf 'garbage\n' > "$HB"; make_cli_at 90
run "깨진 하트비트는 무시하고 발화 앵커를 쓴다" 'after 9[0-9]m'
: > "$HB"
run "빈 하트비트도 무시한다"                    'after 9[0-9]m'

# ⑥ 🔴 미래 시각(시계 어긋남) — 창이 좁아지는 유일한 경로라 통째로 버린다
date -u -d "60 minutes" +%Y-%m-%dT%H:%M:%S.000Z > "$HB"; make_cli_at 90
run     "미래 하트비트를 버리고 발화 앵커를 쓴다" 'after 9[0-9]m'
run_not "미래 하트비트가 창을 좁히지 못한다"      'after 5m'
# 🔴 변이시험이 찾아낸 구멍: CLI까지 죽으면 hb_rescue가 clamp(음수)=5분으로 창을 접는다.
#    위 케이스는 CLI가 살아 있어서 max() 선택이 음수를 걸러줬고, 그래서 가드가 죽어도 안 빨개졌다.
date -u -d "60 minutes" +%Y-%m-%dT%H:%M:%S.000Z > "$HB"; make_cli_fail
run_not "미래 하트비트 + CLI실패 → 5분으로 접히지 않는다" 'after 5m'
run     "그 경우 기본창으로 안전하게 떨어진다"            'after 120m'

# ⑦ 상한은 하트비트 쪽에도 걸린다
set_hb 5000; make_cli_at 2
run "하트비트도 48시간에서 잘린다"   'after 2880m'
run "잘랐다는 사실을 남긴다"         '(48시간|잘랐)'

# ⑧ CLI가 죽어도 하트비트가 있으면 기본창(추측)으로 떨어지지 않는다
set_hb 150; make_cli_fail
run     "CLI 실패 + 하트비트 → 150분 창" 'after (14[5-9]|15[0-5])m'
run_not "CLI 실패해도 기본 120분으로 안 떨어진다" 'after 120m'
run     "CLI가 왜 실패했는지도 같이 말한다" '(종료코드|구버전)'
drop_hb

echo ""
echo "🔴 회귀 잠금 — 하트비트를 쓰는 주체가 '재시작하는 쪽'이면 안 된다:"
# 1차 구현(logs/last-stop-utc)이 정확히 이걸로 죽었다: restart가 맨 위에서 now를 쓰고
# 7초 뒤 읽어 경과가 항상 0 → 창이 5분 고정. 파일 이름만 바꾼 같은 함정을 여기서 잠근다.
writers=$(grep -lE 'session-heartbeat-utc' "$REPO/scripts/restart-nino.sh" "$REPO/scripts/start-nino.sh" 2>/dev/null | wc -l)
[[ "$writers" -eq 0 ]] && ok "restart/start-nino는 하트비트를 쓰지 않는다" \
  || bad "restart/start-nino는 하트비트를 쓰지 않는다" "0개 파일" "${writers}개 파일이 언급"
# 실물 통합: restart를 태운 뒤에도 하트비트가 생기면 안 된다
[[ ! -f "$RWORK/logs/session-heartbeat-utc" ]] && ok "restart 실행이 하트비트를 만들지 않는다" \
  || bad "restart 실행이 하트비트를 만들지 않는다" "파일 없음" "생성됨"

echo ""
echo "🔴 배선 — Stop 훅이 등록돼 있나 (등록 안 된 훅은 하트비트를 영영 안 남긴다):"
# 파일만 만들고 settings.json에 안 걸면 이 PR 전체가 무효다. 그래도 catchup-hint는
# "하트비트 없음" 폴백으로 조용히 예전처럼 동작하므로 **아무도 안 알려준다** — 그래서 잠근다.
if [[ -x "$REPO/hooks/session-heartbeat.sh" ]]; then
  ok "훅 파일이 실행 가능하다"
else
  bad "훅 파일이 실행 가능하다" "chmod +x" "실행 권한 없음"
fi
hooked=$(python3 - "$REPO/.claude/settings.json" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); raise SystemExit(0)
n = sum(1 for g in d.get("hooks", {}).get("Stop", [])
          for h in g.get("hooks", []) if "session-heartbeat" in h.get("command", ""))
print(n)
PYEOF
)
[[ "$hooked" -ge 1 ]] && ok "settings.json Stop 훅에 session-heartbeat가 걸려 있다" \
  || bad "settings.json Stop 훅에 session-heartbeat가 걸려 있다" "1건 이상" "${hooked}건"

echo ""
echo "🟡 배선 — 호출부가 인자를 넘기는지 (테스트가 스크립트만 직접 부르면 배선은 검사 밖):"
# 오늘 양봇이 대칭으로 밟은 함정이라 **주석을 걷고 호출부 전부**를 센다.
# (룬드는 산문의 --limit 을, 나는 주석의 파일명을 코드로 셌다 → 검사 대상 범위부터 좁힌다)
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
echo "결과: $pass pass, $fail fail, $skip skip"
[[ $fail -eq 0 ]]
