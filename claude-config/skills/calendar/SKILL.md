---
name: calendar
description: 카카오 캘린더 + Apple iCloud 캘린더에 일정 추가/조회/삭제
---

Darren의 카카오 캘린더와 Apple iCloud 캘린더에 일정을 추가하는 스킬.

## 카카오 캘린더

### 일정 추가
```bash
python3 /home/bpx27/discord-bot-nino/calendar-tool.py kakao add \
  --title "일정 제목" \
  --start "2026-03-25 14:00" \
  --end "2026-03-25 15:00" \
  --location "장소(선택)" \
  --description "설명(선택)"
```

### 일정 조회
```bash
python3 /home/bpx27/discord-bot-nino/calendar-tool.py kakao list \
  --from "2026-03-25" --to "2026-03-26"
```

### 설정 파일
- config: `~/.kakao-calendar-config.json` (REST API Key, Client Secret)
- token: `~/.kakao-calendar-token.json` (OAuth 토큰, 자동 갱신)
- 토큰 만료 시: `python3 kakao-calendar-setup.py --auth`

## Apple iCloud 캘린더

### 일정 추가
```bash
python3 /home/bpx27/discord-bot-nino/calendar-tool.py apple add \
  --title "일정 제목" \
  --start "2026-03-25 14:00" \
  --end "2026-03-25 15:00" \
  --calendar "개인" \
  --location "장소(선택)"
```

### 일정 조회
```bash
python3 /home/bpx27/discord-bot-nino/calendar-tool.py apple list \
  --from "2026-03-25" --to "2026-03-26"
```

### 설정 파일
- config: `~/.apple-calendar-config.json` (Apple ID, 앱 비밀번호)
- 앱 비밀번호 생성: https://account.apple.com → 로그인 및 보안 → 앱 비밀번호

## 두 캘린더 동시 등록
```bash
python3 /home/bpx27/discord-bot-nino/calendar-tool.py both add \
  --title "일정 제목" \
  --start "2026-03-25 14:00" \
  --end "2026-03-25 15:00"
```
