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

function analyzeHealth(botName, data) {
  const issues = [];
  const now = Date.now();

  if (data === null) {
    issues.push('relay 응답 없음 (연결 실패 또는 타임아웃)');
    return issues;
  }

  if (data.timestamp) {
    const ts = new Date(data.timestamp).getTime();
    if (now - ts > STALE_THRESHOLD_MS) {
      issues.push(`timestamp ${Math.floor((now - ts) / 1000)}초 경과 (stale)`);
    }
  }

  if (data.tmux_alive === false) {
    issues.push('tmux 세션 죽음');
  }

  if (data.watcher_alive === false) {
    issues.push('watcher 미실행 (프롬프트 얼림 위험)');
  }

  if (data.claude_pid === null) {
    issues.push('Claude PID 없음');
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
    // 연결 실패
  }

  const issues = analyzeHealth(target.name, data);

  if (issues.length > 0 && shouldAlert(target.name)) {
    const dmChannel = OWNER_MAP[target.name] || DM_DARREN;
    const issueList = issues.map(i => `• ${i}`).join('\n');
    const alert = `⚠️ **${target.name} 이상 감지**\n${issueList}\n확인 필요`;
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
