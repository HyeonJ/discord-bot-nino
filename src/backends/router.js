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

function isHealthy(adapter, backendConfig) {
  if (!adapter || typeof adapter.health !== 'function') {
    return false;
  }

  try {
    const result = adapter.health(backendConfig);
    return Boolean(result === true || (result && result.alive));
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

function createRouter({ config, adapters, state } = {}) {
  const requestState = state || createDefaultState();
  const backendAdapters = adapters || {};
  const backendConfig = config || { primary: null, fallback: [], backends: {} };

  function chooseBackend(requestId) {
    const primary = backendConfig.primary;
    if (!primary) {
      return { ok: false, reason: 'no_primary', requestId };
    }

    if (!isBackendEnabled(backendConfig, primary)) {
      return { ok: false, reason: 'primary_disabled', backendId: primary, requestId };
    }

    const primaryAdapter = backendAdapters[primary];
    const primaryConfig = getBackendConfig(backendConfig, primary);
    if (isHealthy(primaryAdapter, primaryConfig)) {
      return { ok: true, backendId: primary, adapter: primaryAdapter, config: primaryConfig };
    }

    for (const backendId of backendConfig.fallback || []) {
      if (!isBackendEnabled(backendConfig, backendId)) {
        continue;
      }

      const adapter = backendAdapters[backendId];
      const fallbackConfig = getBackendConfig(backendConfig, backendId);
      if (isHealthy(adapter, fallbackConfig)) {
        return { ok: true, backendId, adapter, config: fallbackConfig };
      }
    }

    return { ok: false, reason: 'backend_unavailable', backendId: primary, requestId };
  }

  function routeRequest(request = {}) {
    const requestId = makeRequestId(request);
    const current = requestState.get(requestId);
    if (current && current.status === 'completed') {
      return completedResult(requestId, current);
    }

    const selected = chooseBackend(requestId);
    if (!selected.ok) {
      return selected;
    }

    const requestWithId = request.requestId ? request : { ...request, requestId };
    let sent = false;
    try {
      sent = selected.adapter.send(requestWithId, selected.config);
    } catch (error) {
      requestState.set(requestId, {
        status: 'failed',
        backendId: selected.backendId,
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
      requestState.set(requestId, { status: 'failed', backendId: selected.backendId });
      return { ok: false, reason: 'send_failed', backendId: selected.backendId, requestId };
    }

    requestState.set(requestId, { status: 'sent', backendId: selected.backendId });
    return { ok: true, backendId: selected.backendId, requestId };
  }

  function markCompleted(requestId, backendId) {
    const current = requestState.get(requestId);
    if (current && current.status === 'completed') {
      return completedResult(requestId, current);
    }

    requestState.set(requestId, { status: 'completed', backendId });
    return { ok: true, requestId, backendId };
  }

  function getState(requestId) {
    return requestState.get(requestId);
  }

  return {
    routeRequest,
    markCompleted,
    getState,
  };
}

module.exports = {
  createRouter,
};
