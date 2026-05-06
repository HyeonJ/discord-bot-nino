const { loadBackendConfig } = require('../src/backends/config');

describe('loadBackendConfig', () => {
  test('PRIMARY_BACKEND=claude with Claude enabled returns healthy Claude config', () => {
    expect(loadBackendConfig({
      PRIMARY_BACKEND: 'claude',
      CLAUDE_ENABLED: 'true',
      CLAUDE_TMUX_SESSION: 'nino-claude',
    })).toEqual({
      primary: 'claude',
      fallback: [],
      backends: {
        claude: { enabled: true, session: 'nino-claude' },
        codex: { enabled: false, session: 'nino-codex' },
      },
      degraded: false,
    });
  });

  test('PRIMARY_BACKEND=codex with Codex enabled returns healthy Codex config', () => {
    expect(loadBackendConfig({
      PRIMARY_BACKEND: 'codex',
      CODEX_ENABLED: 'true',
      CODEX_TMUX_SESSION: 'nino-codex-custom',
    })).toEqual({
      primary: 'codex',
      fallback: [],
      backends: {
        claude: { enabled: true, session: 'nino' },
        codex: { enabled: true, session: 'nino-codex-custom' },
      },
      degraded: false,
    });
  });

  test('uses Codex as primary when Claude is disabled and no primary is specified', () => {
    expect(loadBackendConfig({
      CLAUDE_ENABLED: 'false',
      CODEX_ENABLED: 'true',
      CODEX_TMUX_SESSION: 'nino-codex-only',
    })).toEqual({
      primary: 'codex',
      fallback: [],
      backends: {
        claude: { enabled: false, session: 'nino' },
        codex: { enabled: true, session: 'nino-codex-only' },
      },
      degraded: false,
    });
  });

  test('primary backend disabled rejects startup', () => {
    expect(() => loadBackendConfig({
      PRIMARY_BACKEND: 'codex',
      CODEX_ENABLED: 'false',
    })).toThrow(/primary backend codex is disabled/i);
  });

  test('invalid boolean values reject startup with the variable name', () => {
    expect(() => loadBackendConfig({
      CLAUDE_ENABLED: 'yes',
    })).toThrow(/CLAUDE_ENABLED.*true.*false/i);

    expect(() => loadBackendConfig({
      CODEX_ENABLED: '1',
    })).toThrow(/CODEX_ENABLED.*true.*false/i);
  });

  test('unknown fallback backend rejects startup', () => {
    expect(() => loadBackendConfig({
      FALLBACK_BACKENDS: 'claude,unknown',
    })).toThrow(/unknown fallback backend unknown/i);
  });

  test('fallback list removes duplicates and the primary backend', () => {
    expect(loadBackendConfig({
      PRIMARY_BACKEND: 'claude',
      CLAUDE_ENABLED: 'true',
      CODEX_ENABLED: 'true',
      FALLBACK_BACKENDS: ' codex,claude,codex ',
    })).toMatchObject({
      primary: 'claude',
      fallback: ['codex'],
      degraded: false,
    });
  });

  test('session names are trimmed and empty sessions use defaults', () => {
    expect(loadBackendConfig({
      CLAUDE_TMUX_SESSION: '  nino-claude  ',
      CODEX_TMUX_SESSION: '   ',
    }).backends).toEqual({
      claude: { enabled: true, session: 'nino-claude' },
      codex: { enabled: false, session: 'nino-codex' },
    });
  });

  test('all backends disabled returns degraded mode, not healthy mode', () => {
    expect(loadBackendConfig({
      CLAUDE_ENABLED: 'false ',
      CODEX_ENABLED: 'false',
      FALLBACK_BACKENDS: 'codex',
    })).toEqual({
      primary: null,
      fallback: [],
      backends: {
        claude: { enabled: false, session: 'nino' },
        codex: { enabled: false, session: 'nino-codex' },
      },
      degraded: true,
    });
  });
});
