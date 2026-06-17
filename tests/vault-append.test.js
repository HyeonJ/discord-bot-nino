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
});
