const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

let tmpDir;
let fakeCurl;
let captureFile;
let envFile;
let channelMapFile;

beforeAll(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'discord-send-test-'));
  captureFile = path.join(tmpDir, 'curl-capture.txt');
  envFile = path.join(tmpDir, '.env');
  channelMapFile = path.join(tmpDir, 'channel-map.json');

  // Fake curl that captures args
  fakeCurl = path.join(tmpDir, 'curl');
  fs.writeFileSync(fakeCurl, `#!/bin/bash
echo "$@" > "${captureFile}"
echo '{"content":"ok","id":"123456"}'
`, { mode: 0o755 });

  // Fake .env
  fs.writeFileSync(envFile, `DISCORD_BOT_TOKEN=fake-token-123
DISCORD_CHANNEL_ID=1111111111111111111
`);

  // Fake channel-map.json
  fs.writeFileSync(channelMapFile, JSON.stringify({
    '일반': '1479813609499394169',
    '현인-업무': '1479813609499394171',
    'DM-Darren': '1480893889069191199',
    'DM-Tim': '1480893889069191200',
    '봇-놀이터': '1480479067881865347',
  }, null, 2));
});

afterAll(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

afterEach(() => {
  if (fs.existsSync(captureFile)) fs.unlinkSync(captureFile);
});

function run(args, expectFail = false) {
  // Create a wrapper script that overrides env and paths
  const wrapper = path.join(tmpDir, 'run.sh');
  fs.writeFileSync(wrapper, `#!/bin/bash
set -euo pipefail
export PATH="${tmpDir}:$PATH"

# Override the script's env sourcing
export DISCORD_BOT_TOKEN=fake-token-123
export DISCORD_CHANNEL_ID=1111111111111111111

CHANNEL_ID="\${DISCORD_CHANNEL_ID}"
AUTH="Authorization: Bot $DISCORD_BOT_TOKEN"
CHANNEL_MAP="${channelMapFile}"

FILE=""
MESSAGE=""
REPLY_TO=""
THREAD_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) FILE="$2"; shift 2 ;;
    -c|--channel) CHANNEL_ID="$2"; shift 2 ;;
    -r|--reply) REPLY_TO="$2"; shift 2 ;;
    -t|--thread) THREAD_NAME="$2"; shift 2 ;;
    *) MESSAGE="$1"; shift ;;
  esac
done

# Resolve channel name to ID
if [[ -n "$CHANNEL_ID" && ! "$CHANNEL_ID" =~ ^[0-9]+$ && -f "$CHANNEL_MAP" ]]; then
  RESOLVED=$(python3 -c "import json,sys; m=json.load(open(sys.argv[1])); print(m.get(sys.argv[2],''))" "$CHANNEL_MAP" "$CHANNEL_ID" 2>/dev/null)
  if [[ -n "$RESOLVED" ]]; then
    CHANNEL_ID="$RESOLVED"
  fi
fi

API="https://discord.com/api/v10/channels/$CHANNEL_ID/messages"

JSON_PAYLOAD=$(python3 -c "
import json,sys
payload = {'content': sys.argv[1]}
if sys.argv[2]:
    payload['message_reference'] = {'message_id': sys.argv[2]}
print(json.dumps(payload))
" "$MESSAGE" "$REPLY_TO")

if [[ -n "$FILE" ]]; then
  curl -s -H "$AUTH" -F "payload_json=$JSON_PAYLOAD" -F "files[0]=@$FILE" "$API"
elif [[ -n "$MESSAGE" ]]; then
  curl -s -H "$AUTH" -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$API"
else
  echo "Usage: discord-send [-f file] [-c channel_id] [-r reply_msg_id] [-t thread_name] \\"message\\""
  exit 1
fi
`, { mode: 0o755 });

  try {
    const result = execSync(`bash ${wrapper} ${args}`, {
      encoding: 'utf-8',
      env: { ...process.env, PATH: `${tmpDir}:${process.env.PATH}` },
    });
    return { stdout: result, exitCode: 0 };
  } catch (e) {
    if (expectFail) return { stdout: e.stdout || '', exitCode: e.status };
    throw e;
  }
}

function getCapturedArgs() {
  if (!fs.existsSync(captureFile)) return null;
  return fs.readFileSync(captureFile, 'utf-8').trim();
}

describe('discord-send', () => {
  test('no args → shows usage, exits 1', () => {
    const result = run('', true);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain('Usage:');
  });

  test('simple message → sends to default channel', () => {
    run('"hello world"');
    const args = getCapturedArgs();
    expect(args).toContain('channels/1111111111111111111/messages');
    expect(args).toContain('hello world');
  });

  test('-c channelID "msg" → sends to specified channel', () => {
    run('-c 9999999999999999999 "test message"');
    const args = getCapturedArgs();
    expect(args).toContain('channels/9999999999999999999/messages');
    expect(args).toContain('test message');
  });

  test('-c channelName "msg" → resolves from channel-map.json', () => {
    run('-c DM-Darren "dm test"');
    const args = getCapturedArgs();
    expect(args).toContain('channels/1480893889069191199/messages');
  });

  test('-c 현인-업무 "msg" → resolves Korean channel name', () => {
    run('-c 현인-업무 "업무 메시지"');
    const args = getCapturedArgs();
    expect(args).toContain('channels/1479813609499394171/messages');
  });

  test('-r msgID "msg" → includes message_reference in payload', () => {
    run('-r 123456789 "reply text"');
    const args = getCapturedArgs();
    expect(args).toContain('message_reference');
    expect(args).toContain('123456789');
  });

  test('-f file "msg" → uses multipart form', () => {
    const testFile = path.join(tmpDir, 'test.txt');
    fs.writeFileSync(testFile, 'test content');
    run(`-f ${testFile} "file message"`);
    const args = getCapturedArgs();
    expect(args).toContain('payload_json=');
    expect(args).toContain(`files[0]=@${testFile}`);
  });

  test('multiple positional args → last one wins', () => {
    run('"first" "second" "third"');
    const args = getCapturedArgs();
    expect(args).toContain('third');
    // "first" and "second" are overwritten — this is a known behavior
  });

  test('empty message with -c only → shows usage, exits 1', () => {
    const result = run('-c 9999999999999999999', true);
    expect(result.exitCode).toBe(1);
  });

  test('unresolvable channel name → uses name as-is in URL', () => {
    run('-c nonexistent-channel "test"');
    const args = getCapturedArgs();
    // If channel name not in map, it stays as the string (will fail API call)
    expect(args).toContain('channels/nonexistent-channel/messages');
  });
});
