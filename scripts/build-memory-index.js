#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const defaultRoots = [
  '/home/bpx27/discord-bot-nino/memory',
  '/home/bpx27/.claude/projects/-home-bpx27-discord-bot-nino/memory',
];
const outputPath = process.env.NINO_MEMORY_INDEX_OUTPUT ||
  path.join(repoRoot, 'shared-context', 'MEMORY_INDEX.md');

function parseRoots(value) {
  if (!value) return defaultRoots;
  return value.split(path.delimiter).map((root) => root.trim()).filter(Boolean);
}

function categoryFor(relativePath) {
  const base = path.basename(relativePath);
  if (base === 'current-tasks.md') return 'active-tasks';
  if (base === 'MEMORY.md') return 'long-term-memory';
  if (base.startsWith('feedback_')) return 'feedback';
  if (base.startsWith('user_')) return 'user-memory';
  if (base.startsWith('project_')) return 'project';
  if (base.startsWith('ref_') || base.startsWith('reference_')) return 'reference';
  const normalized = relativePath.split(path.sep).join('/');
  if (normalized.startsWith('discord-history/')) return 'discord-history';
  if (normalized.startsWith('alarms/')) return 'alarm';
  if (normalized.startsWith('research/') || normalized.startsWith('research-results/')) return 'research';
  return 'memory';
}

function walkFiles(root) {
  if (!fs.existsSync(root)) return [];
  const results = [];
  const stack = [''];

  while (stack.length > 0) {
    const relative = stack.pop();
    const absolute = path.join(root, relative);
    let entries;
    try {
      entries = fs.readdirSync(absolute, { withFileTypes: true });
    } catch {
      continue;
    }

    entries
      .filter((entry) => !entry.name.startsWith('.'))
      .sort((a, b) => a.name.localeCompare(b.name))
      .forEach((entry) => {
        const entryRelative = path.join(relative, entry.name);
        const entryAbsolute = path.join(root, entryRelative);
        if (entry.isDirectory()) {
          stack.push(entryRelative);
        } else if (entry.isFile()) {
          const stat = fs.statSync(entryAbsolute);
          results.push({
            relativePath: entryRelative.split(path.sep).join('/'),
            absolutePath: entryAbsolute,
            size: stat.size,
            modified: stat.mtime.toISOString(),
            category: categoryFor(entryRelative),
          });
        }
      });
  }

  return results.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
}

function renderIndex(roots) {
  const lines = [
    '# Nino Memory Index',
    '',
    'This is a generated metadata-only index. private memory contents are intentionally omitted.',
    '',
    '## Roots',
    '',
  ];

  roots.forEach((root) => {
    lines.push(`- ${root}`);
  });

  lines.push('', '## Files', '');

  roots.forEach((root) => {
    lines.push(`### ${root}`, '');
    const files = walkFiles(root);
    if (files.length === 0) {
      lines.push('- No readable files found.', '');
      return;
    }
    files.forEach((file) => {
      lines.push(`- ${file.relativePath}`);
      lines.push(`  - path: ${file.absolutePath}`);
      lines.push(`  - category: ${file.category}`);
      lines.push(`  - size_bytes: ${file.size}`);
      lines.push(`  - modified: ${file.modified}`);
    });
    lines.push('');
  });

  return `${lines.join('\n')}\n`;
}

function main() {
  const roots = parseRoots(process.env.NINO_MEMORY_ROOTS);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, renderIndex(roots), 'utf8');
  console.log(outputPath);
}

if (require.main === module) {
  main();
}

module.exports = {
  categoryFor,
  renderIndex,
  walkFiles,
};
