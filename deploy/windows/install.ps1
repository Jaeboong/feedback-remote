$ErrorActionPreference = "Stop"

$TaskName = if ($env:COKACREMOTE_TASK_NAME) { $env:COKACREMOTE_TASK_NAME } else { "Codex-Remote-Windows" }
$Support = Join-Path $env:LOCALAPPDATA "cokacremote"
$LogDir = Join-Path $Support "logs"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppHome = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$DefaultCwd = if ($env:COKACREMOTE_DEFAULT_CWD) { $env:COKACREMOTE_DEFAULT_CWD } else { $env:USERPROFILE }

function Find-Command([string]$Name, [string[]]$Guesses) {
  $found = Get-Command $Name -ErrorAction SilentlyContinue
  if ($found) { return $found.Source }
  foreach ($guess in $Guesses) {
    if ($guess -and (Test-Path -LiteralPath $guess)) { return $guess }
  }
  return $null
}

function New-ApprovalKey {
  $bytes = New-Object byte[] 32
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $rng.GetBytes($bytes)
  -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

function Protect-PrivateFile([string]$Path) {
  icacls $Path /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
}

$NodeBin = if ($env:COKACREMOTE_NODE) { $env:COKACREMOTE_NODE } else {
  Find-Command "node" @(
    (Join-Path ${env:ProgramFiles} "nodejs\node.exe"),
    (Join-Path ${env:LOCALAPPDATA} "Programs\nodejs\node.exe")
  )
}
if (-not $NodeBin) {
  throw "Node.js 22+ 가 필요합니다. https://nodejs.org 에서 LTS를 설치하세요."
}

$nodeMajor = & $NodeBin -p "process.versions.node.split('.')[0]"
if ([int]$nodeMajor -lt 22) {
  throw "Node.js 22+ 가 필요합니다. 현재: $(& $NodeBin --version)"
}

$NpmCmd = Find-Command "npm" @(
  (Join-Path (Split-Path $NodeBin) "npm.cmd")
)
if (-not $NpmCmd) { throw "npm을 찾지 못했습니다." }

$GitBash = if ($env:COKACREMOTE_DEFAULT_SHELL) { $env:COKACREMOTE_DEFAULT_SHELL } else {
  Find-Command "bash" @(
    (Join-Path ${env:ProgramFiles} "Git\bin\bash.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe")
  )
}
if (-not $GitBash) {
  throw "Git for Windows bash가 필요합니다. https://git-scm.com/download/win 에서 설치하세요. 원본 exec_command가 -lc 플래그를 쓰기 때문입니다."
}

$Tailscale = Find-Command "tailscale" @(
  (Join-Path ${env:ProgramFiles} "Tailscale\tailscale.exe")
)
if (-not $Tailscale) {
  throw "tailscale CLI가 없습니다. https://tailscale.com/download/windows 앱을 설치하고 로그인하세요."
}

$PublicHost = $env:COKACREMOTE_PUBLIC_HOST
if (-not $PublicHost) {
  $status = & $Tailscale status --json | Out-String | ConvertFrom-Json
  $PublicHost = ([string]$status.Self.DNSName).TrimEnd(".")
}
if (-not $PublicHost) {
  throw "Tailscale MagicDNS 이름을 찾지 못했습니다. 먼저 Tailscale에 로그인하세요."
}

$PublicUrl = "https://$PublicHost"
Write-Host "checkout: $AppHome"
Write-Host "node: $NodeBin"
Write-Host "shell: $GitBash"
Write-Host "public host: $PublicHost"
Write-Host "default cwd: $DefaultCwd"

Write-Host "building cokacremote"
Push-Location $AppHome
try {
  if (Test-Path -LiteralPath (Join-Path $AppHome "package-lock.json")) {
    & $NpmCmd ci
  } else {
    & $NpmCmd install
  }
  if ($LASTEXITCODE -ne 0) { throw "npm install/ci failed" }
  & $NpmCmd run build
  if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
} finally {
  Pop-Location
}

New-Item -ItemType Directory -Force -Path $Support, $LogDir | Out-Null
Copy-Item -Force (Join-Path $ScriptDir "start.ps1") (Join-Path $Support "start.ps1")
Copy-Item -Force (Join-Path $ScriptDir "ctl.ps1") (Join-Path $Support "ctl.ps1")
Copy-Item -Force (Join-Path $ScriptDir "oauth-alias-proxy.mjs") (Join-Path $Support "oauth-alias-proxy.mjs")

$KeyFile = Join-Path $Support "approval-key"
if (Test-Path -LiteralPath $KeyFile) {
  $ApprovalKey = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
} else {
  $ApprovalKey = New-ApprovalKey
  Set-Content -LiteralPath $KeyFile -Value $ApprovalKey -Encoding ASCII
  Protect-PrivateFile $KeyFile
}

$EnvFile = Join-Path $Support "env"
$StateFile = Join-Path $Support "oauth-state.json"
@(
  "COKACREMOTE_HOME=$AppHome",
  "COKACREMOTE_NODE=$NodeBin",
  "MCP_HOST=127.0.0.1",
  "MCP_PORT=3001",
  "MCP_ALIAS_HOST=127.0.0.1",
  "MCP_ALIAS_PORT=3000",
  "MCP_ENDPOINT=/mcp",
  "MCP_PUBLIC_URL=$PublicUrl",
  "MCP_ALLOWED_HOSTS=$PublicHost,127.0.0.1,localhost",
  "MCP_TRUST_PROXY_HOPS=1",
  "MCP_AUTH_TOKEN=",
  "MCP_ALLOW_NO_AUTH=false",
  "MCP_OAUTH_ENABLED=true",
  "MCP_OAUTH_APPROVAL_KEY=$ApprovalKey",
  "MCP_OAUTH_ISSUER=$PublicUrl",
  "MCP_OAUTH_RESOURCE=$PublicUrl/mcp",
  "MCP_OAUTH_STATE_FILE=$StateFile",
  "MCP_OAUTH_ACCESS_TOKEN_TTL_SECONDS=3600",
  "MCP_OAUTH_REFRESH_TOKEN_TTL_SECONDS=2592000",
  "MCP_OAUTH_AUTHORIZATION_CODE_TTL_SECONDS=300",
  "MCP_DEFAULT_CWD=$DefaultCwd",
  "MCP_DEFAULT_SHELL=$GitBash",
  "MCP_MAX_REQUEST_BODY=8mb",
  "MCP_MAX_OUTPUT_BYTES=1048576",
  "MCP_MAX_RETAINED_PROCESS_OUTPUT_BYTES=4194304",
  "MCP_PROCESS_RETENTION_MS=3600000",
  "MCP_MAX_PROCESSES=128",
  "MCP_MAX_FILE_CHUNK_BYTES=1048576",
  "MCP_MAX_EDIT_FILE_BYTES=67108864"
) | Set-Content -LiteralPath $EnvFile -Encoding UTF8
Protect-PrivateFile $EnvFile

$StartPs1 = Join-Path $Support "start.ps1"
$arg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$StartPs1`""
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg -WorkingDirectory $AppHome
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Seconds 3) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

$healthy = $false
for ($i = 0; $i -lt 30; $i++) {
  try {
    Invoke-RestMethod -Uri "http://127.0.0.1:3000/health" -TimeoutSec 1 | Out-Null
    $healthy = $true
    break
  } catch {
    Start-Sleep -Milliseconds 200
  }
}

Write-Host ""
Write-Host "local health:"
try { Invoke-RestMethod -Uri "http://127.0.0.1:3000/health" | ConvertTo-Json -Compress } catch { Write-Host "not ready yet" }

Write-Host ""
Write-Host "다음 단계"
Write-Host "1. Tailscale Funnel이 tailnet에서 허용돼 있어야 합니다."
Write-Host "2. Funnel 연결:"
Write-Host "   powershell -File `"$(Join-Path $Support 'ctl.ps1')`" funnel"
Write-Host "3. ChatGPT 플러그인 이름: Codex-Remote-Windows"
Write-Host "4. 서버 URL: $PublicUrl/mcp"
Write-Host "5. 인증: OAuth"
Write-Host "6. 승인 키: $KeyFile"
Write-Host ""
Write-Host "재시작: powershell -File `"$(Join-Path $Support 'ctl.ps1')`" restart"
Write-Host "로그:   powershell -File `"$(Join-Path $Support 'ctl.ps1')`" logs"
