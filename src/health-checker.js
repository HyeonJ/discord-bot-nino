const http = require('http');
const { execSync } = require('child_process');

const SCRIPT_DIR = __dirname;
const DM_DARREN = 'DM-Darren';
const DM_TIM = 'DM-Tim';
const CHECK_INTERVAL_MS = 60 * 1000;
const STALE_THRESHOLD_MS = 90 * 1000;
const COOLDOWN_MS = 5 * 60 * 1000;

const OWNER_MAP = {
  rund: DM_TIM,
  nino: DM_DARREN,
  haru: DM_DARREN,
};

let checkInterval = null;
const lastAlertTime = new Map();

function parseTargets() {
  const raw = process.env.HEALTH_TARGETS || '';
  if (!raw) return [];
  return raw.split(',').map(entry => {
    const [name, url] = entry.split(':http://');
    return { name: name.trim(), url: `http://${url}` };
  }).filter(t => t.name && t.url);
}

function fetchHealth(url) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error('timeout'));
    }, 10000);

    http.get(`${url}/health`, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        clearTimeout(timeout);
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          reject(new Error('invalid json'));
        }
      });
    }).on('error', (e) => {
      clearTimeout(timeout);
      reject(e);
    });
  });
}

function sendAlert(message, dmChannel) {
  try {
    const escaped = message.replace(/'/g, "'\\''");
    execSync(`${SCRIPT_DIR}/discord-send -c ${dmChannel} '${escaped}'`);
  } catch (e) {
    console.error('[health-checker] alert send failed:', e.message);
  }
}

function analyzeBackendHealth(data, issues) {
  const backendEntries = Object.entries(data.backends);
  backendEntries
    .filter(([, backend]) => !backend || typeof backend !== 'object')
    .forEach(([backendId]) => {
      issues.push(`Backend ${backendId} health malformed`);
    });

  const enabledBackends = backendEntries.filter(([, backend]) => backend && backend.enabled === true);
  const enabledBackendAlive = enabledBackends.some(([, backend]) => backend.alive === true);

  if (!enabledBackendAlive) {
    issues.push('No enabled backend alive');
  }

  const primaryBackend = data.primary_backend;
  const primaryHealth = primaryBackend ? data.backends[primaryBackend] : null;
  if (primaryBackend && !Object.prototype.hasOwnProperty.call(data.backends, primaryBackend)) {
    issues.push(`Primary backend ${primaryBackend} missing from health payload`);
  } else if (primaryHealth && primaryHealth.enabled === true && primaryHealth.alive !== true) {
    issues.push(`Primary backend ${primaryBackend} unhealthy`);
  }
}

function analyzeLegacyHealth(data, issues) {
  if (data.tmux_alive === false) {
    issues.push('tmux session dead');
  }

  if (data.claude_pid === null) {
    issues.push('Claude PID missing');
  }
}

function analyzeHealth(botName, data) {
  const issues = [];
  const now = Date.now();

  if (data === null) {
    issues.push('relay response missing (connection failed or timeout)');
    return issues;
  }

  if (data.error) {
    issues.push(`Health payload error: ${data.error}`);
  }

  if (data.timestamp) {
    const ts = new Date(data.timestamp).getTime();
    if (now - ts > STALE_THRESHOLD_MS) {
      issues.push(`timestamp ${Math.floor((now - ts) / 1000)} seconds old (stale)`);
    }
  }

  if (data.backends && typeof data.backends === 'object') {
    analyzeBackendHealth(data, issues);
  } else {
    analyzeLegacyHealth(data, issues);
  }

  if (data.watcher_alive === false) {
    issues.push('watcher dead');
  }

  return issues;
}

function shouldAlert(botName) {
  const lastAlert = lastAlertTime.get(botName) || 0;
  return Date.now() - lastAlert > COOLDOWN_MS;
}

async function checkBot(target) {
  let data = null;
  try {
    data = await fetchHealth(target.url);
  } catch (e) {
    // Connection failed.
  }

  const issues = analyzeHealth(target.name, data);

  if (issues.length > 0 && shouldAlert(target.name)) {
    const dmChannel = OWNER_MAP[target.name] || DM_DARREN;
    const issueList = issues.map(i => `- ${i}`).join('\n');
    const alert = `Health issue detected for ${target.name}\n${issueList}\nPlease check.`;
    sendAlert(alert, dmChannel);
    lastAlertTime.set(target.name, Date.now());
    console.log(`[health-checker] alert sent for ${target.name} via ${dmChannel}: ${issues.join(', ')}`);
  }
}

async function checkAll() {
  const targets = parseTargets();
  if (targets.length === 0) return;

  for (const target of targets) {
    await checkBot(target);
  }
}

function startChecking() {
  const targets = parseTargets();
  if (targets.length === 0) {
    console.log('[health-checker] no targets configured, skipping');
    return;
  }
  console.log(`[health-checker] monitoring ${targets.map(t => t.name).join(', ')}`);
  checkInterval = setInterval(checkAll, CHECK_INTERVAL_MS);
  setTimeout(checkAll, 30000);
}

function stopChecking() {
  if (checkInterval) {
    clearInterval(checkInterval);
    checkInterval = null;
  }
}

module.exports = {
  startChecking,
  stopChecking,
  checkAll,
  fetchHealth,
  analyzeHealth,
  parseTargets,
};
