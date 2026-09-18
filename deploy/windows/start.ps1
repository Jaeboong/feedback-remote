$ErrorActionPreference = "Stop"

$Support = Join-Path $env:LOCALAPPDATA "cokacremote"
$EnvFile = if ($env:COKACREMOTE_ENV_FILE) { $env:COKACREMOTE_ENV_FILE } else { Join-Path $Support "env" }
$LogDir = Join-Path $Support "logs"
$PidFile = Join-Path $Support "service.pids"

function Import-CokacEnv([string]$Path) {
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim().Trim('"')
    Set-Item -Path "Env:$name" -Value $value
  }
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
  throw "cokacremote: missing env file: $EnvFile"
}

Import-CokacEnv $EnvFile

$AppHome = $env:COKACREMOTE_HOME
$NodeBin = $env:COKACREMOTE_NODE
$ProxyJs = Join-Path $Support "oauth-alias-proxy.mjs"

if (-not $AppHome -or -not (Test-Path -LiteralPath (Join-Path $AppHome "dist\src\server.js"))) {
  throw "cokacremote: COKACREMOTE_HOME is missing or not built: $AppHome"
}
if (-not $NodeBin -or -not (Test-Path -LiteralPath $NodeBin)) {
  throw "cokacremote: node not found: $NodeBin"
}
if (-not (Test-Path -LiteralPath $ProxyJs)) {
  throw "cokacremote: missing alias proxy: $ProxyJs"
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location -LiteralPath $AppHome

$script:Backend = $null
$script:Proxy = $null

function Stop-Child([System.Diagnostics.Process]$proc) {
  if ($null -eq $proc) { return }
  try {
    if (-not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  } catch {}
}

function Start-Child([string]$FilePath, [string[]]$Arguments, [string]$OutLog, [string]$ErrLog) {
  return Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $AppHome -PassThru -WindowStyle Hidden -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
}

function Save-Pids {
  $ids = @()
  if ($script:Backend -and -not $script:Backend.HasExited) { $ids += $script:Backend.Id }
  if ($script:Proxy -and -not $script:Proxy.HasExited) { $ids += $script:Proxy.Id }
  Set-Content -LiteralPath $PidFile -Value ($ids -join "`n") -Encoding ASCII
}

function Stop-All {
  Stop-Child $script:Proxy
  Stop-Child $script:Backend
  Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
}

Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Stop-All } | Out-Null
try {
  [Console]::TreatControlCAsInput = $false
} catch {}

while ($true) {
  Stop-All
  $script:Backend = Start-Child $NodeBin @("dist\src\server.js") (Join-Path $LogDir "backend.out.log") (Join-Path $LogDir "backend.err.log")
  Start-Sleep -Milliseconds 400
  $script:Proxy = Start-Child $NodeBin @($ProxyJs) (Join-Path $LogDir "proxy.out.log") (Join-Path $LogDir "proxy.err.log")
  Save-Pids

  while ($script:Backend -and -not $script:Backend.HasExited -and $script:Proxy -and -not $script:Proxy.HasExited) {
    Start-Sleep -Seconds 1
  }
  Write-Output "cokacremote child exited; restarting in 3s"
  Start-Sleep -Seconds 3
}
