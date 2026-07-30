#!/usr/bin/env bash
# mdweb-link-guard.sh 계약 테스트
#
# 왜 이 훅이 필요한가 (Darren 지시 2026-07-30 M:orpb "2. 이거도 고쳐, 나도 .md 떼고 받을께"):
#   md-web 링크 확인은 지금까지 **기억해야 하는 규칙**(feedback_mdweb_check)이었고, 그래서 잊혔다.
#   잊는 주체가 나니까 나를 막는 자리(PreToolUse 훅)로 옮긴다 — darren-mention-guard 와 같은 형태.
#
# 🔴 이 훅이 잡아야 하는 것의 핵심은 "상태코드가 두 상태를 안 가른다"는 것이다 (2026-07-30 실측):
#     http://darren/md-web/memory/current-tasks   → 200 · 3913B
#     http://darren/md-web/memory/없는파일         → 200 · 3913B   ← 코드도 크기도 동일(SPA 껍데기)
#   갈라주는 건 API 뿐이다:
#     /api/file?rootId=memory&path=current-tasks.md → 200
#     /api/file?rootId=memory&path=없는파일.md      → 403
#   그리고 API 는 `.md` 를 **요구**한다(`path=current-tasks` 는 403).
#   즉 사람에게 주는 링크(.md 없음)와 검증에 쓰는 경로(.md 있음)가 반대라 한 자리에서 같이 다뤄야 한다.
#
# 실패 방향: 과잉 차단(오탐)이다. 시끄럽지만 되돌릴 수 있다 — 깨진 링크를 조용히 보내는 쪽이 나쁘다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../claude-config/hooks/mdweb-link-guard.sh"
API='http://localhost:58082/api/file'

pass=0; fail=0; skip=0
ok()    { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()   { echo "  ❌ $1"; echo "     want exit: $2"; echo "     got  exit: $3"; echo "     cmd: $4"; fail=$((fail + 1)); }
skipt() { echo "  ⏭️  $1 — 판정 불가: $2"; skip=$((skip + 1)); }

# $1=설명 $2=기대 exit(0=통과, 2=차단) $3=명령 문자열
check() {
  local desc="$1" want="$2" cmd="$3" got
  printf '%s' "$cmd" | python3 -c '
import json,sys
print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))
' | bash "$HOOK" >/dev/null 2>&1
  got=$?
  [[ "$got" == "$want" ]] && ok "$desc" || bad "$desc" "$want" "$got" "$cmd"
}

# $1=설명 $2=stderr 에 있어야 하는 문구 $3=명령 문자열
# 종료코드만 보면 "왜 막았는지"를 못 가른다 — 실제로 `.md` 판정을 지워도 존재검증이 대신 막아서
# 15개가 그대로 초록이었다(2026-07-30 변이시험). 이유를 고정하는 검사가 따로 있어야 한다.
checkr() {
  local desc="$1" want="$2" cmd="$3" err got
  err=$(printf '%s' "$cmd" | python3 -c '
import json,sys
print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))
' | bash "$HOOK" 2>&1 >/dev/null)
  got=$?
  # -E(정규식): 뗀 주소 검사는 고정문자열로 하면 **항진명제**가 된다 —
  # `…/current-tasks` 는 원본 `…/current-tasks.md` 의 부분문자열이라 이유에 아무것도 안 넣어도 매치된다.
  # 실제로 그래서 "뗀 주소를 이유에서 빼는" 변이가 살아남았다(2026-07-30).
  if [[ "$got" == 2 ]] && printf '%s' "$err" | grep -qE "$want"; then
    ok "$desc"
  else
    bad "$desc" "exit 2 + 이유에 '$want'" "exit $got + 이유: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-120)" "$cmd"
  fi
}

[[ -f "$HOOK" ]] || { echo "🔴 훅이 없다: $HOOK"; exit 1; }

