#!/bin/bash
# 재실 감지 스크립트 — Tim/Darren iPhone ping + ARP로 상태 변화 감지
# ping 성공 OR ARP에 MAC 있음 → 연결 중 / ping 실패 AND ARP에도 없음 → 진짜 나감
# 연속 10회 실패 시 '사라짐' 판정

# .env 로드
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$BOT_DIR/.env" ]; then
  set -a; source "$BOT_DIR/.env"; set +a
fi

STATE_DIR="${NINO_STATE_DIR:?NINO_STATE_DIR 환경변수가 설정되지 않았습니다}"
LOG_FILE="${NINO_LOG_DIR:?NINO_LOG_DIR 환경변수가 설정되지 않았습니다}/presence.log"
TMUX_SESSION="${TMUX_SESSION:?TMUX_SESSION 환경변수가 설정되지 않았습니다}"

TIM_IP="192.168.68.68"
TIM_MAC="ea:f2:7a:f7:ad:88"
DARREN_IP="192.168.68.71"
DARREN_MAC="be:dc:21:d3:a3:51"

mkdir -p "$STATE_DIR"

log_event() {
  local msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE"
}

relay_to_nino() {
  local msg="$1"
  local escaped="${msg//\'/\'\\\'\'}"
  tmux send-keys -t "$TMUX_SESSION" -- "$escaped" C-m 2>/dev/null
}

check_arp() {
  local mac="$1"
  arp -an 2>/dev/null | grep -i "$mac" > /dev/null 2>&1
}

check_person() {
  local name="$1"
  local ip="$2"
  local mac="$3"
  local state_file="$STATE_DIR/${name}.state"

  # 파일 없으면 초기화
  if [ ! -f "$state_file" ]; then
    echo "status=unknown" > "$state_file"
    echo "fail_count=0" >> "$state_file"
  fi

  source "$state_file"
  status="${status:-unknown}"
  fail_count="${fail_count:-0}"

  if ping -c 1 -W 2 "$ip" > /dev/null 2>&1 || check_arp "$mac"; then
    # 핑 성공 또는 ARP에 MAC 있음
    if [ "$status" != "online" ]; then
      echo "status=online" > "$state_file"
      echo "fail_count=0" >> "$state_file"
      log_event "${name} 와이파이 연결"
      relay_to_nino "[${name}아이폰 와이파이 연결]"
    else
      echo "status=online" > "$state_file"
      echo "fail_count=0" >> "$state_file"
    fi
  else
    # 핑 실패 + ARP에도 없음
    fail_count=$((fail_count + 1))
    if [ "$fail_count" -ge 10 ] && [ "$status" != "offline" ]; then
      echo "status=offline" > "$state_file"
      echo "fail_count=$fail_count" >> "$state_file"
      log_event "${name} 와이파이에서 사라짐"
      relay_to_nino "[${name}아이폰 와이파이에서 사라짐]"
    else
      echo "status=$status" > "$state_file"
      echo "fail_count=$fail_count" >> "$state_file"
    fi
  fi
}

check_person "Tim" "$TIM_IP" "$TIM_MAC"
check_person "Darren" "$DARREN_IP" "$DARREN_MAC"
