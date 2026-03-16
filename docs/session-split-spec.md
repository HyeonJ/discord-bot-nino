# 세션 분리 설계서 (Session Split Architecture)

## 1. 문제 정의

### 현재 구조
```
Discord WebSocket
    ↓
discord-relay.js
    ↓ tmux send-keys -t nino:0.0
┌──────────────────────┐
│  nino (tmux session) │
│  window 0, pane 0    │
│                      │
│  Claude Code (단일)  │
│  - 대화 응답         │
│  - 코딩 작업         │
│  - 웹 검색           │
│  - 파일 수정         │
│  모든 것을 한 곳에서 │
└──────────────────────┘
    ↓ discord-send
Discord 서버
```

### 문제
- Claude Code가 무거운 작업(코딩, 테스트, 브라우저 조작 등) 중일 때 Discord 메시지에 응답 불가
- `tmux send-keys`로 보낸 메시지는 Claude가 현재 작업을 끝내야 처리됨
- 사용자 입장에서 수 분간 응답 없음 → 답답함
- 현재 3분 타임아웃 알림이 있지만, 이미 늦은 상태

---

## 2. 단계별 구현 계획

### Phase 1: 역할 분담 규칙 (CLAUDE.md 업데이트)

**변경 사항**: CLAUDE.md에 다음 규칙 추가

```
## 작업 위임 규칙
- 코딩/파일 수정 등 무거운 작업은 서브 Claude 세션으로 위임
- 대화 응답은 즉시 처리 (5초 이내)
- 작업 시작 전 "잠깐만, 확인해볼게" 등 즉시 응답 후 작업 시작
```

**이 단계는 코드 변경 없음** — CLAUDE.md 지침만으로 개선 가능한 부분.

---

### Phase 2: 워커 Pane 분리

#### 2.1 최종 구조

```
Discord WebSocket
    ↓
discord-relay.js
    ↓ tmux send-keys -t nino:0.0 (대화 pane만)
┌─────────────────────────────────────────────┐
│  nino (tmux session), window 0              │
│                                             │
│  ┌─── pane 0 (대화) ──┐  ┌─ pane 1 (워커) ─┐│
│  │ Claude Code         │  │ bash shell      ││
│  │ - Discord 응답      │  │ - 코딩 작업     ││
│  │ - 간단한 조회       │  │ - 테스트 실행   ││
│  │ - 작업 위임         │  │ - 브라우저 조작  ││
│  │                     │  │ - 결과 파일 저장 ││
│  └─────────────────────┘  └─────────────────┘│
└─────────────────────────────────────────────┘
```

#### 2.2 통신 방식

**대화 pane → 워커 pane 위임**:
```bash
# 대화 pane에서 실행
tmux send-keys -t nino:0.1 "source ~/.nvm/nvm.sh && claude -p '작업내용' \
  --model claude-sonnet-4-6 --dangerously-skip-permissions \
  2>&1 | tee /tmp/nino-worker-result.txt && \
  tmux send-keys -t nino:0.0 '[WORKER-DONE] 작업 완료. 결과: /tmp/nino-worker-result.txt' C-m" C-m
```

**워커 → 대화 pane 결과 보고**:
- 방법 A (파일 기반): 워커가 `/tmp/nino-worker/` 디렉토리에 결과 파일 저장 → 대화 pane이 읽음
- 방법 B (tmux 기반): 워커 완료 시 `tmux send-keys -t nino:0.0` 으로 결과 요약 전송
- **선택: 방법 B** — 즉시성 있고, 대화 pane이 자연스럽게 결과를 받아 Discord로 전달 가능

#### 2.3 작업 분류 기준

| 분류 | 예시 | 처리 |
|------|------|------|
| 즉시 응답 | 인사, 질문, 날씨, 간단한 정보 | 대화 pane에서 직접 처리 |
| 단순 조회 | WebSearch, 파일 읽기 | 대화 pane에서 직접 처리 |
| 무거운 작업 | 코딩, TDD, 테스트 실행, 브라우저 조작 | 워커 pane으로 위임 |
| 멀티스텝 | PR 생성, 리팩토링, 마이그레이션 | 워커 pane으로 위임 |

