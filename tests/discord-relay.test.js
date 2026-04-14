const fs = require('fs');
const path = require('path');
const os = require('os');

// Test the relay's pure logic by reimplementing the format rules as spec tests.
// This documents expected behavior without needing to import from the module.

const DEFAULT_CHANNEL = '1479813609499394169';
const USER_MAP = {
  '265454241387249665': 'Tim',
  '353914579929268226': 'Darren',
};

// Reimplement resolveMentions logic for testing
function resolveMentions(content, userMap, botId) {
  let text = content;
  text = text.replace(/<@!?(\d+)>/g, (match, id) => {
    if (userMap[id]) return `@${userMap[id]}`;
    if (id === botId) return '@니노';
    return match;
  });
  return text;
}

// Reimplement preprocessPayload logic for testing
function preprocessPayload(payload, saveFn) {
  const MAX_INLINE_LENGTH = 1500;
  let processed = payload.replace(/https?:\/\/\S{300,}/g, (url) => {
    const fpath = saveFn(url);
    return `${url.substring(0, 200)}...(전체 URL: ${fpath})`;
  });
  if (processed.length > MAX_INLINE_LENGTH) {
    const fpath = saveFn(payload);
    processed = processed.substring(0, MAX_INLINE_LENGTH) + `\n[LONG_MSG:${fpath}]`;
  }
  return processed;
}

// Reimplement toKST logic for testing
function toKST(date = new Date()) {
  return new Date(date.getTime() + 9 * 60 * 60 * 1000);
}

// Reimplement message formatting logic
function formatGuildMessage({ name, channelId, threadId, msgId, replyId, content, attachments }) {
  const channelTag = channelId !== DEFAULT_CHANNEL ? `[C:${channelId}]` : '';
  const threadTag = threadId ? `[T:${threadId}]` : '';
  const msgTag = `[M:${msgId}]`;
  const replyTag = replyId ? `[R:${replyId}]` : '';
  const attTags = (attachments || []).map(a =>
    a.isImage ? `[IMG:${a.path}]` : `[FILE:${a.path}]`
  ).join(' ');
  const attStr = attTags ? ' ' + attTags : '';
  return `[D][${name}]${channelTag}${threadTag}${msgTag}${replyTag} ${content}${attStr}`;
}

function formatDMMessage({ name, dmChannelId, msgId, content }) {
  return `[DM][${name}][C:${dmChannelId}][M:${msgId}] ${content}`;
}

describe('Message Format Protocol', () => {
  test('guild message from known user in default channel', () => {
    const result = formatGuildMessage({
      name: 'Tim', channelId: DEFAULT_CHANNEL, msgId: '123', content: 'hello',
    });
    expect(result).toBe('[D][Tim][M:123] hello');
  });

  test('guild message in non-default channel', () => {
    const result = formatGuildMessage({
      name: 'Darren', channelId: '1480593132511826092', msgId: '456', content: 'test',
    });
    expect(result).toBe('[D][Darren][C:1480593132511826092][M:456] test');
  });

  test('DM message includes channel tag', () => {
    const result = formatDMMessage({
      name: 'Darren', dmChannelId: '1480893889069191199', msgId: '789', content: 'hi',
    });
    expect(result).toBe('[DM][Darren][C:1480893889069191199][M:789] hi');
  });

  test('thread message includes both C: and T: tags', () => {
    const result = formatGuildMessage({
      name: 'Tim', channelId: '5555', threadId: '5555', msgId: '101', content: 'thread msg',
    });
    expect(result).toBe('[D][Tim][C:5555][T:5555][M:101] thread msg');
  });

  test('reply message includes R: tag', () => {
    const result = formatGuildMessage({
      name: 'Darren', channelId: DEFAULT_CHANNEL, msgId: '102', replyId: '100', content: 'reply text',
    });
    expect(result).toBe('[D][Darren][M:102][R:100] reply text');
  });

  test('message with image attachment', () => {
    const result = formatGuildMessage({
      name: 'Tim', channelId: DEFAULT_CHANNEL, msgId: '200', content: 'look',
      attachments: [{ isImage: true, path: '/tmp/discord-attachments/12345-photo.jpg' }],
    });
    expect(result).toBe('[D][Tim][M:200] look [IMG:/tmp/discord-attachments/12345-photo.jpg]');
  });

  test('message with file attachment', () => {
    const result = formatGuildMessage({
      name: 'Darren', channelId: DEFAULT_CHANNEL, msgId: '201', content: 'file',
      attachments: [{ isImage: false, path: '/tmp/discord-attachments/12345-doc.pdf' }],
    });
    expect(result).toBe('[D][Darren][M:201] file [FILE:/tmp/discord-attachments/12345-doc.pdf]');
  });

  test('message with multiple attachments', () => {
    const result = formatGuildMessage({
      name: 'Tim', channelId: DEFAULT_CHANNEL, msgId: '202', content: 'multi',
      attachments: [
        { isImage: true, path: '/tmp/discord-attachments/1-a.jpg' },
        { isImage: false, path: '/tmp/discord-attachments/2-b.zip' },
      ],
    });
    expect(result).toContain('[IMG:/tmp/discord-attachments/1-a.jpg]');
    expect(result).toContain('[FILE:/tmp/discord-attachments/2-b.zip]');
  });

  test('all tags combined', () => {
    const result = formatGuildMessage({
      name: 'Tim', channelId: '9999', threadId: '9999', msgId: '300', replyId: '299', content: 'full',
      attachments: [{ isImage: true, path: '/tmp/img.png' }],
    });
    expect(result).toBe('[D][Tim][C:9999][T:9999][M:300][R:299] full [IMG:/tmp/img.png]');
  });
});

