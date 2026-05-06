jest.mock('../src/backends/tmux', () => ({
  checkSession: jest.fn(),
  sendKeys: jest.fn(),
  getChildPid: jest.fn(),
}));

const tmux = require('../src/backends/tmux');
const claude = require('../src/backends/claude');

describe('claude backend adapter', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('exposes claude identity and process pattern', () => {
    expect(claude.id).toBe('claude');
    expect(claude.processPattern).toBe('claude');
  });

  test('health reports disabled backend without checking tmux', () => {
    expect(claude.health({ enabled: false, session: 'nino' })).toEqual({
      enabled: false,
      alive: false,
      pid: null,
    });

    expect(tmux.checkSession).not.toHaveBeenCalled();
    expect(tmux.getChildPid).not.toHaveBeenCalled();
  });

  test('health checks tmux session and provider pid when enabled', () => {
    tmux.checkSession.mockReturnValue(true);
    tmux.getChildPid.mockReturnValue(12345);

    expect(claude.health({ enabled: true, session: 'nino' })).toEqual({
      enabled: true,
      alive: true,
      pid: 12345,
    });

    expect(tmux.checkSession).toHaveBeenCalledWith('nino');
    expect(tmux.getChildPid).toHaveBeenCalledWith('nino', 'claude');
  });

  test('send prefers explicit payload over preview', () => {
    tmux.sendKeys.mockReturnValue(true);

    expect(claude.send({ payload: 'full message', preview: 'preview only' }, { session: 'nino' })).toBe(true);

    expect(tmux.sendKeys).toHaveBeenCalledWith('nino', 'full message');
  });

  test('send throws when only preview is provided', () => {
    expect(() => claude.send({ preview: 'preview only' }, { session: 'nino' })).toThrow(/payload/i);

    expect(tmux.sendKeys).not.toHaveBeenCalled();
  });

  test('send throws when payload is missing', () => {
    expect(() => claude.send({}, { session: 'nino' })).toThrow(/payload/i);

    expect(tmux.sendKeys).not.toHaveBeenCalled();
  });

  test('restart is explicitly not implemented yet', () => {
    expect(claude.restart({ session: 'nino' })).toEqual({
      ok: false,
      reason: 'not_implemented',
    });
  });
});
