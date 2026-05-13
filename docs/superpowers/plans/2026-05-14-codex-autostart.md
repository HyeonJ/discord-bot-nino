# Codex Autostart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `nino-codex` start automatically after Windows reboot/login through the existing WSL startup path.

**Architecture:** Keep Windows Task Scheduler as the only Windows entry point. Make WSL startup and watchdog scripts backend-aware, idempotent, logged, and deploy the same scripts to the live WSL checkout used by Task Scheduler.

**Tech Stack:** Bash, tmux, WSL Ubuntu, systemd user services, Windows Task Scheduler.

---

### Task 1: Make Backend Startup Idempotent

**Files:**
- Modify: `scripts/start-backend.sh`
- Verify: `bash -n scripts/start-backend.sh`

- [ ] Add a backend liveness check based on exact tmux session, pane command, pane args, and child process.
- [ ] If a session is already alive, leave it running.
- [ ] If a session exists but is not alive, kill and recreate it.

### Task 2: Make Main Startup Backend-Aware

**Files:**
- Modify: `scripts/start-nino.sh`
- Verify: `bash -n scripts/start-nino.sh`

- [ ] Add startup logging to `logs/startup.log`.
- [ ] Add `flock` so duplicate scheduled task runs cannot race.
- [ ] Load `.env` before backend startup.
- [ ] Start Claude only when `CLAUDE_ENABLED=true`.
- [ ] Start Codex only when `CODEX_ENABLED=true`.
- [ ] Do not use destructive git reset on startup.
- [ ] Restart relay after backend startup attempts.

### Task 3: Harden Watchdog

**Files:**
- Modify: `scripts/nino-watchdog.sh`
- Verify: `bash -n scripts/nino-watchdog.sh`

- [ ] Define Codex alive by exact tmux session plus expected pane command/process.
- [ ] Treat `bash`, `sh`, or empty panes as dead.
- [ ] Add grace period for very new sessions.
- [ ] Continue Claude D-state handling only for Claude.

### Task 4: Deploy To Live WSL Path

**Files:**
- Copy to: `/home/bpx27/discord-bot-nino/scripts/start-backend.sh`
- Copy to: `/home/bpx27/discord-bot-nino/scripts/restart-backend.sh`
- Copy to: `/home/bpx27/discord-bot-nino/scripts/start-codex-nino.sh`
- Copy to: `/home/bpx27/discord-bot-nino/scripts/start-nino.sh`
- Copy to: `/home/bpx27/discord-bot-nino/scripts/nino-watchdog.sh`

- [ ] Back up existing live scripts.
- [ ] Copy scripts without touching unrelated dirty files.
- [ ] Mark scripts executable.

### Task 5: Fix Runtime Services

**Runtime files:**
- Modify: `/home/bpx27/.config/systemd/user/nino.service`
- Keep for current rollout: `/home/bpx27/.config/systemd/user/nino-relay.service.d/feature-worktree.conf`

- [ ] Fix `nino.service` `ExecStart` to `/home/bpx27/discord-bot-nino/scripts/start-nino.sh`.
- [ ] Keep relay feature-worktree override until the live WSL checkout contains optional-backend relay code.
- [ ] Run `systemctl --user daemon-reload`.
- [ ] Restart `nino-relay.service`.

### Task 6: Verify

- [ ] Run `bash -n` for modified scripts.
- [ ] Set the Windows `StartNino` logon trigger delay to `PT30S`.
- [ ] Run the exact Windows scheduled-task command manually.
- [ ] Verify `tmux ls` contains `nino-codex`.
- [ ] Verify `tmux list-panes -t =nino-codex -F '#{pane_current_command}'` is `node` or `codex`.
- [ ] Verify relay service is active.
- [ ] Verify `nino.service` is not failed.
