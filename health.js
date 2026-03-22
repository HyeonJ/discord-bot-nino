const http = require('http');
const { execSync } = require('child_process');

const BOT_NAME = 'nino';
const TMUX_SESSION = process.env.TMUX_SESSION || 'nino';
const HEALTH_PORT = parseInt(process.env.HEALTH_PORT || '58090', 10);

const startTime = Date.now();
let lastMessageAt = null;
let server = null;

function checkTmuxAlive() {
  try {
    execSync(`tmux has-session -t '${TMUX_SESSION}' 2>/dev/null`);
    return true;
  } catch {
    return false;
  }
}

function getClaudePid() {
  try {
    const result = execSync(
      `tmux list-panes -t '${TMUX_SESSION}' -F '#{pane_pid}' 2>/dev/null`
    ).toString().trim();
    const panePid = result.split('\n')[0];
    const children = execSync(
      `pgrep -P ${panePid} -f claude 2>/dev/null || echo ""`
    ).toString().trim();
    return children ? parseInt(children.split('\n')[0], 10) : null;
  } catch {
    return null;
  }
}

function checkWatcherAlive() {
  try {
    const result = execSync('pgrep -f "auto-approve-claude.sh" 2>/dev/null')
      .toString().trim();
    return result.length > 0;
  } catch {
    return false;
  }
}

function getHealthData() {
  const now = new Date();
  const kstOffset = 9 * 60 * 60 * 1000;
  const kstNow = new Date(now.getTime() + kstOffset);

  return {
    bot: BOT_NAME,
    timestamp: kstNow.toISOString().replace('Z', '+09:00'),
    claude_pid: getClaudePid(),
    tmux_alive: checkTmuxAlive(),
    relay_alive: true,
    watcher_alive: checkWatcherAlive(),
    last_message_at: lastMessageAt,
    uptime: Math.floor((Date.now() - startTime) / 1000),
  };
}

function start() {
  server = http.createServer((req, res) => {
    if (req.url === '/health' && req.method === 'GET') {
      const data = getHealthData();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data));
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  server.listen(HEALTH_PORT, () => {
    console.log(`[health] listening on port ${HEALTH_PORT}`);
  });

  return server;
}

function stop(callback) {
  if (server) {
    server.close(callback);
  } else if (callback) {
    callback();
  }
}

function setLastMessageAt() {
  const now = new Date();
  const kstOffset = 9 * 60 * 60 * 1000;
  const kstNow = new Date(now.getTime() + kstOffset);
  lastMessageAt = kstNow.toISOString().replace('Z', '+09:00');
}

module.exports = { start, stop, setLastMessageAt, getHealthData };
