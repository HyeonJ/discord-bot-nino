---
name: wake-klaude
description: Klaude(Tim의 봇)가 죽었을 때 깨우기 - Tim에게 알림 + 봇-놀이터 채널에 핑
---

Klaude(Tim의 봇)가 응답이 없거나 죽었을 때 깨우는 스킬.

## 실행 순서

1. SSH로 Mac Studio에 접속하여 restart-klaude.sh 실행
2. 봇-놀이터 채널에 결과 보고
3. SSH 실패 시 Tim에게 멘션 알림

## 구현

```bash
# 1. SSH로 직접 재시작
ssh -o ConnectTimeout=5 klaude@192.168.68.67 "bash ~/Assistant/restart-klaude.sh"

# 2. 성공 시 봇-놀이터에 보고
/home/bpx27/discord-bot-nino/discord-send -c 1480479067881865347 "Klaude 재시작했어!"

# 3. SSH 실패 시 Tim에게 알림
/home/bpx27/discord-bot-nino/discord-send -c 1480479067881865347 "<@265454241387249665> Klaude SSH 접속이 안 돼! Mac 확인 부탁해~"
```

## SSH 정보
- 호스트: klaude@192.168.68.67 (Mac Studio)
- 재시작 스크립트: ~/Assistant/restart-klaude.sh
- 니노 공개키 등록 완료 (2026-03-14)

$ARGUMENTS가 있으면 추가 메시지로 포함할 것.
