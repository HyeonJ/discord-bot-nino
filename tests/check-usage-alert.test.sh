#!/usr/bin/env bash
# check-usage-alert.sh 계약 시험 — **이 검사가 429 를 볼 수 있는가**
#
# 🔴 이 시험이 생긴 이유 (2026-07-31 실측):
#   `curl -s …` 에 `-w` 도 `-f` 도 없어서 **상태코드를 안 봤고**, 로그 파일이 **아예 없었다.**
#   429 본문은 `json.loads` 를 통과하고 버킷이 없어 조용히 `exit 0` 이 된다.
#   ⇒ *"내 로그에 429 없었다"* 는 증거가 아니라 **침묵**이었다. 30분마다 맞고 있었어도 흔적 0.
#
# 🔑 룬드가 자기 쪽에서 소비자 구조를 찾은 근거가 **로그**였다(429 12회 · 자기 호출 → 백오프).
#   로그가 없으면 *"가끔 429가 난다"* 로 끝난다. ⇒ 관측이 조율(공유 백오프)의 선결이다.
#
# ⚠️ 부작용 금지: 실제 API·실제 Discord·실제 ~/.claude 를 안 건드린다. 전부 주입으로 대체한다.
#
# 이식성: bash 3.2 / BSD (룬드 맥) — 원시 `wc -l`·`touch -d`·`stat -c` 를 쓰지 않는다.
#   [[ref_bash_portability_32]] · check-auth.test.sh ⑮ 와 같은 규약.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO/scripts/check-usage-alert.sh"

. "$SCRIPT_DIR/lib/capture-rc.sh"

pass=0; fail=0; skip=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
skipt() { echo "  ⛔ $1"; echo "     사유: $2"; skip=$((skip + 1)); }

# ── 코어 위치 해석 ───────────────────────────────────────────────────────────
# 🔴 2026-07-31 룬드 맥에서 **28 fail** (`#102` 리뷰). 시험이 `CORE_REPO` 를 안 세워
#   스크립트의 **운영 기본값**(`~/yaksu-bot-core-live`)이 그대로 쓰였는데, 그건 니노 전용
#   경로다. 룬드 코어는 `~/yaksu-bot-core` 라 전부 `no_cli_guard` 로 죽었다.
#   🔑 운영 기본값은 맞다 — **틀린 것은 시험이 그 값을 안 세운 것**이다.
#   🔑 원인이 *내가 가진 것*이라 내 기계에선 원리적으로 안 보인다(nvm 때와 같은 자리).
#     상대 기계가 유일한 관찰자였고, 이 해석기가 그 관찰을 내 쪽으로 옮겨온다.
#
# 🔸 스텁 `cli-guard.sh` 를 깔지 않고 **실물 정본**을 쓴다(룬드 제안과 갈린 지점).
#   스텁은 사본이라 코어 계약이 바뀌어도 내 시험은 계속 초록이다 — 오늘 이미 밟은
#   *"사본이 N벌이면 갈린다"* 가 그대로 재현된다. 부재 갈래는 어차피 빈 디렉터리로 만든다.
CORE_FIXTURE=""
for _c in "${CORE_REPO:-}" "$HOME/yaksu-bot-core-live" "$HOME/yaksu-bot-core"; do
    [ -n "$_c" ] && [ -r "$_c/scripts/cli-guard.sh" ] && { CORE_FIXTURE="$_c"; break; }
done
# 🔴 **한 곳에서 export 한다** — 호출부마다 붙이지 않는다.
#   처음엔 `run()`·`runargs()` 두 곳에만 넣었는데, 이 파일엔 스크립트를 부르는 자리가
#   **다섯 곳**이라 나머지 셋이 안 덮였고 룬드 맥 흉내에서 1 fail 로 남았다.
#   🔑 한 시간 전에 `nino-watchdog.sh` 4곳을 두고 *"덮인 3곳이 안 덮인 1곳을 가린다"* 고
#     써놓고, 같은 것을 내 시험 파일에서 그대로 했다. **길목을 하나로 만드는 것이 처방이고,
#     호출부를 세어 붙이는 것은 다음 호출부가 생기면 다시 샌다.**
#   ⇒ 이후 `env …` 로 부르는 자리는 전부 물려받는다. 부재 갈래만 **일부러** 덮어쓴다.
export CORE_REPO="$CORE_FIXTURE"

[ -f "$CHECK" ] || { echo "❌ 없음: $CHECK"; exit 1; }
# 🔴 **씨앗 회수를 «직선 코드»에 두면 안 된다 — 죽는 갈래에서 «운영 자리»에 남는다** (룬드 `#169` 리뷰).
#   실측: 씨앗 심긴 뒤 SIGTERM → 두 상태 파일이 씨앗인 채 남고, **그 상태로 시험을 정상 완주시키면
#   rc=0 · ❌0 인데 씨앗은 그대로**다. 아래 씨앗 로직이 `[ ! -e ]` 일 때만 심으므로 **남은 씨앗은
#   다음 실행에서 안 심고 안 지운다** = **자가 치유가 구조적으로 불가능**하고, BEFORE·AFTER 가 둘 다
#   씨앗이라 **⑮ 는 초록**이다 — **오염을 재는 장치가 «자기가 만든 오염»에 무음**이다.
#   그 뒤 운영 스크립트가 그걸 `prev_band` 로 읽어 **항상 전이**를 만든다.
#   🔑 「검증하느라 만든 것이 검증 대상에 상태를 남긴다」의 실물이고, **`#163` 엔 없던 위험을
#      이 PR 이 도입했다.**
# 🔴 **기존 trap 문자열에 «얹는다»** — `trap … EXIT` 를 따로 걸면 앞엣것이 덮여 사라진다(:329 실측).
# 🔴 **`INT TERM` 도 건다** — bash 는 «안 잡은» 치명 시그널에선 EXIT trap 을 «안» 돌린다.
#   위 실측이 정확히 SIGTERM 이었으므로 EXIT 만으로는 그 갈래가 안 덮인다.
# 🔸 변수는 전부 `:-` 로 읽는다 — 정의 «전»에 죽는 갈래가 있고 `set -u` 아래다.
#   그리고 목록이 아니라 «파일별 깃발»로 둔다(비인용 확장을 아예 안 만든다).
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK";
      [ -n "${OPSTATE_SEEDED_V:-}" ] && rm -f "$OPSTATE_V";
      [ -n "${OPSTATE_SEEDED_B:-}" ] && rm -f "$OPSTATE_B";
      [ -n "${OPSTATE_DIR_MADE:-}" ] && rmdir "${OPSTATE_DIR:-/nonexistent}" 2>/dev/null;
      :' EXIT INT TERM
mkdir -p "$WORK/bin"

# 🔴 **운영 상태의 «좌변»을 시험 시작 전에 뜬다** — 아래 ⑮ 가 이걸로 부작용을 잰다.
#   «없음»도 값이다: 새 체크아웃엔 `logs/` 가 아예 없고, 그때 시험이 만들어버리면
#   그것도 오염이다(부재 → 존재도 변화).
OPSTATE_DIR="$REPO/logs"

# 🔴 **⑮ 가 CI 에서 «항진명제»였다** (룬드 `#162` 리뷰 실측, 2026-08-10).
#   격리를 여섯 줄 다 빼도 CI 조건에선 ⑮ 가 «초록»이다 — 새 체크아웃엔 `logs/` 가 없고
#   스크립트는 **디렉터리가 없으면 상태를 안 쓴다.** 오염이 «날 수 없어서» 안 난 것을
#   ⑮ 는 「안 났다」로 보고한다. ⇒ **관문이 도는 세계에서만 검사가 죽어 있었다.**
#   🔑 지금 CI 가 누수를 잡는 건 «다른 넷»(상태 공유가 구간 로직을 바꾸는 축) 덕이고,
#      오염이 «로직에 영향 없이» 나면 그 넷도 초록이라 **CI 는 무음인데 원장 파생식은 CI 를 읽는다.**
#   ⇒ 잴 수 있는 세계를 «만들고» 잰다. 우리가 만들었으면 끝나고 돌려놓는다.
OPSTATE_DIR_MADE=""
if [ ! -d "$OPSTATE_DIR" ]; then
    mkdir -p "$OPSTATE_DIR" 2>/dev/null && OPSTATE_DIR_MADE=1
fi

# 🔴 **디렉터리를 만든 것으로는 «부족했다» — 새는 쪽은 «파일»이다** (2026-08-10 실측, `#163` 후속).
#   격리(전역 export 두 줄)를 뺀 사본으로 두 세계를 재니 **A 만 잡히고 B 는 0건**이었다:
#   ```
#   세계 B  logs/ 없음(시험이 만듦) · 상태 파일 없음   → 실패 0   ← CI 가 정확히 이 세계다
#   세계 A  logs/ 있음 · 상태 파일 «있음»              → 실패 1   ← ⑮ 「운영 상태 오염」
#   ```
#   범인은 **band 상태 하나**다(`band.state` 가 `ok<TAB>1786363947` 로 덮였다. verdict 는 무사).
#   기전: 그 스크립트는 **구간 «전이»일 때만** band 를 쓰는데, 전이는 «직전 값»이 있어야 성립한다
#   ⇒ **선행 상태가 없으면 누수가 «일어나지 않는다».** 실행 후 `logs/` 가 `rmdir` 로 지워진 것이
#   그 증거다(빈 디렉터리였다).
#   🔑 그래서 `#163` 은 **반쪽을 고쳤다** — 「쓸 자리(디렉터리)」는 만들었는데 「덮을 것(파일)」이 없어
#      CI 에서 ⑮ 는 여전히 항진명제였다. **「잴 수 있는 세계를 만들고 잰다」를 한 겹 더** 적용한다.
#   ⚠️ 있는 파일은 **절대 안 건드린다** — 없을 때만 심고, 심은 것만 지운다.
OPSTATE_V="$OPSTATE_DIR/check-usage-verdict.state"
OPSTATE_B="$OPSTATE_DIR/check-usage-band.state"

