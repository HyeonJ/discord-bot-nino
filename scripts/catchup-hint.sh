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
# 🔴 창의 앵커 = **"니노가 마지막으로 말한 시각"**. 룬드 리뷰 M:vsdg로 두 번 고친 자리다.
#   ① 처음엔 restart가 쓰는 logs/last-stop-utc를 썼다 → restart가 **맨 위에서 now를 쓰고 7초 뒤 읽어서**
#      경과가 항상 0 → 창이 5분에 고정됐다(경과 분기 도달 불가). 부팅 경로에선 며칠 전 값이 남아 반대로 틀렸다.
#   ② 룬드 대안 MAX(timestamp) 전체도 무너진다 — relay는 **세션과 독립 프로세스**라 세션이 죽어도 적재가
#      계속된다(룬드 실측: 전체 MAX는 늘 "지금"). 둘 다 **창이 좁아지는** 방향의 오류다.
#   ③ 우리가 찾는 건 relay가 죽은 시각이 아니라 **세션이 반응을 멈춘 시각**이다. 니노 발화가 그 대리값이다:
#        깨끗한 재시작 → 방금 발화 → 창 작음(실제로 놓친 게 없다)
#        얼어 있었음   → 몇 시간 전 → 창 넓음(그동안 못 처리했다)
#        조용했을 뿐   → 창이 넓어짐 → 좀 더 읽는다(무해 — 안전한 방향)
#   ④ 🔴 **그 대리값을 cron이 위조한다** (Tim 지시 2026-07-29 M:uv86). 니노 이름으로 말하는 건
#      세션만이 아니다 — cron 7개(watchdog 2분·check-auth 5분·usage 30분·core-drift·memory-lint·
#      alarm fire·health-checker)가 **세션이 죽은 동안에도 발화**한다. 그러면 last-seen이 "지금"이 되고
#      **창이 0으로 수렴한다.** 워치독 복구 경로는 "재시작 알림 → 재시작"이라 이 오염이 확정적이다.
#      실측(룬드 2026-07-29): 실발화 2026-07-28T17:36:27Z인데 재시작 알림 03:25:47Z가 앵커가 돼
#      **9시간 50분이 통째로 창 밖으로 밀렸다.**
#      ⇒ 해법: **세션만이 쓸 수 있는 신호**를 하나 더 둔다 = Stop 훅이 남기는 hooks/session-heartbeat.sh.
#
# 🔑 두 앵커 중 **더 오래된 쪽**을 쓴다 (min(시각) = max(경과분)).
#   "하트비트가 언제나 이긴다"가 아니다 — 그러면 하트비트가 틀리는 날 창이 좁아진다.
#   더 오래된 쪽을 고르면 오차가 **항상 계약 ②(넓어지는 방향)** 로만 난다:
#     cron 오염(하트비트 오래됨·발화 최신)      → 하트비트 승 → 창 넓음 ✅ 이 PR이 고치는 것
#     세션은 도는데 조용했음(하트비트 최신)      → 발화 승   → 창 넓음(무해, 좀 더 읽는다)
#     Stop 훅이 401에서도 도는 경우(미확인)      → 발화 승   → 좁아지지 않는다 ✅ 미검증 구간을 덮는다
#   ⚠️ 마지막 줄이 이 선택의 진짜 이유다. 401 중에 Stop 훅이 도는지 나는 **재보지 못했다**
#      (룬드 기계에서 일어난 일이고 재현 수단이 없다). "이긴다" 설계였으면 그 미검증이 유실이 된다.
#
# 🔴 앵커 조회는 **CLI가 정본**이다 (yaksu-history#4 머지·설치 후 전환, 2026-07-27).
#   이전 구현은 sqlite를 직접 열어 `MAX(timestamp) WHERE author_name=...`를 돌렸다. 돌아가긴 했지만
#   **스키마 지식이 CLI 밖으로 한 벌 더 나간** 상태였다 — 컬럼명이 바뀌면 CLI만 따라가고 이 스크립트는
#   조용히 틀린 답을 낸다(룬드 지적 M:ssvm, 오늘 본 드리프트 형태 그대로). 지금은 `last-seen --author`.
#
# 시각 표기: 접미사 없는 시각을 쓰지 않는다(`14:55+09` / `05:55Z`). KST/UTC를 하루에 세 번 뒤집은 뒤 합의한 규칙.
set -uo pipefail