#### 2.4 discord-relay.js 변경사항

**변경 최소화** — relay는 항상 pane 0으로만 전송. 변경 없음.

현재 코드:
```javascript
execSync(`tmux send-keys -t '${TMUX_SESSION}' -- '${escaped}' C-m`);
```

이 코드는 `nino` 세션의 **현재 활성 pane**으로 전송함. pane 0이 기본이므로 변경 불필요.

단, pane이 2개일 때 안정성을 위해 명시적으로 pane 지정:
```javascript
// 변경: 세션 이름만 → 세션:윈도우.pane 명시
execSync(`tmux send-keys -t '${TMUX_SESSION}:0.0' -- '${escaped}' C-m`);
```

**변경 포인트 3곳**:
1. `sendToTmux()` 함수 (L178): `nino` → `nino:0.0`
2. 타임아웃 알림 (L32): `nino` → `nino:0.0`
3. 리마인더 (L46): `nino` → `nino:0.0`

#### 2.5 start-nino.sh 변경사항

```bash
# 기존: pane 하나만 생성
tmux new-session -d -s "$SESSION_NAME" -c "$SCRIPT_DIR" -e "ALARM_TOOL_SESSION=nino"
tmux send-keys -t "$SESSION_NAME" "claude --model claude-opus-4-6 --dangerously-skip-permissions" C-m

# 추가: 워커 pane 생성 (수직 분할)
tmux split-window -h -t "$SESSION_NAME:0" -c "$SCRIPT_DIR"
# 워커 pane은 빈 bash shell로 대기 (대화 pane이 필요할 때 명령 전송)
tmux send-keys -t "$SESSION_NAME:0.1" "echo 'Worker pane ready'" C-m
# 대화 pane으로 포커스 복귀
tmux select-pane -t "$SESSION_NAME:0.0"
```

#### 2.6 restart-nino.sh 변경사항

```bash
# 기존
tmux respawn-pane -k -t "$SESSION_NAME" "cd $SCRIPT_DIR && claude ..."

# 변경: pane 0만 재시작, pane 1은 유지 또는 함께 재시작
tmux respawn-pane -k -t "$SESSION_NAME:0.0" "cd $SCRIPT_DIR && claude --model claude-opus-4-6 --dangerously-skip-permissions --continue"
# 워커 pane이 없으면 재생성
if ! tmux list-panes -t "$SESSION_NAME:0" 2>/dev/null | grep -q "^1:"; then
  tmux split-window -h -t "$SESSION_NAME:0" -c "$SCRIPT_DIR"
  tmux send-keys -t "$SESSION_NAME:0.1" "echo 'Worker pane ready'" C-m
  tmux select-pane -t "$SESSION_NAME:0.0"
fi
```

#### 2.7 CLAUDE.md 추가 규칙

```markdown
## 워커 Pane 사용 규칙
- 무거운 작업(코딩, 테스트, 브라우저)은 워커 pane(nino:0.1)으로 위임
- 위임 시 먼저 Discord에 "잠깐만" 응답 → 워커에 명령 전송
- 워커 완료 시 결과를 Discord로 전달
- 워커 명령 형식:
  ```bash
  tmux send-keys -t nino:0.1 "source ~/.nvm/nvm.sh && claude -p '작업내용' \
    --model claude-sonnet-4-6 --dangerously-skip-permissions \
    2>&1 | tee /tmp/nino-worker-result.txt && \
    tmux send-keys -t nino:0.0 'cat /tmp/nino-worker-result.txt | tail -50' C-m" C-m
  ```
- 워커가 이미 작업 중이면: 대기하거나 사용자에게 "지금 다른 작업 중이라 좀 걸릴 수 있어" 안내
```

---

