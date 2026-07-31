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

/**
 * 🔴 못 잰 것을 0 으로 보고하지 않는다 (2026-07-31 실측)
 *
 * stale 계산이 세 경로로 전부 **조용히 0** 이 된다. 진짜 답이 1건인 픽스처에서:
 *   ① threshold=$(date -d … || echo 0)  → 0 → 모든 노트가 그보다 최신 → stale 0
 *   ② ts=$(date -d "$d" … || echo "")   → 빈 값 → continue      → stale 0
 *   ③ grep -oP '^updated:…' || true     → 빈 값 → continue      → stale 0
 * rc 도 0 이라 **자신 있는 거짓 초록**이 된다.
 *
 * ⚠️ 범위를 자른다 — 처음엔 *"BSD 에서 조용히 틀린다"* 고 적었는데 **틀렸다.**
 *   18행에 GNU date 가드가 이미 있어서 **진짜 BSD 는 rc=1 로 시끄럽게 죽는다**(아래 대조군).
 *   내 첫 스텁이 `date -d` 만 깨고 `date --version` 은 GNU 를 통과시켜, BSD 가 아닌 상태를
 *   BSD 라고 부른 것이었다.
 *
 * 🔑 그런데 **살아남은 쪽이 더 나쁘다.** 남은 축은 *"GNU date 가 있으면 GNU 도구 세트다"* 라는
 *   가정 위에 서 있고, 그 가정을 깨는 기계가 실재한다 — 룬드가 같은 날 잰 `ugrep` 그림자
 *   (date 는 멀쩡한데 `grep` 만 갈린다). 가드가 **date 축만** 보니 grep 축은
 *   *가드가 있는 파일 안에서* 조용히 뚫린다.
 *   ⇒ 경고나 가드를 적어둔 것이 **그 축을 감시한다는 뜻은 아니다.**
 *
 * 🔸 그리고 이건 시험이 아니라 **사람이 읽는 리포트**다. 시험은 거짓 초록이면 나중에 터지지만
 *   리포트는 읽고 안심하면 끝이라 터질 자리가 없다.
 */
