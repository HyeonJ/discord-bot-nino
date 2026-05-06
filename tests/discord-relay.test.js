const mockLogin = jest.fn();

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

describe('discord relay module', () => {
  let fs;
  let processOn;
  let intervalSpy;

  beforeEach(() => {
    fs = require('fs');
    processOn = jest.spyOn(process, 'on').mockImplementation(() => process);
    intervalSpy = jest.spyOn(global, 'setInterval');
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
});
