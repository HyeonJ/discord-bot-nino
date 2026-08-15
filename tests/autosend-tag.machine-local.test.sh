#!/usr/bin/env bash
# 🤝 자동 발신 `[감시]` 태그 — 셔틀 동작 + 「누가 켰나」 분모
#
# 🔴 파일명의 `.machine-local.` 은 «분모»를 말한다 — 이 시험의 「누가 켰나」 절은
#   **작업 트리 전체**(untracked 포함)를 훑는다. 그래서 답이 «기계마다 다르다»:
#     · 내 기계  — 커밋 안 한 자동 발신자까지 잡는다 ⇒ 빨개질 수 있다
#     · CI       — 추적 파일만 체크아웃하니 그 분모가 «비어» 매번 초록이다
#   ⚠️ 그 초록은 **통과가 아니라 「분모가 빈 채 통과」**다 — 그 축에 대해 관측이 아니다
#      (계약: 「좌변이 빈 가드는 매번 초록이라 완전히 무음이다」).
#   ⇒ 원장에는 **실패가 아니라 «판정 불가»**로 실린다(룬드↔니노 2026-08-11).
#
#   🔑 **분모를 «추적 파일»로 좁히지 «않는다»** — 그러면 「아직 커밋 안 한 자동 발신자」
#      축이 통째로 죽는다. 둘은 다른 질문에 답한다:
#        작업 트리  = 「이 «기계»에 지금 위반이 있나」   ← 이 파일
#        추적 파일  = 「«레포»에 위반이 있나」            ← model-names-single-source
#      **문제는 분모가 둘인 게 아니라 이름이 그걸 안 말하는 것**이었다. 그래서 이름에 박는다.
#      (Darren 판정 2026-08-11 `M:qjwd` — 「A 유지 + 이름 바꾸기」. 러너 집계를 «칸으로»
#       가르는 것은 원장 스키마 변경이라 별건이고 룬드 동의가 필요하다.)
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

# 🔴 **가짜 BOT_DIR — 이게 없으면 이 시험은 «내 기계에서만» 돈다.**
#   셔틀이 `$BOT_DIR/.env` 를 절대경로로 source 하는데 CI 엔 그 경로가 없다. `set -e` 아래라
#   그 줄에서 죽고, 태그 로직은 `exec` 앞이라 **거기까지 못 간다** ⇒ rc=1.
#   로컬엔 `.env` 가 있어서 초록이었다 — **초록이 「태그가 붙는다」의 증거가 아니라
#   「내 기계에 `.env` 가 있다」의 증거**였다(2026-08-10 `#166` CI 빨강에서 잡혔다).
#   ⇒ 격리와 같은 처방이다: **호출 자리가 아니라 «환경»에 건다.**
FAKE_BOT="$WORK/bot"; mkdir -p "$FAKE_BOT/config" "$FAKE_BOT/logs"
printf 'DISCORD_BOT_TOKEN=fake-token-for-test\n' > "$FAKE_BOT/.env"
printf '{}\n' > "$FAKE_BOT/config/channel-map.json"
printf '{}\n' > "$FAKE_BOT/config/mention-map.json"

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
        DISCORD_SEND_BOT_DIR="$FAKE_BOT" \
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
echo "── ③-b 🔴 진단문이 시킨 복구가 «실제로» 통한다 ──"
# 🔴 안내가 거짓이면 rc=2 는 「엄격한 실패」가 아니라 **알림이 안 나간 것**이다.
#   이 계약이 막으려던 건 「무표시 발송」이지 「발송 없음」이 아니다 — 출구가 없으면 방향이 뒤집힌다.
#   실물(룬드 `#166` 리뷰): 안내대로 `--` 뒤에 둬도 마지막 인자만 봐서 같은 rc=2, 전송 0건이었다.
#   자동 알림이 마크다운 리스트(`- 항목`)로 시작하면 그대로 걸린다.
run_shim NINO_AUTOSEND=1 -- 봇-놀이터 -- "- 첫 항목"
[ "$RC" = 0 ] && [ "$(last_arg)" = "[감시] - 첫 항목" ] \
  && ok "'--' 뒤의 메시지는 '-' 로 시작해도 태그되어 나간다" \
  || bad "-- 복구" "[감시] - 첫 항목 (rc=0)" "$(last_arg) (rc=$RC)"
