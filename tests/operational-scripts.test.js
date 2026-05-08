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
    expect(startBackend).toContain('COMMAND="\\"$SCRIPT_DIR/start-codex-nino.sh\\""');
    expect(startBackend).toContain('TMUX_TARGET="=$SESSION"');
    expect(startBackend).toContain('TMUX_PANE_TARGET="=$SESSION:"');
    expect(startBackend).toContain('tmux has-session -t "$TMUX_TARGET"');

    expect(startNino).toContain('git reset --hard origin/main');
    expect(startNino).toContain('claude --model claude-opus-4-6 --dangerously-skip-permissions');
    expect(startNino).toContain('TMUX_TARGET="=$SESSION_NAME"');
    expect(startNino).toContain('CODEX_ENABLED="${CODEX_ENABLED:-false}"');
    expect(startNino).toContain('is_enabled "$CODEX_ENABLED"');
    expect(startNino).toContain('"$SCRIPT_DIR/start-backend.sh" codex');
    expect(startNino).toContain('systemctl --user restart nino-relay.service');
  });

  test('restart-backend respawns existing backend sessions or starts them when missing', () => {
    const restartBackend = script('restart-backend.sh');

    expect(restartBackend).toContain('case "$BACKEND" in');
    expect(restartBackend).toContain('TMUX_TARGET="=$SESSION"');
    expect(restartBackend).toContain('TMUX_PANE_TARGET="=$SESSION:"');
    expect(restartBackend).toContain('tmux has-session -t "$TMUX_TARGET"');
    expect(restartBackend).toContain('tmux respawn-pane -k -t "$TMUX_PANE_TARGET"');
    expect(restartBackend).toContain('claude --model claude-opus-4-6 --dangerously-skip-permissions --continue');
    expect(restartBackend).toContain('COMMAND="\\"$SCRIPT_DIR/start-codex-nino.sh\\""');
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
    expect(watchdog).toContain('local tmux_target="=$session"');
    expect(watchdog).toContain('ps -p "$pane_pid" -o args=');
    expect(watchdog).toContain('if [[ "$pane_command" == *"$process_pattern"* ]]');
    expect(watchdog).toContain('pgrep -P "$pane_pid" -f "$process_pattern"');
    expect(watchdog).toContain('check_claude_d_state "$CLAUDE_SESSION"');
    expect(watchdog).toContain('"$SCRIPT_DIR/restart-nino.sh"');
    expect(watchdog).toContain('"$SCRIPT_DIR/restart-backend.sh" "$backend"');
    expect(watchdog).toContain('scan_quota "claude" "$CLAUDE_SESSION"');
    expect(watchdog).toContain('scan_quota "codex" "$CODEX_SESSION"');
    expect(watchdog).toContain('"$SCRIPT_DIR/scan-backend-quota.sh" "$backend" "$session"');
    expect(watchdog).toContain('check_backend "codex" "$CODEX_SESSION" "codex"');
  });

  test('start-codex-nino launches Codex with Nino instructions as the initial prompt', () => {
    const startCodex = script('start-codex-nino.sh');

    expect(startCodex).toContain('codex-config/NINO_CODEX.md');
    expect(startCodex).toContain('CODEX_INSTRUCTIONS_FILE');
    expect(startCodex).toContain('shared-context/NINO_SHARED_CONTEXT.md');
    expect(startCodex).toContain('CODEX_SHARED_CONTEXT_FILE');
    expect(startCodex).toContain('prompt+=$');
    expect(startCodex).toContain('codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox "$prompt"');
    expect(startCodex).toContain('/home/bpx27/discord-bot-nino/src/discord-send -c CHANNEL_ID -r MESSAGE_ID');
  });

  test('shared-data wrapper limits files and performs git sync workflow', () => {
    const sharedData = script('shared-data.sh');

    expect(sharedData).toContain('SHARED_DATA_DIR="${SHARED_DATA_DIR:-/home/bpx27/yaksu-shared-data}"');
    expect(sharedData).toContain('todo-list.md|shopping-list.md|pantry.md|purchase-history.md');
    expect(sharedData).toContain('git -C "$SHARED_DATA_DIR" pull --rebase');
    expect(sharedData).toContain('git -C "$SHARED_DATA_DIR" add -- "$file"');
    expect(sharedData).toContain('git -C "$SHARED_DATA_DIR" commit -m');
    expect(sharedData).toContain('git -C "$SHARED_DATA_DIR" push');
    expect(sharedData).toContain('case "$command" in');
    expect(sharedData).toContain('read)');
    expect(sharedData).toContain('write)');
    expect(sharedData).toContain('append)');
  });

  test('backend-status script manages provider-neutral runtime status files', () => {
    const backendStatus = script('backend-status.sh');

    expect(backendStatus).toContain('STATUS_DIR="${BACKEND_STATUS_DIR:-$BOT_DIR/runtime/backend-status}"');
    expect(backendStatus).toContain('set|clear|show|list');
    expect(backendStatus).toContain('quota_exhausted|cooldown|maintenance|disabled|ready');
    expect(backendStatus).toContain('"state": "$state"');
    expect(backendStatus).toContain('"reason": "$reason"');
    expect(backendStatus).toContain('"until": "$until"');
    expect(backendStatus).toContain('rm -f "$status_file"');
  });

  test('backend quota scanner can mark any backend quota_exhausted from tmux output', () => {
    const scanner = script('scan-backend-quota.sh');

    expect(scanner).toContain('tmux capture-pane');
    expect(scanner).toContain('usage limit reached|rate limit|quota exceeded|limit reached|try again later|too many requests|insufficient_quota');
    expect(scanner).toContain('backend-status.sh" set "$backend" quota_exhausted');
    expect(scanner).toContain('QUOTA_COOLDOWN_UNTIL');
  });
});
