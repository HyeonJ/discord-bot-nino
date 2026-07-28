const {
  analyzeHealth,
  parseTargets,
  registerCheck,
  shouldAlert,
  resetDebounceState,
  FAILURE_THRESHOLD,
} = require('../src/health-checker');

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

  describe('디바운스 (연속 실패 오탐 방지)', () => {
    beforeEach(() => resetDebounceState());

    test('기본 임계값은 3', () => {
      expect(FAILURE_THRESHOLD).toBe(3);
    });

    test('registerCheck: 실패면 +1, 정상이면 0 리셋', () => {
      expect(registerCheck('rund', true)).toBe(1);
      expect(registerCheck('rund', true)).toBe(2);
      expect(registerCheck('rund', false)).toBe(0); // 정상 → 리셋
      expect(registerCheck('rund', true)).toBe(1);
    });

    test('임계값 미만 연속 실패 → 알림 안 함 (단일/이중 blip 거름)', () => {
      registerCheck('rund', true); // 1회
      expect(shouldAlert('rund')).toBe(false);
      registerCheck('rund', true); // 2회
      expect(shouldAlert('rund')).toBe(false);
    });

    test('임계값 도달(3회 연속) → 알림 발동', () => {
      registerCheck('rund', true);
      registerCheck('rund', true);
      registerCheck('rund', true); // 3회
      expect(shouldAlert('rund')).toBe(true);
    });

    test('중간에 정상 1회 끼면 카운터 리셋 → 알림 안 함 (blip 시나리오)', () => {
      registerCheck('rund', true); // 1
      registerCheck('rund', true); // 2
      registerCheck('rund', false); // 정상 blip 복구 → 리셋
      registerCheck('rund', true); // 다시 1
      expect(shouldAlert('rund')).toBe(false);
    });

    test('봇별 카운터 독립', () => {
      registerCheck('rund', true);
      registerCheck('rund', true);
      registerCheck('rund', true);
      registerCheck('haru', true); // haru는 1회뿐
      expect(shouldAlert('rund')).toBe(true);
      expect(shouldAlert('haru')).toBe(false);
    });
  });
});
