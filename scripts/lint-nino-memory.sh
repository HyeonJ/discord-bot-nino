#!/bin/bash
# lint-nino-memory.sh — 니노 기억 건강검진 셔틀
# 봇중립 정본(bot-core memory-schema/lint-memory.sh)을 니노 경로+corpus로 exec.
# 로컬 사본 폐기(드리프트 종결) — 정본만 실행. 사용: bash scripts/lint-nino-memory.sh (보고만, 자동 수정 없음)
set -uo pipefail

# 🔴 정본은 **라이브 클론**이다. 예전 기본값 `~/yaksu-bot-core` 를 셔틀이 실행하는 바람에
#    #64~#74 의 lint 개선이 **하나도 안 돌고 있었다**(0번 경로 표시 섹션 자체가 없었다).
#    "정본만 실행해서 드리프트를 끝냈다"고 적어놨는데, 정본이 둘이면 드리프트는 그대로다.
#
#    🔴 **진단 정정 (2026-08-01 19:1x, 룬드 M:vsya 왕복)** — 여기 원래 *"3일간 갱신이 안 됐다"* 고
#    적혀 있었다. **틀렸다. 그건 낡은 게 아니라 「다른 역할」이었다.**
#      ~/yaksu-bot-core        = **dev** (실측: branch=feat/cli-guard) — main 에서 벗어나 있는 게 정상
#      ~/yaksu-bot-core-live   = **prod** (branch=main)                — src/discord-send:9 가 같은 이유를 적어둠
#    ⇒ *"정본이 묵었다"* 로 읽으면 처방이 **「그 클론을 최신화한다」** 로 가는데, 그건 dev 의 존재
#      이유를 깨뜨린다. 실제 고장은 **셔틀이 dev 를 봤다** 이고 처방은 **셔틀이 dev 를 절대 안 본다**.
#      🔑 진단명을 증상으로 붙이면 처방이 반대로 간다.
#    ⚠️ 따라서 이 레이아웃에선 **심링크(두 이름 한 실체)도, dev 쪽 behind 체크도 쓰면 안 된다** —
#      전자는 prod 를 feat 브랜치로 끌고 가고, 후자는 dev 가 원래 뒤처져 있어서 **영구 오탐**이다.
#      🔴 여기 원래 *"룬드 맥은 심링크로 이 고장이 없다"* 고 적혀 있었다. **그것도 틀렸다**
#      (룬드 실측: 심링크 없음 · 클론 하나 · 실디렉터리). 고장이 없는 이유는 심링크가 아니라
#      **클론이 하나**여서다. ⇒ 정정문에 새 추측을 끼워 넣었다 — **남의 환경은 추측하지 말고 묻는다.**
CANON="${LINT_MEMORY_CANONICAL:-$HOME/yaksu-bot-core-live/memory-schema/lint-memory.sh}"
if [[ ! -f "$CANON" ]]; then
  echo "정본 lint 없음: $CANON (yaksu-bot-core 클론/최신화 필요)" >&2
  exit 1
fi

# 실행 직전에 **어느 클론을 보고 있는지** 를 말한다. 경고만 하고 막지 않는다(rc 항상 0).
# 여기가 dev(feat 브랜치)를 가리키면 lint 는 **에러 없이 옛 검사를 돈다** — 그게 이 파일
# 머리말의 사고였다. 계약·근거는 scripts/core-clone-guard.sh 와 tests/core-clone-guard.test.sh.
bash "$(dirname "${BASH_SOURCE[0]}")/core-clone-guard.sh" \
     "${CORE_CLONE_DIR:-$HOME/yaksu-bot-core-live}" "${CORE_CLONE_EXPECT:-main}" || true

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

# §1-b 위키 고아 — 개인 폴더는 검사 범위 밖이다.
# 🔴 왜 「링크를 달자」가 아니라 「검사에서 빼자」인가: 볼트의 `darren/` 밑 5개가 영구 고아로 떴는데,
#    파보니 **링크 누락이 아니라 범위 불일치**였다 — 인덱스를 만드는 `vault-index.sh` 는 `wiki/` 만
#    스캔하는데 고아 검사는 볼트 **전체**를 본다. 손으로 링크를 달아도 **다음 생성기 실행이 지운다.**
#    고칠 수 없는 경고는 가드를 죽인다(사람은 lint 를 끄지 파일을 고치지 않는다).
#    ⇒ 무엇이 더 나쁜지는 재서 안 나와서 Darren 이 골랐다(ⓑ 개인 폴더 제외, M:mwz4).
# 🔑 정본(bot-core #129)의 **기본값은 비어 있다** — 안 쓰는 봇은 안 바뀌게 만들었다.
#    그래서 정본에 코드가 들어간 것만으로는 **아무것도 안 빠진다.** 값을 주는 건 여기 셔틀 몫이다.
#    (이 배선이 없으면 조용히 예전 그대로 돈다 — `tests/lint-shuttle-env.test.sh` 가 그 자리를 잡는다)
# ⚠️ `:-` 가 아니라 `-` 다. `:-` 는 **빈 값도 「안 준 것」으로 쳐서** darren 을 도로 꽂는다 —
#    실제로 그 판으로 델타를 재다가 `WIKI_ORPHAN_EXCLUDES=''` 대조군이 조용히 실험군과
#    같아졌다(A·B 가 글자까지 동일). 즉 **대조군을 못 만드는 배선**이었다.
#    `-` 면 빈 값으로 끌 수 있어 「제외가 실제로 무엇을 빼는지」를 잴 수 있다.
export WIKI_ORPHAN_EXCLUDES="${WIKI_ORPHAN_EXCLUDES-darren}"

# §14 문서 크기 — SIZE_CORPUS 는 기본값 "$WIKI $AUTO" 가 그대로 맞아서 안 준다(위 두 값에서 파생).
# SIZE_BASELINE 은 준다: 정본이 자리를 주지만 **거기 뭘 꽂을지는 봇 셔틀 소관**이라,
# 정본을 맞춰도 "초록에서 시작"은 공유되지 않는다(2026-08-01 룬드와 실측 — 그쪽은 6줄 꽂아
# 초록, 이쪽은 배선이 없어 19건 적색이었다). 등재분의 용법·회수 시점은 그 파일 주석에.
# ⚠️ 여기도 `-`(하이픈만)다. `:-` 였을 때 `SIZE_BASELINE=''` 출력이 기본값 출력과
#    **225줄 내내 diff 0** 이었다 — 면제 24건을 밖에서 끌 수 없어서 「면제가 무엇을 가리고
#    있나」를 잴 방법이 아예 없었다. 이건 위 WIKI_ORPHAN_EXCLUDES 와 **같은 기전**인데,
#    그걸 고칠 때 같이 못 봤다(룬드가 자기 셔틀의 같은 변수를 고친 걸 보고 분모를 훑어 찾음).
#    🔑 한 자리를 고친 것은 그 축을 닫은 게 아니다 — 같은 파일 안에 하나 더 살아 있었다.
export SIZE_BASELINE="${SIZE_BASELINE-$HOME/discord-bot-nino/config/size-baseline.txt}"

exec bash "$CANON" "$@"
