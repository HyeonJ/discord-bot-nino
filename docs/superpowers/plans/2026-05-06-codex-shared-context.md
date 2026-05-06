# Codex Shared Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Codex consume Nino's existing memory, hook rules, and legacy skills through provider-neutral shared context while keeping Claude optional and intact.

**Architecture:** Add a committed context index that contains only paths and operating rules, not private memory contents. Extend the Codex startup prompt to concatenate the persona file and shared context file. Cover the behavior with focused Jest tests and update operations docs.

**Tech Stack:** Node.js, Jest, Bash, WSL tmux, Markdown configuration.

---

## File Structure

- Create: `shared-context/NINO_SHARED_CONTEXT.md`
  - Provider-neutral index of memory paths, Claude project memory categories, shared-data sync rules, and legacy skill references.
- Modify: `codex-config/NINO_CODEX.md`
  - Keep persona/routing concise and point Codex to the shared context index.
- Modify: `scripts/start-codex-nino.sh`
  - Append `CODEX_SHARED_CONTEXT_FILE` content to the initial Codex prompt when present.
- Modify: `tests/codex-instructions.test.js`
  - Assert required shared context references exist.
- Modify: `tests/operational-scripts.test.js`
  - Assert Codex startup includes `CODEX_SHARED_CONTEXT_FILE` and still launches Codex with the combined prompt.
- Modify: `docs/codex-test-operations.md`
  - Add shared-context smoke test prompts.
- Modify: `PROGRESS.md`
  - Update completed and next tasks.

## Task 1: Shared Context Contract Tests

- [x] Add failing Jest expectations for the new shared context file and startup script behavior.
- [x] Run `npm test -- tests/codex-instructions.test.js tests/operational-scripts.test.js --runInBand`.
- [x] Confirm tests fail because `shared-context/NINO_SHARED_CONTEXT.md` and `CODEX_SHARED_CONTEXT_FILE` behavior do not exist yet.

## Task 2: Shared Context Implementation

- [x] Create `shared-context/NINO_SHARED_CONTEXT.md` with live memory paths and rules.
- [x] Update `scripts/start-codex-nino.sh` to append the shared context file to `prompt`.
- [x] Update `codex-config/NINO_CODEX.md` to reference the shared context index.
- [x] Run the targeted Jest tests and confirm they pass.

## Task 3: Operations Docs

- [x] Update `docs/codex-test-operations.md` with memory/hook/skill smoke test prompts.
- [x] Update `PROGRESS.md` with this phase's status.
- [x] Run `npm test` and bash syntax checks.
- [x] Commit the changes.
