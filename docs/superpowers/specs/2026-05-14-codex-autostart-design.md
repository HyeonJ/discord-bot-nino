# Nino Codex Autostart Design

Date: 2026-05-14
Branch: feat/optional-ai-backends

## Current Finding

The current Windows reboot path is not guaranteed to start `nino-codex`.

Windows has a `StartNino` scheduled task that runs this WSL command:

```text
wsl.exe -d Ubuntu -u bpx27 -e bash -lc /home/bpx27/discord-bot-nino/scripts/start-nino.sh
```

That live WSL checkout is currently on `feat/code-quality-foundation`, not `feat/optional-ai-backends`. Its `scripts/start-nino.sh` and `scripts/nino-watchdog.sh` are Claude-only. The feature branch contains backend-aware startup work, but a GitHub push does not change what the reboot task executes.

Also, `nino.service` is enabled but failed because its `ExecStart` points at `/home/bpx27/discord-bot-nino/start-nino.sh`, while the actual script path is `/home/bpx27/discord-bot-nino/scripts/start-nino.sh`. It should not be treated as a working restart path until fixed or disabled.

The watchdog cron entry is persistent in the user's crontab:

```text
*/2 * * * * /home/bpx27/discord-bot-nino/scripts/nino-watchdog.sh
```

That makes watchdog usable after reboot, but the script it calls is still Claude-only and must be updated before it can recover Codex.

## Goal

After a Windows restart or login, with no manual terminal work:

1. WSL starts through the existing Windows scheduled task.
2. Enabled backend sessions are present in tmux.
3. `nino-codex` starts automatically when `CODEX_ENABLED=true`.
4. Claude remains optional and can still start when `CLAUDE_ENABLED=true`.
5. The relay runs against the same backend configuration and reports Codex alive when `PRIMARY_BACKEND=codex`.
6. If `nino-codex` dies later, watchdog can restart it.

## Recommended Approach

Use the existing Windows scheduled task as the single entry point, but make the WSL startup path backend-aware.

This is the lowest-risk path because Windows already starts WSL correctly and the bot already uses tmux sessions. The fix should live inside the WSL repo scripts, not in a second Windows task, so backend selection remains controlled by `.env`.

### Startup Flow

`StartNino` should continue to call:

```text
/home/bpx27/discord-bot-nino/scripts/start-nino.sh
```

That script should:

1. Load `/home/bpx27/discord-bot-nino/.env`.
2. Read `CLAUDE_ENABLED`, `CODEX_ENABLED`, `CLAUDE_TMUX_SESSION`, and `CODEX_TMUX_SESSION`.
3. Start Claude only when enabled.
4. Start Codex only when enabled.
5. Avoid killing an already healthy tmux session during a normal startup run.
6. Restart or create missing/dead sessions through backend-specific helpers.
7. Use a startup lock such as `flock` so duplicate Windows triggers cannot race each other.
8. Wait briefly for newly started backend tmux panes before restarting relay.
9. Start or restart the relay after backend startup attempts.
10. Write timestamped startup output to `/home/bpx27/discord-bot-nino/logs/startup.log`.

### Backend Helpers

Deploy these backend-aware helper scripts into the live WSL checkout:

- `scripts/start-backend.sh`
- `scripts/restart-backend.sh`
- `scripts/start-codex-nino.sh`

The helpers should use exact tmux targets such as `=nino-codex` to avoid matching the wrong session. They should be idempotent for normal startup: if a backend session is already alive, startup should leave it alone unless an explicit restart mode is requested.

All helper scripts should resolve the repo root and `.env` explicitly for the live path. They must not accidentally read the feature worktree `.env` after being copied into `/home/bpx27/discord-bot-nino`.

### Watchdog Flow

Update the live `scripts/nino-watchdog.sh` so it is no longer Claude-only.

It should:

1. Load `.env`.
2. Check each enabled backend independently.
3. Define Codex alive as: tmux session exists, at least one pane exists, and `pane_current_command` is an expected process such as `node` or `codex` for the Codex bridge. A tmux pane sitting at `bash`, `sh`, or an empty command is not alive.
4. Preserve existing Claude D-state handling only for Claude.
5. Restart `nino-codex` when `CODEX_ENABLED=true` and the Codex tmux pane is missing or not alive by that definition.
6. Skip restart if the session was created very recently, so the watchdog does not interrupt a still-initializing Codex startup.
7. Avoid changing disabled backends.
8. Keep relay recovery separate from backend recovery.