# 🔴 **이 «값»은 실제 band 값과 겹치면 안 된다 — 겹치면 ⑮ 가 조용히 항진명제로 돌아간다.**
#   실측(룬드 `#169` 리뷰, 2026-08-10): 격리를 뺀 사본에서 씨앗을 `ok` 로 바꾸면
#   **전제 ⓐ·ⓑ·ⓒ 가 전부 초록인 채** 통과 94 · 실패 0 · 판정 불가 0 이 나온다.
#   기전: `scripts/check-usage-alert.sh:398-400` — 전이는 **직전 값과 «다를 때»만** 성립하므로
#   씨앗이 실제 값과 겹치면 **전이가 안 나고 누수도 안 난다.**
#   🔑 아래 ⓒ(자리 유도-대조)가 막는 함정의 **«값» 판**이다. 자리를 옮기면 ⓒ 가 빨개지는데
#      **값을 바꾸면 아무것도 안 빨개진다** — 값 축이 한 겹 조용하다.
#   ⚠️ 재발 경로가 구체적이다: 누가 *「더 현실적인 값으로」* `ok`·`na` 로 바꾸면
#      **diff 는 값 하나**이고 CI 는 초록이다. 그래서 실측을 값 옆에 붙여 둔다.
#   🔸 값 집합을 `case` 로 열거해 거부하는 안은 **또 열거**라 안 쓴다(구간 라벨은 사람 값이라 는다).
SEED_STATE='SEED-시험이-심음'

OPSTATE_SEEDED_V=""; OPSTATE_SEEDED_B=""
if [ ! -e "$OPSTATE_V" ]; then
    printf '%s\n' "$SEED_STATE" > "$OPSTATE_V" 2>/dev/null && OPSTATE_SEEDED_V=1
fi
if [ ! -e "$OPSTATE_B" ]; then
    printf '%s\n' "$SEED_STATE" > "$OPSTATE_B" 2>/dev/null && OPSTATE_SEEDED_B=1
fi

opstate_fp() {   # 두 운영 상태 파일의 지문. 없으면 «없음»
    local f out=""
    for f in "$OPSTATE_DIR/check-usage-verdict.state" "$OPSTATE_DIR/check-usage-band.state"; do
        if [ -e "$f" ]; then out="$out$(basename "$f")=$(cat "$f" 2>/dev/null | tr -d '\n');"
        else out="$out$(basename "$f")=없음;"; fi
    done
    printf '%s' "$out"
}
OPSTATE_BEFORE="$(opstate_fp)"

nlines() { wc -l < "$1" | tr -d '[:space:]'; }

# ── 가짜 curl: 상태코드·본문·헤더를 주입으로 제어 ────────────────────────────
# 🔑 실물 curl 의 계약을 흉내낸다 — `-w` 로 상태코드를 덧붙이고 `-D` 로 헤더를 파일에 쓴다.
#    스크립트가 그 둘을 실제로 쓰는지가 이 시험의 본체다.
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
# 🔑 실물 curl 의 계약을 정확히 흉내낸다 — **요청한 것만 준다.**
#   🔴 처음엔 -w 없이도 코드를 붙였다. 그러면 "-w 를 빼는" 변이가 20개 시험 중 **하나도 안 물었다**
#      (변이 M1 이 생존). 스텁이 실물보다 관대하면 **스크립트가 코드를 요청하는지 못 가른다** —
#      픽스처가 계약을 안 지키면 그 위의 초록은 계약의 초록이 아니다(오늘 밤 세 번째 같은 형태).
hdr=""; want_code=0; prev=""
for a in "$@"; do
  [ "$prev" = "-D" ] && hdr="$a"
  case "$a" in *'%{http_code}'*) want_code=1 ;; esac
  prev="$a"
done
[ -n "$hdr" ] && printf 'HTTP/2 %s\r\n%s\r\n\r\n' "${FAKE_CODE:-200}" "${FAKE_HEADERS:-}" > "$hdr"
printf '%s' "${FAKE_BODY:-}"
[ "$want_code" = 1 ] && printf '%s' "${FAKE_CODE:-200}"
exit "${FAKE_CURL_RC:-0}"
STUB
chmod +x "$WORK/bin/curl"

# ── 가짜 discord-send ────────────────────────────────────────────────────────
cat > "$WORK/bin/discord-send" <<'STUB'
#!/bin/bash
if [ "${FAKE_SEND_RC:-0}" != 0 ]; then
  echo "discord-send: 전송 실패(주입)" >&2
  exit "$FAKE_SEND_RC"
fi
# 🔴 발송 1건 = **1줄**로 접는다. 경고 문구가 여러 줄이라 그대로 쓰면 1건이 2줄로 잡히고,
# `nlines` 로 세는 순간 "1건 보냈다"가 "2건"으로 보인다. 오늘 `wc -l` 과 같은 자리 —
# **줄을 세면서 건수를 센다고 생각하는 것**이다.
printf '%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\n' ' ')" >> "$SENT_LOG"
STUB
chmod +x "$WORK/bin/discord-send"

CREDS="$WORK/creds.json"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$CREDS"

# 경고가 나오는 본문: 5시간 윈도우에서 1시간 경과 · 40%% 사용 ⇒ 200%% 예상
alerting_body() {
  python3 - <<'PYEOF'
import json, datetime
now = datetime.datetime.now(datetime.timezone.utc)
print(json.dumps({"five_hour": {"utilization": 40,
    "resets_at": (now + datetime.timedelta(hours=4)).isoformat()}}))
PYEOF
}

# 🔴 **상태 파일을 격리한다.** 안 하면 시험이 `$BOT_DIR/logs/…state` 를 쓴다 —
#   운영 기준선을 시험이 덮어써서 **다음 진짜 전이가 묻힌다**(부작용). 그리고 반대로
#   운영 상태가 시험 결과를 바꿔서 **같은 시험이 기계마다 다른 답**을 낸다.
#   [[feedback_vault_script_test_isolation]] 와 같은 계약.
#
# 🔴 **격리는 «헬퍼»가 아니라 «환경»에 건다** (2026-08-10 실측, `#159` 와 같은 병).
#   이 주석은 예전부터 있었는데 격리는 `run_in()` 안에만 걸려 있었고,
#   `"$CHECK"` 를 직접 부르는 자리 셋(크래시·임시파일·`run_cli`)이 그걸 안 거쳤다.
#   그래서 **운영 상태가 있는 기계에서만** 3건이 빨개졌다:
#     깨끗한 워크트리 통과 89 · 실패 0   /   운영 `logs/` 가 있는 트리 통과 86 · 실패 3
#   기전 확인: `logs/check-usage-{band,verdict}.state` **두 파일만** 복사하면 그 자리에서 뒤집힌다.
#   🔑 **그리고 CI 는 이걸 «구조적으로» 못 본다** — 새 체크아웃엔 `logs/` 가 없고,
#      스크립트는 디렉터리가 없으면 상태를 안 쓴다. **초록이 「격리된다」의 증거가 아니었다.**
#   ⇒ 아래 export 로 **호출 자리를 안 믿는다.** 새 호출을 추가해도 자동으로 격리된다.
export CHECK_USAGE_STATE="$WORK/global-verdict.state"
export CHECK_USAGE_BAND_STATE="$WORK/global-band.state"
run() {   # run <설명없음> — 환경변수는 앞에 붙여 넘긴다. 매 호출이 «새 상태»다
  STATE="$WORK/run$RANDOM"; mkdir -p "$STATE"
  run_in "$STATE" "$@"
}

# 🔑 구간 억제는 «회차 사이»에 사는 규칙이라 상태를 이어야 잴 수 있다.
#   run() 은 매번 새 상태라 전이를 «영원히 첫 회차»로 만든다 — 그걸로는 억제를 못 잰다.
run_in() {   # run_in <상태디렉터리> [환경…]
  STATE="$1"; shift; mkdir -p "$STATE"
  SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"
  LOGF="$STATE/usage.log"
  env PATH="$WORK/bin:$PATH" SENT_LOG="$SENT_LOG" \
      CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$LOGF" \
      CHECK_USAGE_STATE="$STATE/verdict.state" \
      CHECK_USAGE_BAND_STATE="$STATE/band.state" \
      DISCORD_SEND="$WORK/bin/discord-send" \
      "$@" bash "$CHECK" >/dev/null 2>&1
  RC=$?
  return 0
}

# 예상치를 «지정해서» 만드는 본문. 5시간 창·1시간 경과라 util 을 5로 나눈 값이 예상치가 된다.
#   ⇒ projected = util / 1h * 5h = util * 5
body_projected() {   # body_projected <원하는 예상치>
  WANT="$1" python3 - <<'PYEOF'
import json, os, datetime
now = datetime.datetime.now(datetime.timezone.utc)
want = float(os.environ["WANT"])
print(json.dumps({"five_hour": {"utilization": want / 5.0,
    "resets_at": (now + datetime.timedelta(hours=4)).isoformat()}}))
PYEOF
}

