"""
Discord Bot Manager - 여러 봇을 관리하는 스크립트
사용법:
  python botctl.py start <봇이름>    # 봇 시작
  python botctl.py stop <봇이름>     # 봇 중지
  python botctl.py restart <봇이름>  # 봇 재시작
  python botctl.py status            # 전체 봇 상태 확인
  python botctl.py list              # 등록된 봇 목록
"""
import subprocess
import sys
import os
import json

# Windows 콘솔 UTF-8 출력 설정
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    os.system("chcp 65001 >nul 2>&1")

BOTS_DIR = os.path.dirname(os.path.abspath(__file__))
BOTS_CONFIG = os.path.join(BOTS_DIR, "bots.json")

# 기본 봇 설정
DEFAULT_BOTS = {
    "nino": {
        "script": "bot.py",
        "description": "니노 - 친근한 한국인 친구 봇 (Claude Opus 4.6)"
    }
}


def load_bots():
    if os.path.exists(BOTS_CONFIG):
        with open(BOTS_CONFIG, "r", encoding="utf-8") as f:
            return json.load(f)
    save_bots(DEFAULT_BOTS)
    return DEFAULT_BOTS


def save_bots(bots):
    with open(BOTS_CONFIG, "w", encoding="utf-8") as f:
        json.dump(bots, f, ensure_ascii=False, indent=2)


def find_bot_pids(script_name):
    """봇 스크립트를 실행 중인 python PID 찾기"""
    try:
        result = subprocess.run(
            ["powershell", "-Command",
             f"Get-CimInstance Win32_Process -Filter \"name='python.exe'\" | "
             f"Where-Object {{ $_.CommandLine -like '*{script_name}*' }} | "
             f"ForEach-Object {{ $_.ProcessId }}"],
            capture_output=True, text=True, encoding="utf-8"
        )
        pids = [p.strip() for p in result.stdout.strip().split("\n") if p.strip().isdigit()]
        return pids
    except Exception:
        return []


def start_bot(name):
    bots = load_bots()
    if name not in bots:
        print(f"[ERROR] '{name}' 봇이 등록되어 있지 않습니다.")
        print(f"등록된 봇: {', '.join(bots.keys())}")
        return False

    script = bots[name]["script"]
    script_path = os.path.join(BOTS_DIR, script)

    if not os.path.exists(script_path):
        print(f"[ERROR] {script_path} 파일을 찾을 수 없습니다.")
        return False

    # 이미 실행 중인지 확인
    pids = find_bot_pids(script)
    if pids:
        print(f"[WARN] {name} 봇이 이미 실행 중입니다 (PID: {', '.join(pids)})")
        return False

    # 봇 시작
    subprocess.Popen(
        ["python", "-u", script_path],
        cwd=BOTS_DIR,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS,
        stdout=open(os.path.join(BOTS_DIR, f"{name}.log"), "a", encoding="utf-8"),
        stderr=subprocess.STDOUT
    )
    print(f"[OK] {name} 봇 시작됨 ({bots[name]['description']})")
    return True


def stop_bot(name):
    bots = load_bots()
    if name not in bots:
        print(f"[ERROR] '{name}' 봇이 등록되어 있지 않습니다.")
        return False

    script = bots[name]["script"]
    pids = find_bot_pids(script)

    if not pids:
        print(f"[INFO] {name} 봇이 실행 중이 아닙니다.")
        return False

    for pid in pids:
        subprocess.run(["taskkill", "/F", "/PID", pid], capture_output=True)

    print(f"[OK] {name} 봇 중지됨 (PID: {', '.join(pids)})")
    return True


def restart_bot(name):
    stop_bot(name)
    import time
    time.sleep(2)
    start_bot(name)


def status():
    bots = load_bots()
    print(f"{'봇이름':<12} {'상태':<10} {'PID':<15} {'설명'}")
    print("-" * 60)
    for name, info in bots.items():
        pids = find_bot_pids(info["script"])
        if pids:
            state = "[ON]"
            pid_str = ", ".join(pids)
        else:
            state = "[OFF]"
            pid_str = "-"
        print(f"{name:<12} {state:<10} {pid_str:<15} {info['description']}")


def list_bots():
    bots = load_bots()
    for name, info in bots.items():
        print(f"  {name}: {info['description']} ({info['script']})")


def add_bot(name, script, description=""):
    bots = load_bots()
    bots[name] = {"script": script, "description": description or f"{name} 봇"}
    save_bots(bots)
    print(f"[OK] '{name}' 봇 등록됨 (script: {script})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "start" and len(sys.argv) >= 3:
        start_bot(sys.argv[2])
    elif cmd == "stop" and len(sys.argv) >= 3:
        stop_bot(sys.argv[2])
    elif cmd == "restart" and len(sys.argv) >= 3:
        restart_bot(sys.argv[2])
    elif cmd == "status":
        status()
    elif cmd == "list":
        list_bots()
    elif cmd == "add" and len(sys.argv) >= 4:
        desc = sys.argv[4] if len(sys.argv) >= 5 else ""
        add_bot(sys.argv[2], sys.argv[3], desc)
    else:
        print(__doc__)
