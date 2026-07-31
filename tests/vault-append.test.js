const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SCRIPT = path.join(__dirname, '..', 'scripts', 'vault-append.sh');

let vaultDir;
let fakeClaudeBin;
let botDir; // 테스트용 임시 BOT_DIR — 실제 memory/logs 오염 방지

// 가짜 claude: stdin/-p 무시하고 고정 마크다운 노트 출력 (실제 LLM 호출 회피)
function makeFakeClaude(outputMarkdown) {
  const binDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fakebin-'));
  const bin = path.join(binDir, 'claude');
  fs.writeFileSync(
    bin,
    `#!/usr/bin/env bash\ncat <<'FAKEOUT'\n${outputMarkdown}\nFAKEOUT\n`,
    { mode: 0o755 }
  );
  return bin;
}

function runAppend(args, opts = {}) {
  const { env: optsEnv, ...restOpts } = opts;
  return execFileSync('bash', [SCRIPT, ...args], {
    env: {
      ...process.env,
      VAULT_DIR: vaultDir,
      CLAUDE_BIN: fakeClaudeBin,
      BOT_DIR: botDir, // 실제 memory/logs 격리
      ...(optsEnv || {}),
    },
    encoding: 'utf8',
    ...restOpts,
  });
}

function wikiDir() {
  return path.join(vaultDir, 'wiki');
}

beforeEach(() => {
  vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), 'vault-append-'));
  botDir = fs.mkdtempSync(path.join(os.tmpdir(), 'botdir-'));
  fs.mkdirSync(path.join(botDir, 'logs'), { recursive: true });
  fs.mkdirSync(path.join(botDir, 'scripts'), { recursive: true });
  // git 초기화 (스크립트 끝의 git sync가 깨지지 않게)
  execFileSync('git', ['init', '-q', vaultDir]);
  execFileSync('git', ['-C', vaultDir, 'config', 'user.email', 'test@test'], {});
  execFileSync('git', ['-C', vaultDir, 'config', 'user.name', 'test'], {});
  fakeClaudeBin = makeFakeClaude(
    '---\ntitle: "테스트 노트"\ncategory: tech\ncreated: 2026-06-17\nupdated: 2026-06-17\n---\n\n# 테스트 노트\n\n병합된 내용 본문입니다. 충분히 길게 작성된 마크다운 노트 본문.'
  );
});

afterEach(() => {
  fs.rmSync(vaultDir, { recursive: true, force: true });
  fs.rmSync(botDir, { recursive: true, force: true });
});