describe('vault-audit.sh — 못 잰 것을 0 으로 접지 않는다', () => {
  // BSD 흉내: `date -d` 없음 · `grep -P` 없음. 다른 인자는 진짜 도구로 넘긴다.
  function stubBin(which) {
    const d = fs.mkdtempSync(path.join(os.tmpdir(), 'bsdstub-'));
    if (which.date) {
      fs.writeFileSync(path.join(d, 'date'),
        '#!/bin/bash\n[ "$1" = "-d" ] && { echo "date: illegal option -- d" >&2; exit 1; }\nexec /usr/bin/date "$@"\n',
        { mode: 0o755 });
    }
    if (which.bsdDate) {
      fs.writeFileSync(path.join(d, 'date'),
        '#!/bin/bash\ncase "$1" in --version) echo "date (BSD)"; exit 1;; -d) exit 1;; esac\nexec /usr/bin/date "$@"\n',
        { mode: 0o755 });
    }
    if (which.grep) {
      fs.writeFileSync(path.join(d, 'grep'),
        '#!/bin/bash\nfor a in "$@"; do case "$a" in -*P*) echo "grep: invalid option -- P" >&2; exit 2;; esac; done\nexec /usr/bin/grep "$@"\n',
        { mode: 0o755 });
    }
    return d;
  }

  function runWith(which, args = []) {
    const d = stubBin(which);
    try {
      return execFileSync('bash', [SCRIPT, ...args], {
        env: { ...process.env, VAULT_DIR: vaultDir, PATH: `${d}:${process.env.PATH}` },
        encoding: 'utf8',
      });
    } finally {
      fs.rmSync(d, { recursive: true, force: true });
    }
  }

  function seedOneStale() {
    writeNote('tech', '낡은노트.md', '---\nupdated: 2020-01-01\n---\n# 낡은노트\n내용');
    writeNote('tech', '최신노트.md', '---\nupdated: 2026-07-30\n---\n# 최신노트\n내용');
  }

  // 🧪 양성 대조군 — 아래 단언들이 "검사가 아예 없다"와 구별되게 만든다.
  //   이게 없으면 stale 로직이 통째로 죽어도 "0 이라고 말하지 않는다"가 초록이다.
  test('🧪 [양성 대조군] 도구가 성하면 stale 1건을 실제로 찾는다', () => {
    seedOneStale();
    runAudit(['--stale-days', '180']);
    expect(report()).toMatch(/낡은노트/);
  });

  // 🧪 대조군 — **진짜 BSD 는 이미 시끄럽다.** 이걸 안 세우면 아래 시험들이 잡는 것을
  //   "BSD 에서 조용히 틀린다"로 오독하게 된다(내가 처음에 그렇게 적었다).
  test('🧪 [대조군] 진짜 BSD(date --version 도 실패)는 조용하지 않고 rc=1 로 죽는다', () => {
    seedOneStale();
    let rc = 0;
    try {
      runWith({ bsdDate: true }, ['--stale-days', '180']);
    } catch (e) {
      rc = e.status;
    }
    expect(rc).toBe(1);
  });

  // `date --version` 은 GNU 인데 `-d` 만 깨진 상태 — BSD 가 아니라 **PATH 위의 shim**.
  test('date -d 만 깨져도 "stale 0"이라고 말하지 않는다 — 판정 불가로 보고한다', () => {
    seedOneStale();
    const out = runWith({ date: true }, ['--stale-days', '180']);
    const r = report();
    expect(r).toMatch(/판정 불가/);
    expect(`${out}\n${r}`).not.toMatch(/stale 후보 0/);
  });

  // 🔴 이게 셋 중 제일 크다 — 룬드 위키 사고와 **증상이 똑같다**(깨진 링크가 0 으로 보임).
  //   거기선 원인이 안 닫힌 펜스였고 여기선 `grep -P` 부재다. 원인이 달라도 사람이 보는 건 같다.
  test('grep -P 가 없어도 깨진 wikilink 를 놓치지 않는다', () => {
    writeNote('tech', 'a.md', '---\nupdated: 2026-07-30\n---\n# A\n\n[[유령노트]] 링크');
    runWith({ grep: true });
    expect(report()).toMatch(/유령노트/);
  });

  test('grep -P 가 없어도 updated 를 읽는다 (프론트매터 추출은 이식 가능해야 한다)', () => {
    seedOneStale();
    runWith({ grep: true }, ['--stale-days', '180']);
    expect(report()).toMatch(/낡은노트/);
  });

  test('둘 다 없어도 조용한 0 이 아니라 판정 불가가 나온다', () => {
    seedOneStale();
    runWith({ date: true, grep: true }, ['--stale-days', '180']);
    expect(report()).toMatch(/판정 불가/);
  });

  // 🔴 이 시험은 **변이가 찾아냈다.** 위 시험들은 기준선(threshold) 실패만 덮고 있었고,
  //   기준선이 먼저 죽으면 노트별 루프엔 들어가지도 않는다 — 즉 노트 하나의 날짜를 못 읽는
  //   분기는 내가 쓰고도 **아무도 안 재고 있었다**(집계를 지워도 0 fail 이었다).
  //   🔑 내가 쓴 분기라고 덮여 있는 게 아니다. 덮였는지는 지워보고서야 안다.
  test('날짜 모양은 맞는데 못 읽는 노트는 조용히 넘기지 않는다', () => {
    writeNote('tech', '이상한날짜.md', '---\nupdated: 2026-99-99\n---\n# 이상한날짜\n내용');
    writeNote('tech', '정상.md', '---\nupdated: 2026-07-30\n---\n# 정상\n내용');
    runAudit(['--stale-days', '180']);
    const r = report();
    expect(r).toMatch(/판정 불가/);
    expect(r).toMatch(/이상한날짜/);
  });

  // 🔑 0 일 때 안 붙는 것도 잰다. 안 재면 "판정 불가"를 늘 찍어도 위가 전부 초록이다.
  test('판정 불가가 없으면 그 꼬리를 붙이지 않는다', () => {
    seedOneStale();
    runAudit(['--stale-days', '180']);
    expect(report()).not.toMatch(/판정 불가/);
  });
});
