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

### 3. Provider Primary, Ordered Fallback

Use this during migration and while both subscriptions are available.
`PRIMARY_BACKEND` is an operator choice, not a fixed product decision.

```env
PRIMARY_BACKEND=codex
FALLBACK_BACKENDS=claude
CLAUDE_ENABLED=true
CODEX_ENABLED=true
```

Expected behavior:
- The configured primary receives new requests first.
- Fallback backends are tried in `FALLBACK_BACKENDS` order when the primary is disabled, unhealthy, quota-blocked, cooled down, or misses a request deadline.
- The router prevents duplicate Discord replies if both backends eventually respond.

The same structure can be inverted later:

```env
PRIMARY_BACKEND=claude
FALLBACK_BACKENDS=codex
CLAUDE_ENABLED=true
CODEX_ENABLED=true
```

Direct messages can be pinned to a specific backend independently from the guild-channel primary:

```env
DM_BACKEND=claude
```

With this setting, DMs prefer Claude even if `PRIMARY_BACKEND=codex` or the channel is listed in `CODEX_TEST_CHANNELS`. If Claude is disabled or unhealthy, the router falls back to the normal primary/fallback policy so DMs do not silently disappear.

Runtime status files live under:

```text
runtime/backend-status
```

Examples:

```bash
bash scripts/backend-status.sh set codex quota_exhausted "usage limit reached"
bash scripts/backend-status.sh set claude cooldown "maintenance" "2026-05-06T22:00:00+09:00"
bash scripts/backend-status.sh clear codex
```

The watchdog runs `scripts/scan-backend-quota.sh` for enabled backends. If tmux output contains clear limit/rate-limit phrases, it marks that backend `quota_exhausted`, making the router skip it until the status is cleared or expires.

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
