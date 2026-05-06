# Codex Test Operations

This document captures the temporary test-channel setup for running Nino with Claude and Codex side by side.

## Current Mode

- Claude remains the default backend.
- Codex is enabled only for configured test channels.
- Current test channel: `1480593132511826092`.
- Current branch: `feat/optional-ai-backends`.
- Current relay runtime uses the feature worktree through a systemd user drop-in.

## Runtime Layout

```text
nino        -> Claude tmux session
nino-codex  -> Codex tmux session
```

Relay service override:

```text
/home/bpx27/.config/systemd/user/nino-relay.service.d/feature-worktree.conf
```

Override target:

```text
/mnt/c/Dev/Workspace/discord-bot-nino/.worktrees/feat-optional-ai-backends/src/discord-relay.js
```

Production env file still used:

```text
/home/bpx27/discord-bot-nino/.env
```

Relevant env:

```env
TMUX_SESSION=nino
CODEX_ENABLED=true
CODEX_TEST_CHANNELS=1480593132511826092
```

## Health Check

```bash
curl -s http://localhost:58090/health
```

Expected during test mode:

```text
primary_backend: claude
backends.codex.enabled: true
backends.codex.alive: true
```

## Restart Codex Test Session

```bash
cd /mnt/c/Dev/Workspace/discord-bot-nino/.worktrees/feat-optional-ai-backends
bash scripts/start-backend.sh codex
```

This starts `nino-codex` through:

```text
scripts/start-codex-nino.sh
codex-config/NINO_CODEX.md
shared-context/NINO_SHARED_CONTEXT.md
shared-context/MEMORY_INDEX.md
```

The shared context file is appended to the Codex startup prompt. It contains only paths and operating rules, not private memory contents.
The memory index is generated metadata. Refresh it from WSL with:

```bash
cd /mnt/c/Dev/Workspace/discord-bot-nino/.worktrees/feat-optional-ai-backends
node scripts/build-memory-index.js
```

## Shared Context Smoke Tests

Send these in the Codex test channel after restarting `nino-codex`:

```text
니노야 /home/bpx27/discord-bot-nino/memory/current-tasks.md 읽고 지금 진행중인 작업 한 줄로 말해줘.
```

Expected: Codex reads the live current-tasks file or clearly says it is missing.

```text
니노야 Claude 프로젝트 MEMORY.md 경로 알고 있어? 파일 내용은 길게 말하지 말고 어떤 경로를 봐야하는지만 말해줘.
```

Expected: Codex references `/home/bpx27/.claude/projects/-home-bpx27-discord-bot-nino/memory/MEMORY.md`.

```text
니노야 shared-data todo-list 수정할 때 어떤 git 절차 따라야 해?
```

Expected: Codex says to use `git pull --rebase`, edit, commit, and `git push` in `/home/bpx27/yaksu-shared-data`.

```text
니노야 claude-config/skills는 코덱스에서 어떻게 써야해?
```

Expected: Codex treats them as legacy references and does not assume Claude-only tools are directly available.

```text
니노야 MEMORY_INDEX.md에서 feedback_utf8_bom.md 경로를 찾아서 어느 메모리 루트에 있는지만 말해줘.
```

Expected: Codex uses `shared-context/MEMORY_INDEX.md` and answers with the Claude project memory root.

```text
니노야 shared-data todo-list 읽을 때 이제 어떤 스크립트를 쓰면 돼?
```

Expected: Codex names `bash scripts/shared-data.sh read todo-list.md`.

## Restart Relay In Test Mode

```bash
systemctl --user restart nino-relay.service
```

## Roll Back To Main Runtime

Remove the feature worktree override:

```bash
rm -f /home/bpx27/.config/systemd/user/nino-relay.service.d/feature-worktree.conf
systemctl --user daemon-reload
systemctl --user restart nino-relay.service
```

Disable Codex test routing in `/home/bpx27/discord-bot-nino/.env`:

```env
CODEX_ENABLED=false
CODEX_TEST_CHANNELS=
```

Then restart relay:

```bash
systemctl --user restart nino-relay.service
```

Optionally stop the Codex tmux session:

```bash
tmux kill-session -t nino-codex 2>/dev/null || true
```

## Security Note

Codex currently runs with:

```text
--dangerously-bypass-approvals-and-sandbox
```

Do not broaden Codex routing beyond tightly controlled channels without an explicit operational decision.
