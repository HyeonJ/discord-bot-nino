const fs = require('fs');
const path = require('path');

const BLOCKING_STATES = new Set([
  'quota_exhausted',
  'cooldown',
  'maintenance',
  'disabled',
]);

function defaultStatusDir() {
  return path.resolve(__dirname, '..', '..', 'runtime', 'backend-status');
}

function statusDir() {
  return process.env.BACKEND_STATUS_DIR || defaultStatusDir();
}

function statusPath(backendId) {
  return path.join(statusDir(), `${backendId}.json`);
}

function parseUntil(value) {
  if (!value) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function isActiveUntil(until, now) {
  return until ? until.getTime() > now.getTime() : true;
}

function getRuntimeStatus(backendId, now = new Date()) {
  const file = statusPath(backendId);
  if (!fs.existsSync(file)) {
    return {
      backendId,
      state: 'ready',
      blocked: false,
      reason: null,
      until: null,
    };
  }

  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return {
      backendId,
      state: 'invalid',
      blocked: true,
      reason: 'malformed status file',
      until: null,
    };
  }

  const state = String(data.state || 'ready').trim().toLowerCase() || 'ready';
  const until = parseUntil(data.until);
  const blocked = BLOCKING_STATES.has(state) && isActiveUntil(until, now);

  return {
    backendId,
    state,
    blocked,
    reason: data.reason || null,
    until: until ? until.toISOString() : null,
  };
}

function isBlocked(backendId, now = new Date()) {
  return getRuntimeStatus(backendId, now).blocked;
}

module.exports = {
  getRuntimeStatus,
  isBlocked,
  statusPath,
};
