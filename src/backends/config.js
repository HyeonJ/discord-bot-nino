const SUPPORTED_BACKENDS = ['claude', 'codex'];

function parseEnabled(value, defaultValue) {
  if (value === undefined || value === null || value === '') {
    return defaultValue;
  }

  return String(value).toLowerCase() === 'true';
}

function parseBackendId(value, fieldName) {
  const backend = String(value || '').trim().toLowerCase();
  if (!SUPPORTED_BACKENDS.includes(backend)) {
    throw new Error(`Unknown ${fieldName} backend ${backend || '(empty)'}`);
  }
  return backend;
}

function parseFallbacks(value) {
  if (!value) {
    return [];
  }

  return String(value)
    .split(',')
    .map((backend) => backend.trim().toLowerCase())
    .filter(Boolean)
    .map((backend) => parseBackendId(backend, 'fallback'));
}

function loadBackendConfig(env = {}) {
  const backends = {
    claude: {
      enabled: parseEnabled(env.CLAUDE_ENABLED, true),
      session: env.CLAUDE_TMUX_SESSION || env.TMUX_SESSION || 'nino',
    },
    codex: {
      enabled: parseEnabled(env.CODEX_ENABLED, false),
      session: env.CODEX_TMUX_SESSION || 'nino-codex',
    },
  };

  const anyEnabled = SUPPORTED_BACKENDS.some((backend) => backends[backend].enabled);
  if (!anyEnabled) {
    return {
      primary: null,
      fallback: [],
      backends,
      degraded: true,
    };
  }

  const primary = parseBackendId(env.PRIMARY_BACKEND || 'claude', 'primary');
  if (!backends[primary].enabled) {
    throw new Error(`Primary backend ${primary} is disabled`);
  }

  const fallback = parseFallbacks(env.FALLBACK_BACKENDS)
    .filter((backend) => backends[backend].enabled);

  return {
    primary,
    fallback,
    backends,
    degraded: false,
  };
}

module.exports = {
  loadBackendConfig,
};
