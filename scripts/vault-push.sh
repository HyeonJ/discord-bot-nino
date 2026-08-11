#!/usr/bin/env bash
# vault-push.sh — vault 변경사항 git commit + push (1시간마다 cron)
#
# 🔴 이 vault 는 **Darren 이 옵시디언에서 고치는 곳**이다. 크론이 `git add -A` 로 쓸어담으므로
#   커밋에 담기는 글의 저자는 **크론이 알 수 없다.** 그래서 메시지가 저자를 주장하지 않고,
#   대신 «무엇이 담겼나»를 열거한다. (같은 클래스를 `backup-to-nas.sh` 에서 먼저 고쳤다 — #177)
set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
LOG_FILE="${LOG_FILE:-$HOME/discord-bot-nino/logs/vault-sync.log}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

if [ ! -d "$VAULT_DIR/.git" ]; then
    log "SKIP: vault 없음 — $VAULT_DIR"
    exit 0
fi
cd "$VAULT_DIR"

# 먼저 pull (Darren이 옵시디언에서 수정했을 수 있으니)
git pull origin main --rebase > /dev/null 2>&1 || true

# 변경사항 없으면 스킵
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    exit 0
fi

git add -A

# 🔑 `core.quotepath=false` 없이는 한글 파일명이 «\354\232\224...» 8진으로 나와 목록이 못 읽힌다.
#   vault 는 대부분 한글 파일명이라 이 옵션이 없으면 열거가 사실상 무의미해진다.
_staged="$(git -c core.quotepath=false diff --cached --name-status)"
_n="$(printf '%s\n' "$_staged" | grep -c . || true)"

_msgfile="$(mktemp)"
{
    printf 'sync: vault 동기화 %s (크론 자동 · 저자 미상 %s건)\n\n' \
           "$(date '+%Y-%m-%d %H:%M')" "${_n}"
    printf '⚠️ 이 커밋은 «크론이 쓸어담은» 것이라 저자를 말하지 않는다.\n'
    printf '   아래 변경은 Darren 이 옵시디언에서 쓴 것일 수 있고, 이 메시지는 그 유래가 아니다.\n\n'
    printf '%s\n' "$_staged"
} > "$_msgfile"

if git -c user.name="Nino" -c user.email="nino@yaksu.house" commit -q -F "$_msgfile"; then
    log "COMMIT: ${_n}건"
else
    log "COMMIT: 실패 (담긴 것 ${_n}건)"
fi
rm -f "$_msgfile"

# 🔑 `2>/dev/null` 로 삼키면 「failed」만 남고 «왜» 가 사라진다 — 사유를 잡아서 같이 적는다.
if _perr="$(git push origin main 2>&1)"; then
    log "PUSH: vault sync done (${_n}건)"
else
    log "PUSH: failed — $(printf '%s' "$_perr" | tr '\n' ' ' | cut -c1-200)"
fi
