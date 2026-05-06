const fs = require('fs');
const os = require('os');
const path = require('path');
const childProcess = require('child_process');

const root = path.resolve(__dirname, '..');
const scriptPath = path.join(root, 'scripts', 'build-memory-index.js');

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'nino-memory-index-'));
}

describe('memory index builder', () => {
  test('writes metadata-only index for configured memory roots', () => {
    const temp = makeTempDir();
    const botMemory = path.join(temp, 'bot-memory');
    const claudeMemory = path.join(temp, 'claude-memory');
    const output = path.join(temp, 'MEMORY_INDEX.md');

    fs.mkdirSync(path.join(botMemory, 'discord-history'), { recursive: true });
    fs.mkdirSync(path.join(botMemory, 'alarms'), { recursive: true });
    fs.mkdirSync(claudeMemory, { recursive: true });
    fs.writeFileSync(path.join(botMemory, 'current-tasks.md'), 'private task body\n', 'utf8');
    fs.writeFileSync(path.join(botMemory, 'alarms', 'wake-up.md'), 'private alarm\n', 'utf8');
    fs.writeFileSync(path.join(claudeMemory, 'MEMORY.md'), 'private long memory\n', 'utf8');
    fs.writeFileSync(path.join(claudeMemory, 'feedback_utf8_bom.md'), 'private feedback\n', 'utf8');

    childProcess.execFileSync('node', [scriptPath], {
      env: {
        ...process.env,
        NINO_MEMORY_ROOTS: `${botMemory}${path.delimiter}${claudeMemory}`,
        NINO_MEMORY_INDEX_OUTPUT: output,
      },
      encoding: 'utf8',
    });

    const index = fs.readFileSync(output, 'utf8');

    expect(index).toContain('# Nino Memory Index');
    expect(index).toContain(botMemory);
    expect(index).toContain(claudeMemory);
    expect(index).toContain('current-tasks.md');
    expect(index).toContain('MEMORY.md');
    expect(index).toContain('feedback_utf8_bom.md');
    expect(index).toContain('alarms/wake-up.md');
    expect(index).toContain('category: active-tasks');
    expect(index).toContain('category: alarm');
    expect(index).toContain('category: long-term-memory');
    expect(index).toContain('category: feedback');
    expect(index).toContain('private memory contents are intentionally omitted');
    expect(index).not.toContain('private task body');
    expect(index).not.toContain('private long memory');
    expect(index).not.toContain('private feedback');
    expect(index).not.toContain('private alarm');
  });
});
