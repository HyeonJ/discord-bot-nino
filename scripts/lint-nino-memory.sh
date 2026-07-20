#!/bin/bash
# lint-nino-memory.sh — 니노 기억 건강검진 래퍼
# 봇중립 lint-memory.sh(bot-core memory-schema 동기)를 니노 경로로 실행.
# 사용: bash scripts/lint-nino-memory.sh   (보고만, 자동 수정 없음)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 니노 3경로 (auto-memory=하네스 인덱스 / wiki=옵시디언 볼트 / shared=공유 데이터)
export MEMORY_AUTO_DIR="${MEMORY_AUTO_DIR:-$HOME/.claude/projects/-home-bpx27-discord-bot-nino/memory}"
export MEMORY_WIKI_DIR="${MEMORY_WIKI_DIR:-$HOME/obsidian-vault}"
export MEMORY_SHARED_DIR="${MEMORY_SHARED_DIR:-$HOME/yaksu-shared-data}"

exec bash "$DIR/lint-memory.sh" "$@"