# 🔴 정본을 못 찾으면 **이 파일 전체가 판정 불가**다 — 스크립트가 무조건 rc=2 로 죽으므로
#   나머지 단언은 전부 *틀린 이유로* 빨개진다. 🔑 원래 빨간 판 위에 빨간 걸 더하면 아무도 못 본다.
#   ⇒ 조용히 통과시키지도, 거짓 빨강을 내지도 않고 **판정 불가로 세어 보고**한다.
if [ -z "$CORE_FIXTURE" ]; then
    echo "⛔ 판정 불가 — cli-guard 정본을 못 찾았다."
    echo "   찾아본 곳: \$CORE_REPO · ~/yaksu-bot-core-live · ~/yaksu-bot-core"
    echo "   코어를 클론하거나 CORE_REPO=<경로> 로 지정하고 다시 돌릴 것."
    echo "  통과 0 · 실패 0 · 판정 불가 1(파일 전체)"
    exit 0
fi

echo "── ① 🔴 429 를 **볼 수 있다** — 이 시험의 본체 ──"
# 옛 코드: 429 본문이 json.loads 를 통과 → 버킷 없음 → 조용히 exit 0. 흔적 0.
run FAKE_CODE=429 FAKE_BODY='{"error":{"type":"rate_limit_error"}}' \
    FAKE_HEADERS='retry-after: 900'
[ -s "$LOGF" ] && ok "429 여도 로그가 남는다" || bad "429 로그" "1줄 이상" "빈 파일"
grep -q 'code=429' "$LOGF" && ok "상태코드가 로그에 수치로 남는다 (code=429)" \
  || bad "code=429" "있음" "$(cat "$LOGF")"
grep -q 'verdict=ok' "$LOGF" && bad "429 를 정상으로 판정했다" "ok 아님" "$(cat "$LOGF")" \
  || ok "429 를 정상으로 접지 않는다"
# 🔴 `-ne 0` 은 **계약을 안 고정한다** — 1 이든 2 든 통과해서 칸이 갈려도 초록이다.
#    실제로 갈려 있었다: network 는 2, http_error 는 1 이었다(둘 다 "못 쟀다"인데).
#    양봇 규약은 `0 정상 / 2 판정 불가` 라 판정 불가는 **2 여야 한다**(룬드 #35 대조로 발견).
[ "$RC" -eq 2 ] && ok "429 는 rc=2 (판정 불가 — 양봇 규약)" \
  || bad "429 종료코드" "2" "rc=$RC"

echo "── ② 🔑 retry-after 를 기록한다 — 공유 백오프(②)의 설계 근거가 된다 ──"
# 🔸 룬드가 소비자 구조를 찾은 근거가 로그였다. 값을 안 남기면 조율을 설계할 점이 안 쌓인다.
grep -q 'retry_after_s=900' "$LOGF" && ok "retry-after 헤더가 로그에 남는다" \
  || bad "retry_after_s=900" "있음" "$(cat "$LOGF")"

echo "── ③ 정상(200): 로그 1줄 + 경고 없으면 조용하다 ──"
run FAKE_CODE=200 FAKE_BODY='{"five_hour":{"utilization":1,"resets_at":"2099-01-01T00:00:00+00:00"}}'
[ "$(nlines "$LOGF")" = 1 ] && ok "정상도 로그 1줄" || bad "정상 로그" "1줄" "$(nlines "$LOGF")줄"
grep -q 'verdict=ok code=200' "$LOGF" && ok "verdict=ok code=200" || bad "정상 판정" "verdict=ok code=200" "$(cat "$LOGF")"
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "경고 없으면 안 보낸다" || bad "정상 무발송" "0건" "$(nlines "$SENT_LOG")건"

echo "── ④ 경고 발송: alert=sent 로 남는다 ──"
run FAKE_CODE=200 FAKE_BODY="$(alerting_body)"
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "경고 조건이면 1건 보낸다" || bad "경고 발송" "1건" "$(nlines "$SENT_LOG")건"
grep -q 'alert=sent' "$LOGF" && ok "alert=sent" || bad "alert=sent" "있음" "$(cat "$LOGF")"

echo "── ⑤ 🔴 발송 실패를 삼키지 않는다 (#88 과 같은 계약) ──"
run FAKE_CODE=200 FAKE_BODY="$(alerting_body)" FAKE_SEND_RC=1
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "발송이 실제로 실패했다(대조군)" || bad "실패 주입" "0건" "$(nlines "$SENT_LOG")건"
grep -q 'alert=sent' "$LOGF" && bad "실패인데 alert=sent" "sent 아님" "$(cat "$LOGF")" \
  || ok "실패를 sent 로 기록하지 않는다"
grep -q 'alert=send_failed' "$LOGF" && ok "alert=send_failed 로 갈린다" \
  || bad "alert=send_failed" "있음" "$(cat "$LOGF")"

echo "── ⑥ 🔴 토큰 부재를 조용히 넘기지 않는다 ──"
# 옛 코드: `[ -z "$TOKEN" ] && exit 1` 이 전부 — 로그도 알림도 없었다.
run FAKE_CODE=200 CHECK_USAGE_CREDENTIALS="$WORK/does-not-exist.json"
[ -s "$LOGF" ] && ok "토큰이 없어도 로그가 남는다" || bad "토큰 부재 로그" "1줄 이상" "빈 파일"
grep -q 'verdict=no_token' "$LOGF" && ok "verdict=no_token 으로 갈린다" \
  || bad "verdict=no_token" "있음" "$(cat "$LOGF")"
# 🔴 rc 를 아예 안 봤다 — verdict 만 보면 **로그는 맞는데 종료코드가 틀린** 상태를 못 잡는다.
[ "$RC" -eq 2 ] && ok "토큰 부재는 rc=2 (판정 불가)" || bad "토큰 부재 종료코드" "2" "rc=$RC"

echo "── ⑦ 네트워크 실패(curl rc≠0)와 HTTP 오류를 **다른 칸**에 넣는다 ──"
# 🔑 둘을 뭉치면 *못 쟀다* 와 *서버가 거절했다* 가 같은 칸이 된다 — 조치가 다르다.
run FAKE_CURL_RC=6 FAKE_BODY='' FAKE_CODE=000
grep -q 'verdict=network' "$LOGF" && ok "curl 실패는 verdict=network" \
  || bad "verdict=network" "있음" "$(cat "$LOGF")"
grep -q 'verdict=http_error' "$LOGF" && bad "네트워크 실패를 http_error 로 접었다" "network" "$(cat "$LOGF")" \
  || ok "네트워크와 HTTP 오류가 안 섞인다"

echo "── ⑧ 본문 축: 200 인데 못 읽으면 **이유를 갈라** rc=2 ──"
# 🔴 옛 코드는 {"unexpected":1} · null · [] 을 전부 rc=0 verdict=ok 로 접었다(실측).
#    빈 alerts 는 *임계 미달* 과 구별되지 않는다 ⇒ 스키마가 바뀌면 *못 쟀다* 가 *재보니 낮다* 로 접힌다.
# 🔑 갈래 이름은 룬드 check-usage-alert.sh 와 **같은 문면**이다(계약은 링크가 아니라 사본).
#    특히 empty-body 와 json-decode 는 조치가 다르다 —
#    *서버가 아무것도 안 줬다* vs *뭔가 줬는데 JSON 이 아니다*(프록시 오류 페이지 등).
_parse_case() {  # $1=본문  $2=기대 이유  $3=설명
  run FAKE_CODE=200 FAKE_BODY="$1"
  grep -q "verdict=parse-$2" "$LOGF" && ok "$3 → parse-$2" \
    || bad "$3" "verdict=parse-$2" "$(cat "$LOGF")"
  [ "$RC" -eq 2 ] && ok "  → rc=2" || bad "$3 종료코드" "2" "rc=$RC"
}
_parse_case ''                  'empty-body'       '빈 본문'
_parse_case '<html>oops</html>' 'json-decode'      'JSON 아님'
_parse_case 'null'              'not-object'       'null(파싱은 됨)'
_parse_case '[]'                'not-object'       '배열'
_parse_case '{"unexpected":1}'  'no-known-buckets' '아는 칸 0개'
# 🔴 **키만 세면 값의 타입을 안 본다** (룬드 대조 실측 2026-07-31 04:4x).
#    {"five_hour": null} · {"five_hour":"abc"} 는 키가 있어 통과하고, 뒤에서 continue 되어
#    alerts 가 비어 **rc=0 "임계 미달"** 이 됐다 — 고치려던 그 문장 그대로.
_parse_case '{"five_hour":null}'  'no-known-buckets' '칸은 있는데 값이 null'
_parse_case '{"five_hour":"abc"}' 'no-known-buckets' '칸은 있는데 값이 문자열'

# 🔴 **파이썬이 예상 밖으로 죽으면 셸이 그걸 정상으로 접고 있었다.**
#    셸이 `PARSE_RC -eq 3` 만 봐서, 크래시(rc=1)는 어느 분기에도 안 걸리고 verdict=ok 로 흘렀다.
#    아래 본문은 utilization 이 문자열이라 `util <= 0` 에서 TypeError 가 난다 —
#    isinstance(bucket, dict) 로는 안 막히는, **타입이 바뀐 스키마**의 실제 모양이다.
#    🔑 이유를 모르는 실패도 *못 쟀다* 다. 모른다고 정상으로 접지 않는다.
run FAKE_CODE=200 FAKE_BODY='{"five_hour":{"utilization":"abc","resets_at":"2099-01-01T00:00:00Z"}}'
[ "$RC" -eq 2 ] && ok "파이썬이 예상 밖으로 죽어도 rc=2" || bad "예상 밖 크래시 종료코드" "2" "rc=$RC"
grep -q 'verdict=ok' "$LOGF" && bad "크래시를 ok 로 접었다" "ok 아님" "$(cat "$LOGF")" \
  || ok "  → ok 로 접지 않는다"