# md-web 이 떠 있어야 존재 검증 계열을 판정할 수 있다 — 없으면 그 계열은 skip(통과로 접지 않는다)
MDWEB_UP=0
if curl -s --max-time 3 -o /dev/null "$API?rootId=memory&path=current-tasks.md"; then
  code=$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' "$API?rootId=memory&path=current-tasks.md")
  [[ "$code" == "200" ]] && MDWEB_UP=1
fi

echo "훅이 상관없는 명령을 건드리지 않는가:"
check "discord-send 아님 → 통과"                    0 'ls -al /tmp'
check "md-web 링크 없는 discord-send → 통과"        0 'discord-send 봇-놀이터 "그냥 메시지"'
check "다른 URL 은 안 건드림 → 통과"                0 'discord-send 봇-놀이터 "https://github.com/HyeonJ/x/pull/80 봐줘"'
# 이 훅은 **보내는 것**에 대한 검사다. curl 로 링크를 확인하는 명령까지 막으면 확인 자체가 불가능해진다
check "discord-send 아닌 명령의 깨진 링크 → 통과"   0 'curl -s http://darren/md-web/memory/절대없는파일xyz'

echo
echo ".md 가 붙은 링크를 잡는가 (Darren 지시 — 붙이면 렌더링본이 아니라 raw 가 온다):"
checkr "프록시 URL + .md → 차단(이유까지)"     '`\.md` 를 떼고' 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/current-tasks.md 봐줘"'
checkr "포트 URL + .md → 차단(이유까지)"       '`\.md` 를 떼고' 'discord-send 현인-업무 "@Darren http://darren:58082/#/memory/current-tasks.md"'
checkr "localhost + .md → 차단(이유까지)"      '`\.md` 를 떼고' 'discord-send 현인-업무 "@Darren http://localhost:58082/#/memory/current-tasks.md"'
# 떼고 보낼 주소를 이유에 같이 줘야 고칠 수 있다 (차단만 하면 무엇으로 바꿀지 모른다)
checkr "이유에 .md 뗀 주소를 준다"             'raw 가 온다: http://darren/md-web/memory/current-tasks$' \
  'discord-send 현인-업무 "@Darren http://darren/md-web/memory/current-tasks.md 봐줘"'

echo
echo "base path(/md-web/)가 빠진 링크를 잡는가 (폴백이 200 이라 코드로는 안 보임):"
checkr "http://darren/{rootId}/... → 차단"     'base path 가 빠졌다' 'discord-send 현인-업무 "@Darren http://darren/memory/current-tasks 봐줘"'
check "md-web root 아닌 경로는 안 건드림 → 통과"    0 'discord-send 현인-업무 "@Darren http://darren/health 확인했어"'

echo
if [[ "$MDWEB_UP" == 1 ]]; then
  echo "실제 파일 존재를 가르는가 (API 200/403):"
  check "있는 파일 → 통과"                          0 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/current-tasks 봐줘"'
  checkr "없는 파일 → 차단(이유까지)"          '그 파일이 없다' 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/절대없는파일xyz 봐줘"'
  check "없는 rootId → 차단"                        2 'discord-send 현인-업무 "@Darren http://darren/md-web/없는루트/x 봐줘"'
  check "하위 디렉터리 경로도 판정"                 0 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/alarms/memory-audit-20260805 봐줘"'
  check "포트 형식도 같은 판정 → 통과"              0 'discord-send 현인-업무 "@Darren http://darren:58082/#/memory/current-tasks"'
  # 본문을 파일에 써서 보내는 게 내 관례($(cat 파일)) → 인라인만 보면 이 경로가 통째로 빠진다
  FIX=$(mktemp /tmp/mdweb-guard-fixture.XXXXXX)
  trap 'rm -f "$FIX"' EXIT
  printf '@Darren 여기 봐줘: http://darren/md-web/memory/절대없는파일xyz\n' > "$FIX"
  check "파일 경유 본문의 링크도 판정 → 차단"       2 "discord-send 현인-업무 \"\$(cat $FIX)\""
  printf '@Darren 여기 봐줘: http://darren/md-web/memory/current-tasks\n' > "$FIX"
  check "파일 경유 정상 링크 → 통과"                0 "discord-send 현인-업무 \"\$(cat $FIX)\""
