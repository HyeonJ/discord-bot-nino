# 니노 봇 복구 가이드 (Disaster Recovery)

## 복구 시나리오

### 시나리오 1: 새 OS에 설치 (bootstrap)
```bash
git clone https://github.com/HyeonJ/discord-bot-nino.git
cd discord-bot-nino
./scripts/setup.sh --mode bootstrap
```

### 시나리오 2: 백업에서 빠른 복구 (fast-restore)
```bash
cd ~/discord-bot-nino
git pull
./scripts/setup.sh --mode fast-restore
```

## 복구 체크리스트

### 1. 사전 준비
- [ ] NAS (D:\) 접근 가능 확인
- [ ] GitHub 인증 (`gh auth login`)
- [ ] Anthropic API 인증 정보

### 2. setup.sh 실행 후 수동 작업
- [ ] `.env` 값 채우기 (DISCORD_BOT_TOKEN, PICOVOICE_ACCESS_KEY 등)
- [ ] Claude CLI 인증: `claude auth login`
- [ ] Tailscale 인증: `tailscale up`

### 3. 봇 시작
```bash
bash ~/discord-bot-nino/scripts/start-nino.sh
```

### 4. 검증
- [ ] Discord에 "재부팅했어!" 메시지 확인
- [ ] `/health` 엔드포인트 응답 확인 (`curl localhost:58090/health`)
- [ ] 디스코드에서 메시지 수신/응답 확인
- [ ] cron 동작 확인 (`crontab -l`)

## 백업 구조

```
GitHub 레포 (public)
├── src/           ← 코어 봇 코드 (relay, send, health)
├── scripts/       ← 운영 스크립트 (start, watchdog, backup)
├── config/        ← 설정 파일 (bots.json, channel-map)
├── tools/         ← 유틸리티 (calendar, podcast, onedrive)
├── media/         ← 미디어 제어 (TV, YouTube Music, ATV)
├── of/            ← OF 다운로드 도구
├── claude-config/
│   ├── skills/     ← ~/.claude/skills/ 미러
│   ├── hooks/      ← ~/.claude/hooks/ 미러
│   └── user-settings.json
├── .claude/settings.json (프로젝트 설정)
├── .env.example
└── RECOVERY.md

NAS (/mnt/d/Darren/backup/nino/)
├── memory/              ← 매시간 rsync
└── yaksu-history/       ← 매일 새벽 3시 스냅샷 (14일 보관)
```

## 수동 복원 (setup.sh 없이)

### Memory 복원
```bash
mkdir -p ~/.claude/projects/-home-$(whoami)-discord-bot-nino/memory
cp -r /mnt/d/Darren/backup/nino/memory/* \
  ~/.claude/projects/-home-$(whoami)-discord-bot-nino/memory/
```

### Skills/Hooks 복원
```bash
cp -r ~/discord-bot-nino/claude-config/skills/* ~/.claude/skills/
cp ~/discord-bot-nino/claude-config/hooks/* ~/.claude/hooks/
chmod +x ~/.claude/hooks/*
```

### yaksu-history 복원
```bash
mkdir -p ~/.local/share/yaksu-history
LATEST=$(ls -t /mnt/d/Darren/backup/nino/yaksu-history/messages-*.db | head -1)
cp "$LATEST" ~/.local/share/yaksu-history/messages.db
```

## 환경변수 (.env 필수 값)

| 변수 | 설명 |
|------|------|
| DISCORD_BOT_TOKEN | Discord 봇 토큰 |
| DISCORD_CHANNEL_ID | 기본 채널 ID |
| TMUX_SESSION | tmux 세션 이름 |
| PICOVOICE_ACCESS_KEY | Wake word 감지 키 |
| HEALTH_PORT | 헬스체크 포트 |
| HEALTH_TARGETS | 다른 봇 헬스체크 URL |

## 도구 버전 (참고)

| 도구 | 버전 |
|------|------|
| Node.js | v24.14.0 |
| Python | 3.12.3 |
| uv | 0.10.9 |
| tmux | 3.4 |
| Claude Code | 2.1.76+ |
| rsync | 3.2.7 |

## 주의사항
- **memory/는 레포에 올리지 않음** — 개인정보 포함
- **.env는 레포에 올리지 않음** — 비밀키 포함
- setup.sh는 기존 파일을 덮어쓰지 않음 (안전)
- NAS가 접근 불가하면 memory/yaksu-history 복원은 건너뜀
