const fs = require('fs');
const path = require('path');

describe('Codex Nino instructions', () => {
  const instructionsPath = path.resolve(__dirname, '..', 'codex-config', 'NINO_CODEX.md');

  test('defines Nino persona, Discord reply bridge, and shared memory paths', () => {
    const instructions = fs.readFileSync(instructionsPath, 'utf8');

    expect(instructions).toContain('24살');
    expect(instructions).toContain('한국어');
    expect(instructions).toContain('/home/bpx27/discord-bot-nino/src/discord-send');
    expect(instructions).toContain('/home/bpx27/discord-bot-nino/memory');
    expect(instructions).toContain('/home/bpx27/discord-bot-nino/CLAUDE.md');
    expect(instructions).toContain('[C:CHANNEL_ID]');
    expect(instructions).toContain('[M:MESSAGE_ID]');
  });
});
