#!/bin/bash
# 니노 봇 이식/복구 스크립트
# Usage:
#   ./setup.sh --mode bootstrap    # 새 OS에 처음부터 설치
#   ./setup.sh --mode fast-restore # 백업에서 빠른 복구

set -euo pipefail

# ── 색상 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }
step() { echo -e "\n${YELLOW}━━━ $* ━━━${NC}"; }

# ── 인자 파싱 ──
MODE=""
BOT_NAME="nino"
REPO_URL="https://github.com/HyeonJ/discord-bot-nino.git"
BOT_DIR="$HOME/discord-bot-nino"
NAS_BACKUP="/mnt/d/Darren/backup/nino"

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)    MODE="$2"; shift 2 ;;
        --bot-dir) BOT_DIR="$2"; shift 2 ;;
        --nas)     NAS_BACKUP="$2"; shift 2 ;;
        *)         fail "Unknown option: $1" ;;
    esac
done

[[ -z "$MODE" ]] && fail "Usage: ./setup.sh --mode {bootstrap|fast-restore}"
[[ "$MODE" != "bootstrap" && "$MODE" != "fast-restore" ]] && fail "Mode must be 'bootstrap' or 'fast-restore'"

echo "╔══════════════════════════════════════╗"
echo "║  니노 봇 셋업 — mode: $MODE"
echo "╚══════════════════════════════════════╝"

# ═══════════════════════════════════════
# Phase 1: 환경 감지
# ═══════════════════════════════════════
step "Phase 1: 환경 감지"

OS_TYPE="unknown"
if grep -qi microsoft /proc/version 2>/dev/null; then
    OS_TYPE="wsl"
