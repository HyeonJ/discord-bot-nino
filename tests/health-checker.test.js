const { analyzeHealth, parseTargets } = require('../src/health-checker');

describe('health-checker', () => {
  describe('parseTargets', () => {
    test('returns an empty array when HEALTH_TARGETS is empty', () => {
      process.env.HEALTH_TARGETS = '';
      expect(parseTargets()).toEqual([]);
    });

    test('parses HEALTH_TARGETS entries', () => {
      process.env.HEALTH_TARGETS = 'haru:http://100.86.89.63:58090,rund:http://100.86.89.20:58090';
      const targets = parseTargets();
      expect(targets).toHaveLength(2);
      expect(targets[0]).toEqual({ name: 'haru', url: 'http://100.86.89.63:58090' });
      expect(targets[1]).toEqual({ name: 'rund', url: 'http://100.86.89.20:58090' });
    });
  });

  describe('analyzeHealth', () => {
    test('legacy healthy status has no issues', () => {
      const data = {
        bot: 'haru',
        timestamp: new Date().toISOString(),
        claude_pid: 12345,
        tmux_alive: true,
        relay_alive: true,
        watcher_alive: true,
        uptime: 100,
      };

      expect(analyzeHealth('haru', data)).toEqual([]);
    });

    test('provider-neutral healthy primary has no issues even when disabled backend is down', () => {
      const data = {
        bot: 'haru',
        timestamp: new Date().toISOString(),
        primary_backend: 'claude',
        backends: {
          claude: { enabled: true, alive: true, pid: 12345 },
          codex: { enabled: false, alive: false, pid: null },
        },
        watcher_alive: true,
      };

      expect(analyzeHealth('haru', data)).toEqual([]);
    });

    test('provider-neutral health reports when no enabled backend is alive', () => {
      const data = {
        timestamp: new Date().toISOString(),
        primary_backend: 'claude',
        backends: {
          claude: { enabled: true, alive: false, pid: null },
          codex: { enabled: false, alive: false, pid: null },
        },
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('No enabled backend alive'))).toBe(true);
    });

    test('provider-neutral health reports unhealthy enabled primary backend', () => {
      const data = {
        timestamp: new Date().toISOString(),
        primary_backend: 'claude',
        backends: {
          claude: { enabled: true, alive: false, pid: null },
          codex: { enabled: true, alive: true, pid: 67890 },
        },
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('Primary backend claude unhealthy'))).toBe(true);
      expect(issues.some(i => i.includes('No enabled backend alive'))).toBe(false);
    });

    test('provider-neutral health does not alert on disabled primary backend', () => {
      const data = {
        timestamp: new Date().toISOString(),
        primary_backend: 'codex',
        backends: {
          claude: { enabled: true, alive: true, pid: 12345 },
          codex: { enabled: false, alive: false, pid: null },
        },
        watcher_alive: true,
      };

      expect(analyzeHealth('haru', data)).toEqual([]);
    });

    test('provider-neutral health reports missing primary backend entry', () => {
      const data = {
        timestamp: new Date().toISOString(),
        primary_backend: 'claude',
        backends: {
          codex: { enabled: false, alive: false, pid: null },
        },
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('Primary backend claude missing'))).toBe(true);
    });

    test('health payload error is reported before backend liveness issues', () => {
      const data = {
        timestamp: new Date().toISOString(),
        error: 'Primary backend codex is disabled',
        primary_backend: 'codex',
        backends: {
          claude: { enabled: false, alive: false, pid: null },
          codex: { enabled: false, alive: false, pid: null },
        },
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues[0]).toContain('Health payload error: Primary backend codex is disabled');
      expect(issues.some(i => i.includes('No enabled backend alive'))).toBe(true);
    });

    test('provider-neutral health reports malformed backend entries', () => {
      const data = {
        timestamp: new Date().toISOString(),
        primary_backend: 'claude',
        backends: {
          claude: null,
        },
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('Backend claude health malformed'))).toBe(true);
    });

    test('data null reports connection failure', () => {
      const issues = analyzeHealth('haru', null);
      expect(issues).toHaveLength(1);
      expect(issues[0]).toMatch(/connection failed/);
    });

    test('legacy tmux_alive=false is detected', () => {
      const data = {
        timestamp: new Date().toISOString(),
        claude_pid: 12345,
        tmux_alive: false,
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('tmux'))).toBe(true);
    });

    test('watcher_alive=false is detected', () => {
      const data = {
        timestamp: new Date().toISOString(),
        claude_pid: 12345,
        tmux_alive: true,
        watcher_alive: false,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('watcher'))).toBe(true);
    });

    test('legacy claude_pid=null is detected', () => {
      const data = {
        timestamp: new Date().toISOString(),
        claude_pid: null,
        tmux_alive: true,
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('Claude PID'))).toBe(true);
    });

    test('stale timestamp is detected after 90 seconds', () => {
      const staleTime = new Date(Date.now() - 100 * 1000).toISOString();
      const data = {
        timestamp: staleTime,
        claude_pid: 12345,
        tmux_alive: true,
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('stale'))).toBe(true);
    });

    test('recent timestamp is not stale', () => {
      const data = {
        timestamp: new Date().toISOString(),
        claude_pid: 12345,
        tmux_alive: true,
        watcher_alive: true,
      };

      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('stale'))).toBe(false);
    });
  });
});
