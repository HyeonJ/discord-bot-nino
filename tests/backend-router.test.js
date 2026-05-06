jest.mock('../src/backends/tmux', () => ({
  checkSession: jest.fn(() => true),
  sendKeys: jest.fn(() => true),
  getChildPid: jest.fn(() => 34567),
}));

jest.mock('../src/backends/runtime-status', () => ({
  getRuntimeStatus: jest.fn((backendId) => ({
    backendId,
    state: 'ready',
    blocked: false,
    reason: null,
    until: null,
  })),
}));

const { createRouter } = require('../src/backends/router');
const tmux = require('../src/backends/tmux');
const runtimeStatus = require('../src/backends/runtime-status');

function makeAdapter(id, { healthy = true, healthResult } = {}) {
  return {
    id,
    health: jest.fn(() => healthResult || ({ alive: healthy })),
    send: jest.fn(() => true),
  };
}

function makeRequest(overrides = {}) {
  return {
    requestId: 'req-1',
    payload: '[D][Tim] hello',
    messageId: 'msg-1',
    channelId: 'chan-1',
    preview: 'hello',
    ...overrides,
  };
}

describe('backend router', () => {
  beforeEach(() => {
    runtimeStatus.getRuntimeStatus.mockImplementation((backendId) => ({
      backendId,
      state: 'ready',
      blocked: false,
      reason: null,
      until: null,
    }));
  });

  test('routes to Claude primary when Claude is enabled and Codex is disabled', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: false, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest();
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(claude.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino' });
    expect(codex.send).not.toHaveBeenCalled();
  });

  test('routes test channel requests to Codex when Codex is enabled and healthy', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        codexTestChannels: ['test-channel'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ channelId: 'test-channel' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'codex', requestId: 'req-1' });
    expect(codex.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino-codex' });
    expect(claude.send).not.toHaveBeenCalled();
  });

  test('routes to preferred backend before test-channel routing when it is healthy', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex');
    const router = createRouter({
      config: {
        primary: 'codex',
        fallback: ['claude'],
        codexTestChannels: ['test-channel'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ channelId: 'test-channel', preferredBackend: 'claude' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(claude.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino' });
    expect(codex.send).not.toHaveBeenCalled();
  });

  test('falls back to normal routing when preferred backend is unavailable', () => {
    const claude = makeAdapter('claude', { healthy: false });
    const codex = makeAdapter('codex');
    const router = createRouter({
      config: {
        primary: 'codex',
        fallback: ['claude'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ preferredBackend: 'claude' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'codex', requestId: 'req-1' });
    expect(codex.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino-codex' });
    expect(claude.send).not.toHaveBeenCalled();
  });

  test('routes non-test channel requests to Claude primary when Codex is enabled', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        codexTestChannels: ['test-channel'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ channelId: 'regular-channel' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(claude.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino' });
    expect(codex.send).not.toHaveBeenCalled();
  });

  test('falls back to Claude primary for test channel when Codex is disabled', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        codexTestChannels: ['test-channel'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: false, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ channelId: 'test-channel' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(claude.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino' });
    expect(codex.health).not.toHaveBeenCalled();
    expect(codex.send).not.toHaveBeenCalled();
  });

  test('falls back to Claude primary for test channel when Codex is unhealthy', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex', { healthy: false });
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        codexTestChannels: ['test-channel'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ channelId: 'test-channel' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(codex.send).not.toHaveBeenCalled();
    expect(claude.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino' });
  });

  test('falls back to Claude primary for test channel when Codex session is alive but process is missing', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex', {
      healthResult: { enabled: true, sessionAlive: true, alive: false, pid: null },
    });
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        codexTestChannels: ['test-channel'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ channelId: 'test-channel' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(codex.send).not.toHaveBeenCalled();
    expect(claude.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino' });
  });

  test('supports CODEX_TEST_CHANNELS from router env input', () => {
    const claude = makeAdapter('claude');
    const codex = makeAdapter('codex');
    const router = createRouter({
      env: {
        CODEX_TEST_CHANNELS: ' first-channel, second-channel ',
      },
      config: {
        primary: 'claude',
        fallback: [],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude, codex },
    });

    const request = makeRequest({ channelId: 'second-channel' });
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'codex', requestId: 'req-1' });
    expect(codex.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino-codex' });
    expect(claude.send).not.toHaveBeenCalled();
  });

  test('uses built-in Codex adapter for test channels when caller omits Codex adapter', () => {
    const claude = makeAdapter('claude');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        codexTestChannels: ['test-channel'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          codex: { enabled: true, session: 'nino-codex' },
        },
      },
      adapters: { claude },
    });

    const result = router.routeRequest(makeRequest({ channelId: 'test-channel' }));

    expect(result).toEqual({ ok: true, backendId: 'codex', requestId: 'req-1' });
    expect(tmux.sendKeys).toHaveBeenCalledWith('nino-codex', '[D][Tim] hello', { submitDelaySeconds: 1 });
    expect(claude.send).not.toHaveBeenCalled();
  });

  test('routes to tmux backend when session is available but process health is transiently missing', () => {
    const claude = makeAdapter('claude', {
      healthResult: { enabled: true, sessionAlive: true, alive: false, pid: null },
    });
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        backends: {
          claude: { enabled: true, session: 'nino' },
        },
      },
      adapters: { claude },
    });

    const request = makeRequest();
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(claude.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino' });
  });

  test('routes to healthy fallback when the primary is disabled', () => {
    const claude = makeAdapter('claude');
    const fallback = makeAdapter('fallback');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: ['fallback'],
        backends: {
          claude: { enabled: false, session: 'nino' },
          fallback: { enabled: true, session: 'nino-fallback' },
        },
      },
      adapters: { claude, fallback },
    });

    const request = makeRequest();
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'fallback', requestId: 'req-1' });
    expect(claude.health).not.toHaveBeenCalled();
    expect(claude.send).not.toHaveBeenCalled();
    expect(fallback.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino-fallback' });
  });

  test('routes to first healthy fallback when primary is unhealthy', () => {
    const claude = makeAdapter('claude', { healthy: false });
    const fallback = makeAdapter('fallback');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: ['fallback'],
        backends: {
          claude: { enabled: true, session: 'nino' },
          fallback: { enabled: true, session: 'nino-fallback' },
        },
      },
      adapters: { claude, fallback },
    });

    const request = makeRequest();
    const result = router.routeRequest(request);

    expect(result).toEqual({ ok: true, backendId: 'fallback', requestId: 'req-1' });
    expect(claude.send).not.toHaveBeenCalled();
    expect(fallback.send).toHaveBeenCalledWith(request, { enabled: true, session: 'nino-fallback' });
    expect(router.getState('req-1')).toMatchObject({
      backendId: 'fallback',
      status: 'sent',
    });
  });

  test('routes to fallback when any primary backend is quota blocked by runtime status', () => {
    runtimeStatus.getRuntimeStatus.mockImplementation((backendId) => ({
      backendId,
      state: backendId === 'codex' ? 'quota_exhausted' : 'ready',
      blocked: backendId === 'codex',
      reason: backendId === 'codex' ? 'usage limit' : null,
      until: null,
    }));
    const codex = makeAdapter('codex');
    const claude = makeAdapter('claude');
    const router = createRouter({
      config: {
        primary: 'codex',
        fallback: ['claude'],
        backends: {
          codex: { enabled: true, session: 'nino-codex' },
          claude: { enabled: true, session: 'nino' },
        },
      },
      adapters: { codex, claude },
    });

    const result = router.routeRequest(makeRequest());

    expect(result).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(codex.send).not.toHaveBeenCalled();
    expect(claude.send).toHaveBeenCalled();
  });

  test('routeFallback skips current owner and sends to later fallback backend', () => {
    const codex = makeAdapter('codex');
    const claude = makeAdapter('claude');
    const backup = makeAdapter('backup');
    const router = createRouter({
      config: {
        primary: 'codex',
        fallback: ['claude', 'backup'],
        backends: {
          codex: { enabled: true, session: 'nino-codex' },
          claude: { enabled: true, session: 'nino' },
          backup: { enabled: true, session: 'nino-backup' },
        },
      },
      adapters: { codex, claude, backup },
    });

    expect(router.routeRequest(makeRequest())).toEqual({
      ok: true,
      backendId: 'codex',
      requestId: 'req-1',
    });
    const fallbackResult = router.routeFallback(makeRequest());

    expect(fallbackResult).toEqual({ ok: true, backendId: 'claude', requestId: 'req-1' });
    expect(codex.send).toHaveBeenCalledTimes(1);
    expect(claude.send).toHaveBeenCalledTimes(1);
    expect(router.getState('req-1')).toMatchObject({
      status: 'sent',
      backendId: 'claude',
      previousBackendIds: ['codex'],
    });
  });

  test('routeFallback returns unavailable when no later fallback backend is routable', () => {
    const codex = makeAdapter('codex');
    const claude = makeAdapter('claude', { healthy: false });
    const router = createRouter({
      config: {
        primary: 'codex',
        fallback: ['claude'],
        backends: {
          codex: { enabled: true, session: 'nino-codex' },
          claude: { enabled: true, session: 'nino' },
        },
      },
      adapters: { codex, claude },
    });

    router.routeRequest(makeRequest());

    expect(router.routeFallback(makeRequest())).toEqual({
      ok: false,
      reason: 'fallback_unavailable',
      backendId: 'codex',
      requestId: 'req-1',
    });
  });

  test('returns unavailable without sending when primary is unhealthy and no fallback is usable', () => {
    const claude = makeAdapter('claude', { healthy: false });
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        backends: {
          claude: { enabled: true, session: 'nino' },
        },
      },
      adapters: { claude },
    });

    const result = router.routeRequest(makeRequest());

    expect(result).toEqual({
      ok: false,
      reason: 'backend_unavailable',
      backendId: 'claude',
      requestId: 'req-1',
    });
    expect(claude.send).not.toHaveBeenCalled();
  });

  test('ignores later completion when request is already completed', () => {
    const claude = makeAdapter('claude');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        backends: {
          claude: { enabled: true, session: 'nino' },
        },
      },
      adapters: { claude },
    });

    router.markCompleted('req-1', 'claude');
    const result = router.routeRequest(makeRequest());
    const duplicate = router.markCompleted('req-1', 'other');

    expect(result).toEqual({
      ok: false,
      reason: 'already_completed',
      requestId: 'req-1',
      backendId: 'claude',
      ignored: true,
    });
    expect(duplicate).toEqual({
      ok: false,
      reason: 'already_completed',
      requestId: 'req-1',
      backendId: 'claude',
      ignored: true,
    });
    expect(claude.send).not.toHaveBeenCalled();
  });

  test('ignores completion from backend that does not own the sent request', () => {
    const claude = makeAdapter('claude');
    const router = createRouter({
      config: {
        primary: 'claude',
        fallback: [],
        backends: {
          claude: { enabled: true, session: 'nino' },
        },
      },
      adapters: { claude },
    });

    router.routeRequest(makeRequest());
    const result = router.markCompleted('req-1', 'other');

    expect(result).toEqual({
      ok: false,
      reason: 'wrong_backend',
      requestId: 'req-1',
      backendId: 'other',
      ownerBackendId: 'claude',
      ignored: true,
    });
    expect(router.getState('req-1')).toMatchObject({
      backendId: 'claude',
      status: 'sent',
    });
  });
});