describe('vault-append.sh 안전장치', () => {
  test('--dry-run은 파일을 쓰지 않고 계획만 출력한다', () => {
    const out = runAppend([
      '--topic', '새 주제',
      '--category', 'tech',
      '--content', '내용',
      '--dry-run',
    ]);
    expect(out).toMatch(/dry-run|CREATE|계획/i);
    // wiki에 파일이 생기지 않아야 함
    const created = fs.existsSync(path.join(wikiDir(), 'tech'))
      ? fs.readdirSync(path.join(wikiDir(), 'tech'))
      : [];
    expect(created.length).toBe(0);
    // vault log.md도 안 생김
    expect(fs.existsSync(path.join(vaultDir, 'log.md'))).toBe(false);
  });

  test('실제 실행 시 vault log.md(audit trail)에 기록한다', () => {
    runAppend(['--topic', '새 주제', '--category', 'tech', '--content', '내용']);
    const logPath = path.join(vaultDir, 'log.md');
    expect(fs.existsSync(logPath)).toBe(true);
    const log = fs.readFileSync(logPath, 'utf8');
    expect(log).toMatch(/새 주제/);
  });

  test('기존 노트를 병합할 때 .bak 백업을 남긴다', () => {
    // 기존 노트 미리 생성
    const catDir = path.join(wikiDir(), 'tech');
    fs.mkdirSync(catDir, { recursive: true });
    const existing = path.join(catDir, '새-주제.md');
    fs.writeFileSync(existing, '---\ntitle: "새 주제"\n---\n\n# 새 주제\n\n기존 내용');

    runAppend(['--topic', '새 주제', '--category', 'tech', '--content', '추가 내용']);

    const baks = fs.readdirSync(catDir).filter((f) => f.endsWith('.bak'));
    expect(baks.length).toBeGreaterThanOrEqual(1);
  });

  test('새 노트 생성 시 wiki에 파일이 만들어진다', () => {
    runAppend(['--topic', '완전 새 주제', '--category', 'tech', '--content', '내용']);
    const files = fs.readdirSync(path.join(wikiDir(), 'tech'));
    expect(files.some((f) => f.endsWith('.md'))).toBe(true);
  });

  test('필수 인자 누락 시 에러', () => {
    expect(() => runAppend(['--topic', '주제만'])).toThrow();
  });

  test('LLM 출력의 백슬래시가 저장 파일에 보존된다 (printf)', () => {
    const bsBin = makeFakeClaude(
      '---\ntitle: "백슬래시"\ncategory: tech\ncreated: 2026-06-17\n---\n\n# 백슬래시\n\n' +
        String.raw`정규식 \d+ 와 경로 C:\Users\test 를 포함한 충분히 긴 본문입니다.`
    );
    runAppend(['--topic', '백슬래시', '--category', 'tech', '--content', '내용'], {
      env: { CLAUDE_BIN: bsBin },
    });
    const f = fs.readdirSync(path.join(wikiDir(), 'tech')).find((x) => x.endsWith('.md'));
    const body = fs.readFileSync(path.join(wikiDir(), 'tech', f), 'utf8');
    expect(body).toContain(String.raw`\d+`);
    expect(body).toContain(String.raw`C:\Users\test`);
  });

  /**
   * 🔴 nvm 이 없는 기계에서도 돌아야 한다 (2026-07-31, 룬드 맥에서 실측)
   *
   *   scripts/vault-append.sh: line 200: /Users/klaude/.nvm/nvm.sh: No such file or directory
   *
   * 그 줄은 `source ~/.nvm/nvm.sh && … "$CLAUDE_BIN" …` 였고, nvm 이 없으면 **줄 전체가**
   * rc≠0 로 죽어 이 파일의 시험 4건이 통째로 빨간불이었다.
   *
   * 🔑 축을 잘못 고르면 **재현이 안 되는 게 아니라 "없다"로 보인다.** 나는 `grep -P` 스텁으로
   *   흔들어 놓고 6 pass 를 *"결함 없음"* 으로 읽었다 — **없는 축을 흔들고 있었다.**
   * 🔑 원인이 **내가 가진 것**(nvm)이라 내 기계에선 원리적으로 안 보인다.
   *   상대 기계가 유일한 관찰자였고, 이 시험은 그 관찰을 **내 쪽으로 옮겨오는 장치**다.
   *
   * nvm 은 node 를 PATH 에 올리는 **수단**이지 목적이 아니다. 이미 쓸 수 있으면 건너뛴다.
   */
  test('🧪 nvm 이 없는 기계(~/.nvm 부재)에서도 노트를 만든다 — 룬드 맥 재현', () => {
    // ⚠️ HOME 만 바꾸면 **막은 게 아니다.** `NVM_DIR` 이 process.env 로 새어 들어와
    //   가짜 HOME 이어도 내 진짜 nvm 을 가리킨다 — 변이시험이 그걸 잡았다(0 fail).
    //   룬드 맥엔 **둘 다 없다.** 축을 하나만 막고 다른 하나를 열어두면 시험이
    //   맞는 이유가 아니라 **틀린 이유로 통과**한다.
    const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'nonvm-home-'));
    runAppend(['--topic', 'nvm없음', '--category', 'tech', '--content', '내용'], {
      env: { HOME: fakeHome, NVM_DIR: path.join(fakeHome, 'no-such-nvm') },
    });
    const files = fs.readdirSync(path.join(wikiDir(), 'tech'));
    expect(files.some((x) => x.endsWith('.md'))).toBe(true);
    fs.rmSync(fakeHome, { recursive: true, force: true });
  });

  // 🔴 node 도 nvm 도 없으면 **조용히 넘어가지 않는다.**
  //   이 갈래는 처음에 아무 시험도 안 밟고 있었다(변이 → 0 fail). 내 기계엔 node 가 있어서
  //   `load_node_env` 가 늘 성공했기 때문이다. **없는 조건은 만들어야 밟힌다.**
  //   여기서 안 죽으면 CLAUDE_BIN 이 엉뚱하게 실패하고 그게 "LLM 출력이 비었다"로 읽힌다
  //   — 원인이 두 단계 멀어지고, 사람은 프롬프트를 의심하게 된다.
  test('🧪 node 도 nvm 도 없으면 그 이유를 말하고 죽는다 (조용한 실패 금지)', () => {
    const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'nonode-home-'));
    // ⚠️ 처음엔 디렉터리 **이름**으로 걸렀다(`/nvm|node/`). `~/.local/bin` 에도 node 가 있어서
    //   그 필터를 통과했고, 시험이 대조군에서도 실패했다 — **양쪽에서 실패하는 시험은
    //   아무것도 안 가른다**(변이의 빨간불도 증거가 아니게 된다).
    //   ⇒ 이름이 아니라 **실제로 node 가 있는지**로 거른다. 표지가 아니라 성질을 본다.
    const leanPath = (process.env.PATH || '')
      .split(':')
      .filter((p) => p && !fs.existsSync(path.join(p, 'node')))
      .join(':');
    let threw = false;
    try {
      runAppend(['--topic', 'node없음', '--category', 'tech', '--content', '내용'], {
        env: { HOME: fakeHome, NVM_DIR: path.join(fakeHome, 'no-such-nvm'), PATH: leanPath },
      });
    } catch {
      threw = true;
    }
    expect(threw).toBe(true);
    fs.rmSync(fakeHome, { recursive: true, force: true });
  });
});
