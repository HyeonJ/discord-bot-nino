#!/usr/bin/env bash
# discord-send 호출부 가드 (정적 검사 — 전송 없음)
#
# ① 정본 문법 강제 → **코어에 위임** (2026-07-25 코어 PR #55 머지, b50ed69).
#    positional은 코어 CLI 계약이라 가드도 코어가 소유한다. 여기서 두 벌 유지하면
#    정규식이 갈라져 조용히 드리프트한다(합의≠구현 클래스). 니노는 스캔 루트만 준다.
# ② 경로 실재 검증은 **니노 로컬** — `$SD`/`$BOT_DIR`/`$SCRIPT_DIR` 같은 니노 관습 변수를
#    실측 정의값으로 치환해 검증하므로 봇 중립이 아니다(코어 이관 대상 아님).
#    of/* 6곳이 `$SD/discord-send`(src/ 누락)를 호출하며 출력을 /dev/null로 버려
#    **조용히 실패**하고 있었다(2026-07-25 발견). 정적으로 잡아 재발을 막는다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BOT_DIR"

# 코어 가드 경로 — 프로덕션 체크아웃(셔틀과 같은 소스). 없으면 skip이 아니라 fail:
# "코어 없음"을 조용히 통과시키면 가드가 사라진 걸 아무도 모른다.
CORE_GUARD="${CORE_GUARD:-/home/bpx27/yaksu-bot-core-live/relay/discord-send/lint-callers.sh}"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/     /'; }

# 검사 대상에서 제외: 죽은 사본·로그·히스토리·legacy 백업(롤백용이라 옛 문법 보존)
# + 이 테스트 자신: 위 주석이 과거 버그를 `$SD/discord-send`로 **인용**하고 있어 ②가 자기적발한다.
#   (코어 가드는 lint-callers:allow 마커로 같은 문제를 푼다 — ②는 로컬이라 경로 제외로 충분)
EXCLUDE_RE='node_modules|/backups/|\.preflip-bak|/logs/|memory/discord-history|discord-send-legacy|tests/discord-send-callers\.test\.sh'
live_files() {
  grep -rln 'discord-send' \
    --include='*.sh' --include='*.js' --include='*.py' --include='*.md' \
    . 2>/dev/null | grep -vE "$EXCLUDE_RE"
}

echo "① deprecated -c/--channel 잔존 검사 (코어 위임):"
if [[ ! -x "$CORE_GUARD" ]]; then
  bad "코어 가드 없음: $CORE_GUARD — yaksu-bot-core-live pull 확인 (머지≠반영)"
else
  GUARD_OUT=$(CALLER_SCAN_DIR="$BOT_DIR" bash "$CORE_GUARD" 2>&1); GUARD_RC=$?
  if [[ $GUARD_RC -eq 0 ]]; then
    ok "$(printf '%s' "$GUARD_OUT" | tail -1 | sed 's/^✅ *//')"  # 코어 출력의 ✅ 중복 제거
  else
    bad "코어 가드 exit $GUARD_RC" "$GUARD_OUT"
  fi
fi

echo ""
echo "② discord-send 실행경로 실재 검사 (니노 로컬):"
# 호출부에서 참조하는 절대경로/변수전개 경로를 뽑아 존재 확인 (변수는 실측 정의값으로 치환)
BROKEN=""
while IFS= read -r ref; do
  p="${ref/\$SD\//$BOT_DIR/}"; p="${p/\$\{SD\}\//$BOT_DIR/}"
  p="${p/\$BOT_DIR\//$BOT_DIR/}"; p="${p/\$\{BOT_DIR\}\//$BOT_DIR/}"
  p="${p/\$SCRIPT_DIR\//$BOT_DIR\/src/}"; p="${p/\$\{SCRIPT_DIR\}\//$BOT_DIR\/src/}"
  [[ "$p" == /* ]] || continue
  [[ -x "$p" ]] || BROKEN+="$ref → $p (없음)"$'\n'
done < <(live_files | xargs grep -ho '[$A-Za-z_{][^"'"'"' ]*/discord-send' 2>/dev/null | sort -u)

if [[ -z "$BROKEN" ]]; then
  ok "참조된 실행경로 전부 존재"
else
  bad "깨진 경로 발견" "$BROKEN"
fi

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
