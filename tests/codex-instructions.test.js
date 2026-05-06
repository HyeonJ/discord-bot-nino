const fs = require('fs');
const path = require('path');

describe('Codex Nino instructions', () => {
  const instructionsPath = path.resolve(__dirname, '..', 'codex-config', 'NINO_CODEX.md');
  const sharedContextPath = path.resolve(__dirname, '..', 'shared-context', 'NINO_SHARED_CONTEXT.md');

  test('defines Nino persona, Discord reply bridge, and shared memory paths', () => {
    const instructions = fs.readFileSync(instructionsPath, 'utf8');

    expect(instructions).toContain('24살');
    expect(instructions).toContain('한국어');
    expect(instructions).toContain('/home/bpx27/discord-bot-nino/src/discord-send');
    expect(instructions).toContain('/home/bpx27/discord-bot-nino/memory');
    expect(instructions).toContain('/home/bpx27/discord-bot-nino/CLAUDE.md');
    expect(instructions).toContain('shared-context/NINO_SHARED_CONTEXT.md');
    expect(instructions).toContain('[C:CHANNEL_ID]');
    expect(instructions).toContain('[M:MESSAGE_ID]');
  });

  test('defines provider-neutral shared memory, hook, and skill context', () => {
    const sharedContext = fs.readFileSync(sharedContextPath, 'utf8');

    expect(sharedContext).toContain('/home/bpx27/discord-bot-nino/memory');
    expect(sharedContext).toContain('/home/bpx27/.claude/projects/-home-bpx27-discord-bot-nino/memory');
    expect(sharedContext).toContain('/home/bpx27/yaksu-shared-data');
    expect(sharedContext).toContain('memory/current-tasks.md');
    expect(sharedContext).toContain('MEMORY.md');
    expect(sharedContext).toContain('feedback_*');
    expect(sharedContext).toContain('project_*');
    expect(sharedContext).toContain('claude-config/hooks');
    expect(sharedContext).toContain('claude-config/skills');
    expect(sharedContext).toContain('git pull --rebase');
    expect(sharedContext).toContain('git push');
  });
});