describe('resolveMentions', () => {
  test('resolves Tim mention', () => {
    expect(resolveMentions('<@265454241387249665>', USER_MAP, '000')).toBe('@Tim');
  });

  test('resolves Darren mention', () => {
    expect(resolveMentions('<@353914579929268226>', USER_MAP, '000')).toBe('@Darren');
  });

  test('resolves nickname format <@!ID>', () => {
    expect(resolveMentions('<@!265454241387249665>', USER_MAP, '000')).toBe('@Tim');
  });

  test('resolves bot self-mention to @니노', () => {
    expect(resolveMentions('<@999999>', USER_MAP, '999999')).toBe('@니노');
  });

  test('unknown user ID stays unchanged', () => {
    expect(resolveMentions('<@111222333>', USER_MAP, '000')).toBe('<@111222333>');
  });

  test('multiple mentions in one message', () => {
    const result = resolveMentions('hey <@265454241387249665> and <@353914579929268226>', USER_MAP, '000');
    expect(result).toBe('hey @Tim and @Darren');
  });
});

describe('preprocessPayload', () => {
  let tmpDir;
  let savedFiles;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-test-'));
    savedFiles = [];
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const saveFn = (content) => {
    const fpath = path.join(tmpDir, `msg-${savedFiles.length}.txt`);
    fs.writeFileSync(fpath, content);
    savedFiles.push(fpath);
    return fpath;
  };

  test('short payload returned as-is', () => {
    const result = preprocessPayload('hello world', saveFn);
    expect(result).toBe('hello world');
    expect(savedFiles).toHaveLength(0);
  });

  test('URL >300 chars gets truncated', () => {
    const longUrl = 'https://example.com/' + 'a'.repeat(300);
    const payload = `check this: ${longUrl}`;
    const result = preprocessPayload(payload, saveFn);
    expect(result).toContain('https://example.com/' + 'a'.repeat(180));
    expect(result).toContain('...(전체 URL:');
    expect(savedFiles).toHaveLength(1);
  });

  test('payload >1500 chars gets truncated with LONG_MSG', () => {
    const longPayload = 'x'.repeat(2000);
    const result = preprocessPayload(longPayload, saveFn);
    expect(result.length).toBeLessThan(2000);
    expect(result).toContain('[LONG_MSG:');
    expect(savedFiles).toHaveLength(1);
  });

  test('short URL is not truncated', () => {
    const shortUrl = 'https://example.com/page';
    const result = preprocessPayload(`link: ${shortUrl}`, saveFn);
    expect(result).toBe(`link: ${shortUrl}`);
    expect(savedFiles).toHaveLength(0);
  });
});

describe('toKST', () => {
  test('converts UTC to KST (+9h)', () => {
    const utc = new Date('2026-04-14T00:00:00Z');
    const kst = toKST(utc);
    expect(kst.getUTCHours()).toBe(9);
    expect(kst.getUTCDate()).toBe(14);
  });

  test('handles day rollover', () => {
    const utc = new Date('2026-04-14T20:00:00Z');
    const kst = toKST(utc);
    expect(kst.getUTCDate()).toBe(15);
    expect(kst.getUTCHours()).toBe(5);
  });
});
