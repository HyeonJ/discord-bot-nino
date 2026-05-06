const tmux = require('./tmux');

const codex = {
  id: 'codex',
  processPattern: 'codex',

  health(config) {
    const enabled = Boolean(config && config.enabled);
    if (!enabled) {
      return { enabled, sessionAlive: false, alive: false, pid: null };
    }

    const sessionAlive = tmux.checkSession(config.session);
    const pid = sessionAlive ? tmux.getChildPid(config.session, this.processPattern) : null;
    return { enabled, sessionAlive, alive: sessionAlive && pid !== null, pid };
  },

  canRoute(config) {
    const result = this.health(config);
    return Boolean(result && result.alive === true);
  },

  send(request, config) {
    const payload = request && request.payload;
    if (payload === undefined || payload === null) {
      throw new Error('Codex backend send requires a payload');
    }
    if (!config || !config.session) {
      throw new Error('Codex backend send requires a tmux session');
    }

    return tmux.sendKeys(config.session, payload);
  },

  restart() {
    return { ok: false, reason: 'not_implemented' };
  },
};

module.exports = codex;
