#!/usr/bin/env bash
# rc-pipe-guard.test.sh — PreToolUse(Bash) 가드가 「rc 를 볼 자리의 파이프」를 잡는지
#
# 🔴 이 가드가 생긴 이유 (실사고):
#   `git commit -F msg.txt file.sh | tail -2 && git push`
#   → 파이프라인의 rc 는 **마지막 명령(tail)의 것**이라 commit 이 pathspec 오류로 실패해도
#     `&&` 가 못 보고 **빈 브랜치를 push** 했다. 규칙(shell-git-procedure 1번)은 7/2x 부터
#     있었는데 그 뒤로도 밟았다 — **판단을 요구하는 규칙은 샌다**(대전제 Ⅳ: 도구에 넣는다).
#
# 🔑 판정 축 (룬드 조건 반영 — 오탐 잠금이 절반이다):
#   ①파이프 끝이 **관찰·자름 도구**  ②그 파이프라인의 rc 가 `&&`/`||` 로 **소비된다**
#   ③파이프 앞머리가 **rc 가 의미 있는(부작용) 명령**   ④`pipefail` 이 없다
#   넷이 **다 참일 때만** 막는다. 하나라도 빠지면 정상 관용구다.
#
# ⚠️ 가장 큰 오탐원은 **내가 보내는 메시지 본문**이다 — 나는 이 사고 예시를 코드블록으로
#    룬드·Tim 에게 자주 보낸다. heredoc·따옴표 안은 **셸이 실행하지 않는 글자**이므로 분석 전에 지운다.
#    (이게 없으면 가드가 자기 사고 설명을 못 보내게 막는다 = 가드를 죽이는 오탐)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="${RC_PIPE_GUARD:-$REPO/claude-config/hooks/rc-pipe-guard.sh}"

pass=0; fail=0; skip=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want rc=$2  got rc=$3"; fail=$((fail + 1)); }

[ -f "$GUARD" ] || { echo "❌ 없음: $GUARD"; exit 1; }

# 🔴 시험이 «운영» 로그를 쓰지 않게 격리한다. 안 하면 이 파일을 한 번 돌릴 때마다
#   BLOCK 이 20여 줄 쌓여 「오늘 몇 번 막혔나」가 «시험 횟수»가 된다 — 세려고 만든 계측기를
#   세는 행위 자체가 오염시킨다. (`#157` 에서 같은 누수를 잡았다: 시험이 운영 상태 파일을 썼다)
#   🔑 격리는 «헬퍼»가 아니라 «환경»에 건다 — 헬퍼에만 걸면 헬퍼를 안 쓰는 호출이 샌다.
#      실제로 ⑥ 절이 `bash "$GUARD"` 를 직접 불러 «운영 로그에 한 줄을 남겼다»(이 절을 쓰다 발견).
_T="$(mktemp -d)"; trap 'rm -rf "$_T"' EXIT
export RC_PIPE_GUARD_LOG="$_T/scratch.log"

