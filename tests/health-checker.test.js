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

/**
 * 🔴 경보 발송 축 — **두 시험 파일 다 이 축을 안 재고 있었다** (2026-07-31)
 *
 * `sendAlert` 는 `execSync` 실패를 `console.error` 로 삼킨다. 헬스체커가 *"봇이 아프다"* 를
 * 알리려다 실패하면 **그 실패조차 아무도 모른다** — `#88`(check-auth 가 발송 실패를 삼키고
 * "보냈다"로 기록)과 같은 부류인데, 여기선 **감시기 자신의 알림 경로**다.
 *
 * 🔑 그리고 기본값이 틀렸다:
 *   `path.join(process.cwd(), 'src', 'discord-send')`
 *   relay 의 실제 cwd 는 `/home/bpx27/yaksu-bot-core-live` (systemd WorkingDirectory) 라
 *   존재하지 않는 경로가 만들어진다. 지금 안 터지는 건 `.env` 가 `DISCORD_SEND_BIN` 을
 *   덮고 있어서일 뿐이다 — **막아둔 게 아니라 안 밟고 있을 뿐.**
 *   레포 규칙: *"기본값 넣지 말고 필수면 에러로 안내"*.
 *
 * 🔸 룬드 M:6y6k: *"안 잡히면 고장이 없는 게 아니라 재는 시험이 없는 것"* — 정확히 그 자리였다.
 */
