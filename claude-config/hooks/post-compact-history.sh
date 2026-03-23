#!/bin/bash
# PostCompact Hook — compact 후 yaksu-history로 맥락 복구 안내
# Tim 아이디어: AI가 직접 대화를 읽고 판단하는 게 결정론적 스크립트보다 효과적

echo '<system-reminder>
⚠️ 필수 실행 — 건너뛰기 금지!
이전 대화가 압축됐습니다. 다음 두 가지를 반드시 실행하세요:

1. yaksu-history 스킬로 최근 2시간 Discord 대화 확인: /yaksu-history --after 2h --pretty
2. memory/current-tasks.md 읽기

세션 요약이 있더라도 이 단계를 생략하지 마세요. 실제 Discord 메시지에 새로운 요청이나 맥락이 있을 수 있습니다.
</system-reminder>' >&2
exit 2
