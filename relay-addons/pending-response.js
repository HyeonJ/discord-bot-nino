/**
 * relay-addons/pending-response.js — 미응답 메시지 추적 + 리마인더
 *
 * 니노 전용 addon (bot-core 코어엔 없음). 구 discord-relay.js의 pendingResponses 로직 포팅.
 * - 등록: 사람 메시지(봇 아님) & 나(니노)한테 온 것(남 멘션 아님) → onMessage 훅
 * - 해제: 같은 채널에 자기(니노) 또는 다른 봇 메시지가 오면 → 그 채널 pending 제거
 *         (자기 메시지는 core onMessage 미호출 → init에서 client.messageCreate 자체 리스너로 처리)
 * - 타임아웃: 10초마다 체크, PENDING_RESPONSE_SEC(기본 180초) 경과 시 tmux 알림 후 제거
 * - 리마인더: 30분마다 미응답 있으면 tmux 알림
 *
 * env:
 *   DISCORD_APP_ID       봇 자신 ID (자기 메시지 판별)
 *   PENDING_RESPONSE_SEC 미응답 알림 타임아웃(초, 기본 180). **이 노브의 소유자는 이 addon이다** —
 *     코어(relay/index.js)는 같은 env를 읽어놓고 쓰지 않아 "조용히 무시되는 노브"였다(코어 PR #57에서
 *     발견). 기능이 있는 곳이 노브를 소유한다는 합의(룬드 M:o31q)로 여기로 이전. 코어 쪽 const 제거는
 *     이 배선이 머지된 뒤 룬드가 진행.
 */
const DEFAULT_RESPONSE_TIMEOUT_SEC = 180;
const REMINDER_INTERVAL_MS = 30 * 60 * 1000;
const TIMEOUT_CHECK_MS = 10 * 1000;
// 다른 봇이 이 안에 발화한 채널이면 평문은 그 봇 대화로 본다.
// 미응답 타임아웃(기본 180초)보다 넉넉히 커야 뜻이 있다 — 대화가 몇 분 간격으로 이어지기 때문.
const BOT_ACTIVE_WINDOW_MS = 10 * 60 * 1000;

// 🔴 **호출 시점에 읽는다** — 모듈 최상단 상수로 두면 `require` 순간에 얼어붙는다(2026-07-31).
//   시험 파일 두 개가 이 모듈을 require 하는데, env 를 심기 전에 로드되는 쪽이 있으면
//   `BOT_ID=''` 로 굳어 자기 메시지 판별이 통째로 죽는다. 룬드 맥에서 전체 실행 1 fail /
//   단독 39 pass 로 나타났고, 내 기계에선 로드 순서가 달라 **보이지 않았다.**
//   🔑 시험 파일 1행에 *"require 보다 먼저 심는다"* 라고 **적혀 있었다** — 알고 적어뒀지만
//     고친 게 아니라 순서로 피한 것이고, 그 회피는 이 파일이 먼저 로드될 때만 성립한다.
//   ⇒ 고칠 것은 로드 순서가 아니라 **얼리는 형태**다. 읽는 값은 읽을 때 읽는다.
function botId() {
  return process.env.DISCORD_APP_ID || '';
}

/**
 * PENDING_RESPONSE_SEC 해석 — 초 단위 **양의 정수**만 채택.
 * 반환 `{ ms, source }`의 source는 왜 그 값이 됐는지: env(채택) / default(미설정·빈값) / invalid(값이 있으나 무효).
 * invalid를 default와 구분하는 이유: 잘못 준 값이 조용히 무시되면 이 노브가 또 "있는 척"이 된다.
 * 빈 문자열을 default로 보는 건 셔틀 env 관례(`${VAR:-기본}`)와 일치시킨 것.
 */
function resolveTimeoutMs(raw) {
  const fallback = DEFAULT_RESPONSE_TIMEOUT_SEC * 1000;
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return { ms: fallback, source: 'default' };
  }
  const s = String(raw).trim();
  if (!/^\d+$/.test(s)) return { ms: fallback, source: 'invalid' };  // 소수·음수·비숫자 전부 무효
  const sec = Number(s);
  if (!Number.isSafeInteger(sec) || sec <= 0) return { ms: fallback, source: 'invalid' };
  return { ms: sec * 1000, source: 'env' };
}

// msgId → { channelId, timestamp, preview }
const pending = new Map();

/** 스레드면 스레드 id, 아니면 채널 id (구 relay와 동일: pending은 스레드 단위로 추적) */
function channelIdOf(msg) {
  if (msg.channel && typeof msg.channel.isThread === 'function' && msg.channel.isThread()) {
    return msg.channel.id;
  }
  return msg.channelId != null ? msg.channelId : (msg.channel && msg.channel.id);
}

/**
 * 이 메시지를 pending에 등록해야 하나 — 순수 판정.
 *
 * 예전엔 (사람 & 남 멘션 아님)만 봤다. 그래서 **멘션이 하나도 없는 평문**은 전부 "나한테 온 말"이
 * 됐고, Tim이 룬드에게 평문으로 말하면 내 미응답 경고가 남의 대화에 떴다(Darren 지시 2026-07-30).
 * 해제 경로(다른 봇이 답하면 clear)로는 못 막는다 — 등록~해제 **사이**에 타임아웃이 먼저 온다.
 * ⇒ 상대 봇이 답할 대화로 보이면 등록 자체를 안 한다.
 *
 * 판정 순서에 의미가 있다: 앞단 게이트(봇/자기) → 강한 긍정(나 멘션) → 억제 신호들.
 * mentionsMe가 mentionsOther보다 앞인 이유: "@니노 @Darren 확인해줘"는 나한테 온 말이다.
 * 억제 신호가 전부 없으면(= 판정 불가) 등록한다 — 놓치는 쪽보다 뜨는 쪽이 복구가 싸다.
 */
