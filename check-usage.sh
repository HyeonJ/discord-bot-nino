#!/bin/bash
TOKEN=$(python3 -c "import json; d=json.load(open('$HOME/.claude/.credentials.json')); print(d['claudeAiOauth']['accessToken'])")

curl -s "https://api.anthropic.com/api/oauth/usage" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: claude-code/2.1.5" \
  -H "anthropic-beta: oauth-2025-04-20" | python3 -c "
import json, sys
d = json.load(sys.stdin)
labels = {'five_hour': '5시간 한도', 'seven_day': '7일 한도', 'seven_day_sonnet': '7일 Sonnet 한도'}
for k, v in d.items():
    if not isinstance(v, dict): continue
    util = v.get('utilization', 0)
    resets = (v.get('resets_at') or '')[:16].replace('T', ' ')
    label = labels.get(k, k)
    print(f'{label}: {util:.1f}% 사용 / {100-util:.1f}% 남음' + (f'  (리셋: {resets})' if resets else ''))
"