# 🔴 **운영 로그 경로를 여기 «다시 적지» 않는다 — 가드에서 «뽑아»온다** (룬드 🟡, `#159` 리뷰).
#   사본이 둘이면 가드의 기본값이 바뀌었을 때 이쪽은 **엉뚱한 파일을 재게 되고**, 그 파일은
#   보통 없으므로 「0줄 → 0줄」로 **영원히 초록**이다. 오염을 막으려고 만든 검사가 조용히 죽는다.
#   🔑 「사본이 N벌이면 하나만 고쳐진다」의 실물이고, 처방은 **한쪽을 유도된 값으로** 만드는 것.
# 🔸 `eval` 을 안 쓴다 — 확장 «시점»이 갈려서 거짓 음성을 낸 적이 있다(코어 `#62`).
#   `$HOME` 만 문자열 치환으로 편다. 가드가 다른 변수를 쓰기 시작하면 아래 검사가 잡는다.
_derive_oplog() {
    local raw
    # 🔴 «주석»이 아니라 «코드»에서 뽑는다 (룬드 🟡) — 가드에 그 변수를 설명하는 주석이 붙으면
    #   `head -1` 이 그 주석을 집는다. **`#166` ⑤ 에서 내가 고친 그 병이고 처방도 같다**:
    #   주석 줄을 먼저 빼고 유도한다. 지금은 가드에 한 줄뿐이라 «아직» 안 물렸을 뿐이다.
    raw="$(LC_ALL=C grep -vE '^[[:space:]]*#' "$1" \
           | LC_ALL=C sed -n 's/.*RC_PIPE_GUARD_LOG:-\([^}]*\)}.*/\1/p' | head -1)"
    printf '%s' "${raw//\$HOME/$HOME}"
}
OPLOG="$(_derive_oplog "$GUARD")"
# 🔴 **「못 뽑았다」를 「깨끗하다」로 접지 않는다** — 빈 값이면 아래 대조가 0줄→0줄로 통과한다.
OPLOG_OK=1
case "$OPLOG" in
    /*.log) : ;;
    *) OPLOG_OK=0 ;;
esac
case "$OPLOG" in *'$'*) OPLOG_OK=0 ;; esac
OPLOG_BEFORE="$([ -f "$OPLOG" ] && wc -l < "$OPLOG" || echo 0)"

# PreToolUse 페이로드를 만들어 먹인다 (기존 가드들과 같은 계약: stdin JSON, exit 2 = 차단)
run() { run_in "$_T/scratch.log" "$1"; }
run_in() {
  local log="$1"; shift
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.stdin.read()}}))' \
    | RC_PIPE_GUARD_LOG="$log" bash "$GUARD" >/dev/null 2>&1
  echo $?
}
blocks()  { local rc; rc="$(run "$2")"; [ "$rc" = "2" ] && ok "$1" || bad "$1" 2 "$rc"; }
passes()  { local rc; rc="$(run "$2")"; [ "$rc" = "0" ] && ok "$1" || bad "$1" 0 "$rc"; }

echo "① 🔑 계측기 먼저 — 가드가 실제로 무언가를 막을 수 있나"
blocks "실사고 원문을 막는다" 'git commit -F msg.txt file.sh | tail -2 && git push'

echo
echo "② 막힘 — 네 조건이 다 참인 자리"
blocks "head 로 끝나고 && 로 소비"      'git push origin main | head -3 && echo done'
blocks "|| 로 소비해도 같다"            'git commit -F m.txt a.sh | tail -1 || echo failed'
blocks "wc 도 관찰 도구다"              'npm ci | wc -l && npm test'
blocks "중간 파이프가 여럿이어도 끝이 기준" 'git commit -F m.txt a.sh | grep x | tail -2 && git push'

echo
echo "②-b 🔴 룬드 실측 미탐 2건 (리뷰 REQUEST_CHANGES) — 둘 다 «흔한 표기»라 사각이 크다"
# ① `git -C` 는 우리 둘 다 cwd 함정 때문에 표준으로 쓰는 관용구다. 막으려는 사고가
#    가장 자주 나타나는 표기로 오면 통과하고 있었다 — 옵션의 «인자»가 하위명령 자리에 남는다.
blocks "git -C <경로> commit"        'git -C /home/bpx27/yaksu-shared-data commit -m x f.md | tail -2 && git push'
blocks "git -c k=v commit"           'git -c core.hooksPath=/dev/null commit -q -m x f.sh | tail -2 && git push'
blocks "git --git-dir=… push"        'git --git-dir=/x/.git push origin main | head -3 && echo done'
# ② `<<<` 는 heredoc 이 아니다. heredoc 으로 오인하면 델리미터가 영영 안 와서
#    **그 뒤 문장 전부가 사각**이 된다 — 무음이라 더 나쁘다.
blocks "herestring 뒤 문장의 위반"    'grep x <<< "abc"
git commit -F m.txt a.sh | tail -2 && git push'

echo
echo "③ 풀림 — 하나라도 빠지면 정상 관용구다 (여기가 오탐 잠금)"
# 🔑 ②-b 의 짝. 「-C 를 읽는다」가 「-C 면 다 막는다」가 되지 않았는지 본다
passes "git -C 인데 읽기 하위명령"    'git -C /x log --oneline | head -5'
passes "git -c 인데 읽기 하위명령"    'git -c a=b status --short | wc -l && echo ok'
passes "herestring 만 있고 위반 없음" 'grep x <<< "abc"
git log --oneline | head -3'
passes "rc 미소비: 그냥 보기만 한다"     'git log --oneline | head -5'
# 🔴 위 줄만으론 **rc 소비 축을 못 가른다** — `git log` 가 부작용 명령이 아니라서
#    소비 조건을 통째로 지워도 통과한다(변이 M2 실증). 부작용 명령으로 축을 분리한다.
passes "rc 미소비 + 부작용 명령 (M2 격리)" 'git commit -F m.txt a.sh | tail -2'
# 🔑 위와 **다른 자리**다. 위는 「`&&` 가 아예 없다」, 아래는 「파이프라인이 **마지막 조각**이라
#    그 뒤에 rc 를 볼 사람이 없다」. 코드에서도 각각 `len(segs)<2` 와 `segs[:-1]` 이 지킨다 —
#    아래 케이스가 없을 때 `segs[:-1]→segs` 변이가 **안 죽었다**(M2' 실증).
passes "마지막 조각의 파이프 (M2' 격리)"  'echo start && git commit -F m.txt a.sh | tail -2'
passes "파이프 없음: rc 가 정직하다"     'git commit -F m.txt a.sh && git push'
passes "rc 를 눈으로 받는 정본 형태"     'git commit -F m.txt a.sh
rc=$?; echo "commit rc=$rc"'
passes "pipefail 이 켜져 있다"           'set -o pipefail; git commit -F m.txt a.sh | tail -2 && git push'
passes "grep 은 관찰 도구가 아니다 (-q 관용구)" 'cat f | grep -q x && echo found'
passes "앞머리가 부작용 없는 명령"       'echo hi | head -1 && echo ok'
passes "관찰 파이프라인끼리 이어짐"      'git status --short | wc -l && git log --oneline | head -3'

echo
echo "④ 🔑 문장 단위로 가른다 — 한 호출에 여러 문장이 산다"
# 이걸 안 하면 「앞 문장의 파이프 + 뒷 문장의 &&」가 붙어 보여서 오탐이 난다
passes "관찰 문장 다음 줄에 정상 커밋"   'git log --oneline | head -3
git commit -F m.txt a.sh && git push'
blocks "여러 문장 중 하나만 위반이어도 막는다" 'git status --short
git commit -F m.txt a.sh | tail -2 && git push
echo done'

echo
echo "⑤ 🔴 오탐 잠금 — 실행되지 않는 글자(본문·주석)는 코드가 아니다"
# 나는 이 사고 예시를 코드블록으로 자주 보낸다. 여기서 막히면 가드가 자기 설명을 못 하게 한다
# 🔴 픽스처 주의 — 예시 줄이 **문장 첫머리에서 부작용 명령으로 시작**해야 이 축이 갈린다.
#    처음엔 `나쁜 예: git commit …` 처럼 앞에 말을 붙였는데, 그러면 첫 낱말이 `나쁜` 이라
#    **is_effect 가 대신 막아준다** — heredoc·따옴표 제거를 통째로 꺼도 초록이었다(변이 M4·M5 실증).
#    🔑 초록의 이유가 내가 적은 이유와 달랐다. 시험 문구가 아니라 **픽스처**가 축을 정한다.
passes "heredoc 본문 안의 예시" 'read -r -d '"'"''"'"' P <<'"'"'EOF'"'"'
git commit -F m.txt a.sh | tail -2 && git push
EOF
./src/discord-send 봇-놀이터 "$P"'
passes "큰따옴표 인자 안의 예시" './src/discord-send 봇-놀이터 "예시:
git commit -F m.txt a.sh | tail -2 && git push"'
passes "작은따옴표 인자 안의 예시" "./src/discord-send 봇-놀이터 '예시:
git commit -F m.txt a.sh | tail -2 && git push'"
passes "주석 안의 예시" '# git commit -F m.txt a.sh | tail -2 && git push
git status'
# 🔴 위 줄도 축을 못 가른다 — 주석 제거를 꺼도 첫 낱말이 `#` 라 is_effect 가 막아준다(변이 M8).
#    **꼬리 주석**이라야 부작용 명령이 문장 첫머리에 남아 주석 제거만 남는다.
passes "꼬리 주석 안의 예시 (M8 격리)" 'git commit -F m.txt a.sh   # 참고: | tail -2 && git push'
# 🔑 대조군: 지우기가 **너무 많이** 지우면 ①이 통과해버린다 → ①이 그 자리를 지킨다

echo
echo "⑥ 차단 메시지가 무엇을 하라는지 말하나 (막기만 하면 사람이 우회한다)"
msg="$(printf '%s' 'git commit -F m.txt a.sh | tail -2 && git push' \
  | python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.stdin.read()}}))' \
  | bash "$GUARD" 2>&1 >/dev/null)"
case "$msg" in
  *'rc='*) ok "처방(rc 를 먼저 받는 형태)이 메시지에 있다" ;;
  *)       bad "차단 메시지에 처방이 없다" "rc= 포함" "«${msg}»" ;;
esac
case "$msg" in
  *pipefail*) ok "대안(pipefail)도 알려준다" ;;
  *)          bad "대안 미안내" "pipefail 언급" "«${msg}»" ;;
esac

echo
echo "⑦ Bash 도구가 아니면 관여하지 않는다"
rc="$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x"}}' | bash "$GUARD" >/dev/null 2>&1; echo $?)"
[ "$rc" = "0" ] && ok "Edit 페이로드는 통과" || bad "Edit 에 관여" 0 "$rc"
rc="$(printf '%s' 'not json at all' | bash "$GUARD" >/dev/null 2>&1; echo $?)"
[ "$rc" = "0" ] && ok "파싱 불가는 통과 (가드가 도구를 못 쓰게 만들면 안 된다)" || bad "파싱 실패 시 차단" 0 "$rc"

echo
echo "⑧ 🔑 차단을 «셀 수 있나» — 이게 없으면 이 가드의 효과가 일화로만 남는다"
# 🔴 왜 생겼나 (2026-08-10): 룬드의 Tim 보고에 「오늘 세 번 막혔다」를 보태놓고 «세지 않고»
#   말했다. 보낼 땐 2건이었고 3분 뒤에 3건이 돼서 «늦게» 참이 됐다. 재셀 유일 경로가
#   내 세션 jsonl 이었는데, 그건 압축되면 사라지고 «남이 검산할 수도 없다».
#   ⇒ 가드가 스스로 세지 못하면 ⏱️「칸의 효과는 채택 시각 이후 사례로만 센다」를 실행할 수단이 없다.
LOGF="$_T/blocked.log"
rc="$(run_in "$LOGF" 'git commit -F m.txt a.sh | tail -2 && git push')"
n="$([ -f "$LOGF" ] && wc -l < "$LOGF" || echo 0)"
[ "$rc" = "2" ] && [ "$n" -eq 1 ] \
  && ok "차단하면 로그가 «한 줄» 늘어난다" \
  || bad "차단이 안 세어진다 (rc=$rc · ${n}줄)" 2 "$rc"

# 🔑 한 줄이어야 한다 — 여러 줄이면 `wc -l` 이 «건수»가 아니게 되고, 세는 방법이 조용히 틀린다.
grep -q '	BLOCK	' "$LOGF" 2>/dev/null \
  && ok "형식이 «시각 TAB BLOCK TAB 사유» 한 줄이다" \
  || bad "로그 형식이 계약과 다르다 — 세는 쪽이 파싱 못 한다" "BLOCK 행" "$(cat "$LOGF" 2>/dev/null)"

# 🧪 대조군 — 「막을 때만」 적나. 없으면 «늘 적는 것»과 구별이 안 되고 건수가 통과까지 센다.
CTRL="$_T/passed.log"
rc="$(run_in "$CTRL" 'git push origin main | tail -3')"
{ [ "$rc" = "0" ] && [ ! -s "$CTRL" ]; } \
  && ok "[대조군] 통과한 명령은 «안» 적는다 (건수가 통과까지 세지 않는다)" \
  || bad "통과도 로그에 남는다 — 건수가 «차단 수»가 아니게 된다 (rc=$rc)" 0 "$rc"

# 🔴 실패 방향 — 로그를 못 써도 «차단은 그대로» 한다. 계측이 안 된다고 조용히 통과하면
#   가드가 로그 경로 하나로 통째로 무력화된다.
rc="$(run_in /proc/nonexistent-dir/x.log 'git commit -F m.txt a.sh | tail -2 && git push')"
[ "$rc" = "2" ] \
  && ok "로그를 못 써도 차단한다 (계측 실패가 가드를 끄지 않는다)" \
  || bad "로그 경로가 막히면 가드가 통과시킨다 — 우회로다" 2 "$rc"

# 🔴 좌변을 «운영 로그»에 둔다 — 위 격리가 실제로 도는지는 그 파일이 안 늘었을 때만 안다.
#   시험 안에서만 확인하면 「격리했다고 적었다」와 「격리됐다」가 구별이 안 된다.
OPLOG_AFTER="$([ -f "$OPLOG" ] && wc -l < "$OPLOG" || echo 0)"
if [ "$OPLOG_OK" != "1" ]; then
    # 🔴 여기서 「통과」를 주면 안 된다 — 좌변이 없는데 초록이 켜진다.
    bad "운영 로그 경로를 «가드에서 못 뽑았다» — 이 대조가 무엇을 재는지 모른다 (뽑힌 값: '$OPLOG')" \
        "절대경로 .log" "$OPLOG"
elif [ "$OPLOG_AFTER" = "$OPLOG_BEFORE" ]; then
    ok "이 시험이 «운영» 로그를 안 건드렸다 (${OPLOG_BEFORE}줄 그대로 — 건수가 시험 횟수로 안 오염된다)"
else
    bad "시험이 운영 로그를 늘렸다 — 「오늘 몇 번 막혔나」가 «시험 횟수»가 된다" \
        "${OPLOG_BEFORE}줄" "${OPLOG_AFTER}줄"
fi

# 🧪 **뽑아오는 계량기가 실제로 «가드를 읽나»** — 상수를 반환해도 위 대조는 초록이다.
#   가드 사본의 기본 경로를 바꿔서 «뽑힌 값이 따라 바뀌는지» 본다. 안 바뀌면 유도가 죽은 것이다.
_MUT="$_T/guard-mut.sh"
LC_ALL=C sed 's#RC_PIPE_GUARD_LOG:-[^}]*}#RC_PIPE_GUARD_LOG:-/tmp/nino-derive-probe.log}#' "$GUARD" > "$_MUT"
if cmp -s "$GUARD" "$_MUT"; then
    echo "  🔸 판정 불가: 변이를 못 심었다 — 가드의 기본값 표기가 바뀌었다(유도식도 같이 봐야 한다)"
    skip=$((skip + 1))
else
    _got="$(_derive_oplog "$_MUT")"
    [ "$_got" = "/tmp/nino-derive-probe.log" ] \
      && ok "🧪 유도가 «가드를 읽는다» — 기본값을 바꾸니 뽑힌 값도 바뀐다(상수 반환이 아니다)" \
      || bad "유도가 가드를 안 읽는다 — 사본이 둘일 때와 같은 상태다" "/tmp/nino-derive-probe.log" "$_got"
fi

# 🧪 **주석 미끼** — 가드에 그 변수를 «설명하는» 주석이 붙어도 «코드»를 뽑나 (룬드 🟡).
#   지금 가드엔 한 줄뿐이라 이 함정이 «아직» 안 물렸다. 그런 자리는 대조군이 없으면
#   **주석 한 줄이 늘어난 날 조용히 틀린다** — 그날 이 시험은 여전히 초록이다.
_BAIT="$_T/guard-bait.sh"
{ head -1 "$GUARD"
  printf '%s\n' '# 기본값은 ${RC_PIPE_GUARD_LOG:-/tmp/미끼-주석.log} 이다 — 설명 주석'
  tail -n +2 "$GUARD"; } > "$_BAIT"
_bait_got="$(_derive_oplog "$_BAIT")"
case "$_bait_got" in
    */미끼-주석.log) bad "유도가 «주석»을 집었다 — 코드가 아니라 설명을 읽는다" "코드의 기본값" "$_bait_got" ;;
    "$OPLOG")       ok "🧪 설명 주석을 앞에 붙여도 «코드»의 기본값을 뽑는다" ;;
    *)              bad "주석 미끼 뒤 유도가 엉뚱한 값을 냈다" "$OPLOG" "$_bait_got" ;;
