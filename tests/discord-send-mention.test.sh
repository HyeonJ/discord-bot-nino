#!/usr/bin/env bash
# discord-send @이름 → <@ID> 멘션 변환 테스트 (DISCORD_SEND_DRY_RUN 하네스)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SEND="$BOT_DIR/src/discord-send"
CH=1479813609499394169  # 일반 (raw ID — channel-map 조회 우회)

pass=0; fail=0
# $1=설명 $2=입력 메시지 $3=기대 msg 값
check() {
  local desc="$1" input="$2" want="$3"
  local got
  got=$(DISCORD_SEND_DRY_RUN=1 "$SEND" -c "$CH" "$input" 2>&1 | sed -n 's/^DRY_RUN.* msg=//p')
  if [[ "$got" == "$want" ]]; then
    echo "  ✅ $desc"; ((pass++))
  else
    echo "  ❌ $desc"; echo "     want: [$want]"; echo "     got:  [$got]"; ((fail++))
  fi
}

echo "discord-send 멘션 변환:"
check "@룬드 → <@ID>"              "@룬드 안녕"                  "<@1479854253462781962> 안녕"
check "@Darren → <@ID>"           "@Darren 봐봐"               "<@353914579929268226> 봐봐"
check "@충재(본명) → Tim ID"      "@충재 형"                   "<@265454241387249665> 형"
check "@현인(본명) → Darren ID"   "@현인 뭐해"                 "<@353914579929268226> 뭐해"
check "이미 <@ID>면 보존(중복변환X)" "<@265454241387249665> 안녕" "<@265454241387249665> 안녕"
check "이메일 @는 안전(미매칭)"    "메일 test@x.com 확인"       "메일 test@x.com 확인"
check "조사 붙으면 미변환(nuance)" "@룬드가 말했어"             "@룬드가 말했어"
check "멘션 없는 평문 불변"        "그냥 텍스트"                "그냥 텍스트"
check "긴 이름 우선(부분일치 방지)" "@니노 야"                   "<@1479865978803195976> 야"
check "다중 멘션"                  "@룬드 @Darren 회의"         "<@1479854253462781962> <@353914579929268226> 회의"

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
