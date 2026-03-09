const { Client, GatewayIntentBits, Partials, ActivityType } = require('discord.js');
const { execSync } = require('child_process');
const fs = require('fs');
const https = require('https');
const path = require('path');
require('dotenv').config();

const ATTACHMENT_DIR = '/tmp/discord-attachments';
const HISTORY_DIR = path.join(__dirname, 'memory', 'discord-history');

const TMUX_SESSION = process.env.TMUX_SESSION || 'nino';
const GUILD_ID = '1479813608023134342';
const DEFAULT_CHANNEL = '1479813609499394169';

// 니노 봇 ID — .env의 NINO_BOT_ID 또는 아래 기본값
const NINO_BOT_ID = process.env.NINO_BOT_ID || '';

// Discord user ID → display name mapping
const USER_MAP = {
  '265454241387249665': 'Tim',
  '353914579929268226': 'Darren',
};

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.DirectMessages,
  ],
  partials: [Partials.Channel],
});

client.once('ready', () => {
  console.log(`[relay] Logged in as ${client.user.tag}`);
  // 봇 ID를 자동 설정
  if (!NINO_BOT_ID) {
    process.env.NINO_BOT_ID = client.user.id;
  }
  updatePresence();
});

function downloadAttachment(url, filename) {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(ATTACHMENT_DIR)) {
      fs.mkdirSync(ATTACHMENT_DIR, { recursive: true });
    }
    const filePath = path.join(ATTACHMENT_DIR, filename);
    const file = fs.createWriteStream(filePath);
    https.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        https.get(res.headers.location, (res2) => {
          res2.pipe(file);
          file.on('finish', () => { file.close(); resolve(filePath); });
        }).on('error', reject);
      } else {
        res.pipe(file);
        file.on('finish', () => { file.close(); resolve(filePath); });
      }
    }).on('error', reject);
  });
}

async function handleAttachments(msg) {
  if (!msg.attachments || msg.attachments.size === 0) return '';
  const tags = [];
  for (const [, att] of msg.attachments) {
    const timestamp = Date.now();
    const safeName = `${timestamp}-${att.name}`;
    try {
      const localPath = await downloadAttachment(att.url, safeName);
      const isImage = att.contentType && att.contentType.startsWith('image/');
      if (isImage) {
        tags.push(`[IMG:${localPath}]`);
      } else {
        tags.push(`[FILE:${localPath}]`);
      }
    } catch (e) {
      console.error(`[relay] attachment download failed: ${att.name}`, e.message);
      tags.push(`[ATT:${att.name}(download failed)]`);
    }
  }
  return ' ' + tags.join(' ');
}

function toKST(date = new Date()) {
  return new Date(date.getTime() + 9 * 60 * 60 * 1000);
}

function saveHistory(entry) {
  try {
    if (!fs.existsSync(HISTORY_DIR)) {
      fs.mkdirSync(HISTORY_DIR, { recursive: true });
    }
    const kst = toKST();
    const dateStr = kst.toISOString().slice(0, 10);
    const filePath = path.join(HISTORY_DIR, `${dateStr}.jsonl`);
    entry.timestamp = kst.toISOString().replace('Z', '+09:00');
    fs.appendFileSync(filePath, JSON.stringify(entry) + '\n');
  } catch (e) {
    console.error('[relay] history save failed:', e.message);
  }
}

function sendToTmux(payload) {
  console.log(`[relay] ${payload}`);
  try {
    const escaped = payload.replace(/'/g, "'\\''");
    execSync(`tmux send-keys -t '${TMUX_SESSION}' -- '${escaped}' C-m`);
  } catch (e) {
    if (!e.message.includes('no server running') && !e.message.includes("can't find")) {
      console.error(`[relay] tmux send-keys failed:`, e.message);
    }
  }
}

function resolveMentions(msg) {
  let text = msg.content;
  const botId = process.env.NINO_BOT_ID || client.user?.id;
  // User mentions: <@ID> or <@!ID>
  text = text.replace(/<@!?(\d+)>/g, (match, id) => {
    if (USER_MAP[id]) return `@${USER_MAP[id]}`;
    const member = msg.guild?.members?.cache.get(id);
    if (member) return `@${member.displayName}`;
    if (id === botId) return '@니노';
    return match;
  });
  // Role mentions: <@&ID>
  text = text.replace(/<@&(\d+)>/g, (match, id) => {
    const role = msg.guild?.roles?.cache.get(id);
    if (role) return `@${role.name}`;
    return match;
  });
  // Channel mentions: <#ID>
  text = text.replace(/<#(\d+)>/g, (match, id) => {
    const ch = msg.guild?.channels?.cache.get(id);
    if (ch) return `#${ch.name}`;
    return match;
  });
  return text;
}

