const childProcess = require('child_process');

function shellSingleQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function isMissingTmuxSessionError(error) {
  const message = error && error.message ? error.message : '';
  return (
    message.includes('no server running') ||
    message.includes("can't find") ||
    message.includes('not found')
  );
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
  } catch (error) {
    if (isMissingTmuxSessionError(error)) {
      return false;
    }
    throw error;
  }
}

function getChildPid(sessionName, processPattern) {
  try {
    const paneResult = childProcess.execSync(
      `tmux list-panes -t ${shellSingleQuote(sessionName)} -F '#{pane_pid}' 2>/dev/null`
    ).toString().trim();
    const panePid = paneResult.split('\n')[0];
    if (!panePid) {
      return null;
    }

    const childResult = childProcess.execSync(
      `pgrep -P ${panePid} -f ${shellSingleQuote(processPattern)} 2>/dev/null || echo ""`
    ).toString().trim();
    return childResult ? parseInt(childResult.split('\n')[0], 10) : null;
  } catch {
    return null;
  }
}

module.exports = {
  checkSession,
  sendKeys,
  getChildPid,
};