# 🔸 `wc -l` 은 BSD 에서 «공백 패딩»이 붙는다 — 문자열이 아니라 «수»로 비교한다(이식성 가드)
# 🔴 **`--` 를 «먹지» 않는다 — 코어가 이미 먹는다.** 초안은 「코어가 positional 파서라 밀린다」는
#   «거짓 전제» 위에서 셔틀이 `--` 를 지웠고, 그러면 **리터럴 계약이 깨진다**(룬드 `#166` 리뷰).
#   ⇒ 여기서는 **주장을 restate 하지 않고 «코어 파서에 직접 물어본다»** — 순수 함수라 부작용 0.
[ "$(head -1 "$WORK/argv")" = "봇-놀이터" ] \
  && ok "  → target 은 그대로다" \
  || bad "target 훼손" "봇-놀이터" "$(tr '\n' '|' < "$WORK/argv")"
_PARSER="${CORE_PARSER:-/home/bpx27/yaksu-bot-core-live/relay/discord-send/parser.js}"
if [ -r "$_PARSER" ] && command -v node >/dev/null 2>&1; then
    _verdict="$(node -e '
const {parse}=require(process.argv[1]);
const g=a=>{try{const r=parse(a);return JSON.stringify([r.target,r.message,!!r.silent]);}catch(e){return "THROW";}};
const A=g(["봇-놀이터","--","[감시] - 첫 항목"]), B=g(["봇-놀이터","[감시] - 첫 항목"]);
const D=g(["봇-놀이터","--","--silent","메시지"]),  E=g(["봇-놀이터","--silent","메시지"]);
console.log((A===B?"AB같음":"AB다름")+" "+(D==="THROW"?"D던짐":"D안던짐")+" "+(E===D?"DE같음":"DE다름"));
' "$_PARSER" 2>&1)"
    case "$_verdict" in
        "AB같음 D던짐 DE다름")
            ok "  → 🧪 코어 파서에 직접 물었다: '--' 를 넘겨도 결과가 같고(A≡B), 먹으면 리터럴 계약이 깨진다(D 던짐 ≠ E)" ;;
        *)  bad "코어 파서 대조가 예상과 다르다 — '--' 를 안 먹는 근거가 흔들린다" \
                "AB같음 D던짐 DE다름" "$_verdict" ;;
    esac
else
    echo "  🔸 판정 불가: 코어 파서를 못 읽었다($_PARSER) — '--' 를 «안 먹는» 근거를 그 자리에서 못 쟀다"
    skip=$((skip + 1))
fi
# 🔸 출구가 «생겼다»고 «막던 것»이 풀리면 안 된다 — `--` 없는 원래 모호함은 그대로 거절한다.
run_shim NINO_AUTOSEND=1 -- 봇-놀이터 "--"
[ "$RC" = 2 ] \
  && ok "  → '--' 가 «마지막»이면(뒤에 메시지 없음) 여전히 rc=2" \
  || bad "-- 만 있을 때" "rc=2" "rc=$RC · $(last_arg)"

