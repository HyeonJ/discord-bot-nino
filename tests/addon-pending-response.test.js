// BOT_ID는 addon require 시점에 env로 고정된다 → require보다 먼저 심는다
process.env.DISCORD_APP_ID = 'nino';
const addon = require('../relay-addons/pending-response');
const {
  channelIdOf, shouldRegister, mentionsOtherUser,
  registerPending, clearChannel, collectTimedOut, buildReminder, buildTimeoutAlerts,
} = addon;

// 테스트용 msg 팩토리
// botId 는 여기 없다 — mentionsOtherUser(msg, botId) 로 **따로** 넘긴다(호출부가 정본)
function msg({ id = 'm1', channelId = 'c1', thread = null, mentions = [] } = {}) {
  return {
    id,
    channelId: thread ? undefined : channelId,
    channel: thread
      ? { isThread: () => true, id: thread }
      : { isThread: () => false, id: channelId },
    mentions: { users: mentions.map(uid => ({ id: uid })) },
  };
}

// author 가 필요한 배선 테스트용 (onMessage 는 author.bot 을 본다)
function humanMsg({ id = 'h1', channelId = 'c1', mentions = [], repliedUser = null } = {}) {
  const m = msg({ id, channelId, mentions });
  m.author = { id: 'tim', bot: false };
  m.mentions.repliedUser = repliedUser;
  return m;
}
function botMsg({ id = 'b1', channelId = 'c1', authorId = 'lund' } = {}) {
  const m = msg({ id, channelId });
  m.author = { id: authorId, bot: true };
  return m;
}

