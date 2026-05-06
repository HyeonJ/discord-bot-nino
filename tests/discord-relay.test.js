const mockLogin = jest.fn();
const mockClientOnce = jest.fn();
const mockClientOn = jest.fn();
const mockTmuxSendKeys = jest.fn();
const mockTmuxCheckSession = jest.fn();
const mockTmuxGetChildPid = jest.fn();

jest.useFakeTimers();

jest.mock('discord.js', () => ({
  Client: jest.fn(() => ({
    once: mockClientOnce,
    on: mockClientOn,
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
  let appendFileSpy;
  let mkdirSpy;

  beforeEach(() => {
    fs = require('fs');
    processOn = jest.spyOn(process, 'on').mockImplementation(() => process);
    intervalSpy = jest.spyOn(global, 'setInterval');
    appendFileSpy = jest.spyOn(fs, 'appendFileSync').mockImplementation(() => {});
    mkdirSpy = jest.spyOn(fs, 'mkdirSync').mockImplementation(() => {});
    mockTmuxCheckSession.mockReturnValue(false);
    mockTmuxGetChildPid.mockReturnValue(null);
    mockTmuxSendKeys.mockReturnValue(true);
    delete process.env.PRIMARY_BACKEND;
    delete process.env.CLAUDE_ENABLED;
    delete process.env.CODEX_ENABLED;
    delete process.env.CODEX_TEST_CHANNELS;
    delete process.env.CODEX_TMUX_SESSION;
    delete process.env.NINO_BOT_ID;
  });

  afterEach(() => {
    jest.clearAllMocks();
    appendFileSpy.mockRestore();
    mkdirSpy.mockRestore();
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

  test('sendToTmux can route to Codex when Claude is disabled and no primary is specified', () => {
    process.env.CLAUDE_ENABLED = 'false';
    process.env.CODEX_ENABLED = 'true';
    process.env.CODEX_TEST_CHANNELS = 'test-channel';
    process.env.CODEX_TMUX_SESSION = 'nino-codex-test';
    mockTmuxCheckSession.mockReturnValue(true);
    mockTmuxGetChildPid.mockReturnValue(456);
    const relay = require('../src/discord-relay');

    relay.sendToTmux('[D][Tim] hello', 'msg-1', 'test-channel');

    expect(mockTmuxSendKeys).toHaveBeenCalledWith('nino-codex-test', '[D][Tim] hello');
    expect(relay.__test.pendingResponses.get('msg-1')).toMatchObject({
      backendId: 'codex',
    });
  });

  test('own bot messages complete pending responses through the owning backend', async () => {
    process.env.NINO_BOT_ID = 'nino-bot';
    const claudeBackend = require('../src/backends/claude');
    claudeBackend.health.mockReturnValue({ sessionAlive: true, alive: false });
    const relay = require('../src/discord-relay');

    relay.sendToTmux('[D][Tim] hello', 'msg-1', 'chan-1');
    expect(relay.__test.pendingResponses.get('msg-1')).toMatchObject({
      backendId: 'claude',
    });

    const messageHandler = mockClientOn.mock.calls.find(([event]) => event === 'messageCreate')?.[1];
    const attachments = [];
    attachments.size = 0;
    await messageHandler({
      id: 'nino-reply-1',
      guildId: '1479813608023134342',
      channelId: 'chan-1',
      channel: {
        id: 'chan-1',
        name: 'general',
        isThread: () => false,
      },
      author: {
        id: 'nino-bot',
        bot: true,
      },
      content: 'reply',
      attachments,
      guild: {
        members: { cache: new Map() },
        roles: { cache: new Map() },
        channels: { cache: new Map() },
      },
    });

    expect(relay.__test.pendingResponses.has('msg-1')).toBe(false);
  });

  test('other bot messages do not clear pending responses owned by another backend', async () => {
    const claudeBackend = require('../src/backends/claude');
    claudeBackend.health.mockReturnValue({ sessionAlive: true, alive: false });
    const relay = require('../src/discord-relay');

    relay.sendToTmux('[D][Tim] hello', 'msg-1', 'chan-1');
    expect(relay.__test.pendingResponses.get('msg-1')).toMatchObject({
      backendId: 'claude',
    });

    const messageHandler = mockClientOn.mock.calls.find(([event]) => event === 'messageCreate')?.[1];
    const attachments = [];
    attachments.size = 0;
    await messageHandler({
      id: 'bot-msg-1',
      guildId: '1479813608023134342',
      channelId: 'chan-1',
      channel: {
        id: 'chan-1',
        name: 'general',
        isThread: () => false,
      },
      author: {
        id: 'other-bot',
        bot: true,
        username: 'Klaude',
      },
      content: 'message from another bot',
      attachments,
      embeds: [],
      guild: {
        members: { cache: new Map() },
        roles: { cache: new Map() },
        channels: { cache: new Map() },
      },
    });

    expect(relay.__test.pendingResponses.has('msg-1')).toBe(true);
  });

  test('other-bot guild messages in configured test channels route to Codex tmux session', async () => {
    process.env.CODEX_ENABLED = 'true';
    process.env.CODEX_TEST_CHANNELS = 'test-channel';
    process.env.CODEX_TMUX_SESSION = 'nino-codex-test';
    mockTmuxCheckSession.mockReturnValue(true);
    mockTmuxGetChildPid.mockReturnValue(456);
    require('../src/discord-relay');

    const messageHandler = mockClientOn.mock.calls.find(([event]) => event === 'messageCreate')?.[1];
    expect(typeof messageHandler).toBe('function');
    const attachments = [];
    attachments.size = 0;
    const msg = {
      id: 'bot-msg-1',
      guildId: '1479813608023134342',
      channelId: 'test-channel',
      channel: {
        id: 'test-channel',
        name: 'codex-test',
        isThread: () => false,
      },
      author: {
        id: 'other-bot',
        bot: true,
        username: 'Klaude',
      },
      content: 'hello from another bot',
      attachments,
      embeds: [],
      guild: {
        members: { cache: new Map() },
        roles: { cache: new Map() },
        channels: { cache: new Map() },
      },
    };

    await messageHandler(msg);

    expect(mockLogin).not.toHaveBeenCalled();
    expect(mockTmuxSendKeys).toHaveBeenCalledWith(
      'nino-codex-test',
      '[D][Klaude][C:test-channel][M:bot-msg-1] hello from another bot'
    );
  });
});