BOT_DIR="${CATCHUP_BOT_DIR:-/home/bpx27/discord-bot-nino}"
CLI="${CATCHUP_CLI:-$HOME/.local/bin/yaksu-history}"
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
#   CLI가 자르면 생략 건수와 `--until` 경계를 stderr에 남긴다(#4) — 조용한 절단이 아니다.
#   🔸 건수도 근사다: 같은 2시간에 룬드 159건≈35k vs 니노 161건≈49k(본문 길이 분포 차이).
#      200건이 250KB를 넘기는 날이 오면 본문 길이 기준으로 옮긴다(양봇 합의).
LIMIT="${CATCHUP_LIMIT:-200}"

reboot=0; nohead=0
for a in "$@"; do
    case "$a" in
        --reboot)  reboot=1 ;;
        --no-head) nohead=1 ;;   # 호출부가 자기 앞머리를 갖는 경우(start-nino) 문장 중복 방지
    esac
done

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

emit() { printf '%s\n' "${head_msg}$1"; exit 0; }

clamp() {   # 경과분 → 창. MIN/MAX 규칙 한 자리 (앵커가 둘이라 사본이 생길 자리다)
    local e="$1"
    if   (( e > MAX_WINDOW )); then printf '%s' "$MAX_WINDOW"
    elif (( e < MIN_WINDOW )); then printf '%s' "$MIN_WINDOW"
    else printf '%s' "$e"; fi
}

# ── 앵커 A: 세션 하트비트 (cron이 위조할 수 없는 쪽) ────────
# 🔴 음수(미래 시각)는 통째로 버린다. 시계 어긋남으로 창이 **좁아지는** 유일한 경로라서다.
#    버리면 CLI 쪽만 남아 이 PR 이전 동작으로 안전하게 떨어진다.
HEARTBEAT="$BOT_DIR/logs/session-heartbeat-utc"
hb_elapsed=""
if [[ -r "$HEARTBEAT" ]]; then
    hb_elapsed="$(python3 -c '
import sys, datetime as dt
raw = sys.argv[1].strip()
t = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
if t.tzinfo is None:
    raise SystemExit(1)