esac

echo
echo "⑧ 래퍼 — rc 를 «가로채지 않는» 것들을 벗기고 본다 (룬드 #155 동형, 실측 2026-08-11)"
# 🔴 여기 초록이 값을 하려면 **맨몸이 막힌다**가 같이 서 있어야 한다 — 아래 ①·② 가 그 대조군이다.
#   래퍼만 검사하면 「가드가 통째로 고장나서 다 막는다」와 구별이 안 된다.
blocks "관측쪽 «command» (계약이 시키는 손버릇이라 제일 자주 온다)" \
       'git push origin main | command tail -3 && echo ok'
blocks "관측쪽 «timeout <시간>» — 시간 인자가 옵션이 아니라 맨 낱말이다" \
       'git push origin main | timeout 5 tail -3 && echo ok'
blocks "관측쪽 «env VAR=값»"          'git push origin main | env LC_ALL=C wc -l && echo ok'
# 🔑 **효과쪽**은 룬드 판에 없던 축이다 — 그는 관측쪽만 샜다. 나는 긴 git 에 «timeout» 을 쓴다.
blocks "효과쪽 «timeout 60 git push»" 'timeout 60 git push origin main | tail -3 && echo ok'
blocks "효과쪽 «nohup»"               'nohup git push origin main | tail -3 && echo ok'
blocks "래퍼 + «git -C» 가 «겹쳐도» 잡힌다 — 두 수리가 같은 낱말 목록 위에 산다" \
       'timeout 60 git -C /repo commit -m x | tail -3 && echo ok'

