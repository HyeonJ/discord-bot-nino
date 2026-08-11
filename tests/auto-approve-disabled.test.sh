#!/usr/bin/env bash
# auto-approve-claude.sh 는 «기본 꺼짐»이어야 한다.
#
# 왜: 좌변이 `Esc to cancel` 하나뿐이라 **모든 프롬프트**에 걸리는데 키는 `2` 고정이다.
#   `2` 의 뜻은 프롬프트마다 다르고, 파일 편집 승인에선 **「Yes, don't ask again」(영구 허용)** 이다.
#   룬드 트리에서 2026-07-18 에 실제 사고가 났다(`AskUserQuestion` 무승인 적용).
#
# 🔑 이 훅은 **한 번도 돈 적이 없다** — 크론 가드가 자기 크론 줄을 잡아 `||` 가지가 안 돌았다.
#   그래서 「안 돌아서 안전」이 **코드가 아니라 상태**였고, 크론 줄만 고쳐도 저절로 살아난다.
#   ⇒ 순서(로직 먼저 → 런처 나중)로 막지 않는다. **순서는 사람이 기억해야 해서 새고 플래그는 안 그렇다.**
#
# ⚠️ 이 시험은 **훅이 «안 하는» 것**을 잰다. 그런 시험은 조용히 항진명제가 되기 쉬워서
#   ③ 대조군(플래그를 «켜면» 실제로 진행한다)을 반드시 같이 둔다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$BOT_DIR/hooks/auto-approve-claude.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/     /'; }

[[ -f "$HOOK" ]] || { echo "❌ 대상 없음: $HOOK"; exit 1; }

echo "== auto-approve 기본 꺼짐 =="

_t="$(mktemp -d)"
# 가짜 tmux — 실제 세션에 «절대» 키를 안 보낸다. 호출되면 로그에 남는다.
cat > "$_t/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_CALL_LOG"
if [ "$1" = "capture-pane" ]; then
    printf '%s\n' "  Do you want to make this edit?" "  1. Yes" "  2. Yes, don't ask again" \
                  "  Esc to cancel"
fi
exit 0
EOF
chmod +x "$_t/tmux"

# ── ① 플래그 없이 — 즉시 0 종료
_log1="$_t/call1.log"; : > "$_log1"
PATH="$_t:$PATH" TMUX_CALL_LOG="$_log1" timeout 6 bash "$HOOK" > /dev/null 2>&1
_rc=$?
if [ "$_rc" -eq 0 ]; then
    ok "플래그 없으면 즉시 0 종료 (rc=$_rc)"
else
    bad "플래그 없는데 안 끝난다 — rc=$_rc (124 면 루프에 들어갔다)"
fi

# ── ② 🔴 그 사이 tmux 를 «한 번도» 안 부른다 — 화면조차 안 읽는다
_n1="$(grep -c . "$_log1" 2>/dev/null || true)"; _n1="${_n1:-0}"
if [ "$_n1" -eq 0 ]; then
    ok "tmux 호출 0건 — 화면을 읽지도, 키를 보내지도 않는다"
else
    bad "꺼져 있는데 tmux 를 ${_n1}번 불렀다" "$(cat "$_log1")"
fi

# ── ③ [대조군] 🔴 플래그를 «켜면» 실제로 진행한다 — ①② 가 항진명제가 아니다
#     (켠 판은 루프라 timeout 으로 끊는다. 그때 rc=124 이고 tmux 호출이 «있어야» 한다.)
_log2="$_t/call2.log"; : > "$_log2"
PATH="$_t:$PATH" TMUX_CALL_LOG="$_log2" AUTO_APPROVE_ENABLED=1 \
    timeout 6 bash "$HOOK" > /dev/null 2>&1
_rc2=$?
_n2="$(grep -c . "$_log2" 2>/dev/null || true)"; _n2="${_n2:-0}"
if [ "$_n2" -gt 0 ]; then
    ok "[대조군] 켜면 tmux 를 부른다 (${_n2}건) — 위 초록이 「스크립트가 고장나서」가 아니다"
else
    bad "[대조군] 켜도 tmux 를 안 부른다 — ①② 의 초록이 아무 뜻이 없다" "rc=$_rc2"
fi

# ── ④ 🔴 켠 판은 지금도 «위험하다»는 것을 못 박는다 — 픽스처가 「영구 허용」 화면이었다
#     이 단언은 「고쳐졌다」가 아니라 「아직 안 고쳐졌다」를 기록한다. 고치는 PR 이 이 줄을 바꾼다.
if grep -q "send-keys" "$_log2" 2>/dev/null; then
    ok "[기록] 켠 판은 「2. Yes, don't ask again」 화면에도 키를 보낸다 — 라벨 파싱 판이 오기 전엔 켜지 않는다"
else
    bad "[기록] 예상과 다르다 — 켠 판이 키를 안 보냈다. 이 시험의 전제를 다시 봐야 한다" "$(cat "$_log2")"
fi

rm -rf "$_t"
echo ""
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
