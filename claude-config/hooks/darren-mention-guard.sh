#!/bin/bash
# darren-mention-guard.sh — PreToolUse(Bash) hook
# 니노가 현인(Darren) 채널로 discord-send할 때 멘션(<@353914579929268226>)이 없으면 차단.
# Tim 지시(2026-07-17): "현인이 부를 때 꼭 멘션". recall(메모리)이 아니라 구조로 강제.
# exit 2 = 도구 차단 + stderr를 Claude에게 전달 → 니노가 멘션 붙여 재전송.
#
# ⚠️ DM(DM-Darren)은 제외: DM은 1:1이라 무조건 푸시됨 → 멘션 목적(알림 보장)이 이미 달성.
#    hook 취지는 "공용 채널에서 Darren이 못 볼까봐"이므로 DM엔 불필요 (2026-07-20 근본 수정).
#
# 2026-07-27 근본 수정 (Darren 승인 M:pg99):
#   대상 판정을 **명령 문자열 전체 grep → target 인자 파싱**으로 좁혔다.
#   전에는 *다른* 채널로 보내는 메시지 본문에 Darren 채널명/ID를 인용하기만 해도 차단됐다.
#   그 오탐 때문에 보고에서 채널명을 빼게 되어 **정보가 깎이는** 부작용이 있었다.
#
#   🔴 이 수정은 실패 방향을 바꾼다(룬드 M:xjis):
#      전: 과잉 차단(오탐)                    — 시끄럽고 되돌릴 수 있다
#      후: 파싱 오류 시 차단 누락(거짓 음성)  — 조용하고 사고가 나야 안다
#      그래서 ①파싱 실패 시 예전 방식(전체 grep)으로 폴백하고
#             ②tests/darren-mention-guard.test.sh가 "차단이 유지되는가"를 오탐 케이스와 같은 무게로 고정한다.
#
#   알려진 한계: 4자리 해시 target은 채널을 알 수 없어 통과한다(수정 전에도 동일).
#   해시 답장이 Darren 채널로 갈 때 멘션이 강제되지 않는다 → DB 역조회 후속 제안 중.

input=$(cat)
command=$(printf '%s' "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# discord-send 명령 아니면 통과
printf '%s' "$command" | grep -q "discord-send" || exit 0

DARREN_TARGETS='현인-다용도|현인-업무|1480593132511826092|1479813609499394171'
DARREN_DM='DM-Darren'

# 🌙 취침 플래그 — 파일 첫 줄에 «만료 epoch» 하나. 있으면서 아직 안 지났으면 자는 중.
#   🔑 훅은 «요일·기상시각»을 계산하지 않는다. 그건 켜는 쪽이 하고 여기선 «지났나»만 본다
#      (판단이 아니라 비교여야 시험이 붙는다).
#   🔑 읽기 실패·빈 파일·비수치는 전부 «안 자는 중»으로 떨어진다 — 잊거나 깨져도 «시끄러운 쪽»으로.
#      반대로 폴백하면 파일이 잘못 생긴 순간부터 멘션이 조용히 사라진다.
SLEEP_FLAG="${DARREN_SLEEP_FLAG:-$HOME/discord-bot-nino/logs/darren-sleeping}"
is_sleeping() {
  local until
  [ -f "$SLEEP_FLAG" ] || { echo 0; return; }
  until=$(head -1 "$SLEEP_FLAG" 2>/dev/null | tr -d '[:space:]')
  case "$until" in
    ''|*[!0-9]*) echo 0; return ;;
  esac
  [ "$(date +%s)" -lt "$until" ] && echo 1 || echo 0
}

