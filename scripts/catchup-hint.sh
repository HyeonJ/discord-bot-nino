#!/usr/bin/env bash
# catchup-hint.sh — 세션 시작·재시작 때 "놓친 대화 따라잡기" 지시문 한 줄을 만든다.
#
# 왜 별 스크립트인가:
#   같은 지시문이 start-nino.sh와 restart-nino.sh에 **사본 두 벌**로 있었다. 한쪽만 고치면 드리프트가 난다.
#   (2026-07-27: discord-send 문법·yaksu-history 버전이 정확히 그 형태로 4개월씩 갈렸다)
#
# 왜 jsonl 경로 주입에서 CLI로 바꾸나 (Tim 지시 M:qf4k):
#   조회 정본이 yaksu-history CLI다. jsonl 경로를 주입하면 세션이 파일을 직접 읽어야 하고,
#   그 파일에 구멍이 있어도(2026-07-26 07~10시+09 실측 0행) 알 방법이 없다.
#
# 🔴 창의 앵커 = **"니노가 마지막으로 말한 시각"** (DB). 룬드 리뷰 M:vsdg로 두 번 고친 자리다.
#   ① 처음엔 restart가 쓰는 logs/last-stop-utc를 썼다 → restart가 **맨 위에서 now를 쓰고 7초 뒤 읽어서**
#      경과가 항상 0 → 창이 5분에 고정됐다(경과 분기 도달 불가). 부팅 경로에선 며칠 전 값이 남아 반대로 틀렸다.
#   ② 룬드 대안 MAX(timestamp) 전체도 무너진다 — restart가 **relay를 먼저 살리고**(sleep 5) 지시문을 만들어서,
#      그 5초에 메시지 한 건만 와도 앵커가 "방금"이 된다(실측 0분 전). 둘 다 **창이 좁아지는** 방향의 오류다.
#   ③ 우리가 찾는 건 relay가 죽은 시각이 아니라 **세션이 반응을 멈춘 시각**이다. 니노 발화가 그 대리값이다:
#        깨끗한 재시작 → 방금 발화 → 창 작음(실제로 놓친 게 없다)
#        얼어 있었음   → 몇 시간 전 → 창 넓음(그동안 못 처리했다)
#        조용했을 뿐   → 창이 넓어짐 → 좀 더 읽는다(무해 — 안전한 방향)
#
# 시각 표기: 접미사 없는 시각을 쓰지 않는다(`14:55+09` / `05:55Z`). KST/UTC를 하루에 세 번 뒤집은 뒤 합의한 규칙.
set -uo pipefail

BOT_DIR="${CATCHUP_BOT_DIR:-/home/bpx27/discord-bot-nino}"
CLI="${CATCHUP_CLI:-$HOME/.local/bin/yaksu-history}"
DB="${YAKSU_HISTORY_DB:-$HOME/.local/share/yaksu-history/messages.db}"
SELF="${CATCHUP_SELF:-니노}"
NOTIFY="$BOT_DIR/logs/pending-restart-notify.txt"

MIN_WINDOW=5        # 방금까지 말하고 있었어도 최소 5분은 훑는다(경계 메시지 유실 방지)
MAX_WINDOW=2880     # 48시간. 그보다 길면 따라잡기가 아니라 별도 복구 작업이다
DEFAULT_WINDOW=120  # 앵커를 못 구할 때

# 🔴 상한은 시간만으로는 안 걸린다 — **건수**에도 걸어야 한다 (룬드 지적 M:ssvm + 내 DB 실측 7/27):
#      2시간 창  161건  본문 108KB  ≈49k 토큰
#     24시간 창  515건  본문 304KB  ≈138k
#     48시간 창  627건  본문 367KB  ≈167k   ← MAX_WINDOW 안이지만 세션이 압축으로 날아간다
#   앵커는 "언제부터"의 정확도이고 이건 "얼마나 많이"의 상한이라 **층이 다르다.**
#   자를 때 버려지는 건 **가장 오래 기다린 메시지**라, 잘랐다는 사실만으로는 부족하고
#   회수 경로(앞 구간을 어떻게 읽는지)를 지시문에 같이 준다.
MAX_ROWS="${CATCHUP_MAX_ROWS:-200}"

reboot=0; nohead=0
for a in "$@"; do
    case "$a" in
        --reboot)  reboot=1 ;;
        --no-head) nohead=1 ;;   # 호출부가 자기 앞머리를 갖는 경우(start-nino) 문장 중복 방지
    esac
done

# ── 앵커(니노 마지막 발화) → 경과 분 → 건수 상한까지 한 번에 ────────────
# ⚠️ DB를 직접 여는 것은 **임시 구현**이다. 조회 정본은 CLI이고, 스키마 지식이 CLI 밖으로
#    한 벌 더 나가면 컬럼명이 바뀔 때 CLI만 따라간다(룬드 지적 M:ssvm — 오늘 본 드리프트 형태).
#    TODO(#4 머지 후): 이 블록 전체를 `yaksu-history last-seen --author 니노` + `--limit`로 교체.
#    지금은 CLI에 그 두 기능이 없어서(설치본 `--help`에 `last-seen`·`--limit` 없음) 직접 조회한다.
anchor="$(python3 - "$DB" "$SELF" "$MIN_WINDOW" "$MAX_WINDOW" "$DEFAULT_WINDOW" "$MAX_ROWS" <<'PY' 2>/dev/null
import sqlite3, sys, datetime as dt
db, self_name = sys.argv[1], sys.argv[2]
min_w, max_w, default_w, max_rows = (int(x) for x in sys.argv[3:7])
now = dt.datetime.now(dt.timezone.utc)