elif [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
elif [[ "$(uname)" == "Linux" ]]; then
    OS_TYPE="linux"
fi
ok "OS: $OS_TYPE ($(uname -r))"
ok "User: $(whoami)"
ok "Home: $HOME"

# ═══════════════════════════════════════
# Phase 2: 도구 설치 (bootstrap만)
# ═══════════════════════════════════════
if [[ "$MODE" == "bootstrap" ]]; then
    step "Phase 2: 도구 설치"

    # git
    if command -v git &>/dev/null; then
        ok "git $(git --version | cut -d' ' -f3)"
    else
        warn "git 설치 중..."
        sudo apt-get update && sudo apt-get install -y git
    fi

    # Node.js (nvm)
    if command -v node &>/dev/null; then
        ok "node $(node --version)"
    else
        warn "nvm + node 설치 중..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        source "$NVM_DIR/nvm.sh"
        nvm install --lts
        ok "node $(node --version)"
    fi

    # Python + uv
    if command -v python3 &>/dev/null; then
        ok "python3 $(python3 --version | cut -d' ' -f2)"
    else
        warn "python3 설치 중..."
        sudo apt-get install -y python3 python3-pip
    fi

    if command -v uv &>/dev/null; then
        ok "uv $(uv --version | cut -d' ' -f2)"
    else
        warn "uv 설치 중..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    # tmux
    if command -v tmux &>/dev/null; then
        ok "tmux $(tmux -V | cut -d' ' -f2)"
    else
        warn "tmux 설치 중..."
        sudo apt-get install -y tmux
    fi

    # rsync
    if command -v rsync &>/dev/null; then
        ok "rsync installed"
    else
        warn "rsync 설치 중..."
        sudo apt-get install -y rsync
    fi

    # Claude Code CLI
    if command -v claude &>/dev/null; then
        ok "claude $(claude --version 2>/dev/null || echo 'installed')"
    else
        warn "Claude Code CLI 설치 필요 — npm install -g @anthropic-ai/claude-code"
        echo "  설치 후 'claude auth login' 으로 인증하세요"
    fi
fi

# ═══════════════════════════════════════
# Phase 3: 레포 클론 / 업데이트
# ═══════════════════════════════════════
step "Phase 3: 레포"

if [[ -d "$BOT_DIR/.git" ]]; then
    ok "레포 존재 — pull"
    cd "$BOT_DIR" && git pull --ff-only
else
    warn "레포 클론 중..."
    git clone "$REPO_URL" "$BOT_DIR"
fi
cd "$BOT_DIR"
ok "레포 준비 완료: $BOT_DIR"

# ═══════════════════════════════════════
# Phase 4: Claude 설정 복원
# ═══════════════════════════════════════
step "Phase 4: Claude 설정 복원"

CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks"

# skills 복원
if [[ -d "$BOT_DIR/claude-config/skills" ]]; then
    for skill_dir in "$BOT_DIR/claude-config/skills"/*/; do
        skill_name=$(basename "$skill_dir")
        if [[ ! -d "$CLAUDE_DIR/skills/$skill_name" ]]; then
            cp -r "$skill_dir" "$CLAUDE_DIR/skills/"
            ok "skill 복원: $skill_name"
        else
            ok "skill 이미 존재: $skill_name"
        fi
    done
fi

# hooks 복원
if [[ -d "$BOT_DIR/claude-config/hooks" ]]; then
    for hook_file in "$BOT_DIR/claude-config/hooks"/*; do
        hook_name=$(basename "$hook_file")
        cp "$hook_file" "$CLAUDE_DIR/hooks/"
        chmod +x "$CLAUDE_DIR/hooks/$hook_name"
        ok "hook 복원: $hook_name"
    done
fi

# user-settings.json 복원
if [[ -f "$BOT_DIR/claude-config/user-settings.json" ]]; then
    if [[ ! -f "$CLAUDE_DIR/settings.json" ]]; then
        cp "$BOT_DIR/claude-config/user-settings.json" "$CLAUDE_DIR/settings.json"
        ok "user settings 복원"
    else
        warn "user settings 이미 존재 — 덮어쓰지 않음"
    fi
fi

# ═══════════════════════════════════════
# Phase 5: Memory 복원 (NAS에서)
# ═══════════════════════════════════════
step "Phase 5: Memory 복원"

PROJECT_MEMORY="$CLAUDE_DIR/projects/-home-$(whoami)-discord-bot-nino/memory"
mkdir -p "$PROJECT_MEMORY"

if [[ -d "$NAS_BACKUP/memory" ]] && [[ "$(ls -A "$NAS_BACKUP/memory" 2>/dev/null)" ]]; then
    rsync -r --no-perms --no-owner --no-group "$NAS_BACKUP/memory/" "$PROJECT_MEMORY/"
    FILE_COUNT=$(find "$PROJECT_MEMORY" -type f | wc -l)
    ok "memory 복원 완료 ($FILE_COUNT 파일)"
else
    warn "NAS 백업 없음 ($NAS_BACKUP/memory) — memory 복원 건너뜀"
fi

# ═══════════════════════════════════════
# Phase 6: yaksu-history DB 복원
# ═══════════════════════════════════════
step "Phase 6: yaksu-history DB 복원"

HISTORY_DIR="$HOME/.local/share/yaksu-history"
mkdir -p "$HISTORY_DIR"

if [[ -d "$NAS_BACKUP/yaksu-history" ]]; then
    LATEST_SNAP=$(ls -t "$NAS_BACKUP/yaksu-history"/messages-*.db 2>/dev/null | head -1 || true)
    if [[ -n "${LATEST_SNAP:-}" ]]; then
        if [[ ! -f "$HISTORY_DIR/messages.db" ]]; then
            cp "$LATEST_SNAP" "$HISTORY_DIR/messages.db"
            ok "yaksu-history 복원: $(basename "$LATEST_SNAP")"
        else
            warn "yaksu-history 이미 존재 — 덮어쓰지 않음"
        fi
    else
        warn "yaksu-history 스냅샷 없음"
    fi
else
    warn "NAS yaksu-history 백업 없음"
fi

# ═══════════════════════════════════════
# Phase 7: .env 확인
# ═══════════════════════════════════════
step "Phase 7: .env 확인"

if [[ -f "$BOT_DIR/.env" ]]; then
    ok ".env 존재"
elif [[ -f "$NAS_DIR/env.age" ]]; then
    # NAS에 암호화된 .env가 있으면 복호화 시도
    AGE_BIN=$(command -v age 2>/dev/null || echo "$HOME/.local/bin/age")
    if [[ -x "$AGE_BIN" ]]; then
        warn "NAS에서 암호화된 .env 발견 — 복호화 키 파일 경로를 입력하세요"
        read -rp "age 키 파일 경로 (예: /path/to/nino-age-key.txt): " AGE_KEY_PATH
        if [[ -f "$AGE_KEY_PATH" ]]; then
            "$AGE_BIN" -d -i "$AGE_KEY_PATH" "$NAS_DIR/env.age" > "$BOT_DIR/.env"
            ok ".env 복호화 완료!"
        else
            warn "키 파일 없음 — .env 수동 생성 필요"
        fi
    else
        warn "age 미설치 — .env 수동 생성 필요"
    fi
else
    if [[ -f "$BOT_DIR/.env.example" ]]; then
        cp "$BOT_DIR/.env.example" "$BOT_DIR/.env"
        warn ".env.example에서 복사됨 — 값을 채워넣으세요!"
    else
        warn ".env 없음 — 수동 생성 필요"
    fi
fi

# ═══════════════════════════════════════
# Phase 8: cron 등록
# ═══════════════════════════════════════
step "Phase 8: cron 등록"

CRON_ENTRIES=(
    "* * * * * $BOT_DIR/alarm-tool fire"
    "* * * * * $BOT_DIR/scripts/presence-check.sh"
    "*/2 * * * * $BOT_DIR/scripts/nino-watchdog.sh"
    "*/30 * * * * $BOT_DIR/scripts/check-usage-alert.sh"
    "*/5 * * * * source $HOME/.nvm/nvm.sh && $BOT_DIR/scripts/check-auth.sh"
    "0 * * * * bash $BOT_DIR/scripts/backup-to-nas.sh"
)

