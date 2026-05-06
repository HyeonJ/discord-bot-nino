const http = require('http');

jest.mock('../src/backends/claude', () => ({
  health: jest.fn(),
}));

const claude = require('../src/backends/claude');

describe('health endpoint', () => {
  let healthModule;
  const TEST_PORT = 58190;

  beforeAll(() => {
    process.env.HEALTH_PORT = String(TEST_PORT);
    process.env.TMUX_SESSION = 'nino';
    delete process.env.PRIMARY_BACKEND;
    delete process.env.CLAUDE_ENABLED;
    delete process.env.CODEX_ENABLED;
    claude.health.mockReturnValue({
      enabled: true,
      sessionAlive: true,
      alive: true,
      pid: 123,
    });
    healthModule = require('../src/health');
    healthModule.start();
  });

  afterAll((done) => {
    healthModule.stop(done);
  });

  test('/health 엔드포인트가 JSON 응답을 반환한다', (done) => {
    http.get(`http://localhost:${TEST_PORT}/health`, (res) => {
      expect(res.statusCode).toBe(200);
      expect(res.headers['content-type']).toBe('application/json');

      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        const data = JSON.parse(body);
        expect(data.bot).toBe('nino');
        expect(data).toHaveProperty('timestamp');
        expect(data).toHaveProperty('tmux_alive');
        expect(data).toHaveProperty('claude_pid');
        expect(data).toHaveProperty('relay_alive', true);
        expect(data).toHaveProperty('watcher_alive');
        expect(data).toHaveProperty('uptime');
        expect(typeof data.uptime).toBe('number');
        done();
      });
    });
  });

  test('/health 이외의 경로는 404를 반환한다', (done) => {
    http.get(`http://localhost:${TEST_PORT}/other`, (res) => {
      expect(res.statusCode).toBe(404);
      done();
    });
  });

  test('setLastMessageAt이 last_message_at을 갱신한다', (done) => {
    healthModule.setLastMessageAt();

    http.get(`http://localhost:${TEST_PORT}/health`, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        const data = JSON.parse(body);
        expect(data).toHaveProperty('last_message_at');
        expect(data.last_message_at).not.toBeNull();
        done();
      });
    });
  });

  test('/health reports provider-neutral backend health with legacy fields', (done) => {
    http.get(`http://localhost:${TEST_PORT}/health`, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        const data = JSON.parse(body);

        expect(data.primary_backend).toBe('claude');
        expect(data.backends).toEqual({
          claude: {
            enabled: true,
            sessionAlive: true,
            alive: true,
            pid: 123,
          },
          codex: {
            enabled: false,
            sessionAlive: false,
            alive: false,
            pid: null,
          },
        });
        expect(data.claude_pid).toBe(123);
        expect(data.tmux_alive).toBe(true);
        done();
      });
    });
  });
});
