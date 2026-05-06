# Nino Optional AI Backend Scenarios

Date: 2026-05-06
Branch: `feat/optional-ai-backends`

## Goal

Run Nino on WSL while making Claude and Codex optional AI backends. Either subscription may be cancelled later without breaking Discord relay, health checks, memory, or operational scripts.

## Operating Modes

### 1. Claude Only

Use this when Codex is unavailable or intentionally disabled.

```env
PRIMARY_BACKEND=claude
FALLBACK_BACKENDS=
CLAUDE_ENABLED=true
CODEX_ENABLED=false
```

Expected behavior:
- Discord relay sends agent-directed messages to the Claude tmux backend.
- Health reports Claude as enabled and Codex as disabled.
- Codex auth/usage status is not treated as an outage.

### 2. Codex Only

Use this when Claude is cancelled or intentionally disabled.

```env
PRIMARY_BACKEND=codex
FALLBACK_BACKENDS=
CLAUDE_ENABLED=false
CODEX_ENABLED=true
```

Expected behavior:
- Discord relay sends agent-directed messages to the Codex tmux backend.
- Claude auth/usage status is not treated as an outage.
- Claude-specific hooks remain backed up but are not required for normal operation.

### 3. Codex Primary, Claude Fallback

Use this during migration and while both subscriptions are available.

```env
PRIMARY_BACKEND=codex
FALLBACK_BACKENDS=claude
CLAUDE_ENABLED=true
CODEX_ENABLED=true
```

Expected behavior:
- Codex receives new requests first.
- Claude is used only if Codex is disabled, unhealthy, or misses a request deadline.
- The router prevents duplicate Discord replies if both backends eventually respond.

### 4. Claude Primary, Codex Test Channels

Use this for the safest initial rollout.

```env
PRIMARY_BACKEND=claude
FALLBACK_BACKENDS=
CLAUDE_ENABLED=true
CODEX_ENABLED=true
CODEX_TEST_CHANNELS=1480479067881865347
```

Expected behavior:
- Existing production channels continue through Claude.
- Selected test channels route to Codex.
- Health exposes both backend states.

### 5. No AI Backend Available

Use this only as degraded mode.

```env
PRIMARY_BACKEND=
FALLBACK_BACKENDS=
CLAUDE_ENABLED=false
CODEX_ENABLED=false
```

Expected behavior:
- Discord relay stays online.
- Incoming messages are saved to history.
- Agent-directed messages are marked as unhandled and reported to an operator channel.
- The bot does not pretend to be healthy.

## Non-Goals

- Do not remove the current Claude operating system.
- Do not migrate all memory paths in the first implementation pass.
- Do not assume Codex has Claude-equivalent lifecycle hooks.
- Do not make fallback fire without duplicate-response protection.

## Rollout Order

1. Restore test runner and baseline tests.
2. Define backend config schema and startup validation.
3. Add backend contract and wrap current Claude tmux behavior unchanged.
4. Add durable request ownership to prevent duplicate responses.
5. Generalize health and watchdog around backend status.
6. Add Codex tmux backend in test-channel mode.
7. Migrate shared memory/state paths as a separate phase.
