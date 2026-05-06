# Optional AI Backends Progress

Branch: `feat/optional-ai-backends`
Started: 2026-05-06

## Goal

Make Claude and Codex optional AI backends for Nino while preserving WSL/tmux operation and the existing Claude operating system.

## Decisions

- Keep WSL as the operating environment.
- Keep current Claude setup intact.
- Add Codex as a separate backend, initially in parallel/test-channel mode.
- Treat Claude and Codex as optional provider adapters.
- Do not rely on Codex having Claude-equivalent hooks.
- Do not implement fallback until duplicate-response prevention exists.
- Do not migrate all memory paths in the first phase.

## Review Findings To Preserve

- A backend router must be more than a tmux session switch.
- Request ownership must prevent split-brain duplicate Discord replies.
- Health/watchdog must not report false health by checking only Claude.
- Auth and usage checks are provider-specific and may return `unknown`.
- Discord-to-dangerous-agent routing needs explicit security policy.
- Current tests do not run as-is because `package.json` is absent and require paths are wrong.

## Current Phase

Phase 1 implementation and test-channel smoke test complete in branch `feat/optional-ai-backends`.
Phase 2 shared Codex context implementation is in progress.

## Completed Tasks

1. Added `package.json`, lockfile, and restored the Jest test baseline.
2. Added backend config schema with optional Claude/Codex enablement.
3. Wrapped Claude tmux behavior in a Claude backend adapter.
4. Added backend router, request ownership state, fallback handling, and relay integration.
5. Generalized health output around provider-neutral backend status while keeping legacy Claude fields.
6. Added Codex tmux backend routing for configured test channels.
7. Added backend-aware operating scripts while preserving the default Claude production restart flow.
8. Fixed review findings for Claude-disabled/Codex-enabled operation and relay-level ownership completion.
9. Added Codex Discord output bridge, reliable tmux submit handling, and Nino persona bootstrap.
10. Hardened backend watchdog and health semantics after final review.
11. Added provider-neutral shared context for Codex to find Claude-era memory, hook rules, shared-data rules, and legacy skills.
12. Fixed tmux backend pid detection when the provider process is the tmux pane process itself.
13. Added metadata-only memory index generation and shared-data git workflow wrapper.
14. Verified shared-context Discord smoke tests in the Codex test channel.
15. Started Codex-only runtime test and fixed watchdog provider-process detection for pane-owned backend processes.
16. Verified Codex-only Discord routing from a non-test channel, then restored mixed-test mode.

## Current Temporary Runtime State

As of 2026-05-06 20:51 KST this PC is intentionally running a temporary feature-branch mixed-test setup:

- `nino-relay.service` has a systemd user drop-in:
  - `/home/bpx27/.config/systemd/user/nino-relay.service.d/feature-worktree.conf`
  - It runs `/mnt/c/Dev/Workspace/discord-bot-nino/.worktrees/feat-optional-ai-backends/src/discord-relay.js`.
- The service still uses the production env file:
  - `/home/bpx27/discord-bot-nino/.env`
- Backend env in that file:
  - `TMUX_SESSION=nino`
  - `PRIMARY_BACKEND=`
  - `CLAUDE_ENABLED=true`
  - `CODEX_ENABLED=true`
  - `CODEX_TEST_CHANNELS=1480593132511826092`
- tmux sessions:
  - `nino` is the existing Claude session.
  - `nino-codex` is the Codex test session.
- Health at the time of writing:
  - `primary_backend=claude`
  - `backends.claude.enabled=true`
  - `backends.claude.alive=true`
  - `backends.codex.enabled=true`
  - `backends.codex.alive=true`
- Routing behavior:
  - Only channel `1480593132511826092` routes to Codex.
  - Other 약수하우스 channels route to Claude.

## Rollback Commands

Use these if the feature-branch test setup should be reverted before merge:

```bash
rm -f /home/bpx27/.config/systemd/user/nino-relay.service.d/feature-worktree.conf
systemctl --user daemon-reload
systemctl --user restart nino-relay.service
tmux kill-session -t nino-codex 2>/dev/null || true
```

