jest.mock('../src/backends/tmux', () => ({
  checkSession: jest.fn(),
  sendKeys: jest.fn(),
  getChildPid: jest.fn(),
}));

const tmux = require('../src/backends/tmux');
const codex = require('../src/backends/codex');
const { loadBackendConfig } = require('../src/backends/config');

describe('codex backend adapter', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('exposes codex identity and process pattern', () => {
    expect(codex.id).toBe('codex');
    expect(codex.processPattern).toBe('codex');
  });

  test('Codex tmux session defaults to nino-codex', () => {
    expect(loadBackendConfig({}).backends.codex.session).toBe('nino-codex');
  });

  test('health reports disabled backend without checking tmux', () => {
    expect(codex.health({ enabled: false, session: 'nino-codex' })).toEqual({
      enabled: false,
      sessionAlive: false,
      alive: false,
      pid: null,
    });

    expect(tmux.checkSession).not.toHaveBeenCalled();
    expect(tmux.getChildPid).not.toHaveBeenCalled();
  });

  test('health checks tmux session and codex pid when enabled', () => {
    tmux.checkSession.mockReturnValue(true);
    tmux.getChildPid.mockReturnValue(23456);

    expect(codex.health({ enabled: true, session: 'nino-codex' })).toEqual({
      enabled: true,
      sessionAlive: true,
      alive: true,
      pid: 23456,
    });

    expect(tmux.checkSession).toHaveBeenCalledWith('nino-codex');
    expect(tmux.getChildPid).toHaveBeenCalledWith('nino-codex', 'codex');
  });

  test('send uses tmux transport with explicit payload', () => {
    tmux.sendKeys.mockReturnValue(true);

    expect(codex.send({ payload: 'full message', preview: 'preview only' }, { session: 'nino-codex' })).toBe(true);

    expect(tmux.sendKeys).toHaveBeenCalledWith('nino-codex', 'full message');
  });

  test('send throws when payload is missing', () => {
    expect(() => codex.send({}, { session: 'nino-codex' })).toThrow(/payload/i);

    expect(tmux.sendKeys).not.toHaveBeenCalled();
  });

  test('send throws when backend session is missing', () => {
    expect(() => codex.send({ payload: 'full message' }, {})).toThrow(/session/i);

    expect(tmux.sendKeys).not.toHaveBeenCalled();
  });

  test('restart is explicitly not implemented yet', () => {
    expect(codex.restart({ session: 'nino-codex' })).toEqual({
      ok: false,
      reason: 'not_implemented',
    });
  });
});
