const { execSync } = require('child_process');
const os = require('os');
const path = require('path');

const GITHUB_BOT_ID = '1480975077829902377';

const REPO_PATH_MAP = {
  'discord-bot-nino': path.join(os.homedir(), 'discord-bot-nino'),
  'yaksu-shared-data': path.join(os.homedir(), 'yaksu-shared-data'),
};

function extractRepoFromEmbed(embeds) {
  if (!embeds || embeds.length === 0) return null;
  const title = embeds[0]?.title;
  if (!title) return null;
  const match = title.match(/^\[([^:]+):([^\]]+)\]/);
  if (!match) return null;
  return match[1];
}

function getLocalPath(repoName) {
  return REPO_PATH_MAP[repoName] || null;
}

function shouldAutoPull(msg) {
  if (msg.author?.id !== GITHUB_BOT_ID) return false;
  if (!msg.embeds || msg.embeds.length === 0) return false;
  const title = msg.embeds[0]?.title;
  if (!title) return false;
  const match = title.match(/^\[([^:]+):([^\]]+)\]/);
  if (!match) return false;
  return match[2] === 'main';
}

function runAutoPull(msg) {
  const repoName = extractRepoFromEmbed(msg.embeds);
  if (!repoName) return;
  const localPath = getLocalPath(repoName);
  if (!localPath) {
    console.log(`[auto-pull] 알 수 없는 레포: ${repoName}`);
    return;
  }
  try {
    const status = execSync('git status --porcelain', { cwd: localPath, encoding: 'utf-8' });
    if (status.trim()) {
      console.log(`[auto-pull] ${repoName} uncommitted changes 있어서 스킵`);
      return;
    }
    const result = execSync('git pull --ff-only', { cwd: localPath, encoding: 'utf-8' });
    console.log(`[auto-pull] ${repoName} pull 완료: ${result.trim()}`);
  } catch (e) {
    console.error(`[auto-pull] ${repoName} pull 실패: ${e.message}`);
  }
}

module.exports = { extractRepoFromEmbed, getLocalPath, shouldAutoPull, runAutoPull };
