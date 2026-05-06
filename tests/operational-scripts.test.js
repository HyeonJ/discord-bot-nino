const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const script = (name) => fs.readFileSync(path.join(root, 'scripts', name), 'utf8');

describe('operational backend scripts', () => {
  test('start-backend can launch Claude or Codex sessions without replacing start-nino', () => {
    const startBackend = script('start-backend.sh');
    const startNino = script('start-nino.sh');

    expect(startBackend).toContain('case "$BACKEND" in');
    expect(startBackend).toContain('CLAUDE_TMUX_SESSION:-${TMUX_SESSION:-nino}');
    expect(startBackend).toContain('CODEX_TMUX_SESSION:-nino-codex');
    expect(startBackend).toContain('claude --model claude-opus-4-6 --dangerously-skip-permissions');
    expect(startBackend).toContain('codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox');

    expect(startNino).toContain('git reset --hard origin/main');
    expect(startNino).toContain('claude --model claude-opus-4-6 --dangerously-skip-permissions');
    expect(startNino).toContain('systemctl --user restart nino-relay.service');
  });

  test('restart-backend respawns existing backend sessions or starts them when missing', () => {
    const restartBackend = script('restart-backend.sh');

    expect(restartBackend).toContain('case "$BACKEND" in');
    expect(restartBackend).toContain('tmux has-session -t "$SESSION"');
    expect(restartBackend).toContain('tmux respawn-pane -k -t "$SESSION"');
    expect(restartBackend).toContain('claude --model claude-opus-4-6 --dangerously-skip-permissions --continue');
    expect(restartBackend).toContain('codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox');
    expect(restartBackend).toContain('"$SCRIPT_DIR/start-backend.sh" "$BACKEND"');
  });

  test('watchdog watches only enabled backends and keeps Claude D-state handling Claude-only', () => {
    const watchdog = script('nino-watchdog.sh');

    expect(watchdog).toContain('CLAUDE_ENABLED="${CLAUDE_ENABLED:-true}"');
    expect(watchdog).toContain('CODEX_ENABLED="${CODEX_ENABLED:-false}"');
    expect(watchdog).toContain('LEGACY_CLAUDE_SESSION="nino"');
    expect(watchdog).toContain('is_enabled "$CLAUDE_ENABLED"');
    expect(watchdog).toContain('is_enabled "$CODEX_ENABLED"');
    expect(watchdog).toContain('check_backend "claude" "$CLAUDE_SESSION"');
    expect(watchdog).toContain('check_backend "codex" "$CODEX_SESSION"');
    expect(watchdog).toContain('check_claude_d_state "$CLAUDE_SESSION"');
    expect(watchdog).toContain('"$SCRIPT_DIR/restart-nino.sh"');
    expect(watchdog).toContain('"$SCRIPT_DIR/restart-backend.sh" "$backend"');
    expect(watchdog).not.toContain('pgrep -P "$PANE_PID" -f "codex"');
  });
});