# target 인자만 뽑는다. 값을 먹는 옵션(discord-send --help 실측): -r/--reply · -t/--thread · -f/--file · --target · -c
# -f는 반복 지정이 가능해 target 위치가 밀린다 → "첫 positional"이 아니라 "옵션을 건너뛴 첫 non-flag"여야 한다.
targets=$(printf '%s' "$command" | python3 -c '
import shlex, sys, os

try:
    toks = shlex.split(sys.stdin.read(), comments=False, posix=True)
except ValueError:
    sys.exit(3)          # 쿼팅이 안 맞아 파싱 불가 → 폴백(안전한 쪽)

VALUE_OPTS = {"-r", "--reply", "-t", "--thread", "-f", "--file", "--target", "-c", "--channel"}
EXPLICIT = {"--target", "-c", "--channel"}
BREAK = {";", "&&", "||", "|", "&"}

def resolve(args):
    """discord-send 인자에서 target 하나를 뽑는다. --target/-c가 있으면 그게 정본."""
    explicit = positional = None
    i, endopts = 0, False
    while i < len(args):
        a = args[i]
        if a in BREAK:
            break
        if not endopts and a == "--":
            endopts = True; i += 1; continue
        if not endopts and a.startswith("-") and len(a) > 1:
            name, _, inline = a.partition("=")
            if name in EXPLICIT:
                explicit = inline if inline else (args[i + 1] if i + 1 < len(args) else None)
                i += 1 if inline else 2
                continue
            if name in VALUE_OPTS and not inline:
                i += 2; continue
            i += 1; continue
        if positional is None:
            positional = a
        i += 1
    return explicit or positional

out = [t2 for i, t in enumerate(toks) if os.path.basename(t) == "discord-send"
       for t2 in [resolve(toks[i + 1:])] if t2]
print("\n".join(out))
' 2>/dev/null)
rc=$?

if [ "$rc" -ne 0 ]; then
    # 파싱 불가 → 예전 방식으로 폴백. 오탐이 나더라도 차단 누락보다 낫다.
    printf '%s' "$command" | grep -qE "$DARREN_TARGETS" && hits_channel=1
    printf '%s' "$command" | grep -qE "$DARREN_DM" && hits_dm=1
else
    # -x: target 전체가 일치해야 한다. 부분일치를 허용하면 본문 grep 시절의 오탐이 되돌아온다.
    printf '%s' "$targets" | grep -qxE "$DARREN_TARGETS" && hits_channel=1
    printf '%s' "$targets" | grep -qxE "$DARREN_DM" && hits_dm=1
fi

# Darren 을 향하지 않으면 두 모드 다 관심 없다
[ "${hits_channel:-0}" = 1 ] || [ "${hits_dm:-0}" = 1 ] || exit 0

# 파일 경유 메시지($(cat /tmp/xxx))도 내용에 포함해서 검사 (인라인 오탐 방지)
content="$command"
for f in $(printf '%s' "$command" | grep -oE "/tmp/[^ )\"']+" 2>/dev/null); do
  [ -f "$f" ] && content="$content $(cat "$f" 2>/dev/null)"
done

has_mention=0
printf '%s' "$content" | grep -qE "<@353914579929268226>|@Darren" && has_mention=1

if [ "$(is_sleeping)" = 1 ]; then
    # 🌙 취침 모드 — 계약이 «뒤집힌다». 막는 기준은 「멘션이 없나」가 아니라 «소리가 나나»다.
    #    DM 은 멘션이 없어도 소리가 나므로 무조건 막고, 채널은 «평문만» 통과시킨다.
    [ "$hits_dm" = 1 ] 2>/dev/null && {
      echo "🌙 지금은 Darren 취침 모드입니다. DM 은 노트북에서 소리가 나므로 막았습니다 — 급하지 않으면 «현인-다용도 채널에 멘션 없이» 남기세요. (해제: Darren 의 메시지 또는 만료 시각)" >&2
      exit 2
    }
    [ "$has_mention" = 1 ] && {
      echo "🌙 지금은 Darren 취침 모드입니다. 멘션은 노트북에서 소리가 나므로 막았습니다 — 멘션을 빼고 채널에 남기면 통과합니다(아침에 「밤사이 N건」으로 전달). (해제: Darren 의 메시지 또는 만료 시각)" >&2
      exit 2
    }
    exit 0
fi

# 평소 계약 — DM 은 1:1 이라 이미 푸시되므로 멘션을 강제하지 않는다(2026-07-20 근본 수정)
[ "${hits_channel:-0}" = 1 ] || exit 0
[ "$has_mention" = 1 ] && exit 0

# 멘션 없음 → 차단
echo "🚫 현인(Darren) 채널 메시지에 멘션이 없습니다. 본문에 @Darren 또는 <@353914579929268226>를 넣어 재전송하세요. (Tim 지시: 현인 부를 때 멘션 필수 — feedback_mention_darren)" >&2
exit 2
