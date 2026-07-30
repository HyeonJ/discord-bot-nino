---
name: discord-send
description: Discord 메시지 전송 CLI 사용법 — 채널/스레드/DM/reply/파일 전송
---

Discord 메시지 전송 CLI. target은 첫 번째 positional 인자로 자동 판별.

## 기본 사용법

```bash
discord-send <target> "메시지"
```

## Target 종류 (자동 판별)

| 형태 | 설명 | 예시 |
|------|------|------|
| 채널명 | channel-map.json 조회 | `discord-send 충재-다용도 "안녕"` |
| 채널ID | 숫자 ID 직접 지정 | `discord-send 1479813609499394169 "안녕"` |
| 스레드해시 | 4자리 base36 → DB thread 조회 | `discord-send e04z "스레드에 답장"` |
| 메시지해시 | 4자리 base36 → DB message 조회 → reply | `discord-send w3f5 "이 메시지에 reply"` |
| DM | DM-이름 형태 | `discord-send DM-Tim "DM 전송"` |

## 옵션

| 옵션 | 설명 | 예시 |
|------|------|------|
| `-f, --file <경로>` | 파일 첨부 | `discord-send -f /tmp/img.png 일반 "이미지"` |
| `--thread <스레드명>` | 새 스레드 생성 | `discord-send --thread "새 스레드" 일반 "첫 메시지"` |
| `--target <target>` | target을 옵션으로 지정 | `discord-send --target 일반 "메시지"` |

## 자동 기능

- **mention-map 변환**: `@Tim` → `<@265454241387249665>` 자동 변환
- **\n 줄바꿈**: `\n` → 실제 줄바꿈 자동 변환
- **해시 자동 판별**: 4자리 영숫자면 yaksu-history DB에서 스레드/메시지 자동 조회

## 주요 채널명

- `일반`: 기본 채널
- `봇-놀이터`: 봇 전용
- `현인-업무`: Darren 업무
- `현인-다용도`: Darren 개인
- `충재-다용도`: Tim 개인
- `DM-Tim`, `DM-Darren`: DM 전송

## 실행 경로

```
/home/bpx27/discord-bot-nino/src/discord-send
```
