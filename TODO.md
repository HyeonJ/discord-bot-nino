# Darren TODO List

니노 봇 운영을 위해 Darren이 해야 할 작업들.

## 해야 할 것

### 1. upgrade/wsl-relay → main 브랜치 머지
- `upgrade/wsl-relay` 브랜치에 새 구조(WSL + Claude Code + discord-relay.js)가 올라가 있음
- 확인 후 main으로 머지 필요
- ```bash
  git checkout main
  git merge upgrade/wsl-relay
  git push origin main
  ```

### 2. 로그 경로 정리 (선택)
- 현재 relay 로그가 `/tmp/nino-relay.log`에 저장됨
- WSL 재부팅 시 /tmp가 초기화될 수 있음
- 프로젝트 폴더(`~/discord-bot-nino/logs/`)로 변경 권장

## 완료

- [x] GitHub collaborator로 Tim 추가
- [x] WSL에 Node.js(nvm), Claude Code 설치
- [x] .env 파일 생성 (DISCORD_BOT_TOKEN, DISCORD_CHANNEL_ID)
- [x] start-nino.sh로 니노 시작
- [x] tmux 세션에서 Claude Code 로그인
- [x] relay 정상 동작 확인
- [x] 기존 니노(bot.py) 종료
- [x] Windows 자동 실행 등록 (작업 스케줄러)
- [x] Chrome CDP + agent-browser 연결
- [x] 방화벽 규칙 추가 (CDP 포트)
- [x] ChromeCDP 프로필로 네이버 로그인
