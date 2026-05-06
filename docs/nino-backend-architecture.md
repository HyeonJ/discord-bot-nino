# Nino Optional Backend Architecture

Date: 2026-05-06
Branch: `feat/optional-ai-backends`

## Summary

Nino should become a provider-neutral Discord relay with optional AI backend adapters. Claude and Codex are implementation details behind a backend contract, not required parts of Nino Core.

## Current Risk Areas

- `src/discord-relay.js` sends directly to a single `TMUX_SESSION`.
- `src/health.js` checks `claude_pid` and assumes Claude is the agent.
- `src/health-checker.js` alerts on missing Claude PID.
- `scripts/start-nino.sh`, `scripts/restart-nino.sh`, and `scripts/nino-watchdog.sh` directly invoke or inspect Claude.
- `scripts/check-auth.sh` and `scripts/check-usage-alert.sh` use Claude-specific credentials and usage endpoints.
- Memory exists in multiple locations: repo `memory/discord-history`, Claude project memory, and Python `src/memory`.
- Discord input currently reaches a privileged agent session with dangerous permissions.

## Target Components

### Nino Core

Responsibilities:
- Connect to Discord.
- Normalize incoming Discord messages.
- Save history and attachments.
- Decide whether a message needs an agent response.
- Create durable request records.
- Pass requests to the backend router.
- Observe Discord replies and close matching requests.

### Backend Router

Responsibilities:
- Validate backend configuration at startup.
- Select a backend based on channel, primary backend, fallback list, and health.
- Assign a `request_id` and backend lease.
- Record request ownership.
- Suppress duplicate responses after fallback.
- Surface routing decisions to logs and health.

Request fields:

```json
{
  "request_id": "nino-20260506-000001",
  "discord_message_id": "148...",
  "channel_id": "148...",
  "backend_id": "codex",
  "state": "sent",
  "sent_at": "2026-05-06T12:00:00+09:00",
  "deadline_at": "2026-05-06T12:03:00+09:00",
  "preview": "[D][Darren] ..."
}
```

### Backend Adapter Contract

Each backend adapter must expose:

```js
{
  id: 'claude',
  isEnabled(config),
  validate(config),
  health(config),
  send(request, config),
  restart(config),
}
```

Health may return `unknown` for provider-specific fields that are not available.

### Tmux Backend

Claude and Codex can both use a tmux transport initially. The transport is separate from provider identity.

Responsibilities:
- Check tmux session existence.
- Find pane PID.
- Send escaped input safely.
- Report process status.

Provider adapters supply:
- session name
- expected process pattern
- start command
- restart command
- initial startup prompt

### Shared State

Do not move all state at once. First add a configurable state root:

```env
NINO_STATE_DIR=/home/bpx27/discord-bot-nino/state
NINO_LOG_DIR=/home/bpx27/discord-bot-nino/logs
```

Initial state files:
- `state/backend-requests.jsonl`
- `state/active-backend.json`
- `state/pending-responses.json`

### Shared Memory

Memory migration is a later phase. The first phase only documents and reads from existing paths.

Target layout:

```text
memory/
├─ nino-profile.md
├─ user-memory.md
├─ current-tasks.md
├─ discord-history/
└─ summaries/
```

### Security Rules

Before broad fallback/automation:
- Define trusted channels for agent execution.
- Treat DMs and server channels differently.
- Limit attachment size and type.
- Preserve full Discord message context to reduce prompt injection ambiguity.
- Keep dangerous mode explicit per backend.
- Log when a backend receives untrusted or attachment-bearing input.

## Implementation Principles

- Keep Claude working while refactoring.
- Add tests before changing behavior.
- Introduce Codex only after Claude adapter wraps current behavior.
- Avoid global memory migration until routing and health are stable.
- Treat auth and usage as provider-specific, not universal concepts.