print(int((dt.datetime.now(dt.timezone.utc) - t).total_seconds() // 60))
' "$(head -n1 "$HEARTBEAT" 2>/dev/null)" 2>/dev/null)"
    [[ "$hb_elapsed" =~ ^[0-9]+$ ]] || hb_elapsed=""
fi

# CLI 쪽 앵커를 못 구한 자리에서 하트비트가 있으면 그걸 쓴다 — 기본창(추측)보다 정확하다.
hb_rescue() {   # $1 = CLI 쪽 실패 사유
    [[ -n "$hb_elapsed" ]] || return 0
    emit "$CLI --after $(clamp "$hb_elapsed")m --limit $LIMIT 돌려서 못 봤던 대화 파악해줘. 창은 **세션 하트비트**(logs/session-heartbeat-utc = 내가 마지막으로 턴을 끝낸 시각, ${hb_elapsed}분 전)에서 잡았어 — 기본값 추측이 아니야. ⚠️ 다만 $1"
}

# ── 폴백 2·3순위: CLI가 없을 때 ────────────────────────────
# 사유를 안 붙이면 세션이 "yaksu-history 돌려라"를 받고 실패한 명령 앞에서 헤맨다.
if [[ ! -x "$CLI" ]]; then
    TODAY="$(TZ=Asia/Seoul date +%Y-%m-%d)"
    HISTORY_FILE="$BOT_DIR/memory/discord-history/$TODAY.jsonl"
    if [[ -f "$HISTORY_FILE" ]]; then
        emit "조회 CLI가 없어서($CLI 실행 불가) memory/discord-history/$TODAY.jsonl 읽고 못 봤던 대화 파악해줘. CLI 부재도 같이 확인해줘 — 조회 정본이 빠진 상태야."
    fi
    emit "조회 CLI도 오늘 jsonl도 없어서 따라잡을 소스가 없어. memory/current-tasks.md 읽고 이어서 진행하고, 기록 경로가 왜 비었는지 확인해줘."
fi

# ── 앵커 조회 ──────────────────────────────────────────────
# ⚠️ `--db`는 여기서 **서브커맨드 뒤**에 둔다 — yaksu-history#7 이전 설치본에서는 앞에 두면
#    파싱은 되는데 조용히 무시되고 기본 DB 답이 돌아온다(2026-07-27 실측: fixture 1건 대신 실 DB 10,085건).
#    원인은 서브파서의 `default=`가 전역이 넣은 값을 덮어쓰는 argparse 동작이고, #7(`3a95212`)이
#    `default=argparse.SUPPRESS`로 고쳐 **순서 무관**해졌다. 지금 설치본은 4가지 위치 전부 실측 확인됨.
#    ⇒ 그래도 뒤에 두는 이유: 이 스크립트가 구버전 설치본에서도 돌 수 있고, 그 경우 실패가
#      에러가 아니라 **조용한 오답**이라 알아챌 수 없다(안전한 쪽으로 고정).
# 🔴 `"${db_opt[@]}"` 로 쓰면 **bash 3.2 + set -u 에서 죽는다**(빈 배열 확장이 unbound).
#    4.4 에서 빈 확장으로 바뀌었고 니노 기계는 5.x 라 안 걸린다 — 룬드 맥(3.2)에서만 터진다.
#    직접 피해는 없지만(이 스크립트는 니노에서만 돈다) **룬드가 내 PR 을 검증하지 못하게** 된다.
#    `${a[@]:-}` 는 빈 문자열 인자를 하나 넣어버리므로 안 된다 — `${a[@]+"${a[@]}"}` 가 정본.
#    ⚠️ 이 함정은 [[ref_bash_portability_32]] 19행에 이미 적혀 있었는데 안 보고 지나갔다.
db_opt=()
[[ -n "${YAKSU_HISTORY_DB:-}" ]] && db_opt=(--db "$YAKSU_HISTORY_DB")
last_json="$("$CLI" last-seen --author "$SELF" "${db_opt[@]+"${db_opt[@]}"}" 2>/dev/null)"; cli_rc=$?

# 값 / null / 파싱실패를 **한 번의 json 파싱**으로 가른다.
# 추출과 null 판정을 각각 정규식으로 하면 "파싱 실패" 판정 자체가 파싱에 의존한다(룬드와 상호 리뷰).
parsed="$(printf '%s' "$last_json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("PARSE_FAIL"); raise SystemExit(0)
if not isinstance(d, dict) or "last_seen" not in d:
    print("PARSE_FAIL")
elif d["last_seen"] is None:
    print("NULL")
else:
    print("OK " + str(d["last_seen"]))
' 2>/dev/null || printf 'PARSE_FAIL')"

# ⚠️ 구버전 판정 경로에서는 `--limit`을 주지 않는다. `--limit`은 #4 신규라
#    "구버전일 수 있어"라고 말한 그 자리에서 구버전이 못 받는 옵션을 주게 된다(룬드 M:w10f의 대칭).
if (( cli_rc != 0 )); then
    hb_rescue "기준 시각을 구하는 last-seen을 실행하지 못했어(종료코드 ${cli_rc} — 설치본이 구버전일 수 있어). CLI 버전(git -C ~/yaksu-history log --oneline -1)도 확인해줘."
    emit "$CLI --after ${DEFAULT_WINDOW}m 돌려서 못 봤던 대화 파악해줘. ⚠️ 기준 시각을 구하는 last-seen을 실행하지 못했어(종료코드 ${cli_rc} — 설치본이 구버전일 수 있어). 그래서 기본 ${DEFAULT_WINDOW}분으로 잡은 거고 **내 발화 기록이 없어서가 아니야.** 이 설치본엔 --limit도 없을 수 있으니 결과가 너무 많으면 창을 좁혀서 나눠 봐. CLI 버전(git -C ~/yaksu-history log --oneline -1)도 확인해줘."
fi
if [[ "$parsed" == "PARSE_FAIL" ]]; then
    hb_rescue "last-seen은 성공했는데 **출력을 해석하지 못했어**(last_seen 필드를 못 찾음 — 출력 형식이 바뀌었을 수 있어). CLI 출력 형식도 확인해줘."
    emit "$CLI --after ${DEFAULT_WINDOW}m --limit $LIMIT 돌려서 못 봤던 대화 파악해줘. ⚠️ last-seen은 성공했는데 **출력을 해석하지 못했어**(last_seen 필드를 못 찾음 — 출력 형식이 바뀌었을 수 있어). 기록이 없어서가 아니야. 기본 ${DEFAULT_WINDOW}분으로 잡았고, CLI 출력 형식도 확인해줘."
fi
if [[ "$parsed" == "NULL" ]]; then
    hb_rescue "내($SELF) 발화 기록이 없어(last_seen이 null) — 적재가 왜 비었는지도 확인해줘."
    emit "$CLI --after ${DEFAULT_WINDOW}m --limit $LIMIT 돌려서 못 봤던 대화 파악해줘. ⚠️ 내($SELF) 발화 기록이 없어서(last_seen이 null) 기준 시각을 못 구했고 기본 ${DEFAULT_WINDOW}분으로 잡은 거야 — 적재가 왜 비었는지도 확인해줘."
fi

# ── 경과 분 → 창 ──────────────────────────────────────────
elapsed="$(python3 -c '
import sys, datetime as dt
raw = sys.argv[1]
t = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
if t.tzinfo is None:            # tz 없는 값을 UTC로 가정하지 않는다
    raise SystemExit(1)
print(int((dt.datetime.now(dt.timezone.utc) - t).total_seconds() // 60))
' "${parsed#OK }" 2>/dev/null)"

if [[ ! "$elapsed" =~ ^-?[0-9]+$ ]]; then
    hb_rescue "last-seen이 준 시각(${parsed#OK })을 해석하지 못했어 — 시각 형식이 바뀌었는지 확인해줘."
    emit "$CLI --after ${DEFAULT_WINDOW}m --limit $LIMIT 돌려서 못 봤던 대화 파악해줘. ⚠️ last-seen이 준 시각(${parsed#OK })을 해석하지 못해서 기본 ${DEFAULT_WINDOW}분으로 잡았어 — 시각 형식이 바뀌었는지 확인해줘."
fi

# ── 두 앵커 중 더 오래된 쪽 = 경과분이 큰 쪽 ────────────────
# 오차는 언제나 창이 **넓어지는** 방향으로만 난다(계약 ②). 상단 🔑 참조.
anchor_desc="**내가 마지막으로 발화한 시각**"
chosen=$elapsed
if [[ -n "$hb_elapsed" ]] && (( hb_elapsed > elapsed )); then
    chosen=$hb_elapsed
    anchor_desc="**내가 마지막으로 턴을 끝낸 시각**(세션 하트비트 ${hb_elapsed}분 전 — 내 발화 기록은 ${elapsed}분 전인데 그건 cron이 낸 것일 수 있어서 더 오래된 쪽을 골랐어)"
fi

note=""
if (( chosen > MAX_WINDOW )); then
    note=" 앵커가 ${chosen}분 전인데 48시간으로 잘랐어 — 그 앞 구간은 따라잡기가 아니라 별도 복구가 필요해."
fi
window="$(clamp "$chosen")"

emit "$CLI --after ${window}m --limit $LIMIT 돌려서 못 봤던 대화 파악해줘. 그 창은 ${anchor_desc}부터라 그 이후가 못 본 구간이야 (출력 timestamp는 UTC니까 KST는 +9). 상한에 걸리면 CLI가 생략 건수와 --until 경계를 알려주니 그걸로 앞 구간을 나눠 읽어.${note}"
