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
```

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
