const http = require('http');
const { execSync } = require('child_process');
const { loadBackendConfig } = require('./backends/config');
const claude = require('./backends/claude');
const codex = require('./backends/codex');

const BOT_NAME = 'nino';
const HEALTH_PORT = parseInt(process.env.HEALTH_PORT || '58090', 10);

const startTime = Date.now();
let lastMessageAt = null;
let server = null;

function checkWatcherAlive() {
  try {
    const result = execSync('pgrep -f "auto-approve-claude.sh" 2>/dev/null')
      .toString().trim();
    return result.length > 0;
  } catch {
    return false;
  }
}

function disabledBackend(enabled = false) {
  return { enabled, sessionAlive: false, alive: false, pid: null };
}

function getBackendHealth() {
  try {
    const config = loadBackendConfig(process.env);
    return {
      primaryBackend: config.primary,
      backends: {
        claude: claude.health(config.backends.claude),
        codex: codex.health(config.backends.codex),
      },
      error: null,
    };
  } catch (error) {
    return {
      primaryBackend: null,
      backends: {
        claude: disabledBackend(false),
        codex: disabledBackend(false),
      },
      error: error.message,
    };
  }
}

function getHealthData() {
  const now = new Date();
  const kstOffset = 9 * 60 * 60 * 1000;
  const kstNow = new Date(now.getTime() + kstOffset);
  const backendHealth = getBackendHealth();

  const data = {
    bot: BOT_NAME,
    timestamp: kstNow.toISOString().replace('Z', '+09:00'),
    primary_backend: backendHealth.primaryBackend,
    backends: backendHealth.backends,
    // Legacy field for existing external health consumers. Use backends.claude.pid instead.
    claude_pid: backendHealth.backends.claude.pid,
    // Legacy field for existing external health consumers. Use backends.claude.sessionAlive instead.
    tmux_alive: backendHealth.backends.claude.sessionAlive,
    relay_alive: true,
    watcher_alive: checkWatcherAlive(),
    last_message_at: lastMessageAt,
    uptime: Math.floor((Date.now() - startTime) / 1000),
  };

  if (backendHealth.error) {
    data.error = backendHealth.error;
  }

  return data;
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
