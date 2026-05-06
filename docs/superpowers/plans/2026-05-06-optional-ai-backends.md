# Optional AI Backends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude and Codex optional Nino AI backends without breaking the current Claude-based WSL/tmux operation.

**Architecture:** Add a provider-neutral backend contract and router first, then wrap the current Claude tmux behavior as the first adapter. Codex is added only after config validation, routing, health, and duplicate-response ownership are tested.

**Tech Stack:** Node.js CommonJS, discord.js, tmux, bash scripts, Jest or Node-compatible test runner.

---

## Files

- Create: `package.json` for repeatable test commands.
- Modify: `tests/*.test.js` require paths so existing tests run.
- Create: `src/backends/config.js` for backend configuration parsing and validation.
- Create: `src/backends/tmux.js` for shared tmux transport helpers.
- Create: `src/backends/claude.js` for current Claude behavior behind an adapter.
- Create: `src/backends/codex.js` after Claude adapter is tested.
- Create: `src/backends/router.js` for backend selection and request ownership.
- Modify: `src/discord-relay.js` to call the router instead of `tmux send-keys` directly.
- Modify: `src/health.js` and `src/health-checker.js` to report backend-neutral health.
- Modify later: `scripts/start-nino.sh`, `scripts/restart-nino.sh`, `scripts/nino-watchdog.sh`.
- Defer: shared memory migration, hooks/skills migration, setup/restore generalization.

## Task 1: Restore Test Baseline

**Files:**
- Create: `package.json`
- Modify: `tests/health.test.js`
- Modify: `tests/health-checker.test.js`
- Modify: `tests/auto-pull.test.js`

- [ ] **Step 1: Add package metadata and test command**

Create `package.json`:

```json
{
  "name": "discord-bot-nino",
  "private": true,
  "type": "commonjs",
  "scripts": {
    "test": "jest --runInBand"
  },
  "dependencies": {
    "discord.js": "^14.0.0",
    "dotenv": "^16.0.0"
  },
  "devDependencies": {
    "jest": "^30.0.0"
  }
}
```

- [ ] **Step 2: Fix test imports**

Change:

```js
require('../health')
require('../health-checker')
require('./auto-pull')
```

to:

```js
require('../src/health')
require('../src/health-checker')
require('../src/auto-pull')
```

- [ ] **Step 3: Run baseline tests**

Run:

```bash
npm install
npm test
```

Expected: existing tests pass or fail only because production behavior is currently inconsistent. Record failures in `PROGRESS.md`.

- [ ] **Step 4: Commit**

```bash
git add package.json tests
git commit -m "test: restore node test baseline"
```

## Task 2: Backend Config Schema

**Files:**
- Create: `src/backends/config.js`
- Create: `tests/backend-config.test.js`
- Modify: `.env.example`

- [ ] **Step 1: Write config tests**

Cover:
- `PRIMARY_BACKEND=claude` with Claude enabled.
- `PRIMARY_BACKEND=codex` with Codex enabled.
- Primary backend disabled rejects startup.
- Unknown fallback backend rejects startup.
- All backends disabled returns degraded mode, not healthy mode.

- [ ] **Step 2: Implement `loadBackendConfig(env)`**

Return:

```js
{
  primary: 'codex',
  fallback: ['claude'],
  backends: {
    claude: { enabled: true, session: 'nino-claude' },
    codex: { enabled: true, session: 'nino-codex' }
  },
  degraded: false
}
```

- [ ] **Step 3: Update `.env.example`**

Add:

```env
PRIMARY_BACKEND=claude
FALLBACK_BACKENDS=
CLAUDE_ENABLED=true
CODEX_ENABLED=false
CLAUDE_TMUX_SESSION=nino
CODEX_TMUX_SESSION=nino-codex
```

- [ ] **Step 4: Commit**

```bash
git add src/backends/config.js tests/backend-config.test.js .env.example
git commit -m "feat: add backend configuration schema"
```

## Task 3: Tmux Transport and Claude Adapter

**Files:**
- Create: `src/backends/tmux.js`
- Create: `src/backends/claude.js`
- Create: `tests/tmux-backend.test.js`
- Create: `tests/claude-backend.test.js`

- [ ] **Step 1: Test tmux command construction**

Mock `child_process.execSync` and verify:
- session health calls `tmux has-session`.
- send escapes single quotes safely.
- process lookup uses provider process pattern.

- [ ] **Step 2: Implement tmux helpers**

Expose:

```js
checkSession(sessionName)
sendKeys(sessionName, payload)
getChildPid(sessionName, processPattern)
```

