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
# 🔴 주입 seam — 안 그러면 «md-web 이 없는 기계» 갈래를 **실물 서비스를 죽여야만** 잴 수 있다.
#   md-web 은 Darren 이 쓰는 서비스라 시험이 끄면 안 된다. 주소를 바꿀 수 있으면 서비스를 안 건드리고 잰다.
API="${MDWEB_API:-http://localhost:58082/api/file}"
TREE_API="${TREE_API:-http://localhost:58082/api/tree}"   # 하위 디렉터리 픽스처를 여기서 고른다

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
echo "판정 범위가 'discord-send 호출의 인자'인가 (본문 인용만으로 막으면 안 된다):"
# darren-mention-guard 가 2026-07-27 에 이미 고친 것과 **같은 종류의 오탐**이다:
#   명령 문자열 전체 grep → 다른 명령의 본문에 낱말/URL 을 인용만 해도 차단 →
#   그 오탐 때문에 보고에서 채널명을 빼게 되어 **정보가 깎이는** 부작용이 났다.
# 실제로 이 훅이 자기 PR 본문(`discord-send` 라는 낱말 + 예시 URL 포함)을 막았다.
check "PR 본문에 낱말+예시 URL 인용 → 통과"         0 'gh pr create --body "표: | `discord-send` 아닌 명령 | 통과 | 예시 http://darren/md-web/memory/절대없는파일xyz"'
check "메모리에 실패 예시를 적는 것 → 통과"         0 'python3 -c "open(\"/tmp/m.md\",\"w\").write(\"discord-send 로 http://darren/md-web/memory/절대없는파일xyz 를 보내면 막힌다\")"'
check "URL 이 discord-send 인자 밖이면 → 통과"      0 'curl -s http://darren/md-web/memory/절대없는파일xyz && discord-send 봇-놀이터 "확인했어"'
check "구분자 뒤의 실제 호출은 → 차단"              2 'echo 준비완료 && discord-send 현인-업무 "@Darren http://darren/md-web/memory/절대없는파일xyz"'
# 이름에 discord-send 가 들어간 **다른** 명령은 호출이 아니다 (basename 완전일치여야 한다)
check "discord-send* 다른 스크립트 → 통과"          0 'bash scripts/lint-discord-send-callers.sh --report http://darren/md-web/memory/절대없는파일xyz'
# 영역은 구분자에서 끝나야 한다 — 안 끝나면 뒤에 붙은 확인용 curl 까지 인자로 먹는다
check "호출 뒤 구분자 다음의 URL → 통과"            0 'discord-send 봇-놀이터 "확인" && curl -s http://darren/md-web/memory/절대없는파일xyz'
# 쿼팅이 안 맞아 파싱 불가 → 폴백은 **차단** 쪽이어야 한다 (조용한 누락보다 시끄러운 오탐)
check "파싱 불가(쿼팅 깨짐) → 차단"                 2 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/절대없는파일xyz'

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
# 🔴 이 단언만 게이트 밖에 있었다 — **못 재는 것을 「실패」로 세고 있었다** (2026-08-02, CI 이틀 빨강의 마지막 1건).
#   훅의 `bare` 갈래는 `roots()` 로 「memory 가 진짜 rootId 인가」를 확인하고, 못 정하면 **조용히 통과**시킨다:
#       if r is None or root not in r: return    # md-web 링크가 아니거나 판정 불가
#   훅 입장에선 그게 맞다 — 못 가리는데 사람 발송을 막으면 안 된다. 틀린 것은 **시험 쪽**이었다.
#   md-web 이 없는 기계(CI)에선 `roots()` 가 None 이라 차단이 **일어날 수 없고**, 그건 위반이 아니라 **미측정**이다.
#   🔑 같은 파일이 이미 이 구분을 갖고 있었다(아래 `MDWEB_UP` 블록 · live 사본 대조의 「판정 불가」) —
#      **이 한 줄만 그 관례 밖에 있었다.** #130·#133 과 같은 축의 세 번째 자리다.
if [[ "$MDWEB_UP" == 1 ]]; then
  checkr "http://darren/{rootId}/... → 차단"   'base path 가 빠졌다' 'discord-send 현인-업무 "@Darren http://darren/memory/current-tasks 봐줘"'
else
  skipt "http://darren/{rootId}/... → 차단" "md-web 이 안 떠 있어 roots() 가 None — 훅이 «판정 불가로 침묵»하는 갈래라 차단이 일어날 수 없다(미측정이지 위반이 아니다)"
fi
check "md-web root 아닌 경로는 안 건드림 → 통과"    0 'discord-send 현인-업무 "@Darren http://darren/health 확인했어"'

echo
if [[ "$MDWEB_UP" == 1 ]]; then
  echo "실제 파일 존재를 가르는가 (API 200/403):"
  check "있는 파일 → 통과"                          0 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/current-tasks 봐줘"'
  checkr "없는 파일 → 차단(이유까지)"          '그 파일이 없다' 'discord-send 현인-업무 "@Darren http://darren/md-web/memory/절대없는파일xyz 봐줘"'
  check "없는 rootId → 차단"                        2 'discord-send 현인-업무 "@Darren http://darren/md-web/없는루트/x 봐줘"'
  # 🔑 하위 디렉터리 경로는 **이 기계의 md-web 이 실제로 여는 것**을 찾아서 쓴다.
  #    처음엔 `memory/alarms/memory-audit-20260805` 를 박아뒀는데 그건 **내 파일**이라
  #    룬드 맥에서는 그의 md-web 이 403 을 주고 실패로 잡혔다 — 코드 결함이 아니라
  #    *내 트리를 전제한 시험*이었다(룬드 `#81` comment). 트리 API 로 골라 쓰면 양쪽에서 산다.
  #    rootId 도 고정하지 않는다 — 그의 md-web 이 어떤 root 를 다는지 모른다.
  SUBLINK="$(curl -s --max-time 5 "$TREE_API" 2>/dev/null | python3 -c '