else
  skipt "실제 파일 존재 판정" "md-web(58082) 응답 없음 — \`bash scripts/start-md-web.sh\` 후 재실행"
fi

echo
echo "md-web 이 죽었을 때 조용히 통과하지 않는가 (못 여는 링크를 보내면 안 된다):"
dead_err=$(printf '%s' 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/current-tasks"' \
  | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  | MDWEB_API='http://127.0.0.1:1/api/file' MDWEB_TREE='http://127.0.0.1:1/api/tree' bash "$HOOK" 2>&1 >/dev/null)
dead_rc=$?
if [[ "$dead_rc" == 2 ]] && printf '%s' "$dead_err" | grep -qF '응답하지 않아'; then
  ok "md-web 응답 없음 → 차단 + 사유"
else
  bad "md-web 응답 없음 → 차단 + 사유" "exit 2 + '응답하지 않아'" "exit $dead_rc + $(printf '%s' "$dead_err" | tr '\n' ' ' | cut -c1-100)" "(죽은 포트)"
fi

echo "검사기(mdweb-link-check.py)가 없으면 조용히 통과하지 않는가:"
# 없는 검사가 통과로 읽히면 이 훅은 "있는 척"이 된다 — 부재는 조용하다
TMPD=$(mktemp -d /tmp/mdweb-guard-nochecker.XXXXXX)
cp "$HOOK" "$TMPD/"                      # 검사기(.py)는 일부러 안 옮긴다
nc_err=$(printf '%s' 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/current-tasks"' \
  | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  | bash "$TMPD/$(basename "$HOOK")" 2>&1 >/dev/null)
nc_rc=$?
if [[ "$nc_rc" == 2 ]] && printf '%s' "$nc_err" | grep -qF '검사기가 없다'; then
  ok "검사기 없음 → 차단 + 사유"
else
  bad "검사기 없음 → 차단 + 사유" "exit 2 + '검사기가 없다'" "exit $nc_rc + $(printf '%s' "$nc_err" | tr '\n' ' ' | cut -c1-100)" "(검사기 없는 사본)"
fi
rm -rf "$TMPD"

echo
echo "사본이 두 벌인데 어긋나지 않는가 (실행되는 건 live 쪽이다):"
# 훅 사본: live `~/.claude/hooks/` ↔ tracked `claude-config/hooks/`.
# sync-claude-config.sh 는 **live → tracked 단방향**이라, tracked 만 고치면 실제로 도는 건 안 바뀐다.
# 이 시험이 재는 건 tracked 사본이므로, 어긋나면 "초록불인데 안 고쳐진" 상태가 된다.
LIVE_DIR="$HOME/.claude/hooks"
for f in mdweb-link-guard.sh mdweb-link-check.py; do
  tracked="$SCRIPT_DIR/../claude-config/hooks/$f"
  if [[ ! -d "$LIVE_DIR" ]]; then
    skipt "live 사본 대조: $f" "$LIVE_DIR 없음 (CI 등 — 이 기계에 훅이 설치돼 있지 않다)"
  elif [[ ! -f "$LIVE_DIR/$f" ]]; then
    bad "live 사본 대조: $f" "live 에도 있어야 한다" "$LIVE_DIR/$f 없음 — tracked 만 고쳤다(실행되는 건 live)" "cp $tracked $LIVE_DIR/"
  elif diff -q "$tracked" "$LIVE_DIR/$f" >/dev/null 2>&1; then
    ok "live 사본과 같다: $f"
  else
    bad "live 사본 대조: $f" "두 사본이 동일" "$(diff "$tracked" "$LIVE_DIR/$f" | head -3 | tr '\n' ' ')" "diff $tracked $LIVE_DIR/$f"
  fi
done

echo
echo "── 결과: 통과 $pass / 실패 $fail / 판정불가 $skip"
[[ "$fail" == 0 ]] || exit 1
