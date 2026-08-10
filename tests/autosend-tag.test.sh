#!/usr/bin/env bash
# 🤝 자동 발신 `[감시]` 태그 — 셔틀 동작 + 「누가 켰나」 분모
#
# 계약(룬드↔니노 2026-08-10): **자동 발신엔 `[감시]`, 본체가 쓴 것엔 무표시.**
#   부재가 곧 「본체」라서, **자동이 무표시로 나가는 것**이 유일한 나쁜 실패다.
#   ⇒ 이 시험의 좌변도 그 방향으로 잡는다: 「태그가 붙나」보다 **「안 붙고 나가는 길이 있나」**.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIM="$BOT_DIR/src/discord-send"

pass=0; fail=0; skip=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# 가짜 코어 — 받은 인자를 그대로 적는다. 실제 전송은 «절대» 안 한다.
cat > "$WORK/fake-core.js" <<'EOF'
placeholder
EOF
cat > "$WORK/fake-bun" <<EOF
#!/bin/sh
# \$1 = cli 경로, 나머지가 인자
shift
: > "$WORK/argv"
for a in "\$@"; do printf '%s\n' "\$a" >> "$WORK/argv"; done
exit 0
EOF
chmod +x "$WORK/fake-bun"

# 🔴 환경과 인자를 «--» 로 가른다. 안 가르면 `env` 가 첫 인자를 «명령 이름»으로 읽어
#   rc=127 이 나고, 그게 「셔틀이 거절했다」와 구별이 안 된다(초안에서 실제로 밟았다).
run_shim() {   # run_shim <VAR=VAL…> -- <셔틀 인자…>
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    [ "${1:-}" = "--" ] && shift
    : > "$WORK/argv"; : > "$WORK/err"
    env DISCORD_SEND_BUN="$WORK/fake-bun" DISCORD_SEND_CORE_CLI="$WORK/fake-core.js" \
        ${envs[@]+"${envs[@]}"} bash "$SHIM" "$@" >"$WORK/out" 2>"$WORK/err"
    RC=$?
    return 0
}
last_arg() { tail -1 "$WORK/argv" 2>/dev/null; }

echo "── ① 자동(NINO_AUTOSEND) 이면 «마지막 인자»에 태그가 붙는다 ──"
run_shim NINO_AUTOSEND=1 -- 봇-놀이터 "테스트 본문"
[ "$RC" = 0 ] && [ "$(last_arg)" = "[감시] 테스트 본문" ] \
  && ok "정본 문법 — 메시지에 [감시] 가 붙는다" \
  || bad "자동 태그" "[감시] 테스트 본문 (rc=0)" "$(last_arg) (rc=$RC)"

run_shim NINO_AUTOSEND=1 -- 봇-놀이터 -r ab12 "답장 본문"
[ "$RC" = 0 ] && [ "$(last_arg)" = "[감시] 답장 본문" ] \
  && ok "-r 플래그가 섞여도 «메시지»에만 붙는다" \
  || bad "-r 혼합" "[감시] 답장 본문" "$(last_arg) (rc=$RC)"

# 🔑 앞쪽 인자가 안 망가졌는지도 본다 — 「붙였다」만 보면 target 이 깨져도 초록이다
[ "$(head -1 "$WORK/argv")" = "봇-놀이터" ] \
  && ok "  → 앞 인자(target)는 그대로다" \
  || bad "target 훼손" "봇-놀이터" "$(head -1 "$WORK/argv")"

echo
echo "── ② 본체(변수 없음)면 «아무것도» 안 붙는다 ──"
run_shim -- 봇-놀이터 "사람이 쓴 본문"
[ "$RC" = 0 ] && [ "$(last_arg)" = "사람이 쓴 본문" ] \
  && ok "무표시로 나간다 — 부재가 곧 「본체」" \
  || bad "본체 무표시" "사람이 쓴 본문" "$(last_arg) (rc=$RC)"

run_shim NINO_AUTOSEND= -- 봇-놀이터 "빈 값도 해제다"
[ "$(last_arg)" = "빈 값도 해제다" ] \
  && ok '빈 문자열은 «해제»다 — :- 가 아니라 - 의미론' \
  || bad "빈값 해제" "빈 값도 해제다" "$(last_arg)"

echo
echo "── ③ 🔴 메시지를 «못 고르면» 조용히 넘기지 않고 거절한다 ──"
# 이게 이 시험의 핵심이다. 여기서 rc=0 이면 «자동 발신이 무표시로» 나간다.
run_shim NINO_AUTOSEND=1 -- 봇-놀이터 --target
[ "$RC" = 2 ] \
  && ok "마지막 인자가 '-' 로 시작하면 rc=2 — 무표시 발송을 막는다" \
  || bad "모호할 때 거절" "rc=2" "rc=$RC · 보낸 인자: $(last_arg)"
