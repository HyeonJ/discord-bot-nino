# Architecture

## Overview

Discord 비서 봇. WSL2에서 Claude Code 기반으로 실행.
`discord-relay.js`가 Discord WebSocket 이벤트를 수신 → 텍스트로 포맷 → tmux 세션에 전달.
Claude가 `discord-send` CLI로 응답.

## Module Contracts

### src/discord-relay.js

Discord gateway → tmux 텍스트 릴레이.

**Input**: Discord.js `messageCreate` 이벤트 (길드, DM, 스레드, 봇 메시지)
**Output**: 포맷된 텍스트 → `tmux send-keys`

#### Message Format Protocol

```
Guild:  [D][Name][C:channelID][T:threadID][M:msgID][R:replyID] content [IMG:path]
DM:     [DM][Name][C:dmChannelID][M:msgID] content
System: [D][system] content
```

| Tag | 의미 | 조건 |
|-----|------|------|
| `[D]` | Discord 서버 메시지 | 항상 |
| `[DM]` | DM 메시지 | DM일 때 |
| `[C:id]` | 채널 ID | DEFAULT_CHANNEL이 아닐 때 (길드), 항상 (DM) |
| `[T:id]` | 스레드 ID | 스레드일 때 |
| `[M:id]` | 메시지 ID | 항상 |
| `[R:id]` | 답장 참조 ID | 답장일 때 |
| `[IMG:path]` | 이미지 첨부 | 이미지 첨부 시 |
| `[FILE:path]` | 파일 첨부 | 비이미지 첨부 시 |
| `[ATT:name]` | 첨부 (미다운로드) | 봇 메시지 첨부 시 |

#### Invariants

- 자신의 메시지: 히스토리 저장만, tmux 전달 안 함
- 다른 봇 메시지: tmux 전달하되 pending 등록 안 함
- DM: 항상 `[C:dmChannelID]` 태그 포함
- 첨부파일: `/tmp/discord-attachments/`에 다운로드
- 1500자 초과: 잘린 후 `/tmp/nino-msgs/`에 전체 저장, `[LONG_MSG:path]` 태그
- 300자 초과 URL: 앞 200자만 인라인, 전체는 파일 저장
- 응답 타임아웃: 3분 → tmux 시스템 알림
- Pending 추적: 다른 사용자를 멘션하는 메시지는 제외

#### Constants (하드코딩)

- `GUILD_ID`: 1479813608023134342
- `DEFAULT_CHANNEL`: 1479813609499394169
- `ALERT_CHANNEL`: 1480593132511826092
- `USER_MAP`: Tim(265...), Darren(353...)

---

### src/discord-send (Bash)

Discord 메시지 전송 CLI.

**Flags**:
| Flag | 용도 |
|------|------|
| `-c channel` | 채널 ID 또는 이름 (channel-map.json으로 해석) |
| `-f file` | 파일 첨부 |
| `-r msgID` | 답장 |
| `-t name` | 새 스레드 생성 |

**CRITICAL**: 모든 positional arg는 MESSAGE를 덮어씀. 채널 지정은 반드시 `-c` 플래그 사용.

```bash
# 올바른 사용법
discord-send -c DM-Darren "메시지"
discord-send -c 1480593132511826092 "메시지"

# 잘못된 사용법 (MESSAGE로 파싱됨)
discord-send DM-Darren "메시지"  # → "메시지"가 일반 채널로 감
```

**채널 해석**: `-c` 값이 숫자가 아니면 `config/channel-map.json`에서 ID 조회.

---

### src/health.js

HTTP 헬스 엔드포인트.

- **Endpoint**: `GET /health` (포트: HEALTH_PORT, 기본 58090)
- **Response**: `{ bot, timestamp(KST), claude_pid, tmux_alive, relay_alive, watcher_alive, last_message_at, uptime }`

---

### src/health-checker.js

다른 봇 헬스 모니터링 + DM 알림.

- **Input**: `HEALTH_TARGETS` 환경변수 (쉼표 구분 `name:url`)
- **Check**: 60초 간격, 봇당 5분 쿨다운
- **Alert 라우팅**: rund→DM-Tim, nino/haru→DM-Darren
- **감지 항목**: relay 다운, stale timestamp(>90초), tmux 죽음, watcher 미실행, Claude PID 없음

---

### src/auto-pull.js

GitHub 봇 push 알림 → 자동 git pull.

- **Trigger**: GitHub 봇(ID: 1480975077829902377) embed에서 `[repo:main]` 패턴 감지
- **대상 레포**: discord-bot-nino, yaksu-shared-data
- **Safety**: uncommitted changes 있으면 스킵, `--ff-only` 사용

---

## Config Files

| 파일 | 용도 |
|------|------|
| `config/channel-map.json` | 채널 이름 → Discord 채널 ID |
| `config/mention-map.json` | @이름 → Discord 멘션 포맷 |
| `config/bots.json` | 봇 설정 |

## Directory Structure

```
src/        — 코어 (relay, send, health, auto-pull)
scripts/    — 운영 (start, restart, watchdog, backup, cron)
config/     — 런타임 설정
tools/      — 외부 도구 연동
media/      — 미디어 제어 (TV, 음악, 스피커)
tests/      — Jest (JS) + pytest (Python)
logs/       — 런타임 로그
memory/     — 세션 상태, 히스토리
```

## Error Handling

| 모듈 | 처리 방식 |
|------|-----------|
| relay | uncaughtException/unhandledRejection → 로그만 (알림 없음) |
| discord-send | curl 에러 → stdout 출력 (재시도 없음) |
| health-checker | fetch 에러 → 무시 (다음 주기에 재시도) |
| auto-pull | git 에러 → 콘솔 로그 |

## Known Limitations

1. relay에 GUILD_ID, DEFAULT_CHANNEL, USER_MAP 하드코딩 → config로 이동 필요
2. discord-send positional arg 파싱: 모든 비플래그 인자가 MESSAGE 덮어씀
3. relay와 send에 자동 테스트 없음 (가장 중요한 두 모듈)
4. CI 파이프라인 없음