echo
echo "── ③-c 🔴 감시가 «본체»를 띄울 땐 변수를 벗긴다 — 경계를 넘는 자리 ──"
# 🔑 「환경에 건다」는 자식이 «같은 종류»일 때만 맞다. 감시가 감시를 부르면 상속이 맞고,
#   **감시가 본체를 띄우면** 사람이 쓴 말이 `[감시]` 로 나간다(룬드 `#166` 리뷰).
# 🔴 tmux 서버는 한 번 오염되면 «변수 없이» 만든 세션도 물려받는다 — 양쪽 실측
#   (룬드 맥 3.6a · 니노 WSL 3.4). 되돌리려면 서버를 죽여야 하므로 «새기 전»에 벗긴다.
WD="$BOT_DIR/scripts/nino-watchdog.sh"
if [ -f "$WD" ]; then
    LC_ALL=C grep -qE 'env[[:space:]]+-u[[:space:]]+NINO_AUTOSEND[[:space:]]+"\$@"' "$WD" \
      && ok "복구 목(wd_restart)이 env -u 로 변수를 벗기고 자식을 띄운다" \
      || bad "복구 목이 변수를 그대로 물려준다 — 본체 발신이 [감시] 로 나간다" \
             'env -u NINO_AUTOSEND "$@"' "$(LC_ALL=C grep -nE '^\s+.*"\$@" >> "\$LOG"' "$WD")"
    # 🧪 실행 대조군 — 문자열만 보면 「적혀 있다」와 「그렇게 «돈다»」가 안 갈린다.
    #    wd_restart 만 떼어내 진짜로 돌린다.
    cat > "$WORK/wdprobe.sh" <<'PROBE'
export NINO_AUTOSEND=1
LOG=/dev/null
CLI_DRY_RUN=0
PROBE
    LC_ALL=C sed -n '/^wd_restart() {/,/^}/p' "$WD" >> "$WORK/wdprobe.sh"
    printf 'wd_restart /usr/bin/env sh -c %s\n' \
      "'printenv NINO_AUTOSEND > \"\$0\" 2>&1 || echo NONE > \"\$0\"' $WORK/inherit.txt" \
      >> "$WORK/wdprobe.sh"
    : > "$WORK/inherit.txt"
    bash "$WORK/wdprobe.sh" >/dev/null 2>&1
    _inh="$(cat "$WORK/inherit.txt" 2>/dev/null)"
    if [ -z "$_inh" ]; then
        echo "  🔸 판정 불가: 프로브가 아무것도 안 적었다 — wd_restart 를 못 떼어냈다"; skip=$((skip + 1))
    elif [ "$_inh" = "NONE" ]; then
        ok "🧪 실제로 돌려보니 자식에 변수가 «없다» (문자열이 아니라 동작으로 확인)"
    else
        bad "🧪 자식이 변수를 물려받았다 — 벗김이 안 돈다" "NONE" "$_inh"
    fi
else
    echo "  🔸 판정 불가: $WD 가 없다"; skip=$((skip + 1))
fi