grep -q 'verdict=parse-unknown' "$LOGF" && ok "  → parse-unknown 으로 갈린다" \
  || bad "verdict=parse-unknown" "있음" "$(cat "$LOGF")"
# 🔑 **전문을 보여준다** (룬드 #38 에서 가져옴) — 첫 줄 이름만으론 원인을 못 고친다.
#    run() 은 출력을 버리므로 여기서만 stderr 를 직접 받는다.
_crash_out="$(env PATH="$WORK/bin:$PATH" SENT_LOG="$WORK/s.tsv" \
  CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$WORK/c.log" \
  CHECK_USAGE_STATE="$WORK/c.verdict.state" CHECK_USAGE_BAND_STATE="$WORK/c.band.state" \
  DISCORD_SEND="$WORK/bin/discord-send" FAKE_CODE=200 \
  FAKE_BODY='{"five_hour":{"utilization":"abc","resets_at":"2099-01-01T00:00:00Z"}}' \
  bash "$CHECK" 2>&1)"
case "$_crash_out" in
  *Traceback*|*Error*) ok "  → 크래시 전문을 화면에 남긴다" ;;
  *) bad "크래시 전문" "Traceback 포함" "$_crash_out" ;;
esac

# 🔴 **임시파일이 실패 경로에서도 지워지는가** — 변이시험이 이 축이 비었다고 알려줬다
#    (뒤처리를 통째로 지워도 42/0 이었다). 30분 cron 이라 새면 하루 48개씩 쌓인다.
#    🔑 뒤처리는 `emit_log` 안(= 기존 EXIT trap)에 있다. `trap 'rm …' EXIT` 를 **따로 걸면 안 된다** —
#      bash 는 EXIT trap 을 덮어써서 하트비트 로깅이 조용히 사라진다(실측).
_TMP="$(mktemp -d)"
for _ in 1 2 3; do
  env PATH="$WORK/bin:$PATH" TMPDIR="$_TMP" SENT_LOG="$WORK/s2.tsv" \
    CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$WORK/c2.log" \
    CHECK_USAGE_STATE="$WORK/c2.verdict.state" CHECK_USAGE_BAND_STATE="$WORK/c2.band.state" \
    DISCORD_SEND="$WORK/bin/discord-send" FAKE_CODE=200 \
    FAKE_BODY='{"five_hour":{"utilization":"abc","resets_at":"2099-01-01T00:00:00Z"}}' \
    bash "$CHECK" >/dev/null 2>&1
done
_left="$(ls -A "$_TMP" | tr -d '[:space:]')"
[ -z "$_left" ] && ok "  → 실패로 끝나도 임시파일을 안 남긴다" \
  || bad "임시파일 누수" "0개" "$_left"
rm -rf "$_TMP"

# 🔴 **섞인 본문** — 한 칸은 멀쩡하고 다른 칸만 타입이 틀린 경우.
#    변이시험이 이 축이 비어 있다고 알려줬다(루프의 isinstance 를 되돌려도 39/0 이었다).
#    탐지 가드는 *하나라도 dict 면* 통과시키므로, 망가진 칸은 **루프에서** 걸러야 한다.
#    🔑 기대는 rc=2 가 아니라 **rc=0** 이다 — #91 이 세운 원칙(한 칸이 죽어도 나머지는 잰다) 그대로.
run FAKE_CODE=200 FAKE_BODY='{"five_hour":{"utilization":1,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":"abc"}'
[ "$RC" -eq 0 ] && ok "섞인 본문: 멀쩡한 칸이 있으면 잰다 (rc=0)" || bad "섞인 본문 rc" "0" "rc=$RC"
grep -q 'verdict=ok' "$LOGF" && ok "  → verdict=ok (망가진 칸은 건너뛴다)" \
  || bad "섞인 본문 verdict" "ok" "$(cat "$LOGF")"

# 🔑 대조군 — 아는 칸이 있고 임계 미달이면 조용히 rc=0. 위 단언들이 항진명제가 아님을 보인다.
run FAKE_CODE=200 FAKE_BODY='{"five_hour":{"utilization":1,"resets_at":"2099-01-01T00:00:00Z"}}'
[ "$RC" -eq 0 ] && ok "대조군: 아는 칸 있고 임계 미달 → rc=0" || bad "대조군" "0" "rc=$RC"
grep -q 'verdict=ok' "$LOGF" && ok "  → verdict=ok" || bad "대조군 verdict" "ok" "$(cat "$LOGF")"

echo "── ⑨ 🔑 **어떤 경로로 끝나도 로그 1줄** — 갈래마다 시험을 붙일 수 없으니 성질로 잠근다 ──"
# 🔴 이 스크립트엔 조기 종료가 여럿이다. 갈래마다 케이스를 만드는 대신 **exit 앞에 로그가 보장되는 구조**
#    (trap …EXIT)인지를 정적으로 본다. check-auth.sh 가 같은 방식으로 산 사고를 막았다.
# 🔴 **`mktemp` 변수가 전부 trap 문자열에 있나** — 정적으로 잠근다.
#    "cp 와 mv 사이에 죽으면 남는다" 같은 축은 픽스처로 재현이 안 되지만(룬드 #104),
#    *변수가 trap 에 있나* 는 파일만 보면 안다. 재현 불가를 미검증으로 두지 않는 값싼 수.
#    🔑 규칙 문면이 바뀐 자리다 — "trap 을 쓰자"(판단)가 아니라
#      **"mktemp 를 쓸 때마다 그 변수가 trap 에 있나"**(확인). 앞엣것은 이미 trap 이 있으면 안 걸린다.
#    ⚠️ 이 검사가 **변수를 하나도 못 찾으면 공허하게 통과**한다 — 그래서 개수부터 단언한다.
#      (실제로 처음 판이 `VAR="$(mktemp)"` 를 못 잡아 0개로 ✅ 였다)
_mkvars="$(grep -oE '[A-Za-z_][A-Za-z0-9_]*="?\$\(mktemp' "$CHECK" | grep -oE '^[A-Za-z_][A-Za-z0-9_]*' | sort -u)"
_n_mk="$(printf '%s\n' "$_mkvars" | grep -c .)"
[ "$_n_mk" -ge 2 ] && ok "mktemp 변수를 $_n_mk 개 찾았다(검사가 공허하지 않다)" \
  || bad "mktemp 변수 탐지" "2개 이상" "$_n_mk 개 — 정규식이 못 잡는다"
_traps="$(grep '^trap \|rm -f' "$CHECK")"
_miss=""
for _v in $_mkvars; do
  case "$_traps" in *"$_v"*) ;; *) _miss="$_miss $_v" ;; esac
done
[ -z "$_miss" ] && ok "  → mktemp 변수가 전부 뒤처리에 걸려 있다" \
  || bad "뒤처리 누락" "전부 trap/rm 에 있음" "빠짐:$_miss"

grep -q 'trap .*EXIT' "$CHECK" && ok "trap …EXIT 로 로그를 보장한다" \
  || bad "로그 보장 구조" "trap …EXIT" "없음 — 조기 종료 갈래가 조용해진다"

echo "── ⑩ 이식성 — 원시 GNU 명령을 안 쓴다 (룬드 맥 기준선) ──"
_hf_viol="$(mktemp)"   # 🔴 3.2: $( … << ) 형태를 피한다 (heredoc-form-guard)
python3 - "$CHECK" <<'PYEOF' > "${_hf_viol}"
import sys
RAW = {'touch' + ' -d': 'python os.utime', 'stat' + ' -c': 'python getmtime',
       'date' + ' -d': 'python datetime'}
bad = []
for i, ln in enumerate(open(sys.argv[1]), 1):
    if ln.strip().startswith('#'):
        continue
    for raw, fix in RAW.items():
        if raw in ln:
            bad.append("%d행: `%s` → %s" % (i, raw, fix))
print('\n'.join(bad))
PYEOF
_hf_rc_viol=$?   # 🔴 PYEOF 바로 다음 줄 — 한 줄만 밀려도 딴 명령의 rc 다
viol="$(cat "${_hf_viol}")"; rm -f "${_hf_viol}"
if _hf_msg="$(hf_verdict "$_hf_rc_viol" "이식성")"; then
    [ -z "$viol" ] && ok "GNU 전용 명령 0건" || bad "이식성 위반" "0건" "$viol"
else
    bad "$_hf_msg" "rc=0" "«${viol}»"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo "── ⑪ 🔴 인자 계약 (코어 cli-guard) — 09:50 사고의 **형태**를 막는다 ──"
# 🔴 사고 재구성: 진단하려고 `--report` 로 불렀다. 그런 플래그는 없었고 인자 파싱 자체가 없어
#   조용히 무시된 뒤 **평소 검사(=발송 포함)** 가 돌았다. `rc=0` · stdout 0바이트라
#   *"아무 일도 안 났다"* 로 읽혔는데 실제로는 Discord 로 **두 방**이 나간 뒤였다.
#   🔑 고칠 것은 습관이 아니라 형태다 — 양봇 다 **조심하려다** 밟았다.
#
# 🔑 계약 ③: *"플래그가 있나"* 가 아니라 **"스텁이 몇 번 불렸나"** 로 잠근다.
#   `--dry-run` 을 받아들이는지만 보면 **받아놓고 그냥 보내는** 구현이 초록으로 통과한다.