client.on('messageCreate', async (msg) => {
  const botId = process.env.NINO_BOT_ID || client.user?.id;

  // DM 처리
  if (!msg.guildId) {
    if (msg.author.id === botId) {
      saveHistory({
        type: 'dm',
        sender: '니노',
        senderId: botId,
        messageId: msg.id,
        content: msg.content,
        attachments: msg.attachments.map(a => ({ name: a.name, url: a.url, contentType: a.contentType })),
      });
      return;
    }
    if (msg.author.bot) return;
    const name = USER_MAP[msg.author.id] || msg.author.username;
    const msgId = `[M:${msg.id}]`;
    const attTags = await handleAttachments(msg);
    const payload = `[DM][${name}]${msgId} ${msg.content}${attTags}`;
    saveHistory({
      type: 'dm',
      sender: name,
      senderId: msg.author.id,
      messageId: msg.id,
      content: msg.content,
      attachments: msg.attachments.map(a => ({ name: a.name, url: a.url, contentType: a.contentType })),
    });
    sendToTmux(payload);
    return;
  }

  if (msg.guildId !== GUILD_ID) return;

  // Save own messages to history but don't relay to tmux
  if (msg.author.id === botId) {
    saveHistory({
      type: 'guild',
      sender: '니노',
      senderId: botId,
      messageId: msg.id,
      channelId: msg.channel.isThread() ? msg.channel.id : msg.channelId,
      channelName: msg.channel.name || '',
      threadId: msg.channel.isThread() ? msg.channel.id : null,
      replyTo: msg.reference?.messageId || null,
      content: msg.content,
      attachments: msg.attachments.map(a => ({ name: a.name, url: a.url, contentType: a.contentType })),
    });
    return;
  }

  // System messages
  if (msg.system) {
    sendToTmux(`[D][system] ${msg.content || msg.cleanContent || '(시스템 메시지)'}`);
    return;
  }

  const name = USER_MAP[msg.author.id] || msg.author.displayName || msg.author.username;
  const channelId = msg.channel.isThread() ? msg.channel.id : msg.channelId;
  const channelTag = channelId !== DEFAULT_CHANNEL ? `[C:${channelId}]` : '';
  const threadTag = msg.channel.isThread() ? `[T:${msg.channel.id}]` : '';
  const msgId = `[M:${msg.id}]`;
  const replyTag = msg.reference?.messageId ? `[R:${msg.reference.messageId}]` : '';
  const content = resolveMentions(msg);
  const attTags = await handleAttachments(msg);
  const payload = `[D][${name}]${channelTag}${threadTag}${msgId}${replyTag} ${content}${attTags}`;
  saveHistory({
    type: 'guild',
    sender: name,
    senderId: msg.author.id,
    messageId: msg.id,
    channelId: channelId,
    channelName: msg.channel.name || '',
    threadId: msg.channel.isThread() ? msg.channel.id : null,
    replyTo: msg.reference?.messageId || null,
    content: msg.content,
    attachments: msg.attachments.map(a => ({ name: a.name, url: a.url, contentType: a.contentType })),
  });
  sendToTmux(payload);
});

client.on('guildMemberAdd', (member) => {
  if (member.guild.id !== GUILD_ID) return;
  sendToTmux(`[D][system] ${member.user.username} 님이 서버에 입장했습니다.`);
});

client.on('guildMemberRemove', (member) => {
  if (member.guild.id !== GUILD_ID) return;
  sendToTmux(`[D][system] ${member.user.username} 님이 서버에서 나갔습니다.`);
});

// --- 프레즌스(상태) 관리 ---
const STATUS_FILE = '/tmp/nino-status';

function updatePresence() {
  if (!client.isReady()) return;
  try {
    const status = fs.existsSync(STATUS_FILE)
      ? fs.readFileSync(STATUS_FILE, 'utf-8').trim()
      : '';
    console.log(`[relay] presence update: "${status}"`);
    if (status) {
      client.user.setPresence({
        activities: [{ name: status, type: ActivityType.Playing }],
        status: 'online',
      });
    } else {
      client.user.setPresence({ activities: [], status: 'online' });
    }
  } catch (e) {
    console.error('[relay] presence update failed:', e.message);
  }
}

try {
  const statusDir = require('path').dirname(STATUS_FILE);
  const statusBase = require('path').basename(STATUS_FILE);
  fs.watch(statusDir, (eventType, filename) => {
    if (filename === statusBase) updatePresence();
  });
  console.log('[relay] Using fs.watch for status file');
} catch (e) {
  fs.watchFile(STATUS_FILE, { interval: 2000 }, () => {
    updatePresence();
  });
  console.log('[relay] Fallback to fs.watchFile for status file');
}

client.login(process.env.DISCORD_BOT_TOKEN);
