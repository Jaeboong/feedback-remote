# Codex-Remote-Mac

원본 `cokacremote` 소스는 그대로 두고, macOS에서 ChatGPT용 MCP로 쓰는 설치 파일만 들어 있습니다.

각 팀원은 **자기 Mac**에 설치합니다. Tailscale Funnel 주소와 OAuth 승인 키는 기기마다 다릅니다. 한 대를 여러 명이 같이 쓰지 마세요.

## 필요한 것

- macOS
- Node.js 22+
- Tailscale 로그인 완료
- 이 저장소 clone
- ChatGPT Developer mode

## 설치

```bash
git clone https://github.com/Jaeboong/feedback-remote.git
cd feedback-remote
chmod +x deploy/macos/install.sh
COKACREMOTE_DEFAULT_CWD="$HOME" ./deploy/macos/install.sh
```

작업 폴더를 지정하려면:

```bash
COKACREMOTE_DEFAULT_CWD="$HOME/project" ./deploy/macos/install.sh
```

설치 스크립트가 하는 일:

- `npm ci` / `npm run build`
- `~/Library/Application Support/cokacremote/` 에 환경 파일과 승인 키 생성
- LaunchAgent 등록 후 자동 시작
- 이 Mac의 Tailscale 이름으로 `MCP_PUBLIC_URL` 설정

이미 설치한 맥에서 다시 실행하면 기존 승인 키는 유지합니다.

## Funnel

```bash
"$HOME/Library/Application Support/cokacremote/ctl.sh" funnel
```

tailnet에서 Funnel이 꺼져 있으면 `tailscale funnel`이 활성화 URL을 보여줍니다. 관리자가 허용한 뒤 위 명령을 다시 실행하세요.

## ChatGPT

1. 연결 방식: **서버 URL** (터널 아님)
2. 이름: `Codex-Remote-Mac` 또는 본인 Mac이 드러나는 이름
3. URL: `https://<이-맥의-tailscale-이름>.ts.net/mcp`
4. 인증: **OAuth**
5. 승인 키: `~/Library/Application Support/cokacremote/approval-key`

설치가 끝나면 스크립트가 본인 URL을 출력합니다.

## 일상 명령

```bash
SUPPORT="$HOME/Library/Application Support/cokacremote"
"$SUPPORT/ctl.sh" restart
"$SUPPORT/ctl.sh" status
"$SUPPORT/ctl.sh" health
"$SUPPORT/ctl.sh" logs
```

## 업데이트

```bash
cd /path/to/feedback-remote
git pull --ff-only origin main
npm ci
npm run build
"$HOME/Library/Application Support/cokacremote/ctl.sh" restart
```

upstream 원본을 받으려면:

```bash
git fetch upstream
git merge --ff-only upstream/main
```

`src/` 는 원본을 유지하세요. Mac 전용 변경은 `deploy/macos/` 만 추가합니다.
