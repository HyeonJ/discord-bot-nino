#!/usr/bin/env python3
import json, os, sys, tempfile, time

COOLDOWN_SECONDS = 600  # 10분

try:
    data = json.load(sys.stdin)
except:
    data = {}

session_id = data.get("session_id", "unknown")
state_file = os.path.join(tempfile.gettempdir(), f"memory-reminder-{session_id}")
now = time.time()

if os.path.exists(state_file):
    with open(state_file) as f:
        try:
            state = json.load(f)
        except:
            state = {}
    if state.get("consecutive", False):
        state["consecutive"] = False
        with open(state_file, "w") as f:
            json.dump(state, f)
        sys.exit(0)
    if now - state.get("last_reminded", 0) < COOLDOWN_SECONDS:
        sys.exit(0)

with open(state_file, "w") as f:
    json.dump({"last_reminded": now, "consecutive": True}, f)

print("<reminder>\n응답을 마치기 전에 이 세션에서 새로 알게 된 정보가 있는지 확인하세요.\n메모할 정보가 있다면 memory/ 파일에 즉시 기록한 뒤 응답을 완료하세요.\n이미 모두 기록했거나 메모할 게 없으면 하던 일을 그대로 진행하세요.\n</reminder>", file=sys.stderr)
sys.exit(2)
