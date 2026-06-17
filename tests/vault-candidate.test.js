const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SCRIPT = path.join(__dirname, '..', 'scripts', 'vault-candidate.sh');

let vaultDir;

function runCandidate(args, opts = {}) {
  return execFileSync('bash', [SCRIPT, ...args], {
    env: { ...process.env, VAULT_DIR: vaultDir },
    encoding: 'utf8',
    ...opts,
  });
}

function candidatesDir() {
  return path.join(vaultDir, 'inbox', 'wiki-candidates');
}

beforeEach(() => {
  vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), 'vault-cand-'));
});

afterEach(() => {
  fs.rmSync(vaultDir, { recursive: true, force: true });
});

describe('vault-candidate.sh', () => {
  test('local 소스 후보 파일을 inbox/wiki-candidates/에 생성한다', () => {
    runCandidate([
      '--topic', 'Spring Security OAuth2 디버깅',
      '--category', 'tech',
      '--content', 'code 파라미터 누락 시 401. redirect URI 화이트리스트 확인.',
      '--source', 'local',
    ]);
    const files = fs.readdirSync(candidatesDir());
    expect(files.length).toBe(1);
    expect(files[0]).toMatch(/^\d{4}-\d{2}-\d{2}-.*\.md$/);
  });

  test('후보 파일에 provenance frontmatter가 들어간다', () => {
    runCandidate([
      '--topic', '테스트 주제',
      '--category', 'tech',
      '--content', '내용 본문',
      '--source', 'discord',
      '--confidence', 'high',
      '--reason', '재사용 가능한 기술 해결법',
      '--target-note', 'wiki/tech/기존노트.md',
    ]);
    const file = fs.readdirSync(candidatesDir())[0];
    const body = fs.readFileSync(path.join(candidatesDir(), file), 'utf8');
    expect(body).toMatch(/source:\s*discord/);
    expect(body).toMatch(/privacy:\s*public/);
    expect(body).toMatch(/confidence:\s*high/);
    expect(body).toMatch(/reason:\s*".*재사용/);
    expect(body).toMatch(/target_note:\s*"wiki\/tech\/기존노트\.md"/);
    expect(body).toContain('내용 본문');
  });

  test('DM 소스는 기본 거부한다 (프라이버시)', () => {
    expect(() =>
      runCandidate([
        '--topic', 'DM 대화',
        '--category', 'general',
        '--content', '사적인 내용',
        '--source', 'dm',
      ])
    ).toThrow();
    expect(fs.existsSync(candidatesDir())).toBe(false);
  });

  test('privacy=sensitive는 거부한다', () => {
    expect(() =>
      runCandidate([
        '--topic', '계정 정보',
        '--category', 'general',
        '--content', '토큰 abc',
        '--source', 'local',
        '--privacy', 'sensitive',
      ])
    ).toThrow();
  });

  test('필수 인자(topic/category/content) 누락 시 에러', () => {
    expect(() => runCandidate(['--topic', '주제만'])).toThrow();
  });

  test('잘못된 category는 거부한다', () => {
    expect(() =>
      runCandidate([
        '--topic', '주제',
        '--category', 'invalid_cat',
        '--content', '내용',
        '--source', 'local',
      ])
    ).toThrow();
  });
});
