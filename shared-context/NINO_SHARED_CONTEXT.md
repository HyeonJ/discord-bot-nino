# Nino Shared Context

This file is a provider-neutral index for Nino's long-running memory, operating rules, hook replacements, and legacy skills.

Do not copy private memory contents into this repository. Read the live WSL paths below when the conversation requires them.

Generated memory metadata index:

```text
shared-context/MEMORY_INDEX.md
```

Use the index first when you need to decide which memory file to inspect. The index contains file paths, categories, sizes, and modified times only. It intentionally does not contain private memory contents.

Refresh it with:

```bash
node scripts/build-memory-index.js
```

## Live Memory Paths

Primary bot memory:

```text
/home/bpx27/discord-bot-nino/memory
```

Important files and directories:

- `/home/bpx27/discord-bot-nino/memory/current-tasks.md`: active and recently completed Nino tasks.
- `/home/bpx27/discord-bot-nino/memory/discord-history`: daily Discord JSONL history.
- `/home/bpx27/discord-bot-nino/memory/alarms`: alarm and reminder notes.
- `/home/bpx27/discord-bot-nino/memory/research` and `/home/bpx27/discord-bot-nino/memory/research-results`: research notes.

Claude project memory:

```text
/home/bpx27/.claude/projects/-home-bpx27-discord-bot-nino/memory
```

Important categories:

- `MEMORY.md`: high-level long-term memory.
- `user_*`: user-specific profile and preference memory.
- `feedback_*`: remembered corrections, preferences, and operating lessons.
- `project_*`: ongoing or historical project notes.
- `ref_*` and `reference_*`: durable references and setup notes.
- `session-context-snapshot.md`: most recent saved Claude session context.
- `compression-log.md`: Claude compaction history.

Shared household data:

```text
/home/bpx27/yaksu-shared-data
```

Important files:

- `todo-list.md`
- `shopping-list.md`
- `pantry.md`
- `purchase-history.md`

## When To Read Memory

- Before continuing existing work, read `memory/current-tasks.md`.
- When asked what Nino remembers about Darren, Tim, preferences, or prior corrections, inspect Claude project memory first:
  - `MEMORY.md`
  - `user_*`
  - `feedback_*`
- When asked about a project, inspect `project_*`, `ref_*`, and primary bot memory.
- When asked about recent Discord context, inspect the relevant file in `memory/discord-history`.
- Do not invent memory. If a file is missing or does not contain the answer, say that naturally.

## Hook Replacement Rules For Codex

Claude hooks live in:

```text
claude-config/hooks
```

Codex does not receive Claude Code hook events directly. Apply these equivalent operating rules manually:

- Memory reminder: before finishing a meaningful response, decide whether a durable fact or task status should be written to live memory.
- Current task continuity: before starting or resuming non-trivial work, read `/home/bpx27/discord-bot-nino/memory/current-tasks.md` when present.
- Shared-data sync: prefer `scripts/shared-data.sh` for `todo-list.md`, `shopping-list.md`, `pantry.md`, and `purchase-history.md`. It runs `git pull --rebase` before access and commits changes before `git push`.
- Context snapshot: for long-running work, record enough status in `memory/current-tasks.md` or another appropriate memory file so the next session can continue.
- Secrets: never write passwords, tokens, recovery codes, or private authentication material into memory or git.

Shared-data examples:

```bash
bash scripts/shared-data.sh read todo-list.md
bash scripts/shared-data.sh append todo-list.md "- 새 할 일" "Update todo-list.md"
bash scripts/shared-data.sh write shopping-list.md "새 목록 내용" "Update shopping-list.md"
```

## Legacy Skills

Claude skills are mirrored in:

```text
claude-config/skills
```

Use them as legacy references. A Claude skill may mention Claude-specific tools or commands that do not exist in Codex. When using one:

- Read the skill instructions for intent and workflow.
- Prefer provider-neutral shell commands and repo tools.
- Do not call Claude CLI from Codex unless the user explicitly asks for Claude involvement.
- If a skill depends on unavailable Claude-only tools, explain the limitation and perform the closest safe Codex equivalent.

Frequently relevant legacy skill groups:

- `agent-browser`: browser automation workflow references.
- `yaksu-history`: shared server/history references.
- `alarm`: reminder and alarm workflow references.
- `skill-check`: skill usage hygiene.
- `wake-klaude`, `jbl-keep-alive`, `onedrive-vault`, `notion-pcb-vox-admin`: domain-specific operational references.

## Discord Response Rule

For Discord-originated messages, answer through:

```bash
/home/bpx27/discord-bot-nino/src/discord-send -c CHANNEL_ID -r MESSAGE_ID "your reply"
```

Use `[C:...]` and `[M:...]` from the relay payload.

## Jeffrey Translation Rule

- Jeffrey / jeffreytaiwan is Tim's boyfriend; Tim is Jeffrey's boyfriend.
- Jeffrey does not speak Korean.
- When Jeffrey is present in a channel or asks for translation support, provide English translations for Korean messages/content.
- Traditional Chinese is not required unless Jeffrey explicitly asks for it.
