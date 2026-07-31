#!/usr/bin/env bash
# check-usage.sh 계약 시험 — **버킷 하나가 죽으면 뒤가 통째로 사라진다**
#
# 🔴 이 시험이 생긴 사고 (2026-07-31 실측):
#   API 응답에 `utilization: null` 인 버킷이 있다(`extra_usage` · `spend` — 한도가 아니라
#   결제/추가사용 정보다). 그런데 코드가 `v.get('utilization', 0)` 을 쓴다:
#
#     🔑 `.get(k, default)` 는 **키가 없을 때만** 기본값을 준다.
#        키가 있고 값이 None 이면 **None 이 그대로 나온다** — 기본값은 안 먹는다.
#
#   ⇒ `f'{None:.1f}'` 에서 TypeError → **루프 전체가 죽는다.**
#     지금은 five_hour·seven_day 가 먼저 와서 출력된 뒤 죽어 *"조금 시끄러운 성공"* 처럼 보이지만,
#     그건 **딕셔너리 순서에 기댄 우연**이다. null 버킷이 앞으로 오면 한도가 하나도 안 나온다.
#
# 🔑 그래서 중심은 "숫자가 맞나"가 아니라 **"한 버킷의 사고가 다른 버킷을 삼키지 않나"** 다.
#
# ⚠️ 부작용 금지: 실제 API·실제 credentials 를 건드리지 않는다. curl 과 자격증명 경로를 주입한다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO/scripts/check-usage.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$CHECK" ] || { echo "❌ 없음: $CHECK"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# ── 가짜 자격증명 (값은 의미 없음 — 형태만 맞춘다) ───────────────────────────
cat > "$WORK/creds.json" <<'JSON'
{"claudeAiOauth": {"accessToken": "FAKE-FOR-TEST"}}
JSON

# ── 가짜 curl: FAKE_BODY 를 그대로 뱉는다 ────────────────────────────────────
cat > "$WORK/bin/curl" <<'SH'
#!/bin/bash
printf '%s' "${FAKE_BODY:-{\}}"
SH
chmod +x "$WORK/bin/curl"

run() { FAKE_BODY="$1" PATH="$WORK/bin:$PATH" CHECK_USAGE_CREDENTIALS="$WORK/creds.json" bash "$CHECK" 2>&1; }

echo "── check-usage.sh ──────────────────────────────────────────────"

# ① 정상 두 버킷
out="$(run '{"five_hour":{"utilization":28,"resets_at":"2026-07-30T19:50:00Z"},"seven_day":{"utilization":17,"resets_at":"2026-08-05T19:00:00Z"}}')"
case "$out" in
  *"5시간 한도"*"28.0%"*) ok "① 5시간 한도를 출력한다" ;;
  *) bad "① 5시간 한도를 출력한다" "28.0%" "$out" ;;
esac
case "$out" in
  *"7일 한도"*"17.0%"*) ok "① 7일 한도를 출력한다" ;;
  *) bad "① 7일 한도를 출력한다" "17.0%" "$out" ;;
esac

# ② 🔴 핵심: null 버킷이 **앞에** 있어도 뒤의 한도가 살아남는다
#    (실제 응답의 extra_usage·spend 가 이 형태다. 지금 코드는 여기서 죽는다)
out="$(run '{"extra_usage":{"utilization":null},"spend":{"utilization":null},"five_hour":{"utilization":28,"resets_at":"2026-07-30T19:50:00Z"}}')"
case "$out" in
  *"5시간 한도"*"28.0%"*) ok "② null 버킷이 앞에 와도 뒤의 한도가 나온다" ;;
  *) bad "② null 버킷이 앞에 와도 뒤의 한도가 나온다" "5시간 한도 28.0%" "$out" ;;
esac
case "$out" in
  *Traceback*) bad "② traceback 이 없다" "조용" "$out" ;;
  *) ok "② traceback 이 없다" ;;
esac

# ③ null 버킷 자체는 **한도가 아니므로** 줄을 만들지 않는다 (0.0% 로 위조하지 않는다)
#    🔑 모르는 값을 0 으로 적으면 "여유 100%" 라는 **거짓 정보**가 된다 — 빼는 게 맞다.
out="$(run '{"extra_usage":{"utilization":null},"five_hour":{"utilization":28}}')"
case "$out" in
  *extra_usage*) bad "③ null 버킷은 줄을 만들지 않는다" "출력 없음" "$out" ;;
  *) ok "③ null 버킷은 줄을 만들지 않는다" ;;
esac

# ④ 성공 경로의 종료코드는 0
run '{"five_hour":{"utilization":28}}' >/dev/null 2>&1
[ $? -eq 0 ] && ok "④ 정상 응답이면 rc=0" || bad "④ 정상 응답이면 rc=0" "0" "$?"

# ⑤ 🔴 응답이 JSON 이 아니면 **조용히 성공하지 않는다**
#    (429·502 본문은 JSON 이 아닐 수 있다. rc=0 이면 cron 이 "잘 돌았다"로 읽는다)
run 'not json at all' >/dev/null 2>&1
[ $? -ne 0 ] && ok "⑤ JSON 이 아니면 rc≠0" || bad "⑤ JSON 이 아니면 rc≠0" "≠0" "0"

# ⑥ 🔴 자격증명을 못 읽으면 **API 를 부르지 않고** 실패한다
#    (빈 토큰으로 부르면 401 을 받고, 그게 "한도 조회 실패" 로 뭉개진다)
out="$(FAKE_BODY='{}' PATH="$WORK/bin:$PATH" CHECK_USAGE_CREDENTIALS="$WORK/nope.json" bash "$CHECK" 2>&1)"
rc=$?
[ $rc -ne 0 ] && ok "⑥ 자격증명 없으면 rc≠0" || bad "⑥ 자격증명 없으면 rc≠0" "≠0" "$rc"
case "$out" in
  *Traceback*) bad "⑥ 자격증명 실패는 traceback 말고 문장으로" "안내 문구" "$out" ;;
  *) ok "⑥ 자격증명 실패는 traceback 말고 문장으로" ;;
esac

echo "───────────────────────────────────────────────────────────────"
echo "통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
