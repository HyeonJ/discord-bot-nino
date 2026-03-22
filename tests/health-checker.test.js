const { analyzeHealth, parseTargets } = require('../health-checker');

describe('health-checker', () => {
  describe('parseTargets', () => {
    test('빈 HEALTH_TARGETS는 빈 배열 반환', () => {
      process.env.HEALTH_TARGETS = '';
      expect(parseTargets()).toEqual([]);
    });

    test('HEALTH_TARGETS를 올바르게 파싱한다', () => {
      process.env.HEALTH_TARGETS = 'haru:http://100.86.89.63:58090,rund:http://100.86.89.20:58090';
      const targets = parseTargets();
      expect(targets).toHaveLength(2);
      expect(targets[0]).toEqual({ name: 'haru', url: 'http://100.86.89.63:58090' });
      expect(targets[1]).toEqual({ name: 'rund', url: 'http://100.86.89.20:58090' });
    });
  });

  describe('analyzeHealth', () => {
    test('정상 상태면 이슈 없음', () => {
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

    test('data가 null이면 연결 실패', () => {
      const issues = analyzeHealth('haru', null);
      expect(issues).toHaveLength(1);
      expect(issues[0]).toMatch(/연결 실패/);
    });

    test('tmux_alive=false 감지', () => {
      const data = {
        timestamp: new Date().toISOString(),
        claude_pid: 12345,
        tmux_alive: false,
        watcher_alive: true,
      };
      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('tmux'))).toBe(true);
    });

    test('watcher_alive=false 감지', () => {
      const data = {
        timestamp: new Date().toISOString(),
        claude_pid: 12345,
        tmux_alive: true,
        watcher_alive: false,
      };
      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('watcher'))).toBe(true);
    });

    test('claude_pid=null 감지', () => {
      const data = {
        timestamp: new Date().toISOString(),
        claude_pid: null,
        tmux_alive: true,
        watcher_alive: true,
      };
      const issues = analyzeHealth('haru', data);
      expect(issues.some(i => i.includes('Claude PID'))).toBe(true);
    });

    test('stale timestamp 감지 (90초 이상)', () => {
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

    test('최근 timestamp는 stale 아님', () => {
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
