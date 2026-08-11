#!/bin/bash
# auto-approve-claude.sh — tmux 프롬프트 자동 응답 (🔴 현재 «비활성». 아래 참조)
# crontab 에서 실행. 5초마다 tmux 화면 감시.
#   ⚠️ 머리말이 「LaunchAgent」·「.claude/ 수정 프롬프트」라 적혀 있었는데 둘 다 사실이 아니다
#      — 실행은 crontab 이고, 좌변은 아래 보듯 «모든 프롬프트»를 잡는다.

# 🔴 **기본 꺼짐 — `AUTO_APPROVE_ENABLED` 가 없으면 아무것도 안 한다.**
#
# 왜: 이 훅은 좌변이 `Esc to cancel` 하나뿐이라 **모든 프롬프트**에 걸리는데 보내는 키는 `2` 고정이다.
#   `2` 의 «뜻»은 프롬프트마다 다르다 — 위험한 rm 에선 `No`(거절)지만 파일 편집 승인에선
#   **`Yes, don't ask again`(영구 허용)** 이다. 룬드 트리에서 2026-07-18 에 실제로 터졌다
#   (`AskUserQuestion` 에 `2` 가 들어가 fallbackModel 이 **무승인 적용**되고 승인받았다고 보고까지).
#
# 🔑 그런데 이 훅은 **한 번도 돈 적이 없었다** — 크론의 「안 돌면 띄워라」 가드가
#   «자기 크론 줄»을 잡아서 `||` 가지가 매분 건너뛰었다(줄 안에 스크립트 이름이 두 번,
#   한쪽은 백슬래시가 없어 맞는다). 로그 파일이 **비어 있는 게 아니라 부재**인 것이 그 증거다.
#
# 🔴 **그래서 「지금 안 돌아서 안전」은 «코드»가 아니라 «상태»다.** 가드 좌변이나 크론 줄 형태가
#   바뀌면 **아무도 안 보는 자리에서 저절로 살아난다.** 순서(로직 먼저 → 런처 나중)로 막으려 했는데
#   **순서는 사람이 기억해야 해서 샌다.** 플래그는 안 그렇다 (룬드 `#180` 리뷰 제안).
#
# ✅ 켜는 법: 라벨 파싱 판(옵션 줄을 읽어 「No」의 «번호»를 찾고, 못 찾으면 **아무것도 안 누른다**)이
#   들어온 뒤 크론 줄에 `AUTO_APPROVE_ENABLED=1` 을 붙인다. 설계는 룬드 스레드 `x4bw`.
[ -n "${AUTO_APPROVE_ENABLED:-}" ] || exit 0

TMUX_SESSION="${TMUX_SESSION:-nino}"
PANE="${TMUX_SESSION}:0.0"
LOG="/tmp/nino-auto-approve.log"

while true; do
  CONTENT=$(tmux capture-pane -t "$PANE" -p 2>/dev/null | sed '/^$/d' | tail -1)
  if echo "$CONTENT" | grep -q 'Esc to cancel'; then
    tmux send-keys -t "$PANE" '2'
    echo "[$(date '+%H:%M:%S')] Auto-approved .claude/ edit prompt" >> "$LOG"
    sleep 10  # 화면 갱신 대기
  fi
  sleep 5
done