import json, sys
try:
    tree = json.load(sys.stdin)
except Exception:
    sys.exit(1)
def files(node):
    for c in node.get("children") or []:
        if c.get("type") == "file" and "/" in (c.get("path") or ""):
            yield c
        yield from files(c)
for root in tree if isinstance(tree, list) else []:
    for f in files(root):
        print(root.get("rootId", "") + "/" + f["path"]); sys.exit(0)
sys.exit(1)
' 2>/dev/null)"
  if [[ -n "$SUBLINK" ]]; then
    check "하위 디렉터리 경로도 판정"               0 "discord-send 현인-업무 \"@Darren http://darren/md-web/${SUBLINK%.md} 봐줘\""
  else
    # 조용히 건너뛰면 "판정했다" 와 구별이 안 된다 — 세어서 남긴다.
    skipt "하위 디렉터리 경로 판정" "이 기계의 md-web 트리에 하위 디렉터리 파일이 없다(또는 트리 API 응답 없음)"
  fi
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

echo
echo "🔑 훅이 «못 가릴 때 침묵하는» 갈래 — 이 갈래는 지금까지 어느 기계에서도 분모에 없었다:"
# 🔴 훅은 두 주소를 본다. **둘 다 주입해야 「md-web 이 없는 세계」가 된다** (룬드 변이 발견 2026-08-02):
#       MDWEB_API   → 시험이 「떠 있나」를 묻는 곳 (판정부)
#       MDWEB_TREE  → 훅의 roots() 가 실제로 보는 곳 (bare 갈래)
#   ⚠️ 하나만 주입하면 **반쪽 세계**가 된다 — 시험은 「없음」, 훅은 「있음」. 실제로 그렇게 재다가
#     「수리 전 빨강」이 재현이 안 됐다(rc=0 이 나왔다). 둘 다 주입하니 그때서야 재현됐다.
# 🔑 그리고 이 단언이 **훅의 침묵을 «양성으로» 잠근다** — CI 는 skipt 라 안 재고, 개발 기계는
#   md-web 이 실제로 떠 있어 이 갈래에 안 들어간다. **「못 재는 것을 실패로 안 센다」에서 한 발 더,
#   「못 재던 것을 재는 자리를 만든다」.** 침묵이 «옳은 침묵»인지는 여기서만 갈린다.
bare_err=$(printf '%s' 'discord-send 현인-업무 "@Darren http://darren/memory/current-tasks 봐줘"' \
  | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  | MDWEB_API='http://127.0.0.1:1/api/file' MDWEB_TREE='http://127.0.0.1:1/api/tree' bash "$HOOK" 2>&1 >/dev/null)
bare_rc=$?
if [[ "$bare_rc" == 0 ]]; then
  ok "md-web 이 없으면 base path 누락을 «판정 불가»로 두고 발송을 막지 않는다 (rc=0)"
else
  bad "못 가리는데 사람 발송을 막았다" "exit 0 (침묵)" "exit $bare_rc + $(printf '%s' "$bare_err" | tr '\n' ' ' | cut -c1-100)" "(둘 다 죽은 포트)"
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
LIVE_DIR="${LIVE_HOOKS_DIR:-$HOME/.claude/hooks}"   # env 로 뺀 이유: 아래 실패 갈래를 실제로 재보려고
# 🔑 **존재가 아니라 배선으로 잰다.** 원래는 `~/.claude/hooks` 디렉터리 유무로 갈랐는데,
#   그 디렉터리는 훅이 하나라도 있으면 생긴다 — *이 훅과 무관한 사실*이다. 그래서 룬드 맥에서는
#   디렉터리는 있고 이 두 파일만 없어서 **"사본이 어긋났다"(실패)** 로 잡혔다. 실제로는 그 기계가
#   이 훅을 아예 안 거는 것이라 **판정 불가**가 맞다(룬드 `#81` comment).
#   갈라주는 건 설정이 이 훅을 부르느냐다:
#     설정에 참조 있음 → live 에 파일이 **있어야 한다**(없으면 배선이 깨진 것 = 진짜 실패)
#     설정에 참조 없음 → 이 기계는 이 훅을 안 돌린다 = 잴 대상이 없다
#   🔸 같은 형태를 룬드가 `#29` 에서 먼저 썼다 — *구버전은 존재가 아니라 **능력**으로 잰다.*
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
WIRED=0
[[ -f "$SETTINGS" ]] && grep -q 'mdweb-link-guard' "$SETTINGS" 2>/dev/null && WIRED=1
for f in mdweb-link-guard.sh mdweb-link-check.py; do
  tracked="$SCRIPT_DIR/../claude-config/hooks/$f"
  if [[ "$WIRED" != 1 ]]; then
    skipt "live 사본 대조: $f" "이 기계는 이 훅을 안 건다(${SETTINGS} 에 참조 없음) — 비교할 live 사본이 없다"
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
