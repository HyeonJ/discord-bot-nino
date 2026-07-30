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

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$CHECK" ] || { echo "❌ 없음: $CHECK"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

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

run() {   # run <설명없음> — 환경변수는 앞에 붙여 넘긴다
  STATE="$WORK/run$RANDOM"; mkdir -p "$STATE"
  SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"
  LOGF="$STATE/usage.log"
  env PATH="$WORK/bin:$PATH" SENT_LOG="$SENT_LOG" \
      CHECK_USAGE_CREDENTIALS="$CREDS" CHECK_USAGE_LOG="$LOGF" \
      DISCORD_SEND="$WORK/bin/discord-send" \
      "$@" bash "$CHECK" >/dev/null 2>&1
  RC=$?
  return 0
}

echo "── ① 🔴 429 를 **볼 수 있다** — 이 시험의 본체 ──"
# 옛 코드: 429 본문이 json.loads 를 통과 → 버킷 없음 → 조용히 exit 0. 흔적 0.
run FAKE_CODE=429 FAKE_BODY='{"error":{"type":"rate_limit_error"}}' \
    FAKE_HEADERS='retry-after: 900'
[ -s "$LOGF" ] && ok "429 여도 로그가 남는다" || bad "429 로그" "1줄 이상" "빈 파일"
grep -q 'code=429' "$LOGF" && ok "상태코드가 로그에 수치로 남는다 (code=429)" \
  || bad "code=429" "있음" "$(cat "$LOGF")"
grep -q 'verdict=ok' "$LOGF" && bad "429 를 정상으로 판정했다" "ok 아님" "$(cat "$LOGF")" \
  || ok "429 를 정상으로 접지 않는다"
[ "$RC" -ne 0 ] && ok "429 는 rc≠0 (조용한 exit 0 이 아니다, rc=$RC)" \
  || bad "429 종료코드" "0 아님" "rc=0 — 옛 동작"

echo "── ② 🔑 retry-after 를 기록한다 — 공유 백오프(②)의 설계 근거가 된다 ──"
# 🔸 룬드가 소비자 구조를 찾은 근거가 로그였다. 값을 안 남기면 조율을 설계할 점이 안 쌓인다.
grep -q 'retry_after=900' "$LOGF" && ok "retry-after 헤더가 로그에 남는다" \
  || bad "retry_after=900" "있음" "$(cat "$LOGF")"

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

echo "── ⑦ 네트워크 실패(curl rc≠0)와 HTTP 오류를 **다른 칸**에 넣는다 ──"
# 🔑 둘을 뭉치면 *못 쟀다* 와 *서버가 거절했다* 가 같은 칸이 된다 — 조치가 다르다.
run FAKE_CURL_RC=6 FAKE_BODY='' FAKE_CODE=000
grep -q 'verdict=network' "$LOGF" && ok "curl 실패는 verdict=network" \
  || bad "verdict=network" "있음" "$(cat "$LOGF")"
grep -q 'verdict=http_error' "$LOGF" && bad "네트워크 실패를 http_error 로 접었다" "network" "$(cat "$LOGF")" \
  || ok "네트워크와 HTTP 오류가 안 섞인다"

echo "── ⑧ 본문이 JSON 이 아니면 unparseable — 정상으로 접지 않는다 ──"
run FAKE_CODE=200 FAKE_BODY='<html>oops</html>'
grep -q 'verdict=unparseable' "$LOGF" && ok "verdict=unparseable" \
  || bad "verdict=unparseable" "있음" "$(cat "$LOGF")"

echo "── ⑨ 🔑 **어떤 경로로 끝나도 로그 1줄** — 갈래마다 시험을 붙일 수 없으니 성질로 잠근다 ──"
# 🔴 이 스크립트엔 조기 종료가 여럿이다. 갈래마다 케이스를 만드는 대신 **exit 앞에 로그가 보장되는 구조**
#    (trap …EXIT)인지를 정적으로 본다. check-auth.sh 가 같은 방식으로 산 사고를 막았다.
grep -q 'trap .*EXIT' "$CHECK" && ok "trap …EXIT 로 로그를 보장한다" \
  || bad "로그 보장 구조" "trap …EXIT" "없음 — 조기 종료 갈래가 조용해진다"

echo "── ⑩ 이식성 — 원시 GNU 명령을 안 쓴다 (룬드 맥 기준선) ──"
viol="$(python3 - "$CHECK" <<'PYEOF'
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
)"
[ -z "$viol" ] && ok "GNU 전용 명령 0건" || bad "이식성 위반" "0건" "$viol"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
