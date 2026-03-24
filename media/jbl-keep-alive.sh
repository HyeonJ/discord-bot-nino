#!/usr/bin/env bash
# JBL Go 4 keep-alive: 무음 WAV를 반복 재생해서 자동 꺼짐 방지
# Usage: jbl-keep-alive.sh start|stop

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SILENCE_FILE="$SCRIPT_DIR/silence-10min.wav"
PID_FILE="/tmp/jbl-keep-alive.pid"
POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

case "${1:-start}" in
  start)
    # Kill existing if running
    if [[ -f "$PID_FILE" ]]; then
      kill "$(cat "$PID_FILE")" 2>/dev/null
      rm -f "$PID_FILE"
    fi
    # Convert WSL path to Windows path and play with PowerShell MediaPlayer in loop
    WIN_PATH=$(wslpath -w "$SILENCE_FILE")
    $POWERSHELL -Command "
      Add-Type -AssemblyName PresentationCore
      \$player = New-Object System.Windows.Media.MediaPlayer
      \$player.Open([Uri]'$WIN_PATH')
      \$player.Volume = 0.01
      \$player.Play()
      while (\$true) {
        Start-Sleep -Seconds 590
        \$player.Position = [TimeSpan]::Zero
        \$player.Play()
      }
    " &
    echo $! > "$PID_FILE"
    echo "JBL keep-alive started (PID: $(cat "$PID_FILE"))"
    ;;
  stop)
    if [[ -f "$PID_FILE" ]]; then
      kill "$(cat "$PID_FILE")" 2>/dev/null
      rm -f "$PID_FILE"
      echo "JBL keep-alive stopped"
    else
      echo "Not running"
    fi
    ;;
  *)
    echo "Usage: $0 start|stop"
    ;;
esac
