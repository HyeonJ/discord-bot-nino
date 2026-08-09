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
# 🔴 템플릿을 **명시**한다. 인자 없는 `mktemp` 는 `$TMPDIR` 을 쓰는데 맥은 그게
#    `/var/folders/…/T/` 라, 훅의 경로 필터(86행 `/tmp/…` 하드코딩)에 안 걸린다.
#    ⇒ 훅이 파일을 아예 안 읽어 **멘션이 있어도 차단**된다(룬드 맥 20/20 결정론).
#    시험이 훅의 실제 계약(= /tmp 아래만 읽는다)을 밟으려면 /tmp 에 만들어야 한다.
TMPMSG="$(mktemp /tmp/mention-guard-test.XXXXXX)"
OUTMSG="$SCRIPT_DIR/mention-guard-outside.$$"
trap 'rm -f "$TMPMSG" "$OUTMSG"' EXIT
printf '%s 파일로 보내는 보고\n' "$MENTION" > "$TMPMSG"
check "파일 안에 멘션 있으면 통과"                0 "discord-send 현인-업무 \"\$(cat $TMPMSG)\""
printf '멘션 없는 파일 본문\n' > "$TMPMSG"
check "파일 안에도 멘션 없으면 차단"              2 "discord-send 현인-업무 \"\$(cat $TMPMSG)\""

# 🧪 [미탐 대조군] 위 '차단'이 **파일을 읽고 멘션이 없어서**인지 **파일을 못 읽어서**인지,
#   두 상태는 같은 exit 2 를 낸다. 훅은 `/tmp/` 아래만 읽으므로 /tmp 밖 파일은 멘션이
#   있어도 차단된다 — 그게 실제 계약이다. 여기서 고정해두면 위 두 줄이 *"읽었다"* 를
#   전제로 한다는 게 드러난다(맥에서 20/20 빨갛던 자리가 정확히 이 전제였다).
printf '%s /tmp 밖 파일\n' "$MENTION" > "$OUTMSG"
check "🧪 [경계] /tmp 밖 파일은 멘션이 있어도 차단(훅이 안 읽는다)" 2 "discord-send 현인-업무 \"\$(cat $OUTMSG)\""

echo ""
echo "알려진 한계 (수정 범위 밖 — 문서화용 고정):"
check "해시 target은 채널을 알 수 없어 통과"      0 'discord-send ab12 "해시 답장"'

echo ""
echo "🌙 취침 모드 (Darren 승인 2026-08-05 M:e15c — 자는 동안 «소리나는 것»만 막는다):"
# 왜 «반대로» 뒤집나: 평소 계약은 「멘션 없으면 차단」이지만, 자는 동안엔 멘션·DM 이
#   Darren 노트북에서 «소리»를 낸다(본인 실측 M:1sp8). 채널 평문은 무음이라 그것만 통과시킨다.
#   ⇒ 같은 훅이 플래그 하나로 두 모드를 갖는다. 축은 「멘션이냐」가 아니라 «소리가 나느냐».
export DARREN_SLEEP_FLAG="$(mktemp /tmp/darren-sleeping.XXXXXX)"
# ⚠️ `${:-}` 로 받는다 — 아래에서 플래그를 지우고 나면 `set -u` 아래의 trap 이 죽는다.
trap 'rm -f "$TMPMSG" "$OUTMSG" "${DARREN_SLEEP_FLAG:-}"' EXIT

# 🕐 «지금»을 못 박는다 — 아래 계약들은 시간대 기본값(1~7시)이 생기면서
#   **벽시계에 따라 뒤집히는** 것들이 됐다. 안 박으면 새벽에 돌릴 때 «거짓 빨강»이 난다.
#   🔑 고정 epoch 을 리터럴로 쓰지 않는다 — 러너 TZ 가 UTC 라 「몇 시인가」가 갈린다.
#      KST 자정으로 «정규화»한 뒤 시를 더해서, TZ 와 무관하게 원하는 KST 시각을 만든다.
_B=1786000000
KST_MIDNIGHT=$(( _B - (_B + 32400) % 86400 ))
kst()  { echo $(( KST_MIDNIGHT + $1 * 3600 + 1800 )); }   # 그 시 «30분»
kstx() { echo $(( KST_MIDNIGHT + $1 * 3600 ));        }   # 그 시 «정각» (경계용)

# 아래 블록은 «낮»으로 고정 — 시간대가 아니라 «플래그»가 무엇을 하는지만 잰다
export DARREN_NOW_EPOCH="$(kst 10)"

# 만료 시각(epoch)을 파일에 적는다 — 훅이 «요일 판정»을 하지 않게 하려는 것.
#   요일·기상시각 계산은 «켜는 쪽»이 하고, 훅은 «지났나»만 본다(판단 아닌 비교).
printf '%s\n' "$(( DARREN_NOW_EPOCH + 3600 ))" > "$DARREN_SLEEP_FLAG"

check "🌙 취침 중 + 멘션 있음 → 차단(깨운다)"        2 "discord-send 현인-업무 \"$MENTION 보고\""
check "🌙 취침 중 + @Darren 표기도 → 차단"           2 'discord-send 현인-업무 "@Darren 보고"'
check "🌙 취침 중 + 멘션 없음 → 통과(무음)"          0 'discord-send 현인-업무 "보고"'
check "🌙 취침 중 + DM 은 멘션 없어도 차단(소리남)"  2 'discord-send DM-Darren "확인 부탁"'
check "🌙 취침 중이어도 다른 채널은 무관 → 통과"     0 "discord-send 봇-놀이터 \"$MENTION 룬드에게\""

