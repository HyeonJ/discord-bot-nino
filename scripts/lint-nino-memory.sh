#!/bin/bash
# lint-nino-memory.sh — 니노 기억 건강검진 셔틀
# 봇중립 정본(bot-core memory-schema/lint-memory.sh)을 니노 경로+corpus로 exec.
# 로컬 사본 폐기(드리프트 종결) — 정본만 실행. 사용: bash scripts/lint-nino-memory.sh (보고만, 자동 수정 없음)
set -uo pipefail

# 🔴 정본은 **라이브 클론**이다. 예전 기본값 `~/yaksu-bot-core` 는 별도 클론이라 3일간
#    갱신이 안 됐고(842d7d3 · 140줄 vs live 05ee92d · 303줄), 셔틀이 그걸 실행하는 바람에
#    #64~#74 의 lint 개선이 **하나도 안 돌고 있었다**(0번 경로 표시 섹션 자체가 없었다).
#    "정본만 실행해서 드리프트를 끝냈다"고 적어놨는데, 정본이 둘이면 드리프트는 그대로다.
CANON="${LINT_MEMORY_CANONICAL:-$HOME/yaksu-bot-core-live/memory-schema/lint-memory.sh}"
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

# 선택 2개 — **안 주면 정본의 기본값(룬드 레이아웃 `~/Assistant/...`)을 보게 된다.**
# 그래서 검사 11번이 영구 무음이었다: 없는 경로에서 `[[ -f ]]` 가 조용히 빠짐.
# 값을 주는 것 자체가 목적이 아니라, **내 경로를 해석 결과로 찍히게 하는 것**이 목적이다
# (정본 0번 섹션이 필수 3개는 ✅/issue, 선택 2개는 ➖ 로 표시해준다 — bot-core #70).
export PROJECT_CLAUDE_MD="${PROJECT_CLAUDE_MD:-$HOME/discord-bot-nino/CLAUDE.md}"
export CASCADE_QUEUE="${CASCADE_QUEUE:-$MEMORY_AUTO_DIR/state/cascade-queue.md}"

# §14 문서 크기 — SIZE_CORPUS 는 기본값 "$WIKI $AUTO" 가 그대로 맞아서 안 준다(위 두 값에서 파생).
# SIZE_BASELINE 은 준다: 정본이 자리를 주지만 **거기 뭘 꽂을지는 봇 셔틀 소관**이라,
# 정본을 맞춰도 "초록에서 시작"은 공유되지 않는다(2026-08-01 룬드와 실측 — 그쪽은 6줄 꽂아
# 초록, 이쪽은 배선이 없어 19건 적색이었다). 등재분의 용법·회수 시점은 그 파일 주석에.
export SIZE_BASELINE="${SIZE_BASELINE:-$HOME/discord-bot-nino/config/size-baseline.txt}"

exec bash "$CANON" "$@"
