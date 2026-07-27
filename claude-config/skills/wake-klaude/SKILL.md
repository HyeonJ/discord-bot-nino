---
name: wake-klaude
description: 룬드(Tim의 봇, 구 Klaude)가 죽었을 때 깨우기 - SSH 재시작 + 봇-놀이터/현재 채널 보고, 실패 시 Tim 멘션
---

룬드(Tim의 봇, 구 Klaude)가 응답이 없거나 죽었을 때 깨우는 스킬.

## ⚠️ 핵심 주의사항 (2026-06-22 업데이트)
- **tmux 세션 이름은 `rund`** (구 `klaude` 아님 — 룬드 개명됨)
- **비대화형 SSH는 PATH에 tmux/claude가 없음** → 항상 PATH 먼저 export
  - claude 위치: **`/Users/klaude/.local/bin/claude`** (zsh 로그인 셸에만 등록됨)
  - tmux/node: `/opt/homebrew/bin`
  - ⚠️ `start-rund.sh`/`restart-rund.sh`의 tmux 명령은 `~/.local/bin`을 PATH에 안 넣어서 claude가 즉시 종료→세션이 바로 죽음. 수동으로 띄울 땐 아래 PATH를 꼭 포함.
- **호스트 키가 known_hosts에 없으면** `Host key verification failed` → `ssh-keyscan` 으로 등록
- **두 가지 상황 구분**:
  - 세션은 살아있는데 멈춤 → `restart-rund.sh` (respawn-pane)
  - tmux 세션/서버 자체가 내려감(`no server running`) → 아래 수동 new-session
- **`Please run /login` / 401 뜨면** → OAuth 인증 풀림. 니노가 대신 못 함. Tim/Darren이 Mac에서 `tmux attach -t rund` → `/login` → 브라우저 인증 필요.

## 수동으로 세션 띄우기 (스크립트가 죽을 때 — 검증된 방법)
```bash
ssh -o ConnectTimeout=10 -o BatchMode=yes klaude@192.168.68.67 \
'export PATH="/Users/klaude/.local/bin:/Users/klaude/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; \
tmux new-session -d -s rund -c ~/Assistant \
"cd ~/Assistant && export PATH=/Users/klaude/.local/bin:/opt/homebrew/bin:\$PATH; source .env 2>/dev/null; source ~/.secrets 2>/dev/null; claude --dangerously-skip-permissions --effort max --continue || claude --dangerously-skip-permissions --effort max"; \
sleep 8; tmux capture-pane -t rund:0.0 -p | tail -20'
# capture-pane 결과에 "Not logged in"/"Run /login" 보이면 → Tim/Darren에게 /login 요청
```

## 실행 순서

1. 먼저 상태 확인 (tmux 세션 + relay 살아있는지)
2. 상황에 맞는 스크립트 실행 (멈춤 → restart, 완전 다운 → start)
3. 봇-놀이터(또는 요청 온 채널)에 결과 보고
4. SSH 실패 시 Tim에게 멘션 알림

## 구현

```bash
SSH="ssh -o ConnectTimeout=10 -o BatchMode=yes klaude@192.168.68.67"
PATHEXP='export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH";'

# 0. 호스트 키 없으면 등록 (Host key verification failed 날 때)
ssh-keygen -F 192.168.68.67 >/dev/null 2>&1 || \
  ssh-keyscan -T 5 -t ed25519,ecdsa,rsa 192.168.68.67 >> ~/.ssh/known_hosts 2>/dev/null

# 1. 상태 확인
$SSH "$PATHEXP tmux ls 2>&1; pgrep -fl discord-relay.js"

# 2-A. 세션 살아있고 멈춤만 → restart
$SSH "$PATHEXP bash ~/Assistant/restart-rund.sh"

# 2-B. 'no server running' 이면 → 처음부터 시작 (relay는 LaunchAgent로 관리됨)
$SSH "$PATHEXP bash ~/Assistant/start-rund.sh"

# 3. 성공 시 보고 (요청 온 채널 ID로, 없으면 봇-놀이터)
~/discord-bot-nino/src/discord-send 1480479067881865347 "룬드 재시작했어!"

# 4. SSH 실패 시 Tim 멘션
~/discord-bot-nino/src/discord-send 1480479067881865347 "<@265454241387249665> 룬드 SSH 접속이 안 돼! Mac 확인 부탁해~"
```

## SSH 정보
- 호스트: klaude@192.168.68.67 (Mac Studio)
- 시작 스크립트: ~/Assistant/start-rund.sh (전체 부팅), ~/Assistant/restart-rund.sh (멈춤 재시작)
- 니노 공개키 등록 완료 (2026-03-14)

$ARGUMENTS가 있으면 추가 메시지로 포함할 것.
