#!/bin/bash
# mdweb-link-guard.sh — PreToolUse(Bash) hook
# discord-send 로 md-web 링크를 보낼 때 ①`.md` 가 붙었거나 ②실제로 존재하지 않으면 차단.
#
# Darren 지시 2026-07-30 (M:orpb "2. 이거도 고쳐, 나도 .md 떼고 받을께").
# 지금까지 이건 **기억해야 하는 규칙**(feedback_mdweb_check)이었고 그래서 잊혔다 —
# 잊는 주체가 나니까 나를 막는 자리로 옮긴다(darren-mention-guard 와 같은 형태).
#
# 🔴 왜 상태코드로는 못 하나 (2026-07-30 실측):
#     http://darren/md-web/memory/current-tasks  → 200 · 3913B
#     http://darren/md-web/memory/없는파일        → 200 · 3913B  ← 코드도 크기도 같다(SPA 껍데기)
#   가르는 건 API 뿐: /api/file?rootId=&path= 는 있으면 200, 없으면 403.
#   그리고 API 는 `.md` 를 **요구**한다(`path=current-tasks` 는 403).
#   ⇒ 사람에게 주는 링크(.md 없음)와 검증 경로(.md 있음)가 반대라 한 자리에서 같이 다룬다.
#
# 판정부는 옆 파일(mdweb-link-check.py)이다. 인라인 `python3 -c` 로 두다가
#   정규식의 `'`·백틱이 셸 인용을 끊었고, **bash 문법오류 rc=2 가 이 훅의 차단 코드와 같아서**
#   깨진 훅이 "전부 잘 막는 훅"처럼 보였다 → 판정부는 파일로 분리한다.
#
# 실패 방향: 과잉 차단(오탐)이다. 시끄럽지만 되돌릴 수 있다 —
#   깨진 링크를 조용히 보내는 쪽(거짓 음성)이 나쁘다. md-web 이 죽어 있어도 차단한다(못 여는 링크니까).
#
# exit 2 = 도구 차단 + stderr 를 Claude 에게 전달.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$HOOK_DIR/mdweb-link-check.py"

input=$(cat)
command=$(printf '%s' "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

printf '%s' "$command" | grep -q "discord-send" || exit 0

# 판정부가 없으면 조용히 통과하지 않는다 — 없는 검사가 통과로 읽히면 이 훅이 "있는 척"이 된다
if [ ! -f "$CHECKER" ]; then
  echo "🚫 md-web 링크 검사기가 없다: $CHECKER (훅 동기화 확인 — scripts/sync-claude-config.sh)" >&2
  exit 2
fi

# 파일 경유 본문($(cat /tmp/xxx))도 검사 대상 — 내 관례가 파일에 쓰고 보내는 것이라 인라인만 보면 다 빠진다
content="$command"
for f in $(printf '%s' "$command" | grep -oE "/tmp/[^ )\"']+" 2>/dev/null); do
  [ -f "$f" ] && content="$content $(cat "$f" 2>/dev/null)"
done

reason=$(printf '%s' "$content" | python3 "$CHECKER" 2>/dev/null)

[ -z "$reason" ] && exit 0

echo "🚫 md-web 링크를 그대로 보내면 안 된다:" >&2
echo "$reason" >&2
echo "   (링크 확인은 상태코드로 안 된다 — 없는 파일도 200·3913B 로 온다. 가르는 건 /api/file 200/403)" >&2
exit 2