echo
echo "⑨ [대조군] 🔴 벗기면 «뜻이 달라지는» 것은 벗기지 않는다 — 틀릴 거면 미탐 쪽으로"
# xargs 는 래퍼가 아니라 자체 실행기라 그 rc 가 xargs 것이다. 벗기면 **오탐**이 되고,
# 오탐은 가드를 죽인다(사람이 꺼버린다). 이 줄이 없으면 다음 사람이 WRAPPERS 에 xargs 를 넣는다.
passes "«xargs tail» 은 안 벗긴다 (rc 가 정말 xargs 것)" \
       'git push origin main | xargs tail -3 && echo ok'
# 🔑 래퍼를 벗겨도 **끝이 관측 도구가 아니면** 여전히 통과여야 한다 — 벗기기가 좌변을
#   넓히기만 한 게 아니라 «옳은 낱말»을 집는지 가른다.
passes "«command python3» 으로 끝나면 그 rc 가 정답이라 안 문다" \
       'git push origin main | command python3 parse.py && echo ok'

echo
# 🔸 `${skip:+ …}` 는 `skip=0` 도 «비어 있지 않음»이라 조건이 «항상 참»이었다(룬드 🟡).
#   그런데 **항상 내는 쪽이 옳다** — 판정 불가 0 도 「쟀는데 0」이라는 값이다. 조건만 뺀다.
echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ] || exit 1
