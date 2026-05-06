# Provider Neutral Failover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make backend failover provider-neutral so any primary backend can fall back to configured secondary backends when unavailable, quota-exhausted, cooled down, or timed out.

**Architecture:** Add runtime backend status files and route selection that excludes blocked backends. Add a timeout fallback route path that skips the current owner and tries later configured backends. Keep duplicate-response protection through request ownership.

**Tech Stack:** Node.js, Jest, Bash, tmux-backed providers.

---

## File Structure

- Create: `src/backends/runtime-status.js`
  - Reads `runtime/backend-status/<backend>.json` and decides whether the backend is blocked.
- Create: `tests/backend-runtime-status.test.js`
  - Tests absent status, quota/cooldown blocks, and expired cooldown behavior.
- Modify: `src/backends/router.js`
  - Uses runtime status in `canRoute`.
  - Adds `routeFallback(request)` to skip the current owner and try later fallback backends.
- Modify: `tests/backend-router.test.js`
  - Tests quota/cooldown exclusion and timeout fallback behavior for arbitrary backend ids.
- Modify: `src/discord-relay.js`
  - Stores pending payloads and calls `routeFallback` after timeout before alerting.
- Create: `scripts/backend-status.sh`
  - Manual set/clear/list for runtime backend status.
- Modify: docs and progress files.

## Tasks

- [x] Add failing tests for runtime status blocking.
- [x] Implement `runtime-status.js`.
- [x] Add failing tests for router status exclusion and fallback-after-timeout API.
- [x] Implement router changes.
- [x] Add relay timeout fallback integration.
- [x] Add backend status script and static test coverage.
- [x] Update docs and run full verification.