# 🧪 [경계] 만료가 지나면 «평소 계약»으로 돌아온다. 이게 없으면 내가 해제를 잊었을 때
#   멘션이 영영 조용히 안 간다 — 잊어도 «시끄러운 쪽»으로 떨어지게 하는 장치다.
printf '%s\n' "$(( DARREN_NOW_EPOCH - 60 ))" > "$DARREN_SLEEP_FLAG"
check "🧪 [경계] 만료 후 → 멘션 없으면 도로 차단"    2 'discord-send 현인-업무 "보고"'
check "🧪 [경계] 만료 후 → 멘션 있으면 통과"         0 "discord-send 현인-업무 \"$MENTION 보고\""

# 🧪 [미탐 대조군] 플래그가 «깨졌을 때»도 평소 계약이어야 한다. 빈 파일·비수치를
#   「자는 중」으로 읽으면, 파일이 잘못 생긴 순간부터 멘션이 조용히 사라진다.
: > "$DARREN_SLEEP_FLAG"
check "🧪 [폴백] 빈 플래그 → 평소 계약(차단)"        2 'discord-send 현인-업무 "보고"'
printf 'garbage\n' > "$DARREN_SLEEP_FLAG"
check "🧪 [폴백] 숫자 아닌 플래그 → 평소 계약(차단)" 2 'discord-send 현인-업무 "보고"'
rm -f "$DARREN_SLEEP_FLAG"
check "🧪 [폴백] 플래그 파일 없음 → 평소 계약(차단)" 2 'discord-send 현인-업무 "보고"'

echo ""
echo "🌙 기본 취침 «시간대» — Darren 값 1~7시 (2026-08-10 M:ur8v). 플래그 없이도 든다:"
# 왜 생겼나: 플래그는 **Darren 이 「잔다」고 말해야** 켜진다. 본인 말 —
#   *「내가 잔다고 말 안하고 그냥 잘때도 있어」*. 설계가 사람에게 일을 시키고 있었다.
# 🔑 이 블록은 «플래그 없음»에서 잰다 — 위 폴백 블록과 «같은 입력»인데 시각만 다르다.
#   그래서 갈라주는 것이 시간대라는 게 대조로 선다(둘 다 차단이면 아무것도 안 갈린다).

export DARREN_NOW_EPOCH="$(kst 3)"
check "🌙 [시간대] 03시 + 플래그 없음 + 멘션 → 차단"   2 "discord-send 현인-업무 \"$MENTION 보고\""
check "🌙 [시간대] 03시 + 멘션 없음 → 통과(무음)"      0 'discord-send 현인-업무 "보고"'
check "🌙 [시간대] 03시 + DM → 차단(소리남)"           2 'discord-send DM-Darren "확인"'
check "🌙 [시간대] 03시라도 다른 채널은 무관 → 통과"   0 "discord-send 봇-놀이터 \"$MENTION 룬드에게\""

export DARREN_NOW_EPOCH="$(kst 10)"
check "🌙 [대조군] 10시 + 같은 입력 → 평소 계약(통과)" 0 "discord-send 현인-업무 \"$MENTION 보고\""

# 🧪 경계 — `>= from` 과 `< to`. 정각 둘 다 못 박는다(한쪽만 재면 열림/닫힘이 안 갈린다).
export DARREN_NOW_EPOCH="$(kstx 1)"
check "🧪 [경계] 01:00 정각 → 든다(포함)"              2 "discord-send 현인-업무 \"$MENTION 보고\""
export DARREN_NOW_EPOCH="$(kstx 7)"
check "🧪 [경계] 07:00 정각 → 안 든다(미만)"           0 "discord-send 현인-업무 \"$MENTION 보고\""
export DARREN_NOW_EPOCH="$(kstx 0)"
check "🧪 [경계] 00:00 → 아직 안 든다"                 0 "discord-send 현인-업무 \"$MENTION 보고\""

# 🧪 명시 플래그가 «시간대보다 우선»인가 — 낮인데 「잔다」고 찍은 경우
export DARREN_NOW_EPOCH="$(kst 14)"
export DARREN_SLEEP_FLAG="$(mktemp /tmp/darren-sleeping.XXXXXX)"
printf '%s\n' "$(( DARREN_NOW_EPOCH + 3600 ))" > "$DARREN_SLEEP_FLAG"
check "🌙 [우선] 낮 14시라도 명시 플래그가 있으면 차단" 2 "discord-send 현인-업무 \"$MENTION 보고\""
rm -f "$DARREN_SLEEP_FLAG"

# 🧪 창이 «자정을 넘을 때»도 도나 — 값이 바뀌어도 뒤집히지 않게 뜻으로 적었는지 잰다.
#   ⚠️ 지금 값(1~7)으로는 «절대 안 밟히는» 가지다. 안 재면 나중에 값을 바꾸는 순간 조용히 틀린다.
export DARREN_SLEEP_FROM=23 DARREN_SLEEP_TO=7
export DARREN_NOW_EPOCH="$(kst 23)"
check "🧪 [자정넘김] 23시 (from 쪽) → 든다"            2 "discord-send 현인-업무 \"$MENTION 보고\""
export DARREN_NOW_EPOCH="$(kst 2)"
check "🧪 [자정넘김] 02시 (to 쪽) → 든다"              2 "discord-send 현인-업무 \"$MENTION 보고\""
export DARREN_NOW_EPOCH="$(kst 12)"
check "🧪 [자정넘김] 12시 → 안 든다"                   0 "discord-send 현인-업무 \"$MENTION 보고\""
unset DARREN_SLEEP_FROM DARREN_SLEEP_TO
unset DARREN_NOW_EPOCH

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
