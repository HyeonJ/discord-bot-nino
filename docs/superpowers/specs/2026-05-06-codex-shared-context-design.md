# Codex Shared Context Design

## Goal

Make Codex use Nino's existing Claude-era memory, operating habits, hooks, and skills without deleting or replacing the Claude setup.

## Architecture

Nino keeps the current Claude memory and configuration locations as the source data. Codex receives a provider-neutral shared context index at startup, then reads the live memory files from their original WSL paths when a Discord request needs them. This avoids copying private memory into git and avoids forcing Claude-specific hooks into Codex.

## Components

- `shared-context/NINO_SHARED_CONTEXT.md`: provider-neutral index of live memory paths, shared-data paths, legacy hook behavior, and legacy skills.
- `codex-config/NINO_CODEX.md`: short Codex persona and routing instructions that point Codex to the shared context index.
- `scripts/start-codex-nino.sh`: startup script that concatenates Codex persona instructions and shared context into the initial Codex prompt.
- `tests/codex-instructions.test.js` and `tests/operational-scripts.test.js`: tests proving Codex receives the shared context and that startup still launches the expected Codex command.
- `docs/codex-test-operations.md` and `PROGRESS.md`: operational notes and current phase tracking.

## Memory Policy

Do not commit private memory contents. The repo may commit only paths, categories, and usage rules. Codex should read these live locations when needed:

- `/home/bpx27/discord-bot-nino/memory`
- `/home/bpx27/.claude/projects/-home-bpx27-discord-bot-nino/memory`
- `/home/bpx27/yaksu-shared-data`

## Hook And Skill Policy

Claude hooks remain Claude-specific. Codex gets equivalent operating rules in the shared context:

- remember useful new facts by writing to live memory;
- read `current-tasks.md` before continuing work;
- treat shared-data files with git pull/edit/commit/push discipline;
- use `claude-config/skills` as legacy skill references, not as guaranteed executable Codex skills.

## Testing

Automated tests verify startup prompt assembly and required path/rule coverage. Manual Discord smoke tests verify that Codex can answer questions about current tasks, user memory, shared-data, and legacy skill references.
