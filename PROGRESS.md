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

Phase 1 implementation complete in branch `feat/optional-ai-backends`.

## Completed Tasks

1. Added `package.json`, lockfile, and restored the Jest test baseline.
2. Added backend config schema with optional Claude/Codex enablement.
3. Wrapped Claude tmux behavior in a Claude backend adapter.
4. Added backend router, request ownership state, fallback handling, and relay integration.
5. Generalized health output around provider-neutral backend status while keeping legacy Claude fields.
6. Added Codex tmux backend routing for configured test channels.
7. Added backend-aware operating scripts while preserving the default Claude production restart flow.
8. Fixed review findings for Claude-disabled/Codex-enabled operation and relay-level ownership completion.

## Verification

- `npm test`: 10 suites / 94 tests passed.
- `bash -n scripts/start-backend.sh scripts/restart-backend.sh scripts/nino-watchdog.sh scripts/start-nino.sh scripts/restart-nino.sh`: passed.
- Final code review: approved with residual risks around script tests being mostly static and Codex-only mode routing regular channels when Codex is the only enabled backend.

## Next Tasks

1. Run a WSL tmux smoke test with real Claude/Codex sessions.
2. Configure `CODEX_TEST_CHANNELS` and verify Discord test-channel routing end to end.
3. Decide whether Codex-only mode should route all channels or require an explicit `PRIMARY_BACKEND=codex` for production.
4. Decide where shared memory should ultimately live and how Codex should ingest it.

## Open Questions

- Which channels should be trusted for agent execution?
- What timeout should trigger fallback?
- Should fallback be disabled until manual operator approval?
- Where should shared memory ultimately live: repo ignored `memory/` or external `~/nino-shared/memory`?
- Should production `start-nino.sh` continue to run `git reset --hard origin/main`, or should deploy and restart be separated?
