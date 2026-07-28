#!/bin/bash
# lint-nino-memory.sh — 니노 기억 건강검진 셔틀
# 봇중립 정본(bot-core memory-schema/lint-memory.sh)을 니노 경로+corpus로 exec.
# 로컬 사본 폐기(드리프트 종결) — 정본만 실행. 사용: bash scripts/lint-nino-memory.sh (보고만, 자동 수정 없음)
set -uo pipefail

CANON="${LINT_MEMORY_CANONICAL:-$HOME/yaksu-bot-core/memory-schema/lint-memory.sh}"
if [[ ! -f "$CANON" ]]; then
  echo "정본 lint 없음: $CANON (yaksu-bot-core 클론/최신화 필요)" >&2
  exit 1
fi

# 니노 3경로 (auto-memory=하네스 인덱스 / wiki=옵시디언 볼트 / shared=공유 데이터)
export MEMORY_AUTO_DIR="${MEMORY_AUTO_DIR:-$HOME/.claude/projects/-home-bpx27-discord-bot-nino/memory}"
export MEMORY_WIKI_DIR="${MEMORY_WIKI_DIR:-$HOME/obsidian-vault}"
export MEMORY_SHARED_DIR="${MEMORY_SHARED_DIR:-$HOME/yaksu-shared-data}"

# 밀도(§9) corpus = auto-memory: 니노 cascade·[[링크]] 그래프가 사는 곳.
# (옵시디언 볼트는 링크 스트립 export 미러라 8%로 왜곡됐음 — bot-core PR #49.)
# auto-memory엔 unlinkable 클래스(alarms·frozen 등)가 없어 DENSITY_EXCLUDES 기본값 유지.
export CASCADE_CORPUS="${CASCADE_CORPUS:-$MEMORY_AUTO_DIR}"

exec bash "$CANON" "$@"
