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
    # 🔑 상위 디렉터리가 없으면 이 스크립트의 «사유 로깅이 통째로 무음»이 된다 (룬드 #179 곁가지).
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# 🔑 rebase 가 충돌로 멈추면 `.git/rebase-merge` 가 남아 **다음 회차의 모든 git 명령이 그 위에서 돈다.**
#   크론이라 사람이 안 보므로 이 잔재가 제일 비싸다 — 실패하면 반드시 되돌린다.
pull_rebase() {
    local _rerr
    if _rerr="$(git pull origin main --rebase 2>&1)"; then
        return 0
    fi
    log "PULL: failed — $(printf '%s' "$_rerr" | tr '\n' ' ' | cut -c1-200)"
    git rebase --abort > /dev/null 2>&1 || true
    return 1
}

if [ ! -d "$VAULT_DIR/.git" ]; then
    log "SKIP: vault 없음 — $VAULT_DIR"
    exit 0
fi
cd "$VAULT_DIR"

# 변경사항 없으면 «pull 만» 하고 끝낸다.
# 🔑 이 갈래의 pull 을 빼면 안 된다 — 「폰에서만 고친 회차」가 로컬에 영영 안 온다.
#   (아래 커밋-뒤-pull 수리가 이 갈래를 조용히 죽이는 것을 `⑩ 대조군` 이 잡는다.)
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    pull_rebase || true
    exit 0
fi

git add -A

# 🔑 `core.quotepath=false` 없이는 한글 파일명이 «\354\232\224...» 8진으로 나와 목록이 못 읽힌다.
#   vault 는 대부분 한글 파일명이라 이 옵션이 없으면 열거가 사실상 무의미해진다.
_staged="$(git -c core.quotepath=false diff --cached --name-status)"
_n="$(printf '%s\n' "$_staged" | grep -c . || true)"
_n="${_n:-0}"

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

# 🔴 pull 은 **커밋 «뒤»**에 한다 (룬드 #179).
#   앞에 두면 tracked 수정이 있을 때 `cannot pull with rebase: You have unstaged changes` 로
#   **rc=128** 이 나고, 옛 판의 `|| true` 가 그걸 삼켰다. 그런데 **그 갈래가 정확히 pull 이
#   값을 하는 유일한 자리**(로컬 수정 + 원격 앞섬)라, 필요한 곳에서만 반드시 실패했다.
#   커밋 뒤엔 tree 가 clean 이라 rebase 가 **구조적으로 항상 가능**하고 stash 도 필요 없다.
pull_rebase || true

# 🔑 `2>/dev/null` 로 삼키면 「failed」만 남고 «왜» 가 사라진다 — 사유를 잡아서 같이 적는다.
if _perr="$(git push origin main 2>&1)"; then
    log "PUSH: vault sync done (${_n}건)"
else
    log "PUSH: failed — $(printf '%s' "$_perr" | tr '\n' ' ' | cut -c1-200)"
fi
