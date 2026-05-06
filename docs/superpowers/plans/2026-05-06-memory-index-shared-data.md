# Memory Index And Shared Data Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex more reliable at using Nino memory and shared household data without committing private memory contents.

**Architecture:** Add a Node.js memory index builder that scans live WSL memory paths and writes a metadata-only Markdown index. Add a Bash shared-data wrapper that centralizes allowed file access and git pull/commit/push behavior.

**Tech Stack:** Node.js, Jest, Bash, Markdown, git.

---

## File Structure

- Create: `scripts/build-memory-index.js`
  - Scans configured memory roots and writes `shared-context/MEMORY_INDEX.md`.
- Create: `scripts/shared-data.sh`
  - Supports `read`, `write`, and `append` for allowed shared-data files.
- Create: `tests/memory-index.test.js`
  - Tests generated index content using temporary fixture memory roots.
- Modify: `tests/operational-scripts.test.js`
  - Checks shared-data wrapper safety and git workflow.
- Modify: `shared-context/NINO_SHARED_CONTEXT.md`
  - Points Codex to `shared-context/MEMORY_INDEX.md` and `scripts/shared-data.sh`.
- Modify: `docs/codex-test-operations.md`, `PROGRESS.md`
  - Documents commands and verification.

## Task 1: Memory Indexer

- [x] Add failing Jest test for `scripts/build-memory-index.js`.
- [x] Implement metadata-only memory index generation.
- [x] Run targeted test and confirm pass.

## Task 2: Shared Data Wrapper

- [x] Add failing Jest expectations for `scripts/shared-data.sh`.
- [x] Implement allowed-file validation and read/write/append git workflow.
- [x] Run targeted tests and bash syntax check.

## Task 3: Docs And Verification

- [x] Update shared context and operations docs.
- [x] Run `node scripts/build-memory-index.js` once to generate `shared-context/MEMORY_INDEX.md`.
- [x] Run full `npm test` and bash syntax checks.
- [ ] Commit the work.
