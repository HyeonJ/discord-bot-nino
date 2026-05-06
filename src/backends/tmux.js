const childProcess = require('child_process');

function shellSingleQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function checkSession(sessionName) {
  try {
    childProcess.execSync(`tmux has-session -t ${shellSingleQuote(sessionName)} 2>/dev/null`);
    return true;
  } catch {
    return false;
  }
}

function parseSubmitDelaySeconds(value) {
  const delay = Number(value || 0);
  return Number.isFinite(delay) && delay > 0 ? delay : 0;
}

function sendKeys(sessionName, payload, options = {}) {
  try {
    childProcess.execSync(
      `tmux send-keys -t ${shellSingleQuote(sessionName)} -- ${shellSingleQuote(payload)}`
    );
    const submitDelaySeconds = parseSubmitDelaySeconds(options.submitDelaySeconds);
    if (submitDelaySeconds > 0) {
      childProcess.execSync(`sleep ${submitDelaySeconds}`);
    }
    childProcess.execSync(`tmux send-keys -t ${shellSingleQuote(sessionName)} Enter`);
    return true;
  } catch {
    return false;
  }
}

function getChildPid(sessionName, processPattern) {
  try {
    const paneResult = childProcess.execSync(
      `tmux list-panes -t ${shellSingleQuote(sessionName)} -F '#{pane_pid}' 2>/dev/null`
    ).toString().trim();
    const panePid = paneResult.split('\n')[0];
    if (!/^\d+$/.test(panePid)) {
      return null;
    }

    const paneCommand = childProcess.execSync(
      `ps -p ${panePid} -o args= 2>/dev/null || echo ""`
    ).toString().trim();
    if (paneCommand.includes(processPattern)) {
      return parseInt(panePid, 10);
    }

    const childResult = childProcess.execSync(
      `pgrep -P ${panePid} -f ${shellSingleQuote(processPattern)} 2>/dev/null || echo ""`
    ).toString().trim();
    const childPid = childResult.split('\n')[0];
    return /^\d+$/.test(childPid) ? parseInt(childPid, 10) : null;
  } catch {
    return null;
  }
}

module.exports = {
  checkSession,
  sendKeys,
  getChildPid,
};
