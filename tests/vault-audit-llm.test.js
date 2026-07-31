const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SCRIPT = path.join(__dirname, '..', 'scripts', 'vault-audit-llm.sh');

// 🔴 이 스크립트는 `date --version` 이 GNU 가 아니면 **시작하자마자 exit 1** 한다
//   (scripts/vault-audit.sh:18 — 의도된 가드다). 그 갈래를 모르고 그냥 돌리면
//   **BSD 기계에서 이 파일 전부가 빨간불**이 된다. 룬드 맥에서 main 이 17 fail 이었고,
//   전부 vault-audit 계열이었다.
//   🔑 **원래 빨간 판 위에 빨간 걸 더하면 아무도 못 본다.** 그리고 17이 기준선이면
//     상대 봇이 이 레포의 **관측자로 기능하지 못한다** — PR 하나의 문제가 아니다.
//   ⇒ 능력을 재서 판정 불가(skip)로 접는다. 통과로도 실패로도 접지 않는다.
//     bun 은 skip 개수를 세어 보고하므로 "이 축은 저 기계에서 안 쟀다"가 남는다.
const HAS_GNU_DATE = (() => {
  try {
    return execFileSync('date', ['--version'], { encoding: 'utf8' }).includes('GNU');
  } catch {
    return false;
  }
})();


let vaultDir;
let fakeClaudeBin;
let callLog; // 가짜 claude가 호출 인자를 남기는 파일

// 가짜 claude: 호출되면 callLog에 흔적 + 고정 판정 출력
function makeFakeClaude(verdict) {
  const binDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fakebin-'));
  const bin = path.join(binDir, 'claude');
  fs.writeFileSync(
    bin,
    `#!/usr/bin/env bash\necho "called" >> "${callLog}"\ncat <<'OUT'\n${verdict}\nOUT\n`,
    { mode: 0o755 }
  );
  return bin;
}

function note(cat, name, body, ageDays = 0) {
  const d = path.join(vaultDir, 'wiki', cat);
  fs.mkdirSync(d, { recursive: true });
  const p = path.join(d, name);
  fs.writeFileSync(p, body);
  if (ageDays > 0) {
    const t = Date.now() / 1000 - ageDays * 86400;
    fs.utimesSync(p, t, t); // mtime을 과거로
  }
  return p;
}

function runLlmAudit(args = [], claudeBin = fakeClaudeBin) {
  return execFileSync('bash', [SCRIPT, ...args], {
    env: { ...process.env, VAULT_DIR: vaultDir, CLAUDE_BIN: claudeBin },
    encoding: 'utf8',
  });
}

function callCount() {
  if (!fs.existsSync(callLog)) return 0;
  return fs.readFileSync(callLog, 'utf8').trim().split('\n').filter(Boolean).length;
}

beforeEach(() => {
  vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), 'vault-llm-'));
  callLog = path.join(vaultDir, '.calls');
  fakeClaudeBin = makeFakeClaude('모순 없음');
});

afterEach(() => {
  fs.rmSync(vaultDir, { recursive: true, force: true });
});

describe.skipIf(!HAS_GNU_DATE)('vault-audit-llm.sh', () => {
  test('같은 태그를 공유하는 최근 변경 노트 묶음을 LLM에 넘긴다', () => {
    note('travel', 'a.md', '---\ntags: [#travel/japan]\n---\n# A\n도쿄는 비싸다');
    note('travel', 'b.md', '---\ntags: [#travel/japan]\n---\n# B\n도쿄는 싸다');
    runLlmAudit(['--days', '7']);
    expect(callCount()).toBeGreaterThanOrEqual(1); // 태그 묶음에 대해 LLM 호출
  });

  test('태그가 안 겹치면 LLM을 부르지 않는다 (단독 노트)', () => {
    note('travel', 'a.md', '---\ntags: [#travel/japan]\n---\n# A\n내용');
    note('tech', 'b.md', '---\ntags: [#tech/python]\n---\n# B\n내용');
    runLlmAudit(['--days', '7']);
    expect(callCount()).toBe(0); // 묶을 게 없으면 호출 0
  });

  test('오래된(변경 없는) 노트는 대상에서 제외한다', () => {
    note('travel', 'old1.md', '---\ntags: [#travel/japan]\n---\n# old1', 30);
    note('travel', 'old2.md', '---\ntags: [#travel/japan]\n---\n# old2', 30);
    runLlmAudit(['--days', '7']);
    expect(callCount()).toBe(0); // 최근 7일 변경 없음 → 호출 0
  });

  test('llm-audit-report.md를 생성한다', () => {
    note('travel', 'a.md', '---\ntags: [#travel/japan]\n---\n# A\n내용');
    note('travel', 'b.md', '---\ntags: [#travel/japan]\n---\n# B\n내용');
    runLlmAudit(['--days', '7']);
    expect(fs.existsSync(path.join(vaultDir, 'llm-audit-report.md'))).toBe(true);
  });

  test("LLM이 '모순 없음.'(마침표)으로 답해도 모순으로 오탐하지 않는다", () => {
    const cleanBin = makeFakeClaude('모순 없음.');
    note('travel', 'a.md', '---\ntags: [#travel/japan]\n---\n# A\n내용');
    note('travel', 'b.md', '---\ntags: [#travel/japan]\n---\n# B\n내용');
    runLlmAudit(['--days', '7'], cleanBin);
    const report = fs.readFileSync(path.join(vaultDir, 'llm-audit-report.md'), 'utf8');
    expect(report).toMatch(/모순 의심 0건|모순 의심 \(0\)/);
  });

  test('LLM이 모순을 보고하면 리포트에 반영된다', () => {
    const conflictBin = makeFakeClaude('모순 발견: A는 비싸다, B는 싸다');
    note('travel', 'a.md', '---\ntags: [#travel/japan]\n---\n# A\n비싸다');
    note('travel', 'b.md', '---\ntags: [#travel/japan]\n---\n# B\n싸다');
    runLlmAudit(['--days', '7'], conflictBin);
    const report = fs.readFileSync(path.join(vaultDir, 'llm-audit-report.md'), 'utf8');
    expect(report).toMatch(/모순/);
  });
});
