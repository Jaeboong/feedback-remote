# Codex-Remote-Windows

원본 `cokacremote` 소스는 그대로 두고, Windows에서 ChatGPT용 MCP로 쓰는 설치 파일만 들어 있습니다.

각 팀원은 **자기 PC**에 설치합니다. Tailscale Funnel 주소와 OAuth 승인 키는 기기마다 다릅니다.

원본 `exec_command`는 `-lc` / `-c` 셸 플래그를 쓰므로 Windows에서는 **Git Bash**를 기본 셸로 사용합니다. `src/`는 수정하지 않습니다.

## 필요한 것

- Windows 10/11
- [Tailscale for Windows](https://tailscale.com/download/windows) 설치 후 로그인
- 같은 tailnet에서 Funnel 허용. 꺼져 있으면 `tailscale funnel`이 활성화 URL을 보여 줌
- [Node.js 22+](https://nodejs.org)
- [Git for Windows](https://git-scm.com/download/win) (bash.exe)
- ChatGPT Developer mode

PowerShell을 **관리자 없이** 일반 사용자로 실행하면 됩니다.

```powershell
git clone https://github.com/Jaeboong/feedback-remote.git
cd feedback-remote
$env:COKACREMOTE_DEFAULT_CWD = $env:USERPROFILE
powershell -ExecutionPolicy Bypass -File .\deploy\windows\install.ps1
```

작업 폴더를 바꾸려면:

```powershell
$env:COKACREMOTE_DEFAULT_CWD = "$env:USERPROFILE\project"
powershell -ExecutionPolicy Bypass -File .\deploy\windows\install.ps1
```

설치 스크립트가 하는 일:

- `npm ci` / `npm run build`
- `%LOCALAPPDATA%\cokacremote\` 에 환경 파일과 승인 키 생성
- 작업 스케줄러 `Codex-Remote-Windows` 등록 (로그온 시 시작, 실패 시 재시작)
- 이 PC의 Tailscale 이름으로 `MCP_PUBLIC_URL` 설정
- 기본 셸을 Git Bash로 설정

이미 설치한 PC에서 다시 실행하면 기존 승인 키는 유지합니다.

## Funnel

```powershell
powershell -File "$env:LOCALAPPDATA\cokacremote\ctl.ps1" funnel
```

## ChatGPT

1. 연결 방식: **서버 URL** (터널 아님)
2. 이름: `Codex-Remote-Windows`
3. URL: `https://<이-PC의-tailscale-이름>.ts.net/mcp`
4. 인증: **OAuth**
5. 승인 키: `%LOCALAPPDATA%\cokacremote\approval-key`

Mac용 `Codex-Remote-Mac`과 별개로 추가하세요.

## 일상 명령

```powershell
$ctl = "$env:LOCALAPPDATA\cokacremote\ctl.ps1"
powershell -File $ctl restart
powershell -File $ctl status
powershell -File $ctl health
powershell -File $ctl logs
```

## 제한

- `chmod_path` 등 POSIX 권한은 NTFS에서 의미가 다릅니다.
- `run_script`의 `bash`/`sh`는 Git Bash가 있어야 합니다.
- 프로세스 종료는 Windows에서 프로세스 그룹 대신 자식 프로세스에 시그널을 보냅니다. 원본 코드의 `win32` 분기입니다.

## 업데이트

```powershell
cd \path\to\feedback-remote
git pull --ff-only origin main
npm ci
npm run build
powershell -File "$env:LOCALAPPDATA\cokacremote\ctl.ps1" restart
```