describe('health-checker — 경보 발송 실패를 삼키지 않는다', () => {
  const fs = require('fs');
  const os = require('os');
  const path = require('path');

  function freshLoad(envVal) {
    jest.resetModules();          // 🔴 jest 는 자체 레지스트리라 require.cache 조작이 무효다
    if (envVal === undefined) delete process.env.DISCORD_SEND_BIN;
    else process.env.DISCORD_SEND_BIN = envVal;
    return require('../relay-addons/health-checker');
  }

  test('🧪 [양성 대조군] 성공하면 true — 실패 단언이 항진명제가 아님을 고정한다', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hcbin-'));
    const bin = path.join(dir, 'send-ok');
    fs.writeFileSync(bin, '#!/bin/bash\nexit 0\n', { mode: 0o755 });
    const hc = freshLoad(bin);
    expect(hc.sendAlert('메시지', 'DM-Darren')).toBe(true);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  test('발송이 실패하면 false 를 돌려준다 (조용히 성공으로 접지 않는다)', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hcbin-'));
    const bin = path.join(dir, 'send-bad');
    fs.writeFileSync(bin, '#!/bin/bash\necho boom >&2\nexit 3\n', { mode: 0o755 });
    const hc = freshLoad(bin);
    expect(hc.sendAlert('메시지', 'DM-Darren')).toBe(false);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  test('DISCORD_SEND_BIN 이 없으면 cwd 기준 경로를 지어내지 않고 그 사실을 말한다', () => {
    const hc = freshLoad(undefined);
    expect(() => hc.discordSendBin()).toThrow(/DISCORD_SEND_BIN/);
  });

  test('경로를 호출 시점에 읽는다 (require 때 얼지 않는다 — 시험 파일이 둘이다)', () => {
    const hc = freshLoad('/tmp/first-value');
    process.env.DISCORD_SEND_BIN = '/tmp/second-value';
    expect(hc.discordSendBin()).toBe('/tmp/second-value');
  });
});

/**
 * 🔴 배선 축 — **만든 것이 배선한 것으로 자동 승격되지 않는다** (룬드 리뷰 M:eikt)
 *
 * 앞 절 19건은 `sendAlert` 를 **직접 호출**해서 반환값을 잠갔다. 그런데 호출부(:116)는
 * 그 값을 **버리고** 있었고, 시험은 그걸 그대로 둬도 초록이었다.
 *   🔑 *"셀 수 있게 만든 것"* 과 *"세는 것"* 은 다르다. 주석은 *"부르는 쪽이 셀 수 있어야
 *     보냈다와 보내려다 실패했다가 갈린다"* 라고 약속했는데, **아무도 안 세고 있었다.**
 *     — 내가 같은 날 코어 `#110` 에 한 지적을 내가 그대로 했다(약속이 기제보다 넓다).
 *
 * 🔴 그리고 파보니 한 겹 더 있었다:
 *   :117 `lastAlertTime.set(...)`  실패해도 쿨다운을 시작한다 → **재시도가 5분 막힌다**
 *   :118 `console.log('alert sent')` 실패해도 "보냈다"로 남는다 → `#88` 그 자체
 *   ⇒ 발송이 깨진 채로 "보냈다" 로그가 쌓이고, 그동안 재시도는 억제된다.
 */
describe('health-checker — 실패한 발송을 "보냈다"로 만들지 않는다 (배선)', () => {
  const fs = require('fs');
  const os = require('os');
  const path = require('path');

  // 🔴 스텁이 **불렸다는 사실 자체**를 남긴다 — 안 남기면 아래 「실패 집계 0」이 항진명제가 된다.
  //   실제로 그랬다(2026-08-02): 모듈 재적재가 무효라 경보 경로에 아예 안 들어갔는데도
  //   `alertSendFailures() === 0` 은 그대로 참이라 **이 대조군만 초록이었다.**
  //   🔑 「0 이다」는 «안 실패했다»와 «안 돌았다»를 못 가른다. 분모를 같이 잰다.
  function loadWith(binBody) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hcwire-'));
    const bin = path.join(dir, 'send');
    const calls = path.join(dir, 'calls.txt');
    const logged = binBody.replace(
      /^#!.*\n/,
      // 🔑 «호출당 한 줄» 고정 표지 — 인자를 그대로 적으면 알림이 여러 줄이라 1건이 3줄이 된다
      //   (오늘 아침 `grep -c` 에서 밟은 「줄을 센다 ≠ 건을 센다」와 같은 축)
      (m) => `${m}printf 'CALL\\n' >> ${JSON.stringify(calls)}\n`
    );
    fs.writeFileSync(bin, logged, { mode: 0o755 });
    jest.resetModules();          // 🔴 jest 는 자체 레지스트리라 require.cache 조작이 무효다
    process.env.DISCORD_SEND_BIN = bin;
    // 닿지 않는 주소 → fetchHealth 실패 → issues 발생 → 경보 경로로 들어간다
    process.env.HEALTH_TARGETS = '하루:http://127.0.0.1:1/health';
    const sendCount = () =>
      (fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n').filter(Boolean).length : 0);
    return { hc: require('../relay-addons/health-checker'), dir, sendCount };
  }

  test('🧪 [양성 대조군] 발송이 성공하면 실패 집계가 0 이다', async () => {
    const { hc, dir, sendCount } = loadWith('#!/bin/bash\nexit 0\n');
    await hc.checkAll();
    // 🔑 먼저 «돌았나»를 잰다 — 이게 0 이면 아래 집계 0 은 아무 뜻이 없다
    expect(sendCount()).toBe(1);
    expect(hc.alertSendFailures()).toBe(0);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  test('발송이 실패하면 집계에 남는다 (호출부가 반환값을 실제로 읽는다)', async () => {
    const { hc, dir } = loadWith('#!/bin/bash\nexit 3\n');
    await hc.checkAll();
    expect(hc.alertSendFailures()).toBe(1);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  test('🔴 실패한 발송은 쿨다운을 시작하지 않는다 (다음 tick 에 재시도된다)', async () => {
    const { hc, dir } = loadWith('#!/bin/bash\nexit 3\n');
    await hc.checkAll();
    await hc.checkAll();
    // 쿨다운이 걸렸다면 두 번째 시도가 아예 없어 집계는 1 에 머문다
    expect(hc.alertSendFailures()).toBe(2);
    fs.rmSync(dir, { recursive: true, force: true });
  });
});
