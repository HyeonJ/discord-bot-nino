#!/bin/bash
# Claude Code 사용량 조회 (사람이 직접 부르는 쪽 — cron 경보는 check-usage-alert.sh)
#
# 🔴 2026-07-31 이전엔 **버킷 하나가 죽으면 뒤가 통째로 사라졌다.**
#    API 응답에 `utilization: null` 인 항목이 있다(`extra_usage` · `spend` — 한도가 아니라
#    결제/추가사용 정보). 그런데 `v.get('utilization', 0)` 을 썼다:
#
#      🔑 `.get(k, default)` 는 **키가 없을 때만** 기본값을 준다.
#         키가 있고 값이 None 이면 None 이 그대로 나온다 — 기본값은 안 먹는다.
#
#    ⇒ `f'{None:.1f}'` 에서 TypeError → 루프 전체 중단.
#      five_hour·seven_day 가 먼저 와서 출력된 뒤 죽어 *"조금 시끄러운 성공"* 처럼 보였지만,
#      그건 **딕셔너리 순서에 기댄 우연**이다. null 이 앞에 오면 한도가 하나도 안 나온다.
#
# 🔑 null 버킷은 0.0% 로 **위조하지 않는다.** 모르는 값을 0 으로 적으면 *"여유 100%"* 라는
#    거짓 정보가 된다. 한도가 아닌 항목은 줄을 만들지 않는 게 맞다.

set -uo pipefail

CREDENTIALS="${CHECK_USAGE_CREDENTIALS:-$HOME/.claude/.credentials.json}"
API_URL="${USAGE_API_URL:-https://api.anthropic.com/api/oauth/usage}"

# ── 토큰 ─────────────────────────────────────────────────────────────────────
# 🔴 못 읽으면 **API 를 부르지 않는다.** 빈 토큰으로 부르면 401 을 받고,
#    그게 "한도 조회 실패" 로 뭉개져 원인이 사라진다.
TOKEN="$(CRED="$CREDENTIALS" python3 -c "
import json, os
try:
    d = json.load(open(os.environ['CRED']))
    print(d['claudeAiOauth']['accessToken'])
except Exception:
    pass" 2>/dev/null)"

if [ -z "$TOKEN" ]; then
    echo "자격증명을 읽을 수 없습니다: $CREDENTIALS" >&2
    echo "  (로그인 상태를 확인하거나 CHECK_USAGE_CREDENTIALS 로 경로를 지정하세요)" >&2
    exit 1
fi

RESPONSE="$(curl -s "$API_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: claude-code/2.1.5" \
  -H "anthropic-beta: oauth-2025-04-20")"

RESPONSE="$RESPONSE" python3 <<'PYEOF'
import json, os, sys

raw = os.environ.get("RESPONSE", "")

# 🔴 JSON 이 아니면 조용히 성공하지 않는다 — 429·502 본문은 JSON 이 아닐 수 있고,
#    rc=0 이면 부른 쪽이 "잘 돌았는데 한도가 없네" 로 읽는다.
try:
    d = json.loads(raw)
except Exception:
    print("사용량 응답을 해석할 수 없습니다 (JSON 아님)", file=sys.stderr)
    print(f"  앞부분: {raw[:120]!r}", file=sys.stderr)
    sys.exit(1)

labels = {
    'five_hour': '5시간 한도',
    'seven_day': '7일 한도',
    'seven_day_sonnet': '7일 Sonnet 한도',
}

shown = 0
for k, v in d.items():
    if not isinstance(v, dict):
        continue
    util = v.get('utilization')
    if util is None:
        continue          # 한도 버킷이 아니다(extra_usage·spend). 0 으로 위조하지 않는다.
    resets = (v.get('resets_at') or '')[:16].replace('T', ' ')
    label = labels.get(k, k)
    line = f'{label}: {util:.1f}% 사용 / {100 - util:.1f}% 남음'
    if resets:
        line += f'  (리셋: {resets} UTC)'
    print(line)
    shown += 1

if shown == 0:
    print("사용량 버킷이 하나도 없습니다 (응답 형식이 바뀌었을 수 있음)", file=sys.stderr)
    sys.exit(1)
PYEOF
