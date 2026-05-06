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

function sendKeys(sessionName, payload) {
  try {
    childProcess.execSync(
      `tmux send-keys -t ${shellSingleQuote(sessionName)} -- ${shellSingleQuote(payload)} C-m`
    );
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