Then remove or disable Codex test routing in `/home/bpx27/discord-bot-nino/.env`:

```env
CODEX_ENABLED=false
CODEX_TEST_CHANNELS=
```

Restart relay after editing `.env`:

```bash
systemctl --user restart nino-relay.service
```

## Keep Testing Commands

Use these while continuing test-channel operation:

```bash
cd /mnt/c/Dev/Workspace/discord-bot-nino/.worktrees/feat-optional-ai-backends
bash scripts/start-backend.sh codex
systemctl --user restart nino-relay.service
curl -s http://localhost:58090/health
node scripts/build-memory-index.js
bash scripts/shared-data.sh read todo-list.md
```

After restarting `nino-codex`, test shared context with:

```text
니노야 /home/bpx27/discord-bot-nino/memory/current-tasks.md 읽고 지금 진행중인 작업 한 줄로 말해줘.
니노야 Claude 프로젝트 MEMORY.md 경로 알고 있어? 파일 내용은 길게 말하지 말고 어떤 경로를 봐야하는지만 말해줘.
니노야 shared-data todo-list 수정할 때 어떤 git 절차 따라야 해?
니노야 claude-config/skills는 코덱스에서 어떻게 써야해?
니노야 MEMORY_INDEX.md에서 feedback_utf8_bom.md 경로를 찾아서 어느 메모리 루트에 있는지만 말해줘.
니노야 shared-data todo-list 읽을 때 이제 어떤 스크립트를 쓰면 돼?
```

## Verification

- `npm test`: 12 suites / 102 tests passed.
- `bash -n scripts/shared-data.sh scripts/start-backend.sh scripts/start-codex-nino.sh scripts/restart-backend.sh scripts/nino-watchdog.sh scripts/start-nino.sh scripts/restart-nino.sh`: passed.
- `node scripts/build-memory-index.js`: generated `shared-context/MEMORY_INDEX.md`.
- `bash scripts/shared-data.sh read todo-list.md`: read live shared-data through the wrapper.
- Codex-only `/health` with temporary env:
  - `primary_backend=codex`
  - `backends.claude.enabled=false`
  - `backends.codex.alive=true`, `pid=3209`
  - `watcher_alive=null`
- Codex-only watchdog script run with `CLAUDE_ENABLED=false CODEX_ENABLED=true CODEX_TMUX_SESSION=nino-codex`: exit 0 and kept `nino-codex` session alive.
- Codex-only Discord smoke test from a non-test channel: passed; reply returned from Codex.
- Restored mixed-test env after Codex-only smoke:
  - `primary_backend=claude`
  - `backends.claude.alive=true`, `pid=4534`
  - `backends.codex.alive=true`, `pid=3209`
- Earlier mixed-mode `/health` after relay restart was also verified before the temporary Codex-only switch.
- Final code review: approved.
- Real smoke tests passed:
  - Discord test channel routed to `nino-codex`.
  - Codex replied back to Discord through `/home/bpx27/discord-bot-nino/src/discord-send`.
  - Codex persona bootstrap was observed and tested.
  - Codex answered shared-context Discord smoke prompts for `MEMORY_INDEX.md`, `current-tasks.md`, `shared-data.sh`, and legacy `claude-config/skills`.

## Next Tasks

1. Decide whether to keep the feature worktree override until merge or switch back to main before merge.
2. Decide whether Codex-only mode should route all channels or require an explicit `PRIMARY_BACKEND=codex` for production.
3. Prepare final review covering optional backends, Codex shared context, memory index, shared-data wrapper, and Codex-only smoke.
4. Prepare PR/merge only after final review is clean.

## Open Questions

- Which channels should be trusted for agent execution?
- What timeout should trigger fallback?
- Should fallback be disabled until manual operator approval?
- Should shared context eventually move from a startup prompt into a Codex-native skill/hook mechanism if the CLI supports it?
- Should production `start-nino.sh` continue to run `git reset --hard origin/main`, or should deploy and restart be separated?
