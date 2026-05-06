const tmux = require('./tmux');

const claude = {
  id: 'claude',
  processPattern: 'claude',

  health(config) {
    const enabled = Boolean(config && config.enabled);
    if (!enabled) {
      return { enabled, alive: false, pid: null };
    }

    const alive = tmux.checkSession(config.session);
    const pid = alive ? tmux.getChildPid(config.session, this.processPattern) : null;
    return { enabled, alive, pid };
  },

  send(request, config) {
    const payload = request && request.payload !== undefined ? request.payload : request && request.preview;
    if (payload === undefined || payload === null) {
      throw new Error('Claude backend send requires a payload');
    }

    return tmux.sendKeys(config.session, payload);
  },

  restart() {
    return { ok: false, reason: 'not_implemented' };
  },
};

module.exports = claude;
