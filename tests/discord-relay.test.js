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
  afterEach(() => {
    jest.clearAllMocks();
  });

  test('exports sendToTmux without logging into Discord on import', () => {
    const relay = require('../src/discord-relay');

    expect(typeof relay.sendToTmux).toBe('function');
    expect(mockLogin).not.toHaveBeenCalled();
  });
});
