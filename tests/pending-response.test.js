/**
 * pending-response addon — PENDING_RESPONSE_SEC 노브 배선 계약
 *
 * 왜: 코어 relay/index.js가 이 env를 읽어놓고 쓰지 않았고(.env.example은 있다고 광고),
 *     실기능은 이 addon의 하드코딩 3분이었다 = **조용히 무시되는 노브**(니노 발견, 코어 PR #57 논의).
 *     기능이 addon에 있으므로 노브도 addon이 소유한다(룬드 합의 M:o31q).
 *     순서: 니노 배선(이 PR) → 확인 후 코어가 const 제거 + .env.example 주석.
 *
 * 계약: 초 단위 양의 정수만 채택, 그 외(미설정·빈값·0·음수·비숫자)는 기본 180초로 폴백.
 *       폴백은 조용하면 안 된다 — 잘못 준 값이 무시된 걸 알 수 있어야 한다.
 */
const addon = require('../relay-addons/pending-response');

describe('resolveTimeoutMs — PENDING_RESPONSE_SEC 해석', () => {
  test('정상 값: 초 → ms 변환', () => {
    expect(addon.resolveTimeoutMs('60')).toEqual({ ms: 60 * 1000, source: 'env' });
    expect(addon.resolveTimeoutMs('300')).toEqual({ ms: 300 * 1000, source: 'env' });
  });

  test('미설정/빈값 → 기본 180초 (사유 default)', () => {
    expect(addon.resolveTimeoutMs(undefined)).toEqual({ ms: 180 * 1000, source: 'default' });
    expect(addon.resolveTimeoutMs('')).toEqual({ ms: 180 * 1000, source: 'default' });
  });

  test('0·음수 → 기본값 + 사유 invalid (즉시 타임아웃 방지)', () => {
    expect(addon.resolveTimeoutMs('0')).toEqual({ ms: 180 * 1000, source: 'invalid' });
    expect(addon.resolveTimeoutMs('-5')).toEqual({ ms: 180 * 1000, source: 'invalid' });
  });

  test('비숫자·소수 쓰레기 값 → 기본값 + 사유 invalid', () => {
    expect(addon.resolveTimeoutMs('abc')).toEqual({ ms: 180 * 1000, source: 'invalid' });
    expect(addon.resolveTimeoutMs('3분')).toEqual({ ms: 180 * 1000, source: 'invalid' });
    expect(addon.resolveTimeoutMs('NaN')).toEqual({ ms: 180 * 1000, source: 'invalid' });
  });

  test('앞뒤 공백은 허용 (셸에서 붙는 흔한 오염)', () => {
    expect(addon.resolveTimeoutMs(' 90 ')).toEqual({ ms: 90 * 1000, source: 'env' });
  });

  test('소수는 무효 — 초 단위 정수 계약', () => {
    expect(addon.resolveTimeoutMs('1.5')).toEqual({ ms: 180 * 1000, source: 'invalid' });
  });
});

describe('init — 노브를 실제로 사용하고, 해석 결과를 알린다', () => {
  let logs;
  const origLog = console.log;
  const origWarn = console.warn;

  beforeEach(() => {
    logs = [];
    console.log = (...a) => logs.push(a.join(' '));
    console.warn = (...a) => logs.push(a.join(' '));
    addon._pending.clear();
  });

  afterEach(() => {
    console.log = origLog;
    console.warn = origWarn;
    addon.stop();
    delete process.env.PENDING_RESPONSE_SEC;
  });

  test('env 값이 타임아웃에 실제 반영된다 (하드코딩 아님)', () => {
    jest.useFakeTimers();
    process.env.PENDING_RESPONSE_SEC = '1'; // 1초
    const sent = [];
    addon.init({ sendToTmux: (m) => sent.push(m), client: null });

    addon._pending.set('m1', { channelId: 'c1', timestamp: Date.now(), preview: '테스트' });
    jest.advanceTimersByTime(11 * 1000); // 10초 체크 주기 1회 통과 + 1초 타임아웃 경과

    expect(sent.length).toBe(1);
    expect(sent[0]).toContain('테스트');
    expect(addon._pending.size).toBe(0);
    jest.useRealTimers();
  });

  test('기본값이면 1초 후엔 알림이 안 나간다 (180초 계약)', () => {
    jest.useFakeTimers();
    const sent = [];
    addon.init({ sendToTmux: (m) => sent.push(m), client: null });

    addon._pending.set('m1', { channelId: 'c1', timestamp: Date.now(), preview: '테스트' });
    jest.advanceTimersByTime(11 * 1000);

    expect(sent.length).toBe(0);
    expect(addon._pending.size).toBe(1);
    jest.useRealTimers();
  });

  test('해석 결과를 로그로 남긴다 — 조용한 무시 재발 방지', () => {
    process.env.PENDING_RESPONSE_SEC = '45';
    addon.init({ sendToTmux: () => {}, client: null });
    expect(logs.join('\n')).toMatch(/pending-response.*45/);
  });

  test('잘못된 값은 경고로 알린다 (조용히 기본값으로 넘어가지 않음)', () => {
    process.env.PENDING_RESPONSE_SEC = 'abc';
    addon.init({ sendToTmux: () => {}, client: null });
    const out = logs.join('\n');
    expect(out).toMatch(/abc/);
    expect(out).toMatch(/180/);
  });
});
