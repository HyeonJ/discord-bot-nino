#!/usr/bin/env python3
import json, os, subprocess, sys

SHARED_DATA_DIR = os.path.expanduser("~/yaksu-shared-data")
SHARED_FILES = {"pantry.md", "purchase-history.md", "shopping-list.md", "todo-list.md"}

def get_shared_filename(fp):
    return os.path.basename(fp) if fp and os.path.basename(fp) in SHARED_FILES else None

def git_run(*args):
    return subprocess.run(["git", "-C", SHARED_DATA_DIR] + list(args), capture_output=True, text=True, timeout=30)

try:
    data = json.load(sys.stdin)
except:
    sys.exit(0)

tool_name = data.get("tool_name", "")
file_path = data.get("tool_input", {}).get("file_path", "")
filename = get_shared_filename(file_path)
hook_type = os.environ.get("CLAUDE_HOOK_EVENT", "")

if not filename or not os.path.isdir(SHARED_DATA_DIR):
    sys.exit(0)

if "Pre" in hook_type and tool_name == "Read":
    result = git_run("pull", "--rebase", "--quiet", "origin", "main")
    if result.returncode != 0:
        git_run("rebase", "--abort")
        print(f"[shared-data-sync] WARNING: pull --rebase 실패 ({filename}). 수동 확인 필요.\n{result.stderr}", file=sys.stderr)
    src = os.path.join(SHARED_DATA_DIR, filename)
    if os.path.exists(src):
        subprocess.run(["cp", src, file_path], capture_output=True)
elif "Post" in hook_type and tool_name in ("Edit", "Write"):
    subprocess.run(["cp", file_path, os.path.join(SHARED_DATA_DIR, filename)], capture_output=True)
    git_run("add", filename)
    commit_result = git_run("diff", "--cached", "--quiet")
    if commit_result.returncode != 0:
        c = git_run("commit", "-m", f"Update {filename}")
        if c.returncode != 0:
            print(f"[shared-data-sync] ERROR: commit 실패 ({filename}).\n{c.stderr}", file=sys.stderr)
        else:
            push_result = git_run("push", "--quiet", "origin", "main")
            if push_result.returncode != 0:
                # push 실패 시 pull --rebase 후 재시도
                retry_pull = git_run("pull", "--rebase", "--quiet", "origin", "main")
                if retry_pull.returncode != 0:
                    git_run("rebase", "--abort")
                    print(f"[shared-data-sync] WARNING: push 실패 + pull --rebase 실패 ({filename}). 수동 확인 필요.\n{push_result.stderr}", file=sys.stderr)
                else:
                    retry_push = git_run("push", "--quiet", "origin", "main")
                    if retry_push.returncode != 0:
                        print(f"[shared-data-sync] WARNING: push 재시도 실패 ({filename}). 수동 확인 필요.\n{retry_push.stderr}", file=sys.stderr)
