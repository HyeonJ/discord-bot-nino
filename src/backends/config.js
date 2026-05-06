const SUPPORTED_BACKENDS = ['claude', 'codex'];

function parseEnabled(value, defaultValue, variableName) {
  if (value === undefined || value === null) {
    return defaultValue;
  }

  const normalized = String(value).trim().toLowerCase();
  if (normalized === '') {
    return defaultValue;
  }
  if (normalized === 'true') {
    return true;
  }
  if (normalized === 'false') {
    return false;
  }

  throw new Error(`${variableName} must be either true or false`);
}

function parseSession(value, defaultValue) {
  if (value === undefined || value === null) {
    return defaultValue;
  }

  const session = String(value).trim();
  return session || defaultValue;
}

function parseBackendId(value, fieldName) {
  const backend = String(value || '').trim().toLowerCase();
  if (!SUPPORTED_BACKENDS.includes(backend)) {
    throw new Error(`Unknown ${fieldName} backend ${backend || '(empty)'}`);
  }
  return backend;
}

function parseFallbacks(value, primary) {
  if (!value) {
    return [];
  }

  const seen = new Set();
  const fallback = [];
  String(value)
    .split(',')
    .map((backend) => backend.trim().toLowerCase())
    .filter(Boolean)
    .map((backend) => parseBackendId(backend, 'fallback'))
    .forEach((backend) => {
      if (backend !== primary && !seen.has(backend)) {
        seen.add(backend);
        fallback.push(backend);
      }
    });

  return fallback;
}

function choosePrimary(env, backends) {
  if (env.PRIMARY_BACKEND !== undefined && env.PRIMARY_BACKEND !== null && String(env.PRIMARY_BACKEND).trim() !== '') {
    return parseBackendId(env.PRIMARY_BACKEND, 'primary');
  }

  if (backends.claude.enabled) {
    return 'claude';
  }

  return SUPPORTED_BACKENDS.find((backend) => backends[backend].enabled);
}

function loadBackendConfig(env = {}) {
  const backends = {
    claude: {
      enabled: parseEnabled(env.CLAUDE_ENABLED, true, 'CLAUDE_ENABLED'),
      session: parseSession(env.CLAUDE_TMUX_SESSION, parseSession(env.TMUX_SESSION, 'nino')),
    },
    codex: {
      enabled: parseEnabled(env.CODEX_ENABLED, false, 'CODEX_ENABLED'),
      session: parseSession(env.CODEX_TMUX_SESSION, 'nino-codex'),
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

  const primary = choosePrimary(env, backends);
  if (!backends[primary].enabled) {
    throw new Error(`Primary backend ${primary} is disabled`);
  }

  const fallback = parseFallbacks(env.FALLBACK_BACKENDS, primary)
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