- [ ] **Step 3: Implement Claude adapter**

Adapter fields:

```js
id = 'claude'
processPattern = 'claude'
health(config)
send(request, config)
restart(config)
```

It must preserve the existing `tmux send-keys` behavior.

- [ ] **Step 4: Commit**

```bash
git add src/backends/tmux.js src/backends/claude.js tests
git commit -m "feat: wrap claude tmux backend"
```

## Task 4: Backend Router and Request Ownership

**Files:**
- Create: `src/backends/router.js`
- Create: `tests/backend-router.test.js`
- Modify: `src/discord-relay.js`

- [ ] **Step 1: Test routing without fallback**

Given Claude primary and Codex disabled, router sends to Claude.

- [ ] **Step 2: Test disabled primary**

Given primary disabled, router tries the first enabled healthy fallback; if no fallback can route, it returns an explicit unavailable result and does not send.

- [ ] **Step 3: Test fallback lease**

Given primary unhealthy and fallback healthy, router sends to fallback and records `backend_id`.

- [ ] **Step 4: Test duplicate suppression state**

Given request state is already `completed`, router ignores later completion from any backend.

- [ ] **Step 5: Implement router**

Use in-memory state first. Durable JSONL can be added in a later task after behavior is correct.

- [ ] **Step 6: Replace direct relay tmux send**

In `src/discord-relay.js`, replace direct `sendToTmux` internals with router call while keeping the public function name temporarily for minimal diff.

- [ ] **Step 7: Commit**

```bash
git add src/backends/router.js src/discord-relay.js tests/backend-router.test.js
git commit -m "feat: route discord messages through backend router"
```

## Task 5: Provider-Neutral Health

**Files:**
- Modify: `src/health.js`
- Modify: `src/health-checker.js`
- Modify: `tests/health.test.js`
- Modify: `tests/health-checker.test.js`

- [ ] **Step 1: Test new health shape**

Expected health includes:

```json
{
  "primary_backend": "claude",
  "backends": {
    "claude": { "enabled": true, "alive": true, "pid": 123 },
    "codex": { "enabled": false, "alive": false, "pid": null }
  }
}
```

- [ ] **Step 2: Keep backward-compatible fields temporarily**

Keep `tmux_alive` and `claude_pid` for existing external health consumers, but mark them legacy in code comments.

- [ ] **Step 3: Update health checker analysis**

Alert on:
- no enabled backend alive
- primary backend unhealthy
- relay stale

Do not alert on disabled backends.

- [ ] **Step 4: Commit**

```bash
git add src/health.js src/health-checker.js tests
git commit -m "feat: report provider-neutral backend health"
```

## Task 6: Codex Adapter in Test Mode

**Files:**
- Create: `src/backends/codex.js`
- Create: `tests/codex-backend.test.js`
- Modify: `src/backends/router.js`
- Modify: `.env.example`

- [ ] **Step 1: Test Codex adapter command behavior**

Verify process pattern is `codex`, session defaults to `nino-codex`, and send uses tmux transport.

- [ ] **Step 2: Implement Codex adapter**

Use existing tmux transport. Do not change production default to Codex yet.

- [ ] **Step 3: Add test-channel routing**

Support:

```env
CODEX_TEST_CHANNELS=1480479067881865347
```

Messages from those channels route to Codex when Codex is enabled.

- [ ] **Step 4: Commit**

```bash
git add src/backends/codex.js src/backends/router.js tests/codex-backend.test.js .env.example
git commit -m "feat: add codex backend test routing"
```

## Task 7: Operational Scripts Follow-Up

**Files:**
- Modify: `scripts/start-nino.sh`
- Modify: `scripts/restart-nino.sh`
- Modify: `scripts/nino-watchdog.sh`
- Add if needed: `scripts/start-backend.sh`
- Add if needed: `scripts/restart-backend.sh`

- [ ] **Step 1: Do not remove current Claude scripts**

Preserve current commands until Codex is verified.

- [ ] **Step 2: Add backend-specific start script**

Start Claude or Codex based on an argument:

```bash
scripts/start-backend.sh claude
scripts/start-backend.sh codex
```

- [ ] **Step 3: Make watchdog backend-aware**

Watch enabled backends only. Disabled backend failure is not an alert.

- [ ] **Step 4: Commit**

```bash
git add scripts
git commit -m "feat: add backend-aware operating scripts"
```

## Deferred Tasks

- Shared memory migration.
- Claude hook to Codex wrapper approximation.
- Provider-specific auth/usage checks.
- Setup/restore rewrite.
- Security hardening beyond documented trusted-channel policy.
