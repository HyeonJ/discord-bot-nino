/**
 * relay-addons/health-checker.js — 타봇(rund/haru) 헬스 감시 → 이상 시 DM 알림
 *
 * 니노 전용 addon (bot-core 공유 코어엔 없음 — health-server(자기 노출)만 있음).
 * 구 src/health-checker.js 로직을 bot-core addon 인터페이스로 포팅 (순수함수 100% 보존).
 * init(context)에서 폴링 시작. onMessage 불필요(자립형 poller).
 *
 * env:
 *   HEALTH_TARGETS   "rund:http://IP:58090,haru:http://IP:58090" (미설정 시 비활성)
 *   DISCORD_SEND_BIN discord-send 경로 (기본: cwd/src/discord-send)
 */
const http = require('http');
const { execSync } = require('child_process');

const DM_DARREN = 'DM-Darren';
const DM_TIM = 'DM-Tim';
const CHECK_INTERVAL_MS = 60 * 1000;
const STALE_THRESHOLD_MS = 90 * 1000;
const COOLDOWN_MS = 5 * 60 * 1000;

// 🔑 발송 실패를 **센다.** 로그 한 줄만으로는 "보냈다"와 "보내려다 실패했다"가 안 갈린다 —
//   여긴 감시기 자신의 알림 경로라, 실패가 조용하면 **그 실패조차 아무도 모른다.**
let alertSendFailureCount = 0;

// 봇별 알림 대상: rund 이상은 Tim에게, nino/haru 이상은 Darren에게
const OWNER_MAP = { rund: DM_TIM, nino: DM_DARREN, haru: DM_DARREN };

// 🔴 **호출 시점에 읽고, 없으면 지어내지 않는다** (2026-07-31).
//   전엔 `process.env.DISCORD_SEND_BIN || path.join(process.cwd(), 'src', 'discord-send')` 였다.
//   두 가지가 같이 얼었다 — env 와 **cwd**. relay 의 실제 cwd 는 systemd WorkingDirectory 인
//   `/home/bpx27/yaksu-bot-core-live` 라, 폴백은 **존재하지 않는 경로**를 만든다.
//   지금 안 터지는 건 `.env` 가 값을 덮고 있어서일 뿐이다 — 막아둔 게 아니라 안 밟고 있을 뿐.
//   🔑 레포 규칙: *"기본값 넣지 말고 필수면 에러로 안내"*. 틀린 기본값은 없는 것보다 나쁘다 —
//     설정을 빠뜨린 사람에게 **에러 대신 오작동**을 준다.
function discordSendBin() {
  const v = process.env.DISCORD_SEND_BIN;
  if (!v) {
    throw new Error(
      'DISCORD_SEND_BIN 이 설정되지 않았다 — 경보를 보낼 수 없다. .env 에 절대경로로 지정할 것'
    );
  }
  return v;
}

let checkInterval = null;
let startTimeout = null;
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
    const timeout = setTimeout(() => reject(new Error('timeout')), 10000);
    http.get(`${url}/health`, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        clearTimeout(timeout);
        try { resolve(JSON.parse(body)); } catch (e) { reject(new Error('invalid json')); }
      });
    }).on('error', (e) => { clearTimeout(timeout); reject(e); });
  });
}

// 🔴 **발송 실패를 삼키지 않는다** — `#88`(check-auth 가 실패를 삼키고 "보냈다"로 기록)과
//   같은 계약이다. 다만 여기는 **감시기 자신의 알림 경로**라 더 나쁘다: 실패하면
//   *"봇이 아프다"* 를 못 알리고, **그 실패조차 아무도 모른다.**
//   ⚠️ 던지지는 않는다(검사 루프가 죽으면 감시가 통째로 멈춘다). 대신 **성공 여부를 돌려준다** —
//     부르는 쪽이 셀 수 있어야 "보냈다"와 "보내려다 실패했다"가 갈린다.
function sendAlert(message, dmChannel) {
  try {
    const escaped = message.replace(/'/g, "'\\''");
    execSync(`${discordSendBin()} ${dmChannel} '${escaped}'`);
    return true;
  } catch (e) {
    console.error('[health-checker] alert send failed:', e.message);
    return false;
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
  if (data.tmux_alive === false) issues.push('tmux 세션 죽음');
  if (data.watcher_alive === false) issues.push('watcher 미실행 (프롬프트 얼림 위험)');
  if (data.claude_pid === null) issues.push('Claude PID 없음');
  return issues;
}

function shouldAlert(botName) {
  const lastAlert = lastAlertTime.get(botName) || 0;
  return Date.now() - lastAlert > COOLDOWN_MS;
}

async function checkBot(target) {
  let data = null;
  try { data = await fetchHealth(target.url); } catch (e) { /* 연결 실패 */ }
  const issues = analyzeHealth(target.name, data);
  if (issues.length > 0 && shouldAlert(target.name)) {
    const dmChannel = OWNER_MAP[target.name] || DM_DARREN;
    const issueList = issues.map(i => `• ${i}`).join('\n');
    const alert = `⚠️ **${target.name} 이상 감지**\n${issueList}\n확인 필요`;
    // 🔴 **반환값을 실제로 읽는다** (2026-07-31, 룬드 리뷰 M:eikt).
    //   전엔 `sendAlert(...)` 의 값을 버리고 아래 두 줄을 **무조건** 실행했다. 결과:
    //     ① `alert sent` 로그가 **실패해도** 남는다 — `#88`(발송 실패를 삼키고 "보냈다"로 기록) 그 자체
    //     ② `lastAlertTime.set` 이 **실패해도** 돌아 쿨다운이 시작된다 → 재시도가 5분 막힌다
    //   ⇒ 발송이 깨진 채로 "보냈다" 로그가 쌓이고, 그동안 재시도는 억제된다.
    //   🔑 *"셀 수 있게 만든 것"* 과 *"세는 것"* 은 다르다. 앞 절 시험은 `sendAlert` 직접 호출만
    //     잠갔고, 이 호출부는 그대로 둬도 초록이었다 — **만든 것이 배선한 것으로 자동 승격된다.**
    if (sendAlert(alert, dmChannel)) {
      lastAlertTime.set(target.name, Date.now());   // 쿨다운은 **보낸 뒤에만**
      console.log(`[health-checker] alert sent for ${target.name} via ${dmChannel}: ${issues.join(', ')}`);
    } else {
      alertSendFailureCount += 1;
      console.error(
        `[health-checker] ALERT-SEND-FAILED for ${target.name} via ${dmChannel} — ` +
        `쿨다운을 시작하지 않는다(다음 tick 에 재시도). 누적 ${alertSendFailureCount}건`
      );
    }
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
  startTimeout = setTimeout(checkAll, 30000);
}

function stopChecking() {
  if (checkInterval) { clearInterval(checkInterval); checkInterval = null; }
  if (startTimeout) { clearTimeout(startTimeout); startTimeout = null; }
}

module.exports = {
  name: 'health-checker',
  init() { startChecking(); },
  // 순수/테스트용 export (구 src/health-checker.js와 동일 시그니처)
  startChecking,
  sendAlert,        // 시험이 발송 축을 잴 수 있게 연다 (전엔 아무도 못 쟀다)
  alertSendFailures: () => alertSendFailureCount,
  discordSendBin,
  stopChecking,
  checkAll,
  fetchHealth,
  analyzeHealth,
  parseTargets,
};