# 인자를 넘기는 갈래. 기존 run() 은 **환경변수만** 앞에 붙인다 —
# 한 헬퍼에 두 뜻을 담으면 나중에 어느 축이 안 잠겼는지 안 보여서 이름을 가른다.
runargs() {   # runargs <스크립트 인자…>   (GUARD_ENV 를 세우면 CLI_DRY_RUN 을 상속시킨다)
  STATE="$WORK/arg$RANDOM"; mkdir -p "$STATE"
  SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"
  LOGF="$STATE/usage.log"; OUTF="$STATE/out.txt"
  env PATH="$WORK/bin:$PATH" SENT_LOG="$SENT_LOG" \
      CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$LOGF" \
      CHECK_USAGE_STATE="$STATE/verdict.state" \
      CHECK_USAGE_BAND_STATE="$STATE/band.state" \
      DISCORD_SEND="$WORK/bin/discord-send" \
      FAKE_CODE=200 FAKE_BODY="$ALERT_BODY" \
      ${GUARD_ENV:+CLI_DRY_RUN="$GUARD_ENV"} \
      bash "$CHECK" "$@" > "$OUTF" 2>&1
  RC=$?
  return 0
}
ALERT_BODY="$(alerting_body)"

# 🧪 [대조군] **이게 먼저다.** 아래 "발송 0건" 들이 가드 덕인지, 애초에 이 조건에서
#   아무것도 안 보내는 건지 못 가른다 — 대조군이 초록이 아니면 나머지 빨간불은 증거가 아니다.
GUARD_ENV="" runargs
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "🧪 [대조군] 인자 없이 부르면 실제로 1건 나간다" \
  || bad "대조군" "1건" "$(nlines "$SENT_LOG")건 — 이 픽스처는 원래 안 보낸다. 아래 0건은 증거가 아니다"
[ "$RC" = 0 ] && ok "  → 대조군 rc=0" || bad "대조군 rc" "0" "$RC"

# ① 모르는 인자는 **거절**한다. 사고 당시의 그 플래그를 그대로 쓴다.
GUARD_ENV="" runargs --report
[ "$RC" = 2 ] && ok "모르는 인자 --report 를 rc=2 로 거절한다" || bad "모르는 인자 rc" "2" "$RC"
# 🔑 rc=1 이 아니라 2 다 — 모르는 인자는 *틀린 것*이 아니라 **못 쟀다**이고,
#   이 호출로는 아무것도 판정되지 않았다는 뜻이다(양봇 종료코드 규약).
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "  🔑 거절되면 발송 0건 (사고 재현 차단)" \
  || bad "거절인데 발송" "0건" "$(nlines "$SENT_LOG")건 — 09:50 사고가 그대로 재현된다"
grep -q '모르는 인자' "$OUTF" && ok "  → 왜 거절했는지 말한다" || bad "거절 사유" "'모르는 인자' 문구" "$(cat "$OUTF")"

# ② --dry-run 은 **부작용 0**. 진단하려는 사람에게 실행 말고 다른 선택지를 준다.
GUARD_ENV="" runargs --dry-run
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "--dry-run 이면 발송 0건" \
  || bad "dry-run 발송" "0건" "$(nlines "$SENT_LOG")건"
[ "$RC" = 0 ] && ok "  → dry-run 은 정상 종료(rc=0) — 못 잰 게 아니라 안 보낸 것" || bad "dry-run rc" "0" "$RC"
# 🔑 **조용하면 고장과 구별이 안 된다.** dry-run 은 *보려고* 부르는 것이라 왜 조용한지 말해야 한다.
grep -q 'DRY-RUN' "$OUTF" && ok "  → 안 보냈다는 것을 알린다(무음 아님)" || bad "dry-run 안내" "DRY-RUN 문구" "$(cat "$OUTF")"
# 🔴 **기록도 같이 잠근다.** 발송 0건만 재면 로그가 뭐라 남는지는 안 잰 것이다 —
#   실제로 감싸기만 했을 때 `alert=sent` 로 남았다(안 보냈는데 보냈다고). 나중에 이 로그로
#   발송 이력을 세는 쪽이 **없는 발송을 센다.** 🔑 억제를 재는 것과 기록을 재는 것은 다른 축이다.
grep -q 'alert=dry_run' "$LOGF" && ok "  🔑 로그에 alert=dry_run 으로 남는다" \
  || bad "dry-run 기록" "alert=dry_run" "$(cat "$LOGF")"
grep -q 'alert=sent' "$LOGF" && bad "안 보냈는데 sent" "sent 아님" "$(cat "$LOGF")" \
  || ok "  → 안 보낸 것을 sent 로 기록하지 않는다"

# ③ 🔴 환경 상속 거절 — 이 계약이 **자기 자신에게서** 발견한 자리(코어 계약 ④).
#   무시하면 dry-run 을 기대한 쪽이 발송당하고, 따르면 발송을 기대한 쪽이 조용해진다.
#   cron 은 stderr 를 버리므로 후자는 **발송 0건 · rc=0** 으로 성공처럼 보인다.
GUARD_ENV=1 runargs
[ "$RC" = 2 ] && ok "🔴 CLI_DRY_RUN 을 환경에서 물려받으면 rc=2 로 거절한다" \
  || bad "환경 상속" "rc=2" "rc=$RC — 플래그 없이 dry-run 이 켜졌거나 조용히 무시됐다"
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "  → 거절이므로 발송 0건" || bad "상속 거절 발송" "0건" "$(nlines "$SENT_LOG")건"

# ④ --help 도 부작용 0. 도움말 보려다 발송당하면 가드가 새는 것과 같다.
GUARD_ENV="" runargs --help
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "--help 는 발송 0건" || bad "help 발송" "0건" "$(nlines "$SENT_LOG")건"
grep -q 'usage:' "$OUTF" && ok "  → 사용법을 출력한다" || bad "usage 출력" "usage: 줄" "$(cat "$OUTF")"

# ⑤ 🔴 **가드 파일이 없으면 조용히 가드 없이 돌지 않는다.**
#   코어는 별 레포라 클론이 없거나 낡을 수 있다. 그때 `. …/cli-guard.sh` 가 실패하고
#   스크립트가 계속 돌면 **가드를 붙였다고 믿는 채로 안 붙은 상태**가 된다 —
#   붙이기 전보다 나쁘다(붙였다는 믿음이 생겼으니까). 부재는 조용하므로 여기서 시끄럽게 만든다.
# 🔴 **부재를 진짜로 모의하려면 후보를 전부 막아야 한다.** 부트는 코어를 다섯 곳에서 찾는다:
#   `$CORE_REPO` → 자기위치/../{live,core} → `$HOME`/{live,core}.
#   `CORE_REPO` 하나만 막으면 **형제 경로에서 실물을 찾아** 부재가 아니게 된다.
#   🔑 2026-07-31 배선 이관 때 이 절이 4건 빨개져서 드러났다 — 그 전 초록은 *막았다*가
#     아니라 **후보가 하나뿐이라 막힌 것처럼 보였다**였다(사본 배선 시절).
#   ⇒ 스크립트와 부트를 **부모에 코어가 없는 트리로 복사**하고 `HOME` 도 가짜를 준다.
STATE="$WORK/nocore$RANDOM"; mkdir -p "$STATE/repo/scripts/lib" "$STATE/fakehome"
cp "$CHECK" "$STATE/repo/scripts/"
cp "$(dirname "$CHECK")/lib/cli-guard-boot.sh" "$STATE/repo/scripts/lib/"
_NC_CHECK="$STATE/repo/scripts/$(basename "$CHECK")"
SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"
_nc_log="$STATE/usage.log"
_nc_out="$(env PATH="$WORK/bin:$PATH" SENT_LOG="$SENT_LOG" HOME="$STATE/fakehome" \
    CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$_nc_log" \
    DISCORD_SEND="$WORK/bin/discord-send" FAKE_CODE=200 FAKE_BODY="$ALERT_BODY" \
    CORE_REPO="$WORK/no-such-core" bash "$_NC_CHECK" 2>&1)"
_nc_rc=$?
[ "$_nc_rc" = 2 ] && ok "🔴 cli-guard 가 없으면 rc=2 로 죽는다 (조용히 무가드 실행 금지)" \
  || bad "가드 부재" "rc=2" "rc=$_nc_rc — 가드 없이 돌았다. '붙였다'는 믿음만 남는다"
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "  → 가드 부재 시 발송 0건" || bad "가드 부재 발송" "0건" "$(nlines "$SENT_LOG")건"
# 🔴 **rc 로는 못 가른다** (2026-07-31 변이 M2 생존으로 발견).
#   부재 검사를 지워도 rc=2 가 나온다: `set -e` 가 없어 `.` 실패가 안 죽이고, 그 뒤
#   `cli_guard_parse` 가 정의되지 않아 rc=127 → `if !` 가 참 → `bad_args; exit 2`.
#   발송 0건도, bash 자신의 에러 문구에 든 `cli-guard.sh` 도 그대로 통과했다.
#   🔑 **세 단언이 전부 틀린 이유로 초록이었다.** 두 상태를 가르는 값은 rc 가 아니라 **표지**다.
#   🔸 실해: 진짜 원인은 *코어 클론이 없다* 인데 로그엔 `bad_args` 로 남는다 —
#     읽는 사람은 crontab 을 뒤진다. **틀린 표지는 없는 표지보다 비싸다.**
grep -q 'verdict=no_cli_guard' "$_nc_log" 2>/dev/null \
  && ok "  🔑 로그 표지가 no_cli_guard 다 (bad_args 로 뭉개지 않는다)" \
  || bad "가드 부재 표지" "verdict=no_cli_guard" "$(cat "$_nc_log" 2>/dev/null || echo '<로그 없음>')"
