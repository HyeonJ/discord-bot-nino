const { extractRepoFromEmbed, getLocalPath, shouldAutoPull } = require('../src/auto-pull');

const GITHUB_BOT_ID = '1480975077829902377';

describe('extractRepoFromEmbed', () => {
  test('embed title에서 레포명 추출', () => {
    const embeds = [{ title: '[discord-bot-nino:main] 1 new commit' }];
    expect(extractRepoFromEmbed(embeds)).toBe('discord-bot-nino');
  });

  test('다른 레포명 추출', () => {
    const embeds = [{ title: '[yaksu-shared-data:main] 2 new commits' }];
    expect(extractRepoFromEmbed(embeds)).toBe('yaksu-shared-data');
  });

  test('embed 없으면 null 반환', () => {
    expect(extractRepoFromEmbed([])).toBeNull();
    expect(extractRepoFromEmbed(null)).toBeNull();
  });

  test('title 없으면 null 반환', () => {
    const embeds = [{ description: '어떤 내용' }];
    expect(extractRepoFromEmbed(embeds)).toBeNull();
  });

  test('레포명 패턴 안 맞으면 null 반환', () => {
    const embeds = [{ title: '일반 메시지' }];
    expect(extractRepoFromEmbed(embeds)).toBeNull();
  });
});

describe('getLocalPath', () => {
  test('discord-bot-nino → ~/discord-bot-nino', () => {
    const result = getLocalPath('discord-bot-nino');
    expect(result).toContain('discord-bot-nino');
    expect(result).not.toBeNull();
  });

  test('yaksu-shared-data → ~/yaksu-shared-data', () => {
    const result = getLocalPath('yaksu-shared-data');
    expect(result).toContain('yaksu-shared-data');
  });

  test('알 수 없는 레포 → null', () => {
    expect(getLocalPath('unknown-repo')).toBeNull();
  });
});

describe('shouldAutoPull', () => {
  test('GitHub 봇 메시지 + main 브랜치 push → true', () => {
    const msg = {
      author: { id: GITHUB_BOT_ID },
      embeds: [{ title: '[discord-bot-nino:main] 1 new commit' }],
    };
    expect(shouldAutoPull(msg)).toBe(true);
  });

  test('GitHub 봇이 아닌 메시지 → false', () => {
    const msg = {
      author: { id: '999999999' },
      embeds: [{ title: '[discord-bot-nino:main] 1 new commit' }],
    };
    expect(shouldAutoPull(msg)).toBe(false);
  });

  test('main 아닌 브랜치 → false', () => {
    const msg = {
      author: { id: GITHUB_BOT_ID },
      embeds: [{ title: '[discord-bot-nino:feat/something] 1 new commit' }],
    };
    expect(shouldAutoPull(msg)).toBe(false);
  });

  test('embed 없는 메시지 → false', () => {
    const msg = {
      author: { id: GITHUB_BOT_ID },
      embeds: [],
    };
    expect(shouldAutoPull(msg)).toBe(false);
  });
});
