const addon = require('../relay-addons/pending-response');
const {
  channelIdOf, shouldRegister, mentionsOtherUser,
  registerPending, clearChannel, collectTimedOut, buildReminder,
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
