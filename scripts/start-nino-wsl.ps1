$ErrorActionPreference = 'Continue'

$logDir = Join-Path $env:LOCALAPPDATA 'Nino'
$logFile = Join-Path $logDir 'start-nino-wsl.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-NinoLog {
  param([string] $Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] $Message" | Out-File -FilePath $logFile -Append -Encoding utf8
}

$wslArgs = @('-d', 'Ubuntu', '-u', 'bpx27', '-e', '/home/bpx27/discord-bot-nino/scripts/wsl-keepalive.sh')
Write-NinoLog 'Nino WSL supervisor started'

while ($true) {
  Write-NinoLog 'Launching WSL Nino startup and keepalive'
  & wsl.exe @wslArgs 2>&1 |
    ForEach-Object { Write-NinoLog $_ }

  $exitCode = if ($null -eq $LASTEXITCODE) { 'unknown' } else { $LASTEXITCODE }
  Write-NinoLog "WSL keepalive exited with code $exitCode; restarting in 10 seconds"
  Start-Sleep -Seconds 10
}
