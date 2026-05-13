# Backend Readiness Failover Design

Date: 2026-05-14
Branch: `feat/optional-ai-backends`

## Problem

Nino currently routes by configured primary/fallback backend and basic process health. This is not enough for real operation. A backend can have a live tmux session and live process while being unable to answer, for example Claude showing `API Error: 401`, `authentication_error`, or `Please run /login`.

The desired behavior is provider-neutral:

- Any backend can be primary.
- Any enabled backend can be fallback.
- If the current primary cannot actually answer, Nino should route new messages to the next usable backend.
- If a message was already sent to a backend that later proves unusable or times out, the relay should retry the configured fallback without duplicate Discord replies.

## Current Behavior

Already implemented:

- Optional `claude` and `codex` backend adapters.
- Router with primary, fallback, test-channel override, DM preferred backend, and request ownership.
- Runtime backend status files under `runtime/backend-status`.
- Blocking states: `quota_exhausted`, `cooldown`, `maintenance`, `disabled`.
- Timeout fallback through `routeFallback`.
- Quota phrase scanner for tmux panes.

Missing:

- Runtime status does not include auth/session-error states.
- `scripts/scan-backend-quota.sh` only detects quota-like text, not auth failures.
- `FALLBACK_BACKENDS` is not enabled in the current production env.
- Claude fallback decisions still treat `sessionAlive=true` as routable even when the pane is showing auth errors.
- Existing pending requests only fallback after timeout; backend error detection is not yet connected to request ownership.

## Proposed Architecture

Introduce a provider-neutral backend readiness layer.

### 1. Expand Runtime Status States

Add blocking states:

- `auth_error`: credentials are invalid, expired, missing, or login is required.

Keep existing states:

- `quota_exhausted`
- `cooldown`
- `maintenance`
- `disabled`
- `ready`

Router behavior:

- `auth_error` blocks routing exactly like `quota_exhausted`.
- If the blocked backend is primary, router tries `FALLBACK_BACKENDS` in order.
- `auth_error` must be added to both `src/backends/runtime-status.js` `BLOCKING_STATES` and `scripts/backend-status.sh` state validation in the same implementation step. If only one side changes, the scanner/status/router chain silently fails.

`provider_error` is intentionally deferred from pass 1. It needs specific detection patterns before it is useful, and vague provider-error matching would create too many false positives.

### 2. Generalize the Tmux Scanner

Replace or extend `scripts/scan-backend-quota.sh` into a more general `scripts/scan-backend-status.sh`.

Inputs:

```bash
scripts/scan-backend-status.sh <backend> <tmux-session>
```

Detected states in pass 1:

- quota/rate limit patterns -> `quota_exhausted`
- auth patterns -> `auth_error`

Initial auth patterns:

```text
API Error: 401
authentication_error
Invalid authentication credentials
Please run /login
```

Initial quota patterns remain:

```text
usage limit reached
rate limit
quota exceeded
limit reached
try again later
too many requests
insufficient_quota
```

The scanner should capture a larger pane window than the current quota scanner, starting with the last 500 lines, because auth errors can scroll away after an interactive session continues.

When no blocking pattern is found, the scanner should not automatically clear status. Clearing should stay explicit in pass 1 unless an operator sets an `until` timestamp. This avoids oscillation from incomplete pane captures.

Recovery policy for pass 1:

- `auth_error` persists until manually cleared with `scripts/backend-status.sh clear <backend>`, or until an operator sets it with a specific expiry.
- After running `claude auth login`, the operator should clear Claude status.
- Later, we can add a safe positive readiness probe, but pass 1 should not infer recovery only from absence of error text.

### 3. Watchdog Integration

Update `scripts/nino-watchdog.sh`:

- call `scan-backend-status "claude" "$CLAUDE_SESSION"`
- call `scan-backend-status "codex" "$CODEX_SESSION"`
- keep existing process/session restart behavior
- keep Claude D-state handling Claude-only

This turns visible tmux auth errors into runtime status files the router already knows how to consume.

### 4. Env Failover Policy

Set the operating mode explicitly:

```env
PRIMARY_BACKEND=claude
FALLBACK_BACKENDS=codex
CLAUDE_ENABLED=true
CODEX_ENABLED=true
DM_BACKEND=codex
```

This means:

- Claude receives normal channel messages while healthy.
- Codex receives DMs.
- Codex receives normal channel messages when Claude is blocked or unavailable.
- `CODEX_TEST_CHANNELS` can remain set during staged rollout. It should not be required for fallback. Clearing it is a separate rollout decision once fallback is trusted.
- If later Codex becomes primary, invert the values:

```env
PRIMARY_BACKEND=codex
FALLBACK_BACKENDS=claude
```

### 5. Pending Request Fallback

Keep the existing timeout fallback as the first reliable mechanism for already-sent messages.

Flow:

1. Relay sends request to owner backend.
2. Pending map stores payload, channel, message id, owner backend.
3. If owner replies, `markCompleted` clears pending.
4. If timeout fires, `routeFallback` sends the same payload to the next routable fallback backend.
5. If the original owner later replies, request ownership prevents duplicate completion.

Optional later improvement:

- A scanner can mark `auth_error` quickly, but mapping a status change back to already-pending messages is not necessary for the first implementation. Timeout fallback is simpler and safer.

## Testing Plan

Unit tests:

- `runtime-status` blocks `auth_error`.
- `backend-status.sh` accepts `auth_error`.
- scanner maps auth text to `auth_error`.
- scanner maps quota text to `quota_exhausted`.
- router skips `auth_error` primary and routes to fallback.
- relay timeout fallback sends pending primary request to fallback when primary is blocked or timed out.

Operational script tests:

- watchdog calls `scan-backend-status.sh` for both enabled backends.
- old quota scanner compatibility is either preserved as a wrapper or tests are updated to the new script.

Smoke tests:

- Set `PRIMARY_BACKEND=claude`, `FALLBACK_BACKENDS=codex`.
- Manually mark Claude blocked:

```bash
bash scripts/backend-status.sh set claude auth_error "manual smoke test"
```

- Send a normal channel message and verify it appears in `nino-codex`.
- Clear status:

```bash
bash scripts/backend-status.sh clear claude
```

- Verify new normal messages return to Claude if Claude is authenticated.

## Risks

- False positive status detection can route away from a working backend.
- False negative status detection can leave messages waiting until timeout.
- Automatically clearing status could re-enable a broken backend too early.
- Claude currently shows 401; enabling Claude-primary fallback before Claude login is fixed will likely route most messages to Codex.
- Timeout fallback can still produce duplicate Discord posts if the original backend is merely slow, Codex responds after timeout, and the original backend later posts directly to Discord. Request ownership prevents duplicate completion bookkeeping, but it cannot unsend a response already posted by a backend CLI.
- Pass 1 only attempts one timeout fallback. If the fallback backend also times out, the relay sends a system notice instead of trying a third backend.

## Recommendation

Implement this in two small passes:

1. Add readiness states and scanner detection, then set `FALLBACK_BACKENDS=codex`.
2. After smoke testing, decide whether to set `CODEX_TEST_CHANNELS=` so Codex is no longer only a test-channel backend and acts as a true fallback for all guild channels.

Do not add immediate in-flight reroute on scanner detection in the first pass. Timeout fallback plus new-message routing is enough and has lower duplicate-response risk.
