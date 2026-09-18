param(
  [Parameter(Position = 0)]
  [ValidateSet("start", "stop", "restart", "status", "logs", "funnel", "health")]
  [string]$Command
)

$ErrorActionPreference = "Stop"
$TaskName = if ($env:COKACREMOTE_TASK_NAME) { $env:COKACREMOTE_TASK_NAME } else { "Codex-Remote-Windows" }
$Support = Join-Path $env:LOCALAPPDATA "cokacremote"
$EnvFile = Join-Path $Support "env"
$LogDir = Join-Path $Support "logs"
$PidFile = Join-Path $Support "service.pids"
$FunnelPort = "3000"

if (Test-Path -LiteralPath $EnvFile) {
  $alias = Select-String -LiteralPath $EnvFile -Pattern "^MCP_ALIAS_PORT=(.+)$" | Select-Object -First 1
  if ($alias) {
    $FunnelPort = $alias.Matches[0].Groups[1].Value.Trim().Trim('"')
  }
}

function Get-Tailscale {
  $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $guess = Join-Path ${env:ProgramFiles} "Tailscale\tailscale.exe"
  if (Test-Path -LiteralPath $guess) { return $guess }
  throw "tailscale CLI가 없습니다."
}

function Stop-ServiceTree {
  if (Test-Path -LiteralPath $PidFile) {
    Get-Content -LiteralPath $PidFile | ForEach-Object {
      $id = 0
      if ([int]::TryParse($_.Trim(), [ref]$id)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
      }
    }
  }
  Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | ForEach-Object {
    if ($_.CommandLine -and $_.CommandLine -match "oauth-alias-proxy\.mjs|dist\\src\\server\.js") {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }
}

if (-not $Command) {
  Write-Error "usage: ctl.ps1 start|stop|restart|status|logs|funnel|health"
}

switch ($Command) {
  "start" {
    Start-ScheduledTask -TaskName $TaskName
  }
  "stop" {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Stop-ServiceTree
  }
  "restart" {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Stop-ServiceTree
    Start-Sleep -Seconds 1
    Start-ScheduledTask -TaskName $TaskName
  }
  "status" {
    Get-ScheduledTask -TaskName $TaskName | Format-List TaskName, State
    Get-ScheduledTaskInfo -TaskName $TaskName | Format-List LastRunTime, LastTaskResult, NextRunTime
  }
  "logs" {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Get-ChildItem -LiteralPath $LogDir -Filter "*.log" | Sort-Object LastWriteTime | ForEach-Object {
      Write-Output "===== $($_.Name) ====="
      Get-Content -LiteralPath $_.FullName -Tail 80
    }
  }
  "funnel" {
    $tailscale = Get-Tailscale
    & $tailscale funnel --bg --yes $FunnelPort
    & $tailscale funnel status
  }
  "health" {
    Invoke-RestMethod -Uri "http://127.0.0.1:$FunnelPort/health" | ConvertTo-Json -Compress
  }
}