echo
echo "── ④ 🧪 변이 대조군 — 태그 로직을 빼면 ①이 빨개지나 ──"
# 항진명제 방지: 이 시험이 «태그 유무»를 실제로 가르는지 그 자리에서 확인한다.
_mut="$WORK/shim-mut"; sed 's/"\[감시\] \${_args/"${_args/' "$SHIM" > "$_mut"
if ! cmp -s "$SHIM" "$_mut"; then
    : > "$WORK/argv"
    env DISCORD_SEND_BUN="$WORK/fake-bun" DISCORD_SEND_CORE_CLI="$WORK/fake-core.js" \
        DISCORD_SEND_BOT_DIR="$FAKE_BOT" \
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
        # 🔸 시험은 «클래스로» 면제한다 — 자동 발신자가 아니라 셔틀을 **가짜 코어에 대고** 부른다.
        #   여기에 태그를 켜면 시험이 재는 값이 바뀐다(그리고 실채널로 안 나간다).
        tests/*)                     echo "시험 — 가짜 코어에 대고 부른다(자동 발신자가 아니다)" ;;
        *) echo "" ;;
    esac
}
# 🔴 «언급»이 아니라 «호출»을 유도한다 — 주석에 이름만 있는 파일이 딸려오면 분모가 부푼다.
#   실물: `scripts/lib/core-runtime-files.sh` 는 주석에서 `discord-send` 를 «인용»만 하는데
#   `grep -l` 로는 호출자로 잡혔다. (오늘 portability 시험에서 밟은 것과 «같은 병»:
#   「유도된 분모는 유도식이 «보는 것»만큼만 넓다」.)
#   ⇒ 주석 줄(`#` 로 시작)을 뺀 뒤에도 남는 파일만 호출자로 센다.
# 🔴 **좌변을 «꼴의 열거»로 적으면 열거 밖이 남는다 — 두 번 당했다** (룬드 `#166` 리뷰 두 차례).
#   1차: `scripts/*.sh` 만 봐서 JS 발신자가 안 보였다.
#   2차: `+ src/*.js` 로 넓혔더니 **`relay-addons/*.js` 가 여전히 밖**이었고, 정작 운영에서
#        도는 발신자가 거기였다(`relay-addons/health-checker.js:80`). 넓혔는데 **여전히 열거**였다.
#   ⇒ **뜻으로 적는다: 「셔틀을 «부르는» 파일 전부」.** 디렉터리를 손으로 세지 말고
#     **이 레포의 정본 목록**(`tests/deps-declared.test.sh` 의 `SCAN_DIRS`)에서 유도한다.
#     두 자리가 갈리면 「하나가 조용히 좁아진다」가 또 난다.
# 🔴 그 유도가 «실패»하면 열거로 물러서지 않는다 — 좁아지는 걸 모르게 되니까. 빨강으로 말한다.
SCAN_SRC="$BOT_DIR/tests/deps-declared.test.sh"
SCAN_DIRS_LINE="$(LC_ALL=C grep -vE '^[[:space:]]*#' "$SCAN_SRC" 2>/dev/null \
                  | LC_ALL=C sed -n 's/^SCAN_DIRS=(\(.*\))[[:space:]]*$/\1/p' | head -1)"
if [ -z "$SCAN_DIRS_LINE" ]; then
    bad "정본 SCAN_DIRS 를 «못 뽑았다» — 분모의 넓이를 모른다" "SCAN_DIRS=(…)" "$SCAN_SRC 에서 못 찾음"
fi
_strip_comments() {   # $1 = 파일
    case "$1" in
        *.js) LC_ALL=C grep -vE '^[[:space:]]*(//|\*|/\*)' "$1" 2>/dev/null ;;
        *)    LC_ALL=C grep -vE '^[[:space:]]*#' "$1" 2>/dev/null ;;
    esac
}
# 🔸 켜는 «꼴»이 언어마다 다르다. JS 는 **모듈 최상위가 아니라 «발송 자리»**에 걸어야 해서
#   (`execSync(…, { env: { …process.env, NINO_AUTOSEND: '1' } })`) 꼴이 하나로 안 굳는다 —
#   그래서 JS 쪽은 「주석이 아닌 코드에 그 이름이 있나」로 본다. 느슨한 대신 **실동작 대조군**
#   (①~③-b)이 그 축을 따로 잡는다.
_has_switch() {
    case "$1" in
        *.js) _strip_comments "$1" | LC_ALL=C grep -q 'NINO_AUTOSEND' ;;
        *)    LC_ALL=C grep -qE '^[[:space:]]*export[[:space:]]+NINO_AUTOSEND=' "$1" ;;
    esac
}
CALLERS="$(
  for _d in $SCAN_DIRS_LINE; do
      [ -d "$BOT_DIR/$_d" ] || continue
      find "$BOT_DIR/$_d" -type f \( -name '*.sh' -o -name '*.js' \) 2>/dev/null
  done | while read -r _f; do
      [ -f "$_f" ] || continue
      # 🔴 **이름이 «둘»이다** — 운영에서 도는 발신자는 리터럴 `discord-send` 를 안 쓰고
      #   `DISCORD_SEND_BIN` 으로 간접 참조한다(`relay-addons/health-checker.js:85`).
      #   리터럴만 보면 **정본 발신자가 통째로 안 보인다** — 열거의 셋째 얼굴이다.
      _strip_comments "$_f" | LC_ALL=C grep -qE 'discord-send|DISCORD_SEND_BIN' \
        && printf '%s\n' "${_f#$BOT_DIR/}"
  done | sort -u
)"
n_all=0; n_on=0; n_ex=0
for f in $CALLERS; do
    n_all=$((n_all + 1))
    if _has_switch "$BOT_DIR/$f"; then
        n_on=$((n_on + 1)); continue
    fi
    why="$(exempt_reason "$f")"
    if [ -n "$why" ]; then n_ex=$((n_ex + 1)); echo "  🔸 면제: $f — $why"; continue; fi
    bad "자동 발신인데 [감시] 를 안 켰다: $f" "export NINO_AUTOSEND=1" "없음"
done
echo "  분모 $n_all (켬 $n_on · 면제 $n_ex · 훑은 디렉터리: $SCAN_DIRS_LINE)"
[ "$n_all" -gt 0 ] \
  && ok "분모가 «유도»됐다 — 셔틀 호출자 $n_all 개 (정본 SCAN_DIRS 에서)" \
  || bad "분모 0" "1개 이상" "0 — 유도식이 아무것도 못 봤다(패턴이 낡았나)"

# 🧪 **닻(anchor) — 「운영에서 «실제로» 도는 발신자」가 분모 안에 있나.**
# 🔴 앞판의 가드는 「JS ≥ 1」이었는데, 그건 **죽은 사본 하나로 만족됐다**(`src/health-checker.js`
#   는 운영 진입점이 0건이다). **수를 세는 가드는 «어느 것인지»를 안 묻는다.**
#   ⇒ 이름으로 못 박는다. 유도가 좁아지면 여기서 «빨강»으로 말한다.
#   🔸 열거지만 «분모»의 열거가 아니라 «분모가 반드시 포함해야 할 것»의 열거다 —
#     빠지는 쪽으로만 실패하고, 새 발신자를 놓치는 것은 위 유도가 잡는다.
for _anchor in relay-addons/health-checker.js scripts/nino-watchdog.sh; do
    printf '%s\n' "$CALLERS" | LC_ALL=C grep -qx "$_anchor" \
      && ok "🧪 닻: 운영 발신자 $_anchor 가 분모 안에 있다" \
      || bad "🧪 닻이 분모 밖이다: $_anchor — 유도가 조용히 좁아졌다" "분모 포함" "없음"
done

echo
echo "── ⑥ 🔴 이음매가 «기본값»이 되지 않았나 — 안 걸면 하드코딩 경로로 간다 ──"
# 🔑 위 시험 전부가 `DISCORD_SEND_BOT_DIR` 를 걸고 돈다. 그러면 **셔틀이 그 변수 «없이»도
#   제 경로로 가는지**는 아무도 안 잰다 — 이음매가 조용히 정본이 되는 길이다.
#   (이 파일 머리의 「정체 고정」이 지키려던 바로 그 값이다.)
NINO_HOME="/home/bpx27/discord-bot-nino"
LC_ALL=C grep -q -- ":-$NINO_HOME}" "$SHIM" \
  && ok "안 걸었을 때의 기본값이 하드코딩 경로다 (정적)" \
  || bad "기본값" ":-$NINO_HOME}" "$(LC_ALL=C grep -n 'BOT_DIR=' "$SHIM")"

# 🔸 위는 «문자열» 좌변이라 재서술에 죽는다. 실제로 그 경로로 «가는지»는 셔틀을 돌려야 재진다.
#
# 🔴 **여기 있던 판정 불가가 «원장에 안 보이는» 판정 불가였다** (룬드 `#170` 리뷰).
#   초안은 *「`.env` 가 있어야 재니까 CI 에선 못 잰다」*로 적고 `skip++` 했는데, 러너는
#   **파일 rc 로만** 분류하므로(`scripts/run-tests.sh:307`) 파일이 rc=0 이면 원장엔 **통과**로만
#   실린다 ⇒ **CI 에선 이 축이 «항상» 판정 불가인데 그 사실이 어디에도 안 남는다.**
#   하필 `#170` 이 자기 이음매의 근거로 든 시험이 이것이었다.
# 🔑 **고친 방향은 「판불을 보이게」가 아니라 「부재로 잰다」다** — `.env` 가 없으면 셔틀은
#   `source "$BOT_DIR/.env"` 에서 **그 경로를 짚으며** 죽는다(`set -e`). ⇒ 「어느 BOT_DIR 로
#   갔나」를 **stderr 가 말해준다.** 부재는 이 축을 못 재게 하는 조건이 아니라 «다른 관측»이다.
: > "$WORK/argv"; : > "$WORK/env"
cat > "$WORK/fake-bun-env" <<EOF
#!/bin/sh
printf '%s\n' "\$CHANNEL_MAP" > "$WORK/env"
exit 0
EOF
chmod +x "$WORK/fake-bun-env"

# 🧪 **대조군 — 탐지기 자신을 «모든 기계»에서 잰다.** 아래 본 검사는 기계에 따라 갈래가 갈리므로,
#   「죽을 때 stderr 가 BOT_DIR 를 말해준다」가 참인지는 여기서 따로 세운다. 이게 없으면
#   본 검사의 음성(=문구 없음)이 「경로가 다르다」인지 「원래 안 말해준다」인지 못 가른다.
_probe="$(env DISCORD_SEND_BOT_DIR="$WORK/nope" DISCORD_SEND_BUN="$WORK/fake-bun-env" \
              DISCORD_SEND_CORE_CLI="$WORK/fake-core.js" \
              bash "$SHIM" 봇-놀이터 x 2>&1 >/dev/null)"; _prc=$?
if [ "$_prc" -ne 0 ] && printf '%s\n' "$_probe" | LC_ALL=C grep -qF "$WORK/nope/.env"; then
    ok "🧪 대조군: env 파일이 없으면 셔틀이 «그 BOT_DIR 를 짚으며» 죽는다 (탐지기가 선다)"
else
    bad "🧪 대조군 — 탐지기가 안 선다" "rc≠0 + '$WORK/nope/.env' 언급" "rc=$_prc · $_probe"
fi

if [ -r "$NINO_HOME/.env" ]; then
    env DISCORD_SEND_BUN="$WORK/fake-bun-env" DISCORD_SEND_CORE_CLI="$WORK/fake-core.js" \
        bash "$SHIM" 봇-놀이터 "기본값 확인" >/dev/null 2>&1
    [ "$(cat "$WORK/env" 2>/dev/null)" = "$NINO_HOME/config/channel-map.json" ] \
      && ok "  → 실제로 그 경로의 config 를 코어에 넘긴다 (실측 · env 파일 있는 기계)" \
      || bad "기본 BOT_DIR" "$NINO_HOME/config/channel-map.json" "$(cat "$WORK/env" 2>/dev/null)"
else
    # 🔑 CI 가 도는 갈래. 「실행에서도 기본값이 그 값인가」를 **부재로** 잰다.
    _err="$(env DISCORD_SEND_BUN="$WORK/fake-bun-env" DISCORD_SEND_CORE_CLI="$WORK/fake-core.js" \
                bash "$SHIM" 봇-놀이터 "기본값 확인" 2>&1 >/dev/null)"; _erc=$?
    if [ "$_erc" -ne 0 ] && printf '%s\n' "$_err" | LC_ALL=C grep -qF "$NINO_HOME/.env"; then
        ok "  → 이음매 없이 돌리면 «$NINO_HOME/.env» 를 짚는다 (실측 · env 파일 없는 기계)"
    else
        bad "기본 BOT_DIR(부재 축)" "rc≠0 + '$NINO_HOME/.env' 언급" "rc=$_erc · $_err"
    fi
fi

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ]
