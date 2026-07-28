#!/usr/bin/env bash
# darren-mention-guard.sh 계약 테스트
#
# 왜 이 테스트가 필요한가 (룬드 M:xjis):
#   이 훅의 수정은 **실패 방향을 바꾸는** 수정이다.
#     수정 전: 명령 문자열 전체 grep → 과잉 차단(오탐). 시끄럽고 되돌릴 수 있다.
#     수정 후: target 인자만 판정      → 파싱을 틀리면 차단 누락(거짓 음성). 조용하고 사고가 나야 안다.
#   그래서 "오탐이 사라졌다"만 보면 안 되고 **차단이 유지되는지**를 같은 무게로 고정한다.
#
# 값을 먹는 옵션(discord-send --help 실측): -r/--reply · -t/--thread · -f/--file · --target · -c
#   -f는 반복 지정 가능 → target 위치가 계속 밀린다. `$1`만 보면 놓친다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../claude-config/hooks/darren-mention-guard.sh"
MENTION="<@353914579929268226>"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     want exit: $2"; echo "     got  exit: $3"; echo "     cmd: $4"; fail=$((fail + 1)); }

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

echo "차단이 유지되는가 (거짓 음성 방지 — 이게 훅의 존재 이유):"
check "이름 target + 멘션 없음 → 차단"            2 'discord-send 현인-업무 "보고"'
check "채널ID target + 멘션 없음 → 차단"          2 'discord-send 1479813609499394171 "보고"'
# `-c` 는 deprecated 지만 **아직 동작한다**(§8 계측 중). 동작하는 한 가드도 그 경로를
# 막아야 하므로 이 줄은 일부러 옛 문법을 쓴다 — 지우면 커버리지가 사라진다.
# ⚠️ 면제 마커는 **매치된 줄 자체**에 있어야 한다(린트가 `grep -v` 로 그 줄을 거른다).
#    앞줄 주석에 달면 안 먹는다 — 실제로 그렇게 달았다가 여전히 잡혔다.
check "-c target + 멘션 없음 → 차단"              2 'discord-send -c 현인-업무 "보고"'  # lint-callers:allow
check "--target 지정 + 멘션 없음 → 차단"          2 'discord-send --target 현인-업무 "보고"'
check "-f 앞에 붙어 target이 밀림 → 차단"         2 'discord-send -f /tmp/a.png 현인-업무 "이미지"'
check "-f 반복으로 더 밀림 → 차단"                2 'discord-send -f /tmp/a.png -f /tmp/b.png 현인-다용도 "둘"'
check "-r 해시가 앞에 와도 → 차단"                2 'discord-send -r ab12 현인-업무 "답장"'
check "-t 스레드 옵션이 앞에 와도 → 차단"         2 'discord-send -t 새스레드 현인-업무 "스레드"'
check "절대경로 실행 + 멘션 없음 → 차단"          2 '/home/bpx27/discord-bot-nino/src/discord-send 현인-업무 "보고"'
check "체인 뒤쪽 명령이 대상 → 차단"              2 'echo hi && discord-send 현인-업무 "보고"'

echo ""
echo "통과해야 하는가 (오탐 방지 — 이번 수정의 목적):"
check "이름 target + 멘션 있음 → 통과"            0 "discord-send 현인-업무 \"$MENTION 보고\""
check "🔴 다른 채널인데 본문에 대상 채널명 인용"   0 'discord-send 충재-다용도 "현인-업무 채널에 올렸어"'
check "🔴 다른 채널인데 본문에 대상 채널ID 인용"   0 'discord-send 충재-다용도 "1479813609499394171 확인"'
check "🔴 본문이 훅 자체를 설명(채널명 포함)"      0 'discord-send 봇-놀이터 "훅이 현인-다용도|현인-업무 를 grep해"'
check "DM-Darren은 멘션 불필요 → 통과"            0 'discord-send DM-Darren "확인 부탁"'
check "discord-send 아닌 명령 → 통과"             0 'echo 현인-업무 1479813609499394171'
check "@Darren 표기도 멘션으로 인정 → 통과"       0 'discord-send 현인-업무 "@Darren 보고"'

echo ""
echo "파일 경유 메시지(기존 기능 보존):"
TMPMSG="$(mktemp)"; trap 'rm -f "$TMPMSG"' EXIT
printf '%s 파일로 보내는 보고\n' "$MENTION" > "$TMPMSG"
check "파일 안에 멘션 있으면 통과"                0 "discord-send 현인-업무 \"\$(cat $TMPMSG)\""
printf '멘션 없는 파일 본문\n' > "$TMPMSG"
check "파일 안에도 멘션 없으면 차단"              2 "discord-send 현인-업무 \"\$(cat $TMPMSG)\""

echo ""
echo "알려진 한계 (수정 범위 밖 — 문서화용 고정):"
check "해시 target은 채널을 알 수 없어 통과"      0 'discord-send ab12 "해시 답장"'

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