[ ! -s "$WORK/argv" ] \
  && ok "  → 거절했으면 코어를 «안 부른다»(0건 전송)" \
  || bad "거절인데 호출됨" "argv 비어 있음" "$(cat "$WORK/argv")"
LC_ALL=C grep -q "NINO_AUTOSEND" "$WORK/err" \
  && ok "  → 왜 막혔는지 stderr 에 적는다" \
  || bad "진단문" "NINO_AUTOSEND 언급" "$(cat "$WORK/err")"

echo
echo "── ④ 🧪 변이 대조군 — 태그 로직을 빼면 ①이 빨개지나 ──"
# 항진명제 방지: 이 시험이 «태그 유무»를 실제로 가르는지 그 자리에서 확인한다.
_mut="$WORK/shim-mut"; sed 's/"\[감시\] \${_args/"${_args/' "$SHIM" > "$_mut"
if ! cmp -s "$SHIM" "$_mut"; then
    : > "$WORK/argv"
    env DISCORD_SEND_BUN="$WORK/fake-bun" DISCORD_SEND_CORE_CLI="$WORK/fake-core.js" \
        NINO_AUTOSEND=1 bash "$_mut" 봇-놀이터 "변이 본문" >/dev/null 2>&1
    [ "$(last_arg)" = "변이 본문" ] \
      && ok "🧪 태그 문자열을 지우면 붙지 않는다 — ①은 항진명제가 아니다" \
      || bad "변이 대조군" "태그 없는 본문" "$(last_arg)"
else
    echo "  🔸 판정 불가: 변이를 못 심었다(셔틀 문구가 바뀌었다)"; skip=$((skip + 1))
fi

echo
echo "── ⑤ 분모 — discord-send 를 부르는 «자동» 스크립트가 전부 켰나 ──"
# 🔑 열거하지 않고 «유도»한다: scripts/ 에서 셔틀을 부르는 파일 전부가 분모다.
#    새 cron 스크립트를 추가해도 자동으로 이 분모에 들어온다.
# 🔸 면제는 «이름 + 이유»로만. 사람이 손으로 돌리는 것들이다.
exempt_reason() {
    case "$1" in
        scripts/setup.sh)            echo "사람이 1회 돌리는 설치 스크립트" ;;
        *) echo "" ;;
    esac
}
# 🔴 «언급»이 아니라 «호출»을 유도한다 — 주석에 이름만 있는 파일이 딸려오면 분모가 부푼다.
#   실물: `scripts/lib/core-runtime-files.sh` 는 주석에서 `discord-send` 를 «인용»만 하는데
#   `grep -l` 로는 호출자로 잡혔다. (오늘 portability 시험에서 밟은 것과 «같은 병»:
#   「유도된 분모는 유도식이 «보는 것»만큼만 넓다」.)
#   ⇒ 주석 줄(`#` 로 시작)을 뺀 뒤에도 남는 파일만 호출자로 센다.
CALLERS="$(
  for _f in "$BOT_DIR"/scripts/*.sh "$BOT_DIR"/scripts/*/*.sh; do
      [ -f "$_f" ] || continue
      LC_ALL=C grep -vE '^[[:space:]]*#' "$_f" 2>/dev/null | LC_ALL=C grep -q 'discord-send' \
        && printf '%s\n' "${_f#$BOT_DIR/}"
  done | sort
)"
n_all=0; n_on=0; n_ex=0
for f in $CALLERS; do
    n_all=$((n_all + 1))
    if LC_ALL=C grep -qE '^[[:space:]]*export[[:space:]]+NINO_AUTOSEND=' "$BOT_DIR/$f"; then
        n_on=$((n_on + 1)); continue
    fi
    why="$(exempt_reason "$f")"
    if [ -n "$why" ]; then n_ex=$((n_ex + 1)); echo "  🔸 면제: $f — $why"; continue; fi
    bad "자동 발신인데 [감시] 를 안 켰다: $f" "export NINO_AUTOSEND=1" "없음"
done
echo "  분모 $n_all (켬 $n_on · 면제 $n_ex)"
[ "$n_all" -gt 0 ] \
  && ok "분모가 «유도»됐다 — scripts/ 에서 셔틀 호출자 $n_all 개" \
  || bad "분모 0" "1개 이상" "0 — 유도식이 아무것도 못 봤다(패턴이 낡았나)"

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ]
