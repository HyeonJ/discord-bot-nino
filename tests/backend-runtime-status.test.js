const fs = require('fs');
const os = require('os');
const path = require('path');

describe('backend runtime status', () => {
  let status;
  let tempDir;

  beforeEach(() => {
    jest.resetModules();
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'nino-backend-status-'));
    process.env.BACKEND_STATUS_DIR = tempDir;
    status = require('../src/backends/runtime-status');
  });

  afterEach(() => {
    delete process.env.BACKEND_STATUS_DIR;
  });

  function writeStatus(backendId, data) {
    fs.writeFileSync(
      path.join(tempDir, `${backendId}.json`),
      JSON.stringify(data, null, 2),
      'utf8'
    );
  }

  test('missing status file leaves backend routable', () => {
    expect(status.getRuntimeStatus('codex')).toEqual({
      backendId: 'codex',
      state: 'ready',
      blocked: false,
      reason: null,
      until: null,
    });
    expect(status.isBlocked('codex')).toBe(false);
  });

  test('quota_exhausted blocks backend routing', () => {
    writeStatus('codex', {
      state: 'quota_exhausted',
      reason: '5h limit reached',
    });

    expect(status.getRuntimeStatus('codex')).toMatchObject({
      backendId: 'codex',
      state: 'quota_exhausted',
      blocked: true,
      reason: '5h limit reached',
    });
    expect(status.isBlocked('codex')).toBe(true);
  });

  test('active cooldown blocks until expiry', () => {
    writeStatus('claude', {
      state: 'cooldown',
      until: '2026-05-06T12:30:00.000Z',
    });

    expect(status.isBlocked('claude', new Date('2026-05-06T12:00:00.000Z'))).toBe(true);
  });

  test('expired cooldown no longer blocks routing', () => {
    writeStatus('claude', {
      state: 'cooldown',
      until: '2026-05-06T11:30:00.000Z',
    });

    expect(status.getRuntimeStatus('claude', new Date('2026-05-06T12:00:00.000Z'))).toMatchObject({
      state: 'cooldown',
      blocked: false,
    });
  });

  test('malformed status file blocks conservatively', () => {
    fs.writeFileSync(path.join(tempDir, 'codex.json'), '{bad json', 'utf8');

    expect(status.getRuntimeStatus('codex')).toMatchObject({
      state: 'invalid',
      blocked: true,
      reason: 'malformed status file',
    });
  });
});