case "$_nc_out" in
    *"코어 클론"*) ok "  → 어떻게 고치는지 말한다(git pull 안내)" ;;
    *) bad "가드 부재 안내" "'코어 클론' 복구 안내" "${_nc_out:-<조용함>}" ;;
esac

# 🧪 [양성 대조군] **같은 격리 트리**에서 코어를 실물로 주면 정상 동작해야 한다.
#   없으면 위 rc=2 가 *가드가 없어서*인지 *복사한 트리가 깨져서*인지 못 가른다 — 둘 다 rc=2 다.
#   격리는 **축을 하나만** 움직여야 축을 잰 것이 된다.
_ck_log="$STATE/ctrl.log"; _ck_sent="$STATE/ctrl.tsv"; : > "$_ck_sent"
env PATH="$WORK/bin:$PATH" SENT_LOG="$_ck_sent" HOME="$STATE/fakehome" \
    CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$_ck_log" \
    DISCORD_SEND="$WORK/bin/discord-send" FAKE_CODE=200 FAKE_BODY="$ALERT_BODY" \
    CORE_REPO="$CORE_FIXTURE" bash "$_NC_CHECK" --dry-run >/dev/null 2>&1
_ck_rc=$?
if [ "$_ck_rc" = 0 ] && ! grep -q 'no_cli_guard' "$_ck_log" 2>/dev/null; then
  ok "🧪 [양성 대조군] 같은 트리에서 코어를 주면 정상 동작한다(격리 자체는 안 깨졌다)"
else
  bad "🧪 [양성 대조군] 격리 트리" "rc=0 · no_cli_guard 아님" \
      "rc=$_ck_rc · $(cat "$_ck_log" 2>/dev/null || echo '<로그 없음>') — 위 rc=2 를 가드 부재로 못 읽는다"
fi

echo
echo "── ⑨ bash 3.2 형태 잠금 — heredoc 을 명령 치환 «밖»에 둔다 ──"
# 🔴 맥 bash 3.2 는 `$(…)` 안 heredoc **본문을 재스캔**한다. 인용 heredoc 이어도
#   본문에 **짝 안 맞는 백틱**이 생기는 순간 syntax error 로 죽는다.
#   ⚠️ 죽는 조건은 «백틱 유무»가 아니라 «짝»이다 — 짝수면 3.2 도 통과하고 실행도 안 된다(08-02 대조군).
#   그리고 **bash 5 는 짝수·홀수 둘 다 통과**한다 ⇒ `bash -n` 으로는 내 기계에서 영영 못 잡는다.
#   ⇒ 증상이 아니라 **형태**를 잠근다. 형태는 백틱이 «오기 전에» 운다.
#   경위: 룬드 코어 #133 / inbox #154 (같은 결함의 세 번째 사본이 이 파일이었다)

# 주석과 herestring 을 걷어낸 «실행되는 줄»만 본다.
#   · 주석: 이 경고문 자체가 판별식을 울리면 분모가 오염된다(실측 3회).
#   · `<<<`: herestring 은 heredoc 이 아닌데 `<<` 로 걸린다 — 룬드의 `<<[^<]` 보정도 두 번째 `<` 부터
#     매치돼서 틀렸다. 지워서 없앤다.
form_only() { LC_ALL=C grep -v '^[[:space:]]*#' "$1" | LC_ALL=C sed -e 's/\\\$//g' -e 's/<<<//g'; }

_n_form="$(form_only "$_NC_CHECK" | LC_ALL=C grep -c '\$(.*<<' || true)"
[ "${_n_form:-1}" -eq 0 ] \
  && ok "치환 안 heredoc 0건 — 백틱이 들어와도 3.2 에서 안 죽는다" \
  || bad "치환 안 heredoc" "0건" "${_n_form}건 — \$( … << ) 형태가 남아 있다(3.2 지뢰)"

# 🧪 [음성 대조군] 판별식이 **잡을 수 있는가**. 이게 없으면 위 0 은 «형태가 없다»인지
#   «판별식이 아무것도 못 잡는다»인지 안 갈린다 — 둘 다 0 이다.
_bait="$STATE/bait.sh"
printf 'V="$(python3 << %sX%s\nprint(1)\nX\n)"\n' "'" "'" > "$_bait"
[ "$(form_only "$_bait" | LC_ALL=C grep -c '\$(.*<<' || true)" -eq 1 ] \
  && ok "  🧪 [음성 대조군] 같은 판별식이 미끼는 잡는다(1건)" \
  || bad "🧪 미끼를 못 잡음" "1건" "0건 — 위 0 은 판별식 고장일 수 있다"

# 🧪 [오탐 대조군] herestring 과 이스케이프는 **세면 안 된다**.
_fp="$STATE/fp.sh"
{ printf 'python3 <<< "print(1)"\n'; printf 'msg="\\$(설명) << 은 예시일 뿐"\n'; } > "$_fp"
[ "$(form_only "$_fp" | LC_ALL=C grep -c '\$(.*<<' || true)" -eq 0 ] \
  && ok "  🧪 [오탐 대조군] herestring·이스케이프는 안 센다" \
  || bad "🧪 오탐" "0건" "herestring 이나 이스케이프를 heredoc 으로 셌다"

echo
# ═════════════════════════════════════════════════════════════════════════════
# 판정 «변화» 알림 — 401 이 구조적으로 `unreachable` 이던 것
#
# 🔴 결함(2026-08-03 실측): `exit 2` 네 갈래(no_token · network · http_error · parse-*)가
#   전부 알림 블록(294행)의 **앞**에 있다. EXIT trap 은 있는데 안에 로그·뒤처리만 있어서
#   **알림이 한 번도 도달할 수 없다.** 인증이 만료되면 401 이 30분마다 나는데 아무도 모른다.
#   🔑 **그릇은 있고 내용물이 반쪽**이었다 — trap 이 있다는 것이 알린다는 뜻이 아니다.
#
# 🔑 「알림은 사실이 아니라 «변화»에」 — 401 이 지속되는 동안 매 회차 울리면 그건 소음이고,
#   소음은 곧 무시된다. 그래서 «전이»에만 운다: ok→http_error 와 http_error→ok 둘 다.
#   복구 알림을 빼면 「울리다 멈춘 것」과 「고쳐진 것」이 같은 모양이 된다.
# ─────────────────────────────────────────────────────────────────────────────
VDIR="$STATE/verdict"; mkdir -p "$VDIR"
VSENT="$VDIR/sent.tsv"; VLOG="$VDIR/usage.log"; VSTATE="$VDIR/verdict.state"
VARGS=""
vrun() {   # vrun <env…> — 상태·로그를 «유지»한다(전이를 보려면 회차가 이어져야 한다)
  : > "$VSENT"
  env PATH="$WORK/bin:$PATH" SENT_LOG="$VSENT" \
      CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$VLOG" \
      CHECK_USAGE_STATE="$VSTATE" DISCORD_SEND="$WORK/bin/discord-send" \
      "$@" bash "$CHECK" $VARGS >/dev/null 2>&1
  VRC=$?
  return 0
}
vreset() { rm -f "$VSTATE" "$VLOG"; VARGS=""; }
# 🔑 판정 변화 알림만 센다 — 사용량 경고와 같은 통로로 나가므로 문면으로 가른다.
#   본문을 비알림(`{}`)으로 두면 사용량 경고는 0건이라 이 셈이 깨끗해진다.
# 🔴 **«건수»만 세면 방향이 안 보인다**(룬드 `#148` 리뷰) — 복구 시험이 「이상」 문면으로 나가도
#   1건이라 통과한다. 축이 「몇 건」이 아니라 **«무엇이» 나갔나**여서 셋으로 가른다.
#   🔑 [[#273]] 「표면이 실질을 위장한다」가 **내 시험 안에서** 난 것이다 — 건수가 방향을 위장했다.
# 🔴 **`{}` 는 `verdict=ok` 가 아니다** — JSON 은 통과하지만 버킷이 없어 `parse-no-known-buckets` 다.
#   처음엔 이걸 「정상」 픽스처로 썼고, 그래서 ③ 이 «복구»가 아니라 **다른 전이**를 재고 있었다.
#   방향을 안 보던 동안에는 건수 1 이 맞아떨어져 초록이었다(룬드 `#148` 리뷰가 이걸 꺼냈다).
#   🔑 **픽스처가 내가 말한 상태를 실제로 만드는지 확인하지 않으면, 그 위 초록은 다른 것의 초록이다.**
VOK_BODY='{"five_hour":{"utilization":1,"resets_at":"2099-01-01T00:00:00+00:00"}}'
vbad() { LC_ALL=C grep -c '감시 이상' "$VSENT" 2>/dev/null || true; }    # 이상 알림
vok()  { LC_ALL=C grep -c '감시 복구' "$VSENT" 2>/dev/null || true; }    # 복구 알림
vany() { LC_ALL=C grep -c '사용량 감시' "$VSENT" 2>/dev/null || true; }  # 판정 변화 알림 전체

echo "── 판정 변화 알림 ──"