def minutes_since(ts):
    t = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    if t.tzinfo is None:                 # tz 없는 값은 UTC로 가정하지 않는다
        raise ValueError(ts)
    return int((now - t).total_seconds() // 60)

try:
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    row = c.execute(
        "SELECT MAX(timestamp) FROM messages WHERE author_name = ?", (self_name,)
    ).fetchone()
    try:
        elapsed = minutes_since(row[0]) if row and row[0] else None
    except ValueError:
        elapsed = None

    if elapsed is None:
        window, clamp = default_w, "noanchor"
    elif elapsed > max_w:
        window, clamp = max_w, "max"
    elif elapsed < min_w:
        window, clamp = min_w, "min"
    else:
        window, clamp = elapsed, "ok"

    # 건수 상한: 창 안의 건수를 세고, 넘치면 **N번째 최근 메시지 시각까지** 창을 좁힌다.
    cutoff = (now - dt.timedelta(minutes=window)).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = c.execute(
        "SELECT COUNT(*) FROM messages WHERE timestamp >= ?", (cutoff,)
    ).fetchone()[0]
    orig_window, orig_rows = window, rows
    if rows > max_rows:
        nth = c.execute(
            "SELECT timestamp FROM messages ORDER BY timestamp DESC LIMIT 1 OFFSET ?",
            (max_rows - 1,),
        ).fetchone()
        if nth and nth[0]:
            try:
                window = max(minutes_since(nth[0]), min_w)
                rows, clamp = max_rows, "rows"
            except ValueError:
                pass
except sqlite3.Error:
    raise SystemExit(1)

print(f"{window} {clamp} {elapsed if elapsed is not None else -1} {orig_window} {orig_rows}")
PY
)"

window=""; note=""
read -r window clamp elapsed orig_window orig_rows <<< "$anchor"
if [[ ! "$window" =~ ^[0-9]+$ ]]; then
    # DB 자체를 못 열었다. 여기서 "모른다"를 말하지 않으면 기본 창이 실제 중단 시간처럼 읽힌다.
    window=$DEFAULT_WINDOW
    note=" 내 마지막 발화 시각을 못 구해서(DB 조회 실패) 기본 ${DEFAULT_WINDOW}분으로 잡았어 — 빠진 게 있어 보이면 창을 넓혀서 다시 봐."
else
    case "$clamp" in
        noanchor)
            note=" 내 마지막 발화 시각을 못 구해서(내 발화 기록 없음) 기본 ${DEFAULT_WINDOW}분으로 잡았어 — 빠진 게 있어 보이면 창을 넓혀서 다시 봐." ;;
        max)
            note=" 내 마지막 발화가 ${elapsed}분 전인데 48시간으로 잘랐어 — 그 앞 구간은 따라잡기가 아니라 별도 복구가 필요해." ;;
        rows)
            # 잘린 쪽이 **가장 오래 기다린 메시지**라 회수 경로를 같이 준다.
            note=" 원래 창은 ${orig_window}분(${orig_rows}건)인데 한 번에 읽을 상한(${MAX_ROWS}건)에 맞춰 ${window}분으로 좁혔어 — 앞 구간(${orig_window}분 전~${window}분 전)은 아직 안 본 거야. 필요하면 --after ${orig_window}m --channel <채널명>으로 채널을 나눠서 그 구간을 읽어." ;;
    esac
fi

# ── 앞머리 ────────────────────────────────────────────────
if (( nohead )); then
    head_msg=""
elif (( reboot )) && [[ -f "$NOTIFY" ]]; then
    head_msg="재부팅했어. logs/pending-restart-notify.txt 있으니까 처리해줘. "
elif (( reboot )); then
    head_msg="재부팅했어. "
else
    head_msg="재시작됐어. "
fi

# ── 따라잡기 수단: CLI → jsonl → current-tasks 순서로 폴백 ──
# 폴백이 있는 이유: CLI가 없을 때 "yaksu-history 돌려줘"를 주면 세션이 실패한 명령을 보고 헤맨다.
if [[ -x "$CLI" ]]; then
    printf '%s\n' "${head_msg}$CLI --after ${window}m 돌려서 못 봤던 대화 파악해줘 (출력 timestamp는 UTC니까 KST는 +9).${note}"
    exit 0
fi

TODAY="$(TZ=Asia/Seoul date +%Y-%m-%d)"
HISTORY_FILE="$BOT_DIR/memory/discord-history/$TODAY.jsonl"
if [[ -f "$HISTORY_FILE" ]]; then
    printf '%s\n' "${head_msg}조회 CLI가 없어서($CLI 실행 불가) memory/discord-history/$TODAY.jsonl 읽고 못 봤던 대화 파악해줘. CLI 부재도 같이 확인해줘 — 조회 정본이 빠진 상태야."
else
    printf '%s\n' "${head_msg}조회 CLI도 오늘 jsonl도 없어서 따라잡을 소스가 없어. memory/current-tasks.md 읽고 이어서 진행하고, 기록 경로가 왜 비었는지 확인해줘."
fi