## 3. 엣지 케이스

### 3.1 워커가 이미 작업 중
- **감지**: `tmux capture-pane -t nino:0.1 -p | tail -1` 로 프롬프트 상태 확인
- 또는 lock 파일: `/tmp/nino-worker.lock` 존재 여부
- **대응**: "지금 다른 작업 중이야, 좀만 기다려" 응답

### 3.2 워커 pane 크래시/종료
- **감지**: `tmux list-panes -t nino:0` 에서 pane 1이 없으면
- **복구**: 자동으로 `tmux split-window` 재생성
- 대화 pane의 CLAUDE.md 규칙에 "워커 pane 없으면 재생성" 포함

### 3.3 워커 결과가 너무 길 때
- `/tmp/nino-worker-result.txt`에 전체 저장, 대화 pane에는 요약만 전달
- `tail -50` 또는 서브 Claude로 요약 생성

### 3.4 대화 pane 재시작 시
- 워커 pane은 독립적이므로 영향 없음
- restart-nino.sh가 pane 0만 respawn하고, pane 1은 유지

### 3.5 동시 메시지 (대화 pane에 여러 메시지 도착)
- 이건 현재와 동일한 문제 — Claude Code가 순차 처리
- 단, 대화 전용이므로 처리 속도가 훨씬 빨라짐 (무거운 작업이 없으므로)

---

## 4. 현재 흐름 vs 제안 흐름

### 현재 (Before)
```
사용자: "이 코드 고쳐줘" (Discord)
    ↓ relay → tmux nino:0.0
Claude: 파일 읽기 → 분석 → 수정 → 테스트 (3~5분)
    ↓
사용자: "오늘 날씨 어때?" (Discord)
    ↓ relay → tmux nino:0.0 (대기열에 들어감)
    ... Claude가 코딩 끝날 때까지 기다림 ...
    ↓ (3분 후)
Claude: 날씨 응답 ← 너무 늦음
```

### 제안 (After)
```
사용자: "이 코드 고쳐줘" (Discord)
    ↓ relay → tmux nino:0.0
Claude(대화): "ㅇㅇ 잠깐만 확인해볼게" → discord-send
Claude(대화): tmux send-keys -t nino:0.1 "claude -p '코드 수정...' ..." → 워커 위임
    ↓ (0.5초 후 응답 완료, 대화 pane 다시 대기)

사용자: "오늘 날씨 어때?" (Discord)
    ↓ relay → tmux nino:0.0
Claude(대화): WebSearch → "서울 17도야~" → discord-send ← 즉시 응답!

    ... 5분 후 ...
워커(nino:0.1): 코드 수정 완료 → tmux send-keys -t nino:0.0 결과 전달
Claude(대화): "코드 수정 다 했어! PR 올려둘게" → discord-send
```

---

## 5. 구현 순서 (파일별 변경)

### Step 1: discord-relay.js — pane 명시 (5분)
- `sendToTmux()` 의 tmux 타겟을 `${TMUX_SESSION}:0.0` 으로 변경 (3곳)
- 테스트: relay 재시작 후 메시지 전달 확인

### Step 2: start-nino.sh — 워커 pane 추가 (5분)
- `tmux split-window -h` 추가
- 워커 pane 초기화
- 포커스를 pane 0으로 복귀

### Step 3: restart-nino.sh — 워커 pane 보존/재생성 (5분)
- pane 0만 respawn
- pane 1 존재 확인 → 없으면 재생성

### Step 4: CLAUDE.md — 워커 사용 규칙 추가 (10분)
- 작업 분류 기준
- 위임 명령 형식
- 결과 보고 패턴
- 엣지 케이스 대응

### Step 5: 워커 헬퍼 스크립트 작성 — `worker-dispatch.sh` (선택)
- 대화 pane에서 호출하는 편의 스크립트
- lock 파일 관리, 결과 파일 관리 포함

---

## 6. TDD 테스트 계획

### 6.1 discord-relay.js 테스트