# ① 핵심 결함: 401 이면 알림이 «나가야» 한다 (지금은 구조적으로 0건)
vreset; vrun FAKE_CODE=401 FAKE_BODY='{}'
[ "$(vbad)" -eq 1 ] \
  && ok "401(http_error) 에서 «이상» 알림 1건 — 조기 종료가 trap 에 닿는다" \
  || bad "401 알림" "1건" "$(vbad)건 — exit 2 가 알림 앞에서 끊고 있다"

# ② 같은 판정이 이어지면 두 번째 회차는 조용하다
vrun FAKE_CODE=401 FAKE_BODY='{}'
[ "$(vany)" -eq 0 ] \
  && ok "  같은 판정 반복은 0건 — 30분마다 우는 소음이 아니다" \
  || bad "반복 회차" "0건" "$(vbad)건 — 변화가 아니라 상태에 울고 있다"

# ③ 복구도 «변화»다 — 이게 없으면 「멈췄다」와 「고쳐졌다」가 같은 모양이다
vrun FAKE_CODE=200 FAKE_BODY="$VOK_BODY"
# 🔑 «복구» 문면이 1건이고 «이상» 문면이 0건이어야 한다 — 건수만 보면 방향이 뒤집혀도 통과한다
[ "$(vok)" -eq 1 ] && [ "$(vbad)" -eq 0 ] \
  && ok "  http_error→ok 는 «복구» 문면 1건 · 「이상」 0건" \
  || bad "복구 알림 방향" "복구 1건 · 이상 0건" "복구 $(vok)건 · 이상 $(vbad)건"

# ④ 🧪 [대조군] 정상이 이어지면 0건. 이게 없으면 ①③ 의 1건이
#    «전이를 잡은 것»인지 «아무 때나 우는 것»인지 안 갈린다.
vrun FAKE_CODE=200 FAKE_BODY="$VOK_BODY"
[ "$(vany)" -eq 0 ] \
  && ok "  🧪 [대조군] ok→ok 는 0건 — 위 1건이 전이를 잡은 값이다" \
  || bad "🧪 대조군" "0건" "$(vbad)건 — 판정과 무관하게 울고 있다"

# ⑤ 토큰을 못 읽는 갈래도 닿는다 — trap 이므로 «모든» 조기 종료가 알림을 지난다
vreset; vrun CHECK_USAGE_CREDENTIALS="$VDIR/nonexistent.json"
[ "$(vbad)" -eq 1 ] \
  && ok "no_token 갈래도 알림 1건 — 갈래마다 따로 붙이지 않았다" \
  || bad "no_token 알림" "1건" "$(vbad)건"

# ⑥ 🔴 발송이 실패하면 상태를 갱신하지 «않는다» — 다음 회차가 다시 시도한다.
#    갱신해버리면 **못 보낸 전이가 영구히 묻힌다**(`#147` 에서 같은 자리를 밟았다).
vreset; vrun FAKE_CODE=401 FAKE_BODY='{}' FAKE_SEND_RC=1
vrun FAKE_CODE=401 FAKE_BODY='{}'
[ "$(vbad)" -eq 1 ] \
  && ok "발송 실패는 전이를 소비하지 않는다 — 다음 회차가 재시도" \
  || bad "발송 실패 후 재시도" "1건" "$(vbad)건 — 못 보낸 전이가 묻혔다"

# ⑦ 🔴 dry-run 도 전이를 소비하지 않는다. 진단 한 번이 **진짜 알림을 먹는** 자리다.
vreset; VARGS="--dry-run"; vrun FAKE_CODE=401 FAKE_BODY='{}'
VARGS=""; vrun FAKE_CODE=401 FAKE_BODY='{}'
[ "$(vbad)" -eq 1 ] \
  && ok "dry-run 은 전이를 소비하지 않는다 — 진단이 알림을 먹지 않는다" \
  || bad "dry-run 후 실제 회차" "1건" "$(vbad)건 — 진단 한 번이 알림을 먹었다"

# ⑧ 칸을 «시각 둘»로 둔다 — 하나면 「전이가 언제 났나」와 「언제 알렸나」가 안 갈린다.
#    그 둘의 «간격»이 곧 `unreachable` 의 관측값이다(룬드 실측: 복구 32초 vs 복구 알림 30분 5초).
vreset; vrun FAKE_CODE=401 FAKE_BODY='{}'
# 🔴 **칸이 있는지가 아니라 «값이 들었는지»를 본다**(룬드 `#148` 리뷰). `printf` 가 항상 두 칸을
#   내므로 `na na` 여도 「칸 있음」은 초록이다 — 주석은 「간격이 관측값」이라 적어놓고
#   정작 그 값이 시각인지를 안 봤다. 🔑 [[#273]] 이 여기서도 났다: **형태가 내용을 위장한다.**
_vl="$(LC_ALL=C grep -cE 'verdict_changed_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T.*notified_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$VLOG" 2>/dev/null || true)"
[ "${_vl:-0}" -ge 1 ] \
  && ok "두 칸에 «시각이» 들어 있다 — 간격이 도달 지연의 관측값" \
  || bad "로그 칸 값" "둘 다 ISO 시각" "$(LC_ALL=C grep -o 'verdict_changed_at=[^ ]* notified_at=[^ ]*' "$VLOG" | tail -1)"
# 🧪 [음성 대조군] 전이가 «없는» 회차는 두 칸이 `na` 로 남아야 한다 — 위 판별식이
#   아무 줄이나 무는 것이면 여기서도 물어서 갈린다.
vrun FAKE_CODE=401 FAKE_BODY='{}'
_vn="$(LC_ALL=C grep -c 'verdict_changed_at=na notified_at=na' "$VLOG" 2>/dev/null || true)"
[ "${_vn:-0}" -ge 1 ] \
  && ok "  🧪 [음성 대조군] 전이 없는 회차는 na na — 판별식이 아무 줄이나 물지 않는다" \
  || bad "🧪 na 줄" "1줄 이상" "${_vn}줄"

# ── ⑨ 구간(band) 게이트 ─────────────────────────────────────────────────────
# 🔴 왜 생겼나: 사용량 경고 «본체»는 조건이 맞는 동안 **매 회차** 나갔다(cron */30 ⇒ 같은 값 반복).
#   전이 쪽만 STATE 로 고쳐놓고 본체를 안 고쳤고, **그 결함이 스크립트 :81 주석에 이미 적혀 있었다.**
#   Darren 지시 2026-08-10 `M:5elk`·`M:juia`: 「구간이 변할 때만 + 지속되면 2시간마다, 룬드 것 그대로」
#
# 🔑 이 시험이 «잠그는 것»과 «못 잠그는 것»:
#   ✅ 잠근다   — 같은 구간이 이어지면 조용한가 · 구간이 바뀌면 우는가 · 지속 주기가 도는가
#   ⛔ 못 잠근다 — 경계값(100/150/200) 이 «옳은가». 그건 사람 값이라 시험이 판정할 것이 아니다
#                 ⇒ 대신 «경계가 코드와 시험 두 곳에 갈려 사는 것»을 막는다: 시험은 경계를
#                   재선언하지 않고 «양쪽 바깥 값»으로만 민다(99/101 이 아니라 20/500).
echo
echo "⑨ 구간 게이트 — 전이에만 울고, 높은 구간은 주기마다 한 번 더"
BS="$WORK/bandseq"; rm -rf "$BS"

nsent() { nlines "$SENT_LOG"; }

# ⑨-1 첫 회차가 높으면 운다 (상태 없음 → ok 로 가정 → 전이)
run_in "$BS" FAKE_BODY="$(body_projected 500)"
[ "$(nsent)" = 1 ] && ok "첫 회차 높은 구간 → 운다 (상태 없음을 «ok» 로 본다)" \
  || bad "첫 회차" "1건" "$(nsent)건"
LC_ALL=C grep -q 'band=200+' "$LOGF" && ok "  로그에 band=200+ 가 남는다" \
  || bad "로그 band 칸" "band=200+" "$(tail -1 "$LOGF")"

# ⑨-2 같은 구간이 이어지면 «조용하다» — 이게 이 PR 의 본체다
run_in "$BS" FAKE_BODY="$(body_projected 500)"
[ "$(nsent)" = 0 ] && ok "같은 구간 반복 → 조용하다 (30분마다 같은 값이 안 나간다)" \
  || bad "같은 구간 반복" "0건" "$(nsent)건 — 억제가 안 걸렸다"
LC_ALL=C grep -q 'alert=suppressed' "$LOGF" && ok "  🔑 «억제»가 로그에 남는다 — 「안 걸림」과 안 헷갈린다" \
  || bad "억제 기록" "alert=suppressed" "$(tail -1 "$LOGF")"

# ⑨-3 구간이 «올라가면» 운다
run_in "$BS" FAKE_BODY="$(body_projected 120)"
[ "$(nsent)" = 1 ] && ok "구간 하강(200+ → 100-149) → 운다" || bad "하강 전이" "1건" "$(nsent)건"
run_in "$BS" FAKE_BODY="$(body_projected 500)"
[ "$(nsent)" = 1 ] && ok "구간 상승(100-149 → 200+) → 운다" || bad "상승 전이" "1건" "$(nsent)건"

# ⑨-4 정상으로 «내려가는 것»도 전이다 — 창 리셋이 이 경로로 나간다
run_in "$BS" FAKE_BODY="$(body_projected 20)"
[ "$(nsent)" = 1 ] && ok "정상 복귀(200+ → ok) → 운다 (창 리셋이 이 경로다)" \
  || bad "복귀 전이" "1건" "$(nsent)건"
