#!/usr/bin/env bash
# discord-send 호출부 가드 (정적 검사 — 전송 없음)
#
# ① 정본 문법 강제: 살아있는 호출부에 deprecated `-c/--channel`이 남으면 실패.
#    `-c`는 이름이 channel인데 target은 채널명·메시지해시·스레드해시·DM-이름·raw ID로 넓어져
#    의미가 어긋난다(§8 A안, Darren 승인 M:2yl2). 문서·예시도 실행 경로라 같이 검사한다.
# ② 경로 실재 검증: 호출부가 가리키는 discord-send 실행파일이 실제로 있어야 한다.
#    of/* 6곳이 `$SD/discord-send`(src/ 누락)를 호출하며 출력을 /dev/null로 버려
#    **조용히 실패**하고 있었다(2026-07-25 발견). 정적으로 잡아 재발을 막는다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BOT_DIR"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/     /'; }

# 검사 대상에서 제외: 죽은 사본·로그·히스토리·legacy 백업(롤백용이라 옛 문법 보존)·이 테스트 자신
live_files() {
  grep -rln 'discord-send' \
    --include='*.sh' --include='*.js' --include='*.py' --include='*.md' \
    . 2>/dev/null |
    grep -v 'node_modules\|/backups/\|\.preflip-bak\|/logs/\|memory/discord-history\|discord-send-legacy\|tests/discord-send-callers.test.sh'
}

echo "① deprecated -c/--channel 잔존 검사:"
# discord-send 호출 뒤에 -c/--channel이 붙은 라인만 (python3 -c·tmux -c 오탐 회피: discord-send 뒤만 본다)
# 셸/문서형: `discord-send … -c <target>` / 파이썬 리스트형: `[…"discord-send", "-c", DM…]`
HITS=$(live_files | xargs grep -nE 'discord-send[^|;]*([[:space:]]|["'"'"'])(-c|--channel)(["'"'"']|[[:space:]])' 2>/dev/null || true)
if [[ -z "$HITS" ]]; then
  ok "살아있는 호출부·문서에 -c 없음 (positional 정본)"
else
  bad "deprecated -c 잔존 $(echo "$HITS" | wc -l)건" "$HITS"
fi

echo ""
echo "② discord-send 실행경로 실재 검사:"
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
