---
name: alarm
description: 알람/리마인더 설정, 조회, 취소 — alarm-tool CLI + TTS 지원
---

알람과 리마인더를 설정하고 관리하는 스킬.

## 사용법

### 알람 설정
```bash
# 특정 시각
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "HH:MM"
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "YYYY-MM-DD HH:MM"

# 상대 시간
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "+30m"
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "+2h"

# 반복
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "09:00" --repeat daily
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "09:00" --repeat weekdays
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "09:00" --repeat 30m --until "2026-03-20 10:00"
```

### 조회/취소
```bash
/home/bpx27/discord-bot-nino/alarm-tool list
/home/bpx27/discord-bot-nino/alarm-tool cancel --id 아이디
```

## 시간 형식
- `HH:MM` — 오늘 해당 시각 (지났으면 내일)
- `+30m`, `+2h`, `+1h30m` — 상대 시간
- `YYYY-MM-DD HH:MM` — 절대 시간
- 모든 시간은 KST 기준

## 반복 옵션
- `daily` — 매일
- `weekly` — 매주
- `weekdays` — 평일만
- `30m`, `2h` 등 — 시간 간격

## TTS 연동
알람에 TTS가 필요한 경우 (예: 사람 깨우기), Discord 메시지와 함께 TTS도 실행:
```bash
# Discord 메시지 전송
/home/bpx27/discord-bot-nino/discord-send -c 채널명 "알람 메시지"

# TTS (Windows 집컴 스피커로 출력)
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('알람 메시지')"
```

## 사람 깨우기 패턴
Tim/Darren을 깨울 때는 Discord 멘션 + TTS + 반복 알람 조합:
1. `alarm-tool set` 으로 반복 알람 등록 (예: 5분 간격)
2. 알람 발동 시 Discord 채널에 멘션 메시지 전송
3. TTS로 스피커에 음성 출력
4. 응답 올 때까지 반복

$ARGUMENTS가 있으면 알람 메시지로 사용할 것.