function shouldRegister({ isBot, isSelf, mentionsOther, mentionsMe, repliesToOtherBot, otherBotActive }) {
  if (isBot || isSelf) return false;   // 봇/자기 메시지는 등록 안 함
  if (mentionsMe) return true;         // 나를 부른 건 아래 억제 신호를 전부 이긴다
  if (mentionsOther) return false;     // 남(@Tim/@Darren 등) 멘션 = 나한테 하는 말 아닐 확률↑
  if (repliesToOtherBot) return false; // 다른 봇 메시지에 답장 = 그 봇과의 대화
  if (otherBotActive) return false;    // 그 채널에서 다른 봇이 최근 발화 = 그 봇이 답할 대화
  return true;
}

/** msg가 나(니노)를 멘션하는지 */
function mentionsMeUser(msg, botId) {
  const users = msg && msg.mentions && msg.mentions.users;
  if (!users) return false;
  const ids = typeof users.map === 'function'
    ? [...(typeof users.values === 'function' ? users.values() : users)].map(u => u.id)
    : [];
  return ids.some(id => id === botId);
}

/**
 * 답장 대상이 **나 아닌 봇**인지.
 * discord.js는 답장이고 원 작성자가 멘션될 때 mentions.repliedUser를 채운다 —
 * 답장 핑이 꺼져 있으면 비어 있다. 없으면 false(판정 불가)로 두고 otherBotActive가 받는다.
 */
function repliesToOtherBot(msg, botId) {
  const r = msg && msg.mentions && msg.mentions.repliedUser;
  if (!r) return false;
  return !!r.bot && r.id !== botId;
}

/** channelId → 다른 봇이 마지막으로 발화한 시각(ms) */
const botSpeakers = new Map();

function noteBotSpeaker(store, channelId, now) {
  if (channelId == null) return;
  store.set(channelId, now);
}

/** 그 채널에서 다른 봇이 windowMs 안에 발화했나 (경계 포함 = 활성) */
function isOtherBotActive(store, channelId, now, windowMs) {
  const last = store.get(channelId);
  if (last === undefined) return false;
  return now - last <= windowMs;
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
  botId,   // 시험이 로드 순서 의존을 잠그는 데 쓴다 (얼지 않았음을 확인)

  // 사람 메시지 등록 + 다른 봇 메시지로 해제 (core onMessage는 self 미호출)
  onMessage(result, msg) {
    const isBot = !!(msg.author && msg.author.bot);
    const myId = botId();
    const channelId = channelIdOf(msg);
    if (isBot) {
      // 다른 봇이 응답 → 해당 채널 pending 해제 + 발화 시각 기록(이후 평문 억제용)
      clearChannel(pending, channelId);
      noteBotSpeaker(botSpeakers, channelId, Date.now());
      return;
    }
    const register = shouldRegister({
      isBot,
      isSelf: false,
      mentionsMe: mentionsMeUser(msg, myId),
      mentionsOther: mentionsOtherUser(msg, myId),
      repliesToOtherBot: repliesToOtherBot(msg, myId),
      otherBotActive: isOtherBotActive(botSpeakers, channelId, Date.now(), BOT_ACTIVE_WINDOW_MS),
    });
    if (register) {
      registerPending(pending, msg.id, channelId, previewOf(result, msg));
    }
  },

  init(context) {
    const sendToTmux = context.sendToTmux;
    const client = context.client;

    // 자기(니노) 메시지가 채널에 뜨면 = 응답함 → pending 해제 (onMessage는 self 미호출이라 여기서)
    if (client && typeof client.on === 'function') {
      client.on('messageCreate', (msg) => {
        if (msg.author && msg.author.id === botId()) {
          clearChannel(pending, channelIdOf(msg));
        }
      });
    }

    // 타임아웃 값 결정 + **반드시 알림**(조용한 무시가 이 노브의 원래 병이었음)
    const { ms: responseTimeoutMs, source } = resolveTimeoutMs(process.env.PENDING_RESPONSE_SEC);
    if (source === 'invalid') {
      console.warn(
        `[pending-response] PENDING_RESPONSE_SEC 값이 무효라 무시함: "${process.env.PENDING_RESPONSE_SEC}"`
        + ` → 기본 ${DEFAULT_RESPONSE_TIMEOUT_SEC}초 사용 (초 단위 양의 정수만 허용)`,
      );
    } else {
      console.log(`[pending-response] 미응답 타임아웃 ${responseTimeoutMs / 1000}초 (${source})`);
    }

    // 타임아웃 → tmux 알림
    timeoutTimer = setInterval(() => {
      const timedOut = collectTimedOut(pending, Date.now(), responseTimeoutMs);
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
  _botSpeakers: botSpeakers,
  channelIdOf,
  shouldRegister,
  mentionsOtherUser,
  mentionsMeUser,
  repliesToOtherBot,
  noteBotSpeaker,
  isOtherBotActive,
  registerPending,
  clearChannel,
  collectTimedOut,
  buildReminder,
  resolveTimeoutMs,
};
