#!/bin/bash
# dm-smoke.sh — DM 스모크 게이트 (bot-core relay 전환 검증, 회귀5호=DM 완전사망 방지)
#
# 사람(Darren)이 니노에게 DM으로 마커를 보내면, DM 경로 6종을 실측 검증한다.
# diff로 못 잡는 DM 경로를 관문마다 확인 (룬드 회귀5호 교훈: Partials.Channel 누락 시 DM 전멸).
#   1 수신   relay 로그에 마커        (RELAY_LOG 지정 시)
#   2 주입   tmux에 [DM][이름]…마커
#   3 JSONL  오늘자 .jsonl에 type:dm
#   4 DB     messages 테이블 type=dm 행
#   5 이름   author=본명(Darren), raw id면 USER_MAP 회귀
#   6 육안   Discord에서 online+Playing (사람 눈, 자동화 불가)
#
# 하나라도 ✗(1~5)면 exit 1 → 전환(6단계) 진입 차단. 사용:
#   [RELAY_LOG=/path] EXPECT_NAME=Darren TIMEOUT=90 bash scripts/dm-smoke.sh
set -uo pipefail

TMUX_SESSION="${TMUX_SESSION:-nino}"
JSONL_DIR="${HISTORY_JSONL_DIR:-$HOME/discord-bot-nino/memory/discord-history}"
DB="${YAKSU_HISTORY_DB:-$HOME/.local/share/yaksu-history/messages.db}"
RELAY_LOG="${RELAY_LOG:-}"
EXPECT_NAME="${EXPECT_NAME:-Darren}"
TIMEOUT="${TIMEOUT:-90}"
MARKER="smoke-$(date +%s)"
TODAY="$(TZ=Asia/Seoul date +%F)"

pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAILED=1; }
FAILED=0

echo "🚪 DM 스모크 게이트 (마커: $MARKER)"
echo "👉 $EXPECT_NAME 님, 니노에게 DM으로 이 텍스트를 보내주세요:  $MARKER"
echo "   (DB에 뜰 때까지 최대 ${TIMEOUT}초 대기…)"

# DB에 마커 DM이 뜰 때까지 폴링
db_has() {
  bun -e "const{Database}=require('bun:sqlite');const d=new Database(process.argv[1],{readonly:true});const r=d.query(\"SELECT type,author_name FROM messages WHERE content LIKE ? ORDER BY timestamp DESC LIMIT 1\").get(process.argv[2]+'%');if(!r)process.exit(2);console.log(r.type+'|'+r.author_name);process.exit(0)" "$DB" "$MARKER" 2>/dev/null
}
ROW=""
for _ in $(seq 1 "$TIMEOUT"); do
  ROW="$(db_has)" && break
  sleep 1
done

echo ""
echo "== 검증 =="
# 4 DB
if [[ -n "$ROW" ]]; then
  DTYPE="${ROW%%|*}"; DNAME="${ROW#*|}"
  [[ "$DTYPE" == "dm" ]] && pass "4 DB: type=dm 행 존재" || fail "4 DB: 행은 있으나 type=$DTYPE (dm 아님)"
  # 5 이름매핑
  [[ "$DNAME" == "$EXPECT_NAME" ]] && pass "5 이름매핑: author=$DNAME" || fail "5 이름매핑: author=$DNAME (기대=$EXPECT_NAME, raw id면 USER_MAP 회귀)"
else
  fail "4 DB: ${TIMEOUT}초 내 마커 DM 미도착 (수신 자체 실패 = 회귀5호 의심!)"
  fail "5 이름매핑: (DB 행 없어 확인 불가)"
fi

# 2 tmux 주입
if tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null | grep -qF "$MARKER"; then
  tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null | grep -F "$MARKER" | grep -q "\[DM\]" \
    && pass "2 tmux 주입: [DM] 프리픽스로 도착" || pass "2 tmux 주입: 마커 도착(프리픽스 확인은 육안)"
else
  fail "2 tmux 주입: nino tmux에 마커 없음"
fi

# 3 JSONL
JF="$JSONL_DIR/$TODAY.jsonl"
if [[ -f "$JF" ]] && grep -qF "$MARKER" "$JF" && grep -F "$MARKER" "$JF" | grep -q '"type":"dm"'; then
  pass "3 JSONL: 오늘자 파일에 type:dm 기록"
else
  fail "3 JSONL: $JF 에 type:dm 마커 없음 (HISTORY_JSONL_DIR 미설정=회귀4호 의심)"
fi

# 1 수신 (RELAY_LOG 지정 시)
if [[ -n "$RELAY_LOG" ]]; then
  grep -qF "$MARKER" "$RELAY_LOG" 2>/dev/null && pass "1 수신: relay 로그에 마커" || fail "1 수신: relay 로그에 마커 없음"
else
  echo "  ⏭  1 수신: RELAY_LOG 미지정 → 스킵 (2 tmux 도착으로 수신 간접 확인)"
fi

# 6 육안
echo "  👁  6 presence: Discord에서 니노가 online + Playing으로 보이는지 눈으로 확인하세요 (회귀2호, 로그로 못 잡음)"

echo ""
if [[ "$FAILED" == "0" ]]; then
  echo "🎉 DM 스모크 게이트 통과 (1~5 자동검사). 6 육안 확인 후 전환 진행 가능."
  exit 0
else
  echo "🚫 DM 스모크 게이트 실패 — 전환(6단계) 진입 금지. 위 ❌ 원인 해결 후 재실행."
  exit 1
fi
