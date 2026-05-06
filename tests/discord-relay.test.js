const mockLogin = jest.fn();
const mockTmuxSendKeys = jest.fn();
const mockTmuxCheckSession = jest.fn();
const mockTmuxGetChildPid = jest.fn();

jest.useFakeTimers();

jest.mock('discord.js', () => ({
  Client: jest.fn(() => ({
    once: jest.fn(),
    on: jest.fn(),
    login: mockLogin,
  })),
  GatewayIntentBits: {
    Guilds: 1,
    GuildMembers: 2,
    GuildMessages: 3,
    MessageContent: 4,
    DirectMessages: 5,
  },
  Partials: {
    Channel: 1,
  },
  ActivityType: {
    Playing: 0,
  },
}));

jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  watch: jest.fn(() => ({ close: jest.fn() })),
  watchFile: jest.fn(),
}));

jest.mock('../src/backends/claude', () => ({
  id: 'claude',
  health: jest.fn(() => ({ alive: false })),
  send: jest.fn(),
}));

jest.mock('../src/backends/tmux', () => ({
  checkSession: mockTmuxCheckSession,
  getChildPid: mockTmuxGetChildPid,
  sendKeys: mockTmuxSendKeys,
}));

describe('discord relay module', () => {
  let fs;
  let processOn;
  let intervalSpy;

  beforeEach(() => {
    fs = require('fs');
    processOn = jest.spyOn(process, 'on').mockImplementation(() => process);
    intervalSpy = jest.spyOn(global, 'setInterval');
    mockTmuxCheckSession.mockReturnValue(false);
    mockTmuxGetChildPid.mockReturnValue(null);
    mockTmuxSendKeys.mockReturnValue(true);
    delete process.env.PRIMARY_BACKEND;
    delete process.env.CLAUDE_ENABLED;
    delete process.env.CODEX_ENABLED;
    delete process.env.CODEX_TEST_CHANNELS;
    delete process.env.CODEX_TMUX_SESSION;
  });

  afterEach(() => {
    jest.clearAllMocks();
    processOn.mockRestore();
    intervalSpy.mockRestore();
    jest.resetModules();
  });

  test('exports sendToTmux without starting relay side effects on import', () => {
    const relay = require('../src/discord-relay');

    expect(typeof relay.sendToTmux).toBe('function');
    expect(typeof relay.startRelay).toBe('function');
    expect(mockLogin).not.toHaveBeenCalled();
    expect(intervalSpy).not.toHaveBeenCalled();
    expect(fs.watch).not.toHaveBeenCalled();
    expect(fs.watchFile).not.toHaveBeenCalled();
    expect(processOn).not.toHaveBeenCalled();
  });

  test('sendToTmux removes pending response when routing fails', () => {
    const relay = require('../src/discord-relay');

    relay.sendToTmux('[D][Tim] hello', 'msg-1', 'chan-1');

    expect(relay.__test.pendingResponses.has('msg-1')).toBe(false);
  });

  test('sendToTmux routes configured test channels to Codex tmux session', () => {
    process.env.CODEX_ENABLED = 'true';
    process.env.CODEX_TEST_CHANNELS = 'test-channel';
    process.env.CODEX_TMUX_SESSION = 'nino-codex-test';
    mockTmuxCheckSession.mockReturnValue(true);
    mockTmuxGetChildPid.mockReturnValue(456);
    const relay = require('../src/discord-relay');

    relay.sendToTmux('[D][Tim] hello', 'msg-1', 'test-channel');

    expect(mockTmuxSendKeys).toHaveBeenCalledWith('nino-codex-test', '[D][Tim] hello');
  });
});