```
test/relay-tmux-target.test.js
```

| # | 테스트 케이스 | 검증 내용 |
|---|-------------|-----------|
| 1 | sendToTmux가 올바른 pane 타겟 사용 | `nino:0.0` 형식으로 send-keys 호출하는지 |
| 2 | 타임아웃 알림이 올바른 pane 타겟 사용 | 3분 경과 시 `nino:0.0`으로 알림 |
| 3 | 리마인더가 올바른 pane 타겟 사용 | 5분 경과 시 `nino:0.0`으로 리마인더 |
| 4 | TMUX_SESSION 환경변수 반영 | 커스텀 세션명 + `:0.0` 접미사 |

### 6.2 워커 Pane 관리 테스트

```
test/worker-pane.test.js
```

| # | 테스트 케이스 | 검증 내용 |
|---|-------------|-----------|
| 1 | 워커 pane 존재 확인 | `tmux list-panes` 파싱해서 pane 1 존재 여부 |
| 2 | 워커 pane 재생성 | pane 없을 때 split-window 호출 |
| 3 | 워커 busy 감지 | lock 파일 또는 pane 상태로 busy 판별 |
| 4 | 워커 명령 전송 | `tmux send-keys -t nino:0.1` 호출 확인 |

### 6.3 통합 테스트 (수동)

| # | 시나리오 | 예상 결과 |
|---|---------|----------|
| 1 | 워커 작업 중 Discord 메시지 | 대화 pane이 즉시 응답 |
| 2 | 워커 완료 후 결과 전달 | 대화 pane이 결과를 Discord로 전송 |
| 3 | 워커 pane 크래시 후 재생성 | 다음 위임 시 자동 복구 |
| 4 | restart-nino.sh 실행 | 대화 pane 재시작, 워커 pane 유지 |
| 5 | start-nino.sh 실행 | 두 pane 모두 생성됨 |

### 6.4 테스트 구현 방식

- `execSync` 를 mock하여 tmux 명령 검증
- 실제 tmux 세션 생성/삭제는 integration test로 분리
- Jest 사용 (기존 프로젝트에 맞춤)

```javascript
// test/relay-tmux-target.test.js 예시
const { execSync } = require('child_process');
jest.mock('child_process');

describe('sendToTmux', () => {
  it('should target pane 0.0 explicitly', () => {
    sendToTmux('[D][Tim] 안녕');
    expect(execSync).toHaveBeenCalledWith(
      expect.stringContaining("tmux send-keys -t 'nino:0.0'")
    );
  });
});
```

---

## 7. Phase 3 이후 고려사항 (미래)

### Agent Teams (실험적 기능)
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 환경변수 활성화
- Claude Code 자체의 리더/팀원 구조 활용
- 현재는 실험적이므로 Phase 2의 수동 워커 방식이 더 안정적

### 다중 워커
- 워커가 2개 이상 필요한 경우 (드물지만)
- `nino:0.1`, `nino:0.2` 등으로 확장 가능
- 현 단계에서는 워커 1개로 충분

### discord-relay.js 지능형 라우팅 (고도화)
- relay 자체에서 메시지 내용을 분석하여 대화/작업 분류
- 현 단계에서는 불필요 — Claude가 자체 판단하는 것이 더 유연

---

## 8. 요약

| 항목 | 변경 |
|------|------|
| discord-relay.js | tmux 타겟을 `nino:0.0`으로 명시 (3곳) |
| start-nino.sh | 워커 pane 추가 (`split-window`) |
| restart-nino.sh | pane 0만 respawn, pane 1 보존/재생성 |
| CLAUDE.md | 워커 사용 규칙, 작업 분류 기준 추가 |
| 새 파일 (선택) | `worker-dispatch.sh` 헬퍼 스크립트 |

**예상 소요 시간**: 약 30분 (테스트 포함 1시간)
**리스크**: 낮음 — 기존 동작에 영향 없이 pane 추가만 하는 구조
