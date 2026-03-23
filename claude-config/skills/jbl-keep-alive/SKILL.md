---
name: jbl-keep-alive
description: JBL Go 4 스피커 자동 꺼짐 방지 — 노래 끄면 무음 재생으로 스피커 유지
---

Darren이 노래를 끄면 JBL Go 4가 자동 꺼지지 않도록 무음 재생을 시작하는 스킬.

## 동작

1. 노래 끄기 요청 → YouTube Music 일시정지/정지
2. 무음 재생 시작 → `jbl-keep-alive.sh start`
3. 다시 노래 재생 요청 → 무음 재생 중지 + 음악 재생

## 구현

```bash
# 무음 재생 시작 (JBL 자동 꺼짐 방지)
bash /home/bpx27/discord-bot-nino/jbl-keep-alive.sh start

# 무음 재생 중지
bash /home/bpx27/discord-bot-nino/jbl-keep-alive.sh stop
```

## 규칙
- Darren이 "노래 꺼줘", "음악 멈춰" 등 요청 시: YTM 정지 → jbl-keep-alive start
- Darren이 다시 "노래 틀어줘" 요청 시: jbl-keep-alive stop → YTM 재생
- JBL 출력 전환할 때도 keep-alive 상태 유지