CURRENT_CRON=$(crontab -l 2>/dev/null || true)
ADDED=0
for entry in "${CRON_ENTRIES[@]}"; do
    if ! echo "$CURRENT_CRON" | grep -qF "$(echo "$entry" | awk '{print $NF}')"; then
        CURRENT_CRON="$CURRENT_CRON
$entry"
        ((ADDED++))
    fi
done

if [[ $ADDED -gt 0 ]]; then
    echo "$CURRENT_CRON" | crontab -
    ok "cron $ADDED개 추가"
else
    ok "cron 이미 등록됨"
fi

# ═══════════════════════════════════════
# Phase 9: 헬스체크
# ═══════════════════════════════════════
step "Phase 9: 헬스체크"

# 필수 파일 확인
REQUIRED_FILES=(".env" "src/discord-relay.js" "src/discord-send" "CLAUDE.md" "scripts/start-nino.sh")
for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$BOT_DIR/$f" ]] || [[ -x "$BOT_DIR/$f" ]]; then
        ok "파일 존재: $f"
    else
        warn "파일 없음: $f"
    fi
done

# 권한 확인
if [[ -f "$BOT_DIR/.env" ]]; then
    PERMS=$(stat -c %a "$BOT_DIR/.env" 2>/dev/null || stat -f %Lp "$BOT_DIR/.env" 2>/dev/null)
    if [[ "$PERMS" == "600" ]]; then
        ok ".env 권한 OK (600)"
    else
        chmod 600 "$BOT_DIR/.env"
        ok ".env 권한 600으로 설정"
    fi
fi

# ═══════════════════════════════════════
# 완료
# ═══════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  셋업 완료!                          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "다음 단계:"
echo "  1. .env 값 채우기 (DISCORD_BOT_TOKEN 등)"
echo "  2. Claude CLI 인증: claude auth login"
echo "  3. 봇 시작: bash $BOT_DIR/start-nino.sh"
echo ""