describe('addon: pending-response', () => {
  test('addon 인터페이스 (name + init + onMessage)', () => {
    expect(addon.name).toBe('pending-response');
    expect(typeof addon.init).toBe('function');
    expect(typeof addon.onMessage).toBe('function');
  });

  describe('channelIdOf — 스레드 인식', () => {
    test('일반 채널은 channelId', () => {
      expect(channelIdOf(msg({ channelId: 'c9' }))).toBe('c9');
    });
    test('스레드면 스레드 id', () => {
      expect(channelIdOf(msg({ thread: 't7' }))).toBe('t7');
    });
  });

  describe('shouldRegister — 사람 & 남 멘션 아님만', () => {
    test('사람 + 남 멘션 없음 → 등록', () => {
      expect(shouldRegister({ isBot: false, isSelf: false, mentionsOther: false })).toBe(true);
    });
    test('봇 메시지 → 등록 안 함', () => {
      expect(shouldRegister({ isBot: true, isSelf: false, mentionsOther: false })).toBe(false);
    });
    test('자기 메시지 → 등록 안 함', () => {
      expect(shouldRegister({ isBot: false, isSelf: true, mentionsOther: false })).toBe(false);
    });
    test('남 멘션 → 등록 안 함 (나한테 하는 말 아닐 확률↑)', () => {
      expect(shouldRegister({ isBot: false, isSelf: false, mentionsOther: true })).toBe(false);
    });
  });

  // ── 남의 대화에 미응답 경고가 뜨는 문제 (Darren 지시 2026-07-30, M:orpb "1. 응 고치자")
  // 근본원인: 멘션이 **하나도 없는** 평문은 mentionsOther=false 라 "나한테 온 말"로 등록됐다.
  // 해제 경로(다른 봇이 답하면 clear)는 있었지만, 등록~해제 **사이**에 타임아웃 경고가 나간다.
  // ⇒ 상대 봇이 답할 대화면 **등록 자체를 안 한다**.
  describe('shouldRegister — 상대 봇이 답할 대화는 등록 안 함', () => {
    const base = { isBot: false, isSelf: false, mentionsOther: false };

    test('평문인데 그 채널에서 다른 봇이 최근 발화 → 등록 안 함', () => {
      expect(shouldRegister({ ...base, otherBotActive: true })).toBe(false);
    });
    test('다른 봇 메시지에 답장 → 등록 안 함', () => {
      expect(shouldRegister({ ...base, repliesToOtherBot: true })).toBe(false);
    });
    test('나를 멘션하면 다른 봇이 떠들던 채널이어도 등록 (강한 긍정)', () => {
      expect(shouldRegister({ ...base, mentionsMe: true, otherBotActive: true })).toBe(true);
    });
    test('나+남 동시 멘션 → 등록 (mentionsMe 가 mentionsOther 를 이긴다)', () => {
      expect(shouldRegister({ ...base, mentionsMe: true, mentionsOther: true })).toBe(true);
    });
    test('봇/자기 메시지는 mentionsMe 여도 등록 안 함 (앞단 게이트가 최우선)', () => {
      expect(shouldRegister({ ...base, isBot: true, mentionsMe: true })).toBe(false);
      expect(shouldRegister({ ...base, isSelf: true, mentionsMe: true })).toBe(false);
    });
    test('새 인자를 안 주면 예전 동작 그대로 (신호 없음 = 등록)', () => {
      expect(shouldRegister({ isBot: false, isSelf: false, mentionsOther: false })).toBe(true);
    });
  });

  describe('봇 발화 추적 — noteBotSpeaker / isOtherBotActive', () => {
    const W = 10 * 60 * 1000;
    test('기록이 없으면 활성 아님 (기본은 등록 쪽)', () => {
      expect(addon.isOtherBotActive(new Map(), 'c1', 1000, W)).toBe(false);
    });
    test('창 안이면 활성', () => {
      const s = new Map();
      addon.noteBotSpeaker(s, 'c1', 1000);
      expect(addon.isOtherBotActive(s, 'c1', 1000 + W - 1, W)).toBe(true);
    });
    test('창 경계(정확히 창 크기)는 활성', () => {
      const s = new Map();
      addon.noteBotSpeaker(s, 'c1', 1000);
      expect(addon.isOtherBotActive(s, 'c1', 1000 + W, W)).toBe(true);
    });
    test('창을 벗어나면 활성 아님', () => {
      const s = new Map();
      addon.noteBotSpeaker(s, 'c1', 1000);
      expect(addon.isOtherBotActive(s, 'c1', 1000 + W + 1, W)).toBe(false);
    });
    test('채널별로 따로 본다', () => {
      const s = new Map();
      addon.noteBotSpeaker(s, 'c1', 1000);
      expect(addon.isOtherBotActive(s, 'c2', 1000, W)).toBe(false);
    });
    test('같은 채널 재발화는 시각을 갱신한다', () => {
      const s = new Map();
      addon.noteBotSpeaker(s, 'c1', 1000);
      addon.noteBotSpeaker(s, 'c1', 5000);
      expect(addon.isOtherBotActive(s, 'c1', 5000 + W, W)).toBe(true);
    });
  });

  describe('mentionsMeUser / repliesToOtherBot — 배선 판정', () => {
    test('나를 멘션하면 true', () => {
      expect(addon.mentionsMeUser(msg({ mentions: ['nino'] }), 'nino')).toBe(true);
    });
    test('남만 멘션하면 false', () => {
      expect(addon.mentionsMeUser(msg({ mentions: ['tim'] }), 'nino')).toBe(false);
    });
    test('멘션 없으면 false', () => {
      expect(addon.mentionsMeUser(msg({}), 'nino')).toBe(false);
    });
    test('답장 대상이 다른 봇이면 true', () => {
      const m = humanMsg({ repliedUser: { id: 'lund', bot: true } });
      expect(addon.repliesToOtherBot(m, 'nino')).toBe(true);
    });
    test('답장 대상이 사람이면 false', () => {
      const m = humanMsg({ repliedUser: { id: 'tim', bot: false } });
      expect(addon.repliesToOtherBot(m, 'nino')).toBe(false);
    });
    test('답장 대상이 나(니노)면 false — 내 말에 답한 건 나한테 온 말', () => {
      const m = humanMsg({ repliedUser: { id: 'nino', bot: true } });
      expect(addon.repliesToOtherBot(m, 'nino')).toBe(false);
    });
    test('repliedUser 가 없으면 false (판정 불가 — otherBotActive 가 받는다)', () => {
      expect(addon.repliesToOtherBot(humanMsg({}), 'nino')).toBe(false);
    });
  });

  describe('onMessage 배선 — 봇이 떠든 채널의 평문은 등록되지 않는다', () => {
    beforeEach(() => { addon._pending.clear(); addon._botSpeakers.clear(); });

    test('룬드 발화 → Tim 평문 → 등록 0개 (이게 오탐이던 자리)', () => {
      addon.onMessage({}, botMsg({ channelId: 'c1' }));
      addon.onMessage({ formatted: '그럼 v3로 가자' }, humanMsg({ id: 'h1', channelId: 'c1' }));
      expect(addon._pending.size).toBe(0);
    });
    test('다른 채널의 평문은 그대로 등록된다 (억제가 채널을 넘지 않는다)', () => {
      addon.onMessage({}, botMsg({ channelId: 'c1' }));
      addon.onMessage({ formatted: '니노 이거 봐줘' }, humanMsg({ id: 'h2', channelId: 'c2' }));
      expect(addon._pending.size).toBe(1);
    });
    test('룬드가 떠든 채널이어도 나를 멘션하면 등록된다', () => {
      addon.onMessage({}, botMsg({ channelId: 'c1' }));
      const m = humanMsg({ id: 'h3', channelId: 'c1', mentions: ['nino'] });
      addon.onMessage({ formatted: '@니노 확인' }, m);
      expect(addon._pending.size).toBe(1);
    });
    test('봇 발화가 없던 채널의 평문은 등록된다 (기존 동작 유지)', () => {
      addon.onMessage({ formatted: '평문' }, humanMsg({ id: 'h4', channelId: 'c3' }));
      expect(addon._pending.size).toBe(1);
    });
  });

  describe('mentionsOtherUser', () => {
    test('나만 멘션 → false', () => {
      expect(mentionsOtherUser(msg({ mentions: ['BOT'] }), 'BOT')).toBe(false);
    });
    test('남 멘션 → true', () => {
      expect(mentionsOtherUser(msg({ mentions: ['OTHER'] }), 'BOT')).toBe(true);
    });
    test('멘션 없음 → false', () => {
      expect(mentionsOtherUser(msg({ mentions: [] }), 'BOT')).toBe(false);
    });
  });

  describe('register / clearChannel', () => {
    test('등록 후 같은 채널 해제 시 제거됨', () => {
      const store = new Map();
      registerPending(store, 'm1', 'c1', 'hi');
      registerPending(store, 'm2', 'c1', 'yo');
      registerPending(store, 'm3', 'c2', 'other');
      expect(store.size).toBe(3);
      const cleared = clearChannel(store, 'c1');
      expect(cleared).toBe(2);
      expect(store.size).toBe(1);
      expect(store.has('m3')).toBe(true);
    });
    test('msgId 없으면 등록 안 함', () => {
      const store = new Map();
      registerPending(store, null, 'c1', 'x');
      expect(store.size).toBe(0);
    });
  });

  describe('collectTimedOut', () => {
    test('타임아웃 초과분만 빼서 반환', () => {
      const store = new Map();
      store.set('old', { channelId: 'c1', timestamp: 1000, preview: 'old' });
      store.set('new', { channelId: 'c1', timestamp: 9000, preview: 'new' });
      const out = collectTimedOut(store, 10000, 5000); // now=10000, 5초 초과
      expect(out).toHaveLength(1);
      expect(out[0].msgId).toBe('old');
      expect(store.has('old')).toBe(false);
      expect(store.has('new')).toBe(true);
    });
  });

  describe('buildTimeoutAlerts — 경보 단위는 «채널»이다', () => {
    test('한 채널의 여러 미응답은 «한 통»으로 묶인다', () => {
      const out = buildTimeoutAlerts([
        { msgId: 'm1', info: { channelId: 'c1', timestamp: 0, preview: '세꼬시 안싫어하겠지' } },
        { msgId: 'm2', info: { channelId: 'c1', timestamp: 0, preview: '믿음의 영역' } },
        { msgId: 'm3', info: { channelId: 'c1', timestamp: 0, preview: '다 좋아할것이라는' } },
        { msgId: 'm4', info: { channelId: 'c1', timestamp: 0, preview: '술 넘 땡기게' } },
      ]);
      expect(out).toHaveLength(1);
      expect(out[0]).toMatch(/4개/);
      expect(out[0]).toMatch(/세꼬시 안싫어하겠지/);
      expect(out[0]).toMatch(/술 넘 땡기게/);
    });

    test('채널이 다르면 따로 나간다 — 묶는 축은 채널뿐이다', () => {
      const out = buildTimeoutAlerts([
        { msgId: 'm1', info: { channelId: 'c1', timestamp: 0, preview: 'a' } },
        { msgId: 'm2', info: { channelId: 'c2', timestamp: 0, preview: 'b' } },
      ]);
      expect(out).toHaveLength(2);
    });

    test('하나뿐이면 «개수»를 안 붙인다 — 「1개」는 소음이다', () => {
      const out = buildTimeoutAlerts([
        { msgId: 'm1', info: { channelId: 'c1', timestamp: 0, preview: '안녕' } },
      ]);
      expect(out).toHaveLength(1);
      expect(out[0]).toMatch(/안녕/);
      expect(out[0]).not.toMatch(/1개/);
    });

    test('빈 입력이면 한 통도 안 나간다', () => {
      expect(buildTimeoutAlerts([])).toEqual([]);
    });

    test('«clearChannel 과 같은 단위»다 — 이 모듈이 이미 채널을 응답 단위로 본다', () => {
      // 대조군: 한 채널에 넷을 넣고 clearChannel 하면 넷이 통째로 지워진다.
      const store = new Map();
      for (const id of ['m1', 'm2', 'm3', 'm4']) {
        store.set(id, { channelId: 'c1', timestamp: 0, preview: id });
      }
      expect(clearChannel(store, 'c1')).toBe(4);
      expect(store.size).toBe(0);
      // ⇒ 경보도 같은 단위여야 한다 (넷을 지우는 한 번의 응답 ↔ 한 통의 경보)
      const alerts = buildTimeoutAlerts([
        { msgId: 'm1', info: { channelId: 'c1', timestamp: 0, preview: 'm1' } },
        { msgId: 'm2', info: { channelId: 'c1', timestamp: 0, preview: 'm2' } },
        { msgId: 'm3', info: { channelId: 'c1', timestamp: 0, preview: 'm3' } },
        { msgId: 'm4', info: { channelId: 'c1', timestamp: 0, preview: 'm4' } },
      ]);
      expect(alerts).toHaveLength(1);
    });
  });

  describe('buildReminder', () => {
    test('비어있으면 null', () => {
      expect(buildReminder(new Map())).toBeNull();
    });
    test('있으면 개수+프리뷰 포함', () => {
      const store = new Map();
      store.set('m1', { channelId: 'c1', timestamp: 0, preview: '안녕' });
      const r = buildReminder(store);
      expect(r).toMatch(/1개/);
      expect(r).toMatch(/안녕/);
    });
  });

  describe('onMessage 통합', () => {
    beforeEach(() => addon._pending.clear());
    test('사람 메시지 등록, 다른 봇 메시지로 해제', () => {
      addon.onMessage({ formatted: '[D][Darren] 안녕' }, { ...msg({ id: 'h1', channelId: 'c1' }), author: { bot: false } });
      expect(addon._pending.size).toBe(1);
      // 다른 봇이 같은 채널에 응답 → 해제
      addon.onMessage({}, { ...msg({ id: 'b1', channelId: 'c1' }), author: { bot: true } });
      expect(addon._pending.size).toBe(0);
    });
  });
});

