const codexAdapter = require('./codex');
const runtimeStatus = require('./runtime-status');

function createDefaultState() {
  return new Map();
}

function makeRequestId(request) {
  if (request && request.requestId) {
    return request.requestId;
  }

  const messageId = request && request.messageId ? request.messageId : 'no-message';
  const channelId = request && request.channelId ? request.channelId : 'no-channel';
  return `${channelId}:${messageId}:${Date.now()}`;
}

function isBackendEnabled(config, backendId) {
  return Boolean(config && config.backends && config.backends[backendId] && config.backends[backendId].enabled);
}

function getBackendConfig(config, backendId) {
  return config && config.backends ? config.backends[backendId] : undefined;
}

function parseChannelList(value) {
  if (!value) {
    return [];
  }

  if (Array.isArray(value)) {
    return value.map((channel) => String(channel).trim()).filter(Boolean);
  }

  return String(value)
    .split(',')
    .map((channel) => channel.trim())
    .filter(Boolean);
}

function canRoute(adapter, backendConfig) {
  if (!adapter) {
    return false;
  }

  try {
    const status = runtimeStatus.getRuntimeStatus(adapter.id);
    if (status && status.blocked) {
      return false;
    }

    if (typeof adapter.canRoute === 'function') {
      return Boolean(adapter.canRoute(backendConfig));
    }
    if (typeof adapter.ready === 'function') {
      return Boolean(adapter.ready(backendConfig));
    }
    if (typeof adapter.health !== 'function') {
      return false;
    }

    const result = adapter.health(backendConfig);
    if (adapter.id === 'codex') {
      return Boolean(result && result.alive === true);
    }
    return Boolean(result === true || (result && (result.sessionAlive || result.alive)));
  } catch {
    return false;
  }
}

function completedResult(requestId, stateEntry) {
  return {
    ok: false,
    reason: 'already_completed',
    requestId,
    backendId: stateEntry.backendId,
    ignored: true,
  };
}

function createRouter({ config, adapters, state, env } = {}) {
  const requestState = state || createDefaultState();
  const backendAdapters = { codex: codexAdapter, ...(adapters || {}) };
  const backendConfig = config || { primary: null, fallback: [], backends: {} };
  const runtimeEnv = env || process.env;
  const codexTestChannels = new Set(parseChannelList(
    backendConfig.codexTestChannels ||
    backendConfig.testChannels ||
    (runtimeEnv && runtimeEnv.CODEX_TEST_CHANNELS)
  ));

  function getRoutableBackend(backendId) {
    if (!isBackendEnabled(backendConfig, backendId)) {
      return null;
    }

    const adapter = backendAdapters[backendId];
    const configForBackend = getBackendConfig(backendConfig, backendId);
    if (!canRoute(adapter, configForBackend)) {
      return null;
    }

    return { ok: true, backendId, adapter, config: configForBackend };
  }

  function chooseBackend(requestId, request) {
    if (request && request.preferredBackend) {
      const preferredBackend = getRoutableBackend(String(request.preferredBackend).trim().toLowerCase());
      if (preferredBackend) {
        return preferredBackend;
      }
    }

    if (request && request.channelId && codexTestChannels.has(String(request.channelId))) {
      const codex = getRoutableBackend('codex');
      if (codex) {
        return codex;
      }
    }

    const primary = backendConfig.primary;
    if (!primary) {
      return { ok: false, reason: 'no_primary', requestId };
    }

    const primaryBackend = getRoutableBackend(primary);
    if (primaryBackend) {
      return primaryBackend;
    }

    for (const backendId of backendConfig.fallback || []) {
      const fallbackBackend = getRoutableBackend(backendId);
      if (fallbackBackend) {
        return fallbackBackend;
      }
    }

    return { ok: false, reason: 'backend_unavailable', backendId: primary, requestId };
  }

  function routeToSelectedBackend(selected, request, requestId, previousBackendIds = []) {
    const requestWithId = request.requestId ? request : { ...request, requestId };
    let sent = false;
    try {
      sent = selected.adapter.send(requestWithId, selected.config);
    } catch (error) {
      requestState.set(requestId, {
        status: 'failed',
        backendId: selected.backendId,
        previousBackendIds,
        error: error.message,
      });
      return {
        ok: false,
        reason: 'send_failed',
        backendId: selected.backendId,
        requestId,
        error: error.message,
      };
    }

    if (sent === false) {
      requestState.set(requestId, { status: 'failed', backendId: selected.backendId, previousBackendIds });
      return { ok: false, reason: 'send_failed', backendId: selected.backendId, requestId };
    }

    requestState.set(requestId, { status: 'sent', backendId: selected.backendId, previousBackendIds });
    return { ok: true, backendId: selected.backendId, requestId };
  }

  function routeRequest(request = {}) {
    const requestId = makeRequestId(request);
    const current = requestState.get(requestId);
    if (current && current.status === 'completed') {
      return completedResult(requestId, current);
    }

    const selected = chooseBackend(requestId, request);
    if (!selected.ok) {
      return selected;
    }

    return routeToSelectedBackend(selected, request, requestId);
  }

  function routeFallback(request = {}) {
    const requestId = makeRequestId(request);
    const current = requestState.get(requestId);
    if (!current || current.status !== 'sent' || !current.backendId) {
      return { ok: false, reason: 'no_current_backend', requestId };
    }
    if (current.status === 'completed') {
      return completedResult(requestId, current);
    }

    const chain = [backendConfig.primary, ...(backendConfig.fallback || [])].filter(Boolean);
    const currentIndex = chain.indexOf(current.backendId);
    const candidates = currentIndex >= 0 ? chain.slice(currentIndex + 1) : backendConfig.fallback || [];
    for (const backendId of candidates) {
      const fallbackBackend = getRoutableBackend(backendId);
      if (fallbackBackend) {
        const previousBackendIds = [...(current.previousBackendIds || []), current.backendId];
        return routeToSelectedBackend(fallbackBackend, request, requestId, previousBackendIds);
      }
    }

    return {
      ok: false,
      reason: 'fallback_unavailable',
      backendId: current.backendId,
      requestId,
    };
  }

  function markCompleted(requestId, backendId) {
    const current = requestState.get(requestId);
    if (current && current.status === 'completed') {
      return completedResult(requestId, current);
    }
    if (current && current.backendId && current.backendId !== backendId) {
      return {
        ok: false,
        reason: 'wrong_backend',
        requestId,
        backendId,
        ownerBackendId: current.backendId,
        ignored: true,
      };
    }

    requestState.set(requestId, { status: 'completed', backendId });
    return { ok: true, requestId, backendId };
  }

  function getState(requestId) {
    return requestState.get(requestId);
  }

  return {
    routeRequest,
    routeFallback,
    markCompleted,
    getState,
  };
}

module.exports = {
  createRouter,
};
