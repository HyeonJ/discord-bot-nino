/**
 * relay-addons/pending-response.js — 미응답 메시지 추적 + 리마인더
 *
 * 니노 전용 addon (bot-core 코어엔 없음). 구 discord-relay.js의 pendingResponses 로직 포팅.
 * - 등록: 사람 메시지(봇 아님) & 나(니노)한테 온 것(남 멘션 아님) → onMessage 훅
 * - 해제: 같은 채널에 자기(니노) 또는 다른 봇 메시지가 오면 → 그 채널 pending 제거
 *         (자기 메시지는 core onMessage 미호출 → init에서 client.messageCreate 자체 리스너로 처리)
 * - 타임아웃: 10초마다 체크, 3분 경과 시 tmux 알림 후 제거
 * - 리마인더: 30분마다 미응답 있으면 tmux 알림
 *
 * env: DISCORD_APP_ID (봇 자신 ID — 자기 메시지 판별)
 */
const RESPONSE_TIMEOUT_MS = 3 * 60 * 1000;
const REMINDER_INTERVAL_MS = 30 * 60 * 1000;
const TIMEOUT_CHECK_MS = 10 * 1000;

const BOT_ID = process.env.DISCORD_APP_ID || '';

// msgId → { channelId, timestamp, preview }
const pending = new Map();

/** 스레드면 스레드 id, 아니면 채널 id (구 relay와 동일: pending은 스레드 단위로 추적) */
function channelIdOf(msg) {
  if (msg.channel && typeof msg.channel.isThread === 'function' && msg.channel.isThread()) {
    return msg.channel.id;
  }
  return msg.channelId != null ? msg.channelId : (msg.channel && msg.channel.id);
}

/** 이 메시지를 pending에 등록해야 하나 — 순수 판정 (사람 & 남 멘션 아님) */
function shouldRegister({ isBot, isSelf, mentionsOther }) {
  if (isBot || isSelf) return false;   // 봇/자기 메시지는 등록 안 함
  if (mentionsOther) return false;     // 남(@Tim/@Darren 등) 멘션 = 나한테 하는 말 아닐 확률↑
  return true;
}

/** msg가 나 아닌 다른 유저를 멘션하는지 (discord.js Collection 또는 배열 모두 허용) */
function mentionsOtherUser(msg, botId) {
  const users = msg && msg.mentions && msg.mentions.users;
  if (!users) return false;
  const ids = typeof users.map === 'function'
    ? [...(typeof users.values === 'function' ? users.values() : users)].map(u => u.id)
    : [];
  return ids.some(id => id !== botId);
}

function registerPending(store, msgId, channelId, preview) {
  if (!msgId || channelId == null) return;
  store.set(msgId, { channelId, timestamp: Date.now(), preview });
}

/** 해당 채널의 모든 pending 제거 → 제거한 개수 */
function clearChannel(store, channelId) {
  let n = 0;
  for (const [id, info] of store) {
    if (info.channelId === channelId) { store.delete(id); n++; }
  }
  return n;
}

/** 타임아웃(경과 timeoutMs 초과) 항목을 store에서 빼고 배열로 반환 */
function collectTimedOut(store, now, timeoutMs) {
  const out = [];
  for (const [id, info] of store) {
    if (now - info.timestamp > timeoutMs) { store.delete(id); out.push({ msgId: id, info }); }
  }
  return out;
}

/** 미응답 리마인더 문자열 (없으면 null) */
function buildReminder(store) {
  if (store.size === 0) return null;
  const previews = [...store.values()].map(v => `- ${v.preview}`).join('\n');
  return `[SYSTEM] ⏰ 리마인더: 아직 응답 못 한 메시지 ${store.size}개 있어!\n${previews}`;
}

function previewOf(result, msg) {
  const base = (result && result.formatted) || (msg && msg.content) || '';
  return base.substring(0, 80).replace(/\n/g, ' ');
}

let timeoutTimer = null;
let reminderTimer = null;

module.exports = {
  name: 'pending-response',

  // 사람 메시지 등록 + 다른 봇 메시지로 해제 (core onMessage는 self 미호출)
  onMessage(result, msg) {
    const isBot = !!(msg.author && msg.author.bot);
    const botId = BOT_ID;
    if (isBot) {
      // 다른 봇이 응답 → 해당 채널 pending 해제
      clearChannel(pending, channelIdOf(msg));
      return;
    }
    if (shouldRegister({ isBot, isSelf: false, mentionsOther: mentionsOtherUser(msg, botId) })) {
      registerPending(pending, msg.id, channelIdOf(msg), previewOf(result, msg));
    }
  },

  init(context) {
    const sendToTmux = context.sendToTmux;
    const client = context.client;

    // 자기(니노) 메시지가 채널에 뜨면 = 응답함 → pending 해제 (onMessage는 self 미호출이라 여기서)
    if (client && typeof client.on === 'function') {
      client.on('messageCreate', (msg) => {
        if (msg.author && msg.author.id === BOT_ID) {
          clearChannel(pending, channelIdOf(msg));
        }
      });
    }

    // 3분 타임아웃 → tmux 알림
    timeoutTimer = setInterval(() => {
      const timedOut = collectTimedOut(pending, Date.now(), RESPONSE_TIMEOUT_MS);
      for (const { info } of timedOut) {
        try { sendToTmux(`[SYSTEM] ⚠️ 응답 못 한 메시지 있어! 확인해줘: ${info.preview}`); } catch (e) {}
      }
    }, TIMEOUT_CHECK_MS);

    // 30분 리마인더
    reminderTimer = setInterval(() => {
      const reminder = buildReminder(pending);
      if (reminder) { try { sendToTmux(reminder); } catch (e) {} }
    }, REMINDER_INTERVAL_MS);
  },

  stop() {
    if (timeoutTimer) { clearInterval(timeoutTimer); timeoutTimer = null; }
    if (reminderTimer) { clearInterval(reminderTimer); reminderTimer = null; }
  },

  // 테스트용 export
  _pending: pending,
  channelIdOf,
  shouldRegister,
  mentionsOtherUser,
  registerPending,
  clearChannel,
  collectTimedOut,
  buildReminder,
};
