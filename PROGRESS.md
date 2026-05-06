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

Phase 0: Documentation and planning.

## Next Tasks

1. Add `package.json` and fix test require paths.
2. Add backend config schema tests.
3. Add backend router contract tests.
4. Wrap current Claude tmux behavior in a Claude adapter without changing production behavior.
5. Add durable request state for backend ownership.
6. Generalize health output around backend status.
7. Add Codex backend after Claude adapter is covered by tests.

## Open Questions

- Which channels should be trusted for agent execution?
- What timeout should trigger fallback?
- Should fallback be disabled until manual operator approval?
- Where should shared memory ultimately live: repo ignored `memory/` or external `~/nino-shared/memory`?
- Should production `start-nino.sh` continue to run `git reset --hard origin/main`, or should deploy and restart be separated?
