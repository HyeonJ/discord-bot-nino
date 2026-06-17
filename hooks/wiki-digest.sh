#!/usr/bin/env bash
# wiki-digest.sh — 대화 중 위키에 축적할 내용이 있으면 '후보'로 적재하도록 안내
# Claude Code Stop hook으로 사용
#
# Stop hook이 넘기는 stdin JSON은 사용하지 않는다 (리마인더 출력만).
# 이 훅은 리마인더 역할 — 실제 판단은 Claude가 함.
# 정책: 자동 '저장(병합)'이 아니라 자동 '후보화'. 병합은 사람/명시 명령으로만.

cat <<'REMINDER'
<wiki-digest>
이 대화에 wiki로 축적할 '재사용 가능한 지식'이 있었는지 확인하세요.
(리서치 결과 / 기술 결정·해결법 / 학습 내용 / 재사용 가능한 사실)

있으면 — 기존 노트에 바로 병합하지 말고 후보로만 적재하세요:

bash ~/discord-bot-nino/scripts/vault-candidate.sh \
  --topic "주제명" \
  --category 카테고리 \
  --content "축적할 내용" \
  --source local|discord \
  [--confidence high|medium|low] \
  [--reason "왜 저장 가치가 있는지"] \
  [--target-note "wiki/카테고리/기존노트.md"]

카테고리: travel, tech, work, music, gaming, general

규칙:
- 자동 병합 금지 — 후보는 inbox/wiki-candidates/ 에 쌓이고, 검토 후 vault-append.sh로 병합.
- DM·타인 발언·계정/토큰/인증/건강/금전 등 민감 내용은 후보화 금지 (source=dm, privacy=sensitive 는 스크립트가 거부).
- 단순 잡담·일회성 명령 실행은 기록 불필요.
- 사용자가 명시적으로 "두뇌에 넣어줘/위키에 저장"이라고 하면 바로 vault-append.sh 로 저장 허용.
</wiki-digest>
REMINDER