The current cron entry can remain:

```text
*/2 * * * * /home/bpx27/discord-bot-nino/scripts/nino-watchdog.sh
```

### systemd Cleanup

Fix the broken user service `nino.service`.

It should point to:

```text
/home/bpx27/discord-bot-nino/scripts/start-nino.sh
```

This makes systemd status honest and gives WSL another recovery path. Do not leave it enabled and failed.

`nino-relay.service` is already enabled and active, but it currently has a feature-worktree override:

```text
/home/bpx27/.config/systemd/user/nino-relay.service.d/feature-worktree.conf
```

Final deployment must remove or replace that override so relay executes from `/home/bpx27/discord-bot-nino/src/discord-relay.js`, not from the temporary worktree. During the current feature-branch rollout, keep the override in place until the live checkout contains the optional-backend relay code. Removing it too early would start the old live relay, which does not understand Codex routing.

## Deployment Requirement

Do not assume the pushed feature branch is live.

Before claiming reboot safety, the backend-aware scripts must be deployed to `/home/bpx27/discord-bot-nino`, which is the path used by Windows Task Scheduler and cron. Because that checkout has dirty and untracked files, deployment should avoid destructive git operations.

Safe deployment options:

1. Preferred: merge the feature branch carefully into the live checkout after reviewing dirty files.
2. Operational hotfix: copy only the startup/watchdog scripts from the feature worktree to the live checkout, preserving backups.
3. Current safe rollout: keep `nino-relay.service.d/feature-worktree.conf` pointing at the feature worktree while only startup/watchdog scripts are copied to the live checkout.
4. Longer-term: make `/home/bpx27/discord-bot-nino` track the final merged main branch and remove the temporary feature-worktree service override.

Before any deployment, list the dirty files in the live checkout and confirm whether the startup scripts, watchdog, service files, or `.env` are already modified. If those files are dirty, preserve backups and merge by hand instead of overwriting.

## Verification Plan

Run these before saying autostart is fixed.

### Reboot Simulation

1. Kill or rename the `nino-codex` tmux session.
2. Run the exact scheduled-task command manually from Windows:

```powershell
wsl.exe -d Ubuntu -u bpx27 -e bash -lc /home/bpx27/discord-bot-nino/scripts/start-nino.sh
```

3. Verify `tmux ls` contains `nino-codex`.
4. Verify `tmux list-panes -t =nino-codex -F '#{pane_current_command}'` shows the expected Codex process.
5. Verify relay health reports `primary_backend=codex` and `codex.alive=true`.
6. Check `/home/bpx27/discord-bot-nino/logs/startup.log` for startup errors.

### Watchdog Recovery

1. Kill `nino-codex`.
2. Run `/home/bpx27/discord-bot-nino/scripts/nino-watchdog.sh` manually.
3. Verify `nino-codex` is recreated.
4. Confirm Discord messages route to Codex again.

### Windows Task Scheduler Check

1. Confirm the task has an appropriate logon delay or add a short delay so WSL/systemd user services have time to initialize.
2. Run `Start-ScheduledTask -TaskName StartNino`.
3. Confirm WSL starts both enabled sessions.
4. Confirm no manual tmux command is required.

### Real Reboot Check

1. Restart Windows.
2. Do not manually open WSL.
3. After login, check tmux sessions and relay health.
4. Send a Discord test message in a non-test channel and confirm Codex answers.

## Risks and Decisions

- The live checkout is dirty. Startup fixes must not use `git reset`, `git checkout --`, or destructive cleanup.
- If `PRIMARY_BACKEND=codex` and Codex fails to start, the current no-fallback setup can still leave the bot silent. Readiness-based failover is a separate planned feature.
- Starting Codex can take longer than relay startup. The startup script should use a concrete wait/poll window, and watchdog should include a grace period for recently created sessions.
- The feature worktree service override is useful for testing, but it is not a final deployment shape.

## Recommendation

Implement the minimal reliable path first:

1. Deploy backend-aware startup scripts to the live WSL checkout.
2. Make `start-nino.sh` idempotently start all enabled backends.
3. Make `nino-watchdog.sh` recover all enabled backends.
4. Fix or disable the broken `nino.service`.
5. Run reboot simulation, watchdog simulation, scheduled-task test, then real reboot test.

After that works, implement readiness-based fallback so Claude can answer if the primary backend is unavailable.