/**
 * 🔴 시험 간 간섭 — 단독은 통과, 전체에서만 실패 (2026-07-31, 룬드 맥에서만 보였다)
 *
 * 이 파일 1행의 주석이 이미 알고 있었다: *"BOT_ID는 require 시점에 env로 고정된다 →
 * require보다 먼저 심는다"*. 🔑 **알고 적어뒀는데 고친 게 아니라 순서로 피한 것**이고,
 * 그 회피는 **이 파일이 먼저 로드될 때만** 성립한다. `pending-response.test.js` 도 같은
 * 모듈을 require 하므로, 그쪽이 먼저 로드되면 `BOT_ID=''` 로 굳고 자기 메시지 판별이 죽는다.
 *   → 룬드 맥: 전체 1 fail · 단독 39 pass. 내 기계: 전체 0 fail. **순서가 기계마다 다르다.**
 *
 * 🔑 이런 건 **단독으로 돌리면 사라져서** 각자 파일만 보는 습관에선 영원히 안 잡힌다.
 * ⇒ 고칠 것은 시험의 로드 순서가 아니라 **env 를 얼리는 형태**다. 호출 시점에 읽는다.
 */
describe('BOT_ID — 로드 순서에 의존하지 않는다', () => {
  test('🧪 모듈이 env 보다 먼저 로드돼도 현재 env 를 읽는다', () => {
    const key = require.resolve('../relay-addons/pending-response');
    const saved = process.env.DISCORD_APP_ID;
    delete require.cache[key];
    delete process.env.DISCORD_APP_ID;
    const fresh = require('../relay-addons/pending-response'); // 룬드 맥 순서 재현
    process.env.DISCORD_APP_ID = 'nino';
    try {
      expect(fresh.botId()).toBe('nino');
    } finally {
      process.env.DISCORD_APP_ID = saved;
      delete require.cache[key];
      require('../relay-addons/pending-response');
    }
  });
});
