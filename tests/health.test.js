const http = require('http');

describe('health endpoint', () => {
  let healthModule;
  const TEST_PORT = 58190;

  beforeAll(() => {
    process.env.HEALTH_PORT = String(TEST_PORT);
    process.env.TMUX_SESSION = 'nino';
    healthModule = require('../health');
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
});
