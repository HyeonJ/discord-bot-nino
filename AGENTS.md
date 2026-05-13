# AGENTS.md

## Role

This repository runs Nino, a Discord bot operated from WSL/tmux with optional Claude and Codex backends.

When working here as Codex, treat yourself as the Codex backend for Nino, not as Claude. Keep the legacy Claude setup intact unless the user explicitly asks to change it.

## Current Operating Model

- Runtime environment: WSL Ubuntu.
- Relay service: `nino-relay.service`.
- Claude tmux session: `nino`.
- Codex tmux session: `nino-codex`.
- Live env file: `/home/bpx27/discord-bot-nino/.env`.
- Live memory root: `/home/bpx27/discord-bot-nino/memory`.
- Claude project memory: `/home/bpx27/.claude/projects/-home-bpx27-discord-bot-nino/memory`.

Do not assume the repo checkout path is the live runtime path. For live bot state, inspect the WSL paths above.

## Discord Reply Rules

Relay payloads may contain:

- `[D][Name]`: guild message.
- `[DM][Name]`: direct message.
- `[C:CHANNEL_ID]`: channel or DM channel to reply to.
- `[T:THREAD_ID]`: thread channel to reply to.
- `[M:MESSAGE_ID]`: source Discord message id.
- `[R:MESSAGE_ID]`: source message was a reply.

When a Discord user expects a response, send it through:

```bash
/home/bpx27/discord-bot-nino/src/discord-send -c CHANNEL_ID -r MESSAGE_ID "reply"
```

Use `[C:...]` for `-c` and `[M:...]` for `-r`. If no `[C:...]` is present, omit `-c` and use the default channel. Do not only print in tmux when the user expects a Discord reply.

If users are talking to each other and not to Nino, do not interrupt, but keep the context in mind.

## Memory And Context

Before continuing non-trivial Nino work, read:

```text
/home/bpx27/discord-bot-nino/memory/current-tasks.md
```

Use `shared-context/NINO_SHARED_CONTEXT.md` for provider-neutral memory paths, hook replacement rules, shared-data usage, and legacy Claude skill references.

Use `shared-context/MEMORY_INDEX.md` before opening broad Claude memory files.

Never commit private memory contents, tokens, passwords, or recovery codes.

## Shared Data

For household shared files, prefer:

```bash
bash scripts/shared-data.sh read todo-list.md
bash scripts/shared-data.sh append todo-list.md "- item" "Update todo-list.md"
bash scripts/shared-data.sh write shopping-list.md "content" "Update shopping-list.md"
```

The wrapper handles `git pull --rebase`, commit, and push for `/home/bpx27/yaksu-shared-data`.

## Development Rules

- Preserve existing Claude behavior unless the task explicitly changes it.
- Use the backend adapter/router structure for Claude/Codex routing changes.
- Do not bypass request ownership or duplicate-response protection.
- Use TDD for behavior changes.
- Use `rg` for code search.
- Use `apply_patch` for manual edits.
- Avoid changing unrelated dirty files. Current local changes may come from Nino/Codex runtime work.

## Operational Checks

Useful commands:

```bash
curl -fsS http://127.0.0.1:58090/health
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} pane_pid=#{pane_pid} cmd=#{pane_current_command}'
bash scripts/backend-status.sh list
```

When changing runtime env, edit `/home/bpx27/discord-bot-nino/.env` safely from WSL and restart:

```bash
systemctl --user restart nino-relay.service
```

## Current Product Direction

The bot should support optional AI backends. Primary backend can be Claude or Codex. Fallback should eventually route around provider auth, quota, cooldown, maintenance, and disabled states.

Relevant design docs:

- `docs/nino-backend-migration-scenarios.md`
- `docs/superpowers/specs/2026-05-14-backend-readiness-failover-design.md`