# 🧪 [음성 대조군] ok 가 «이어지면» 조용해야 한다. 없으면 위 초록이 「항상 운다」와 구별이 안 된다.
run_in "$BS" FAKE_BODY="$(body_projected 20)"
[ "$(nsent)" = 0 ] && ok "  🧪 [음성 대조군] ok 지속 → 조용하다 (「항상 운다」가 아니다)" \
  || bad "ok 지속" "0건" "$(nsent)건"

# ⑨-5 높은 구간이 «지속되면» 주기마다 한 번 더 — Darren 값(2시간)
#   🔑 시각을 «흐르게» 못 하니 주기를 0 으로 눌러 「주기가 지났다」를 만든다.
#     ⚠️ 이건 「2시간이 맞나」를 안 잰다 — 그건 사람 값이다. 재는 것은 «주기 경로가 도는가»다.
BS2="$WORK/bandrepeat"; rm -rf "$BS2"
run_in "$BS2" FAKE_BODY="$(body_projected 500)"                                  # 첫 전이
run_in "$BS2" CHECK_USAGE_BAND_REPEAT_MIN=0 FAKE_BODY="$(body_projected 500)"
[ "$(nsent)" = 1 ] && ok "높은 구간 지속 + 주기 경과 → 한 번 더 운다 (무음으로 안 빠진다)" \
  || bad "지속 반복" "1건" "$(nsent)건"
LC_ALL=C grep -q 'band_reason=지속' "$LOGF" && ok "  사유가 «지속»으로 남는다 — 전이와 안 섞인다" \
  || bad "지속 사유" "band_reason=지속…" "$(tail -1 "$LOGF")"
# 🧪 [음성 대조군] ok 는 주기가 지나도 «안» 운다 — 안 그러면 조용할 자리가 2시간마다 시끄러워진다
run_in "$BS2" CHECK_USAGE_BAND_REPEAT_MIN=0 FAKE_BODY="$(body_projected 20)"     # 전이(→ok), 운다
run_in "$BS2" CHECK_USAGE_BAND_REPEAT_MIN=0 FAKE_BODY="$(body_projected 20)"
[ "$(nsent)" = 0 ] && ok "  🧪 [음성 대조군] ok 는 주기가 지나도 안 운다" \
  || bad "ok 주기 억제" "0건" "$(nsent)건"

# ⑨-6 🔴 발송 실패·dry-run 은 기준선을 «갱신하지 않는다» — 그러면 그 회차가 영구히 묻힌다
BS3="$WORK/bandfail"; rm -rf "$BS3"
run_in "$BS3" FAKE_SEND_RC=1 FAKE_BODY="$(body_projected 500)"
run_in "$BS3" FAKE_BODY="$(body_projected 500)"
[ "$(nsent)" = 1 ] && ok "발송 실패 회차는 기준선을 안 먹는다 — 다음 회차가 다시 운다" \
  || bad "실패 후 재시도" "1건" "$(nsent)건 — 실패가 기준선이 됐다"

# ⑨-7 🔴 파이썬이 BAND 줄을 안 내면 «정상으로 접지 않는다»
#   본문 파서가 바뀌어 첫 줄 계약이 깨지면, 억제기는 항상 band=na 로 「전이 없음」을 볼 수 있다.
BS4="$WORK/bandcontract"; rm -rf "$BS4"; mkdir -p "$BS4"
sed 's/^print("BAND/#print("BAND/' "$CHECK" > "$BS4/nob.sh"
STATE="$BS4"; SENT_LOG="$BS4/sent.tsv"; : > "$SENT_LOG"; LOGF="$BS4/usage.log"
env PATH="$WORK/bin:$PATH" SENT_LOG="$SENT_LOG" CHECK_USAGE_CREDENTIALS="$CREDS" \
    CHECK_USAGE_LOG="$LOGF" CHECK_USAGE_STATE="$BS4/v.state" \
    CHECK_USAGE_BAND_STATE="$BS4/b.state" DISCORD_SEND="$WORK/bin/discord-send" \
    FAKE_BODY="$(body_projected 500)" bash "$BS4/nob.sh" >/dev/null 2>&1
_nbrc=$?
[ "$_nbrc" = 2 ] && LC_ALL=C grep -q 'verdict=parse-no-band' "$LOGF" \
  && ok "🧪 [대조군] BAND 줄이 없으면 rc=2 «판정 불가» — 조용한 ok 로 안 접힌다" \
  || bad "BAND 줄 부재" "rc=2 + verdict=parse-no-band" "rc=$_nbrc / $(tail -1 "$LOGF" 2>/dev/null)"

echo "── ⑮ 🔴 시험이 «운영 상태»를 안 건드린다 (격리를 환경에 걸었는지의 좌변) ──"
# 🔑 좌변이 «시험 안의 값»이 아니라 «시험 밖의 파일»이다. 격리가 새면 여기서만 보인다 —
#   다른 단언은 전부 격리된 자리를 보고 있어서 새는 걸 못 본다(그래서 오늘까지 안 잡혔다).
# 🔴 **전제 먼저 — 「잴 수 있는 세계였나」.** 이게 없으면 아래 초록은 「안 샜다」가 아니라
#   「샐 자리가 없었다」를 뜻하고, 그 둘은 다른 사실이다(룬드 `#162` 실측).
[ -d "$OPSTATE_DIR" ] \
  && ok "전제 ⓐ: 운영 상태를 «쓸 수 있는» 자리가 있다 ($OPSTATE_DIR)" \
  || bad "⑮ 전제 불성립" "$OPSTATE_DIR 존재" "없음 — 아래 초록은 아무 뜻이 없다"

# 🔴 **전제 ⓑ — 「덮을 것이 있나」.** 디렉터리만 있고 «파일»이 없으면 누수가 «일어나지 않는다»
#   (band 는 구간 전이일 때만 쓰고, 전이는 직전 값이 있어야 성립한다). 실측으로 확인한 축이다.
[ -e "$OPSTATE_V" ] && [ -e "$OPSTATE_B" ] \
  && ok "전제 ⓑ: 덮일 «선행 상태»가 둘 다 있다 — 누수가 일어날 수 있는 세계다" \
  || bad "⑮ 전제 불성립 — 덮을 것이 없다" "상태 파일 둘" "$(opstate_fp)"

# 🔴 **씨앗이 «스크립트가 쓰는 그 자리»인가 — 경로를 여기 다시 적지 않고 «뽑아»온다.**
#   딴 데 심으면 전제 ⓑ 는 초록인데 누수는 여전히 안 보인다(가장 나쁜 조합: 대비했다는 착각).
#   🔑 `#167` 과 같은 처방이고 같은 함정이다 — 주석 줄을 먼저 뺀 뒤 «코드»에서 뽑는다.
_derive_state() {   # $1 = 변수명
    local raw
    raw="$(LC_ALL=C grep -vE '^[[:space:]]*#' "$REPO/scripts/check-usage-alert.sh" \
           | LC_ALL=C sed -n "s/.*\${$1:-\([^}]*\)}.*/\1/p" | head -1)"
    printf '%s' "${raw//\$BOT_DIR/$REPO}"
}
_dv="$(_derive_state CHECK_USAGE_STATE)"; _db="$(_derive_state CHECK_USAGE_BAND_STATE)"
if [ -z "$_dv" ] || [ -z "$_db" ]; then
    bad "스크립트에서 기본 상태 경로를 «못 뽑았다» — 씨앗이 맞는 자리인지 모른다" "두 경로" "v='$_dv' b='$_db'"
elif [ "$_dv" = "$OPSTATE_V" ] && [ "$_db" = "$OPSTATE_B" ]; then
    ok "  → 씨앗 자리 = 스크립트의 기본 경로 (유도해서 대조했다)"
else
    bad "씨앗을 «딴 데» 심었다 — 전제 ⓑ 가 초록이어도 누수는 안 보인다" "$OPSTATE_V · $OPSTATE_B" "$_dv · $_db"
fi

OPSTATE_AFTER="$(opstate_fp)"
[ "$OPSTATE_BEFORE" = "$OPSTATE_AFTER" ] \
  && ok "운영 상태 파일이 시험 전후로 같다" \
  || bad "운영 상태 오염" "$OPSTATE_BEFORE" "$OPSTATE_AFTER"

# 🔸 회수는 **머리의 EXIT·INT·TERM trap** 이 한다 — 여기 직선 코드로 두면 죽는 갈래에서
#   씨앗이 «운영 자리»에 남고, 그 오염을 이 검사 자신이 못 본다(룬드 `#169`, 머리말 참조).

# 🧪 대조군 — 이 검사가 «변화를 실제로 잡나». 안 그러면 위 초록은 항진명제다.
_op_probe="$WORK/opprobe"; mkdir -p "$_op_probe"
( OPSTATE_DIR="$_op_probe"
  _b="$(opstate_fp)"
  printf 'x\n' > "$_op_probe/check-usage-band.state"
  _a="$(opstate_fp)"
  [ "$_b" != "$_a" ] ) \
  && ok "🧪 [대조군] 상태가 바뀌면 지문이 달라진다" \
  || bad "지문 대조군" "달라짐" "같음 — 이 검사는 아무것도 못 잡는다"

echo
# 🔸 판정 불가를 요약줄에 **항상** 싣는다(0이어도). 조건부로 붙이면 0과 '이 칸이 없음'이
#   같은 모양이 되고, 상대 봇이 요약줄만 보고 세는데 그 둘은 다른 사실이다.
echo "  통과 $pass · 실패 $fail · 판정 불가 $skip   (코어 정본: $CORE_FIXTURE)"
[ "$fail" -eq 0 ]
