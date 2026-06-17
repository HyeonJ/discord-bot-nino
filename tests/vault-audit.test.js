const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SCRIPT = path.join(__dirname, '..', 'scripts', 'vault-audit.sh');

let vaultDir;

function wikiCat(cat) {
  const d = path.join(vaultDir, 'wiki', cat);
  fs.mkdirSync(d, { recursive: true });
  return d;
}

function writeNote(cat, name, body) {
  fs.writeFileSync(path.join(wikiCat(cat), name), body);
}

function runAudit(args = []) {
  return execFileSync('bash', [SCRIPT, ...args], {
    env: { ...process.env, VAULT_DIR: vaultDir },
    encoding: 'utf8',
  });
}

function report() {
  return fs.readFileSync(path.join(vaultDir, 'audit-report.md'), 'utf8');
}

beforeEach(() => {
  vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), 'vault-audit-'));
});

afterEach(() => {
  fs.rmSync(vaultDir, { recursive: true, force: true });
});

describe('vault-audit.sh', () => {
  test('깨진 wikilink([[없는노트]])를 검출한다', () => {
    writeNote('tech', '노트A.md', '# 노트A\n\n[[실존노트]] 참고');
    writeNote('tech', '실존노트.md', '# 실존노트\n내용');
    writeNote('tech', '노트B.md', '# 노트B\n\n[[유령노트]] 링크'); // 유령노트.md 없음
    runAudit();
    const r = report();
    expect(r).toMatch(/유령노트/);
    expect(r).not.toMatch(/실존노트.*broken|broken.*실존노트/i); // 실존노트는 깨진 링크 아님
  });

  test('중복 파일명(slug)을 검출한다', () => {
    writeNote('tech', '도쿄여행.md', '# 도쿄여행\n내용1');
    writeNote('travel', '도쿄여행.md', '# 도쿄여행\n내용2'); // 다른 카테고리 같은 이름
    runAudit();
    expect(report()).toMatch(/도쿄여행/);
    expect(report()).toMatch(/중복|duplicate/i);
  });

  test('오래된 노트(stale)를 후보로 표시한다', () => {
    writeNote('tech', '낡은노트.md', '---\nupdated: 2020-01-01\n---\n# 낡은노트\n내용');
    writeNote('tech', '최신노트.md', '---\nupdated: 2026-06-17\n---\n# 최신노트\n내용');
    runAudit(['--stale-days', '180']);
    const r = report();
    expect(r).toMatch(/낡은노트/);
    expect(r).not.toMatch(/최신노트.*stale|stale.*최신노트/i);
  });

  test('깨끗한 vault는 발견 0으로 리포트한다', () => {
    writeNote('tech', 'a.md', '---\nupdated: 2026-06-17\n---\n# A\n\n[[b]]');
    writeNote('tech', 'b.md', '---\nupdated: 2026-06-17\n---\n# B\n\n[[a]]');
    runAudit();
    const r = report();
    expect(r).toMatch(/0/); // 요약에 0건
  });

  test('audit-report.md를 vault 루트에 생성한다', () => {
    writeNote('tech', 'a.md', '# A\n내용');
    runAudit();
    expect(fs.existsSync(path.join(vaultDir, 'audit-report.md'))).toBe(true);
  });

  test('stdout에 요약(broken/중복/stale 카운트)을 출력한다', () => {
    writeNote('tech', 'a.md', '# A\n\n[[없는것]]');
    const out = runAudit();
    expect(out).toMatch(/broken|깨진/i);
  });
});
