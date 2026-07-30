---
name: send-to-haru
description: 하루(HP 노트북 봇)에게 SCP로 파일 전송
---

하루에게 파일을 SCP로 직접 전송한다.

## 사용법

```bash
scp -P 2223 <파일경로> bpx27@100.86.89.63:/tmp/
```

## 전송 후
- 하루에게 Discord로 파일 도착 알림: `discord-send 봇-놀이터 "하루야 /tmp/<파일명> 보냈어!"`
- 하루가 `/tmp/` 에서 파일을 읽어서 처리

## 예시

```bash
# 파일 전송
scp -P 2223 /tmp/global-claude-md.txt bpx27@100.86.89.63:/tmp/

# 알림
discord-send 봇-놀이터 "하루야 /tmp/global-claude-md.txt 보냈어 확인해!"
```

## 참고
- 하루 SSH: `bpx27@100.86.89.63` (포트 2223)
- Discord 파일 첨부는 하루가 못 읽으므로 SCP 사용
