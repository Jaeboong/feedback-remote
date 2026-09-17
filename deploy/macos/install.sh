#!/bin/bash
set -euo pipefail

LABEL="${COKACREMOTE_LABEL:-com.feedback.codex-remote-mac}"
SUPPORT="${HOME}/Library/Application Support/cokacremote"
LOG_DIR="${HOME}/Library/Logs/cokacremote"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_HOME="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NODE_BIN="${COKACREMOTE_NODE:-}"
DEFAULT_CWD="${COKACREMOTE_DEFAULT_CWD:-$HOME}"
DEFAULT_SHELL="${COKACREMOTE_DEFAULT_SHELL:-${SHELL:-/bin/zsh}}"

if [[ -z "$NODE_BIN" ]]; then
  NODE_BIN="$(command -v node || true)"
fi
if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  echo "Node.js 22+ 가 필요합니다. Homebrew로 설치하세요: brew install node" >&2
  exit 1
fi

node_major="$("$NODE_BIN" -p "process.versions.node.split('.')[0]")"
if [[ "$node_major" -lt 22 ]]; then
  echo "Node.js 22+ 가 필요합니다. 현재: $("$NODE_BIN" --version)" >&2
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale CLI가 없습니다. Tailscale 앱을 설치한 뒤 로그인하세요." >&2
  exit 1
fi

PUBLIC_HOST="${COKACREMOTE_PUBLIC_HOST:-}"
if [[ -z "$PUBLIC_HOST" ]]; then
  PUBLIC_HOST="$(tailscale status --json 2>/dev/null | "$NODE_BIN" -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(0, "utf8"));
    const name = data?.Self?.DNSName || "";
    process.stdout.write(name.replace(/\.$/, ""));
  ')"
fi
if [[ -z "$PUBLIC_HOST" ]]; then
  echo "Tailscale MagicDNS 이름을 찾지 못했습니다. 먼저 tailscale login 후 다시 실행하세요." >&2
  exit 1
fi

PUBLIC_URL="https://${PUBLIC_HOST}"
echo "checkout: $APP_HOME"
echo "node: $NODE_BIN"
echo "public host: $PUBLIC_HOST"
echo "default cwd: $DEFAULT_CWD"

echo "building cokacremote"
(
  cd "$APP_HOME"
  if [[ -f package-lock.json ]]; then
    npm ci
  else
    npm install
  fi
  npm run build
)

mkdir -p "$SUPPORT" "$LOG_DIR" "${HOME}/Library/LaunchAgents"
chmod 700 "$SUPPORT"

cp "$SCRIPT_DIR/start.sh" "$SUPPORT/start.sh"
cp "$SCRIPT_DIR/ctl.sh" "$SUPPORT/ctl.sh"
cp "$SCRIPT_DIR/oauth-alias-proxy.mjs" "$SUPPORT/oauth-alias-proxy.mjs"
chmod 755 "$SUPPORT/start.sh" "$SUPPORT/ctl.sh"

if [[ -f "$SUPPORT/approval-key" ]]; then
  APPROVAL_KEY="$(tr -d '[:space:]' < "$SUPPORT/approval-key")"
else
  APPROVAL_KEY="$(openssl rand -hex 32)"
  printf '%s\n' "$APPROVAL_KEY" > "$SUPPORT/approval-key"
  chmod 600 "$SUPPORT/approval-key"
fi

cat > "$SUPPORT/env" <<EOF
COKACREMOTE_HOME=${APP_HOME}
COKACREMOTE_NODE=${NODE_BIN}
MCP_HOST=127.0.0.1
MCP_PORT=3001
MCP_ALIAS_HOST=127.0.0.1
MCP_ALIAS_PORT=3000
MCP_ENDPOINT=/mcp
MCP_PUBLIC_URL=${PUBLIC_URL}
MCP_ALLOWED_HOSTS=${PUBLIC_HOST},127.0.0.1,localhost
MCP_TRUST_PROXY_HOPS=1
MCP_AUTH_TOKEN=
MCP_ALLOW_NO_AUTH=false
MCP_OAUTH_ENABLED=true
MCP_OAUTH_APPROVAL_KEY=${APPROVAL_KEY}
MCP_OAUTH_ISSUER=${PUBLIC_URL}
MCP_OAUTH_RESOURCE=${PUBLIC_URL}/mcp
MCP_OAUTH_STATE_FILE="${SUPPORT}/oauth-state.json"
MCP_OAUTH_ACCESS_TOKEN_TTL_SECONDS=3600
MCP_OAUTH_REFRESH_TOKEN_TTL_SECONDS=2592000
MCP_OAUTH_AUTHORIZATION_CODE_TTL_SECONDS=300
MCP_DEFAULT_CWD=${DEFAULT_CWD}
MCP_DEFAULT_SHELL=${DEFAULT_SHELL}
MCP_MAX_REQUEST_BODY=8mb
MCP_MAX_OUTPUT_BYTES=1048576
MCP_MAX_RETAINED_PROCESS_OUTPUT_BYTES=4194304
MCP_PROCESS_RETENTION_MS=3600000
MCP_MAX_PROCESSES=128
MCP_MAX_FILE_CHUNK_BYTES=1048576
MCP_MAX_EDIT_FILE_BYTES=67108864
EOF
chmod 600 "$SUPPORT/env"

sed \
  -e "s|__LABEL__|${LABEL}|g" \
  -e "s|__START_SH__|${SUPPORT}/start.sh|g" \
  -e "s|__APP_HOME__|${APP_HOME}|g" \
  -e "s|__HOME__|${HOME}|g" \
  -e "s|__STDOUT__|${LOG_DIR}/stdout.log|g" \
  -e "s|__STDERR__|${LOG_DIR}/stderr.log|g" \
  "$SCRIPT_DIR/com.feedback.codex-remote-mac.plist.template" > "$PLIST"
chmod 644 "$PLIST"

UID_NUM="$(id -u)"
DOMAIN="gui/${UID_NUM}"
SERVICE="${DOMAIN}/${LABEL}"
if launchctl print "$SERVICE" >/dev/null 2>&1; then
  launchctl kickstart -k "$SERVICE"
else
  launchctl bootstrap "$DOMAIN" "$PLIST"
fi

for _ in $(seq 1 30); do
  if curl -fsS --max-time 1 http://127.0.0.1:3000/health >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

echo
echo "local health:"
curl -fsS http://127.0.0.1:3000/health || true
echo
echo
echo "다음 단계"
echo "1. Tailscale Funnel이 tailnet에서 허용돼 있어야 합니다."
echo "2. Funnel 연결:"
echo "   ${SUPPORT}/ctl.sh funnel"
echo "3. ChatGPT 플러그인 이름: Codex-Remote-Mac"
echo "4. 서버 URL: ${PUBLIC_URL}/mcp"
echo "5. 인증: OAuth"
echo "6. 승인 키: ${SUPPORT}/approval-key"
echo
echo "재시작: ${SUPPORT}/ctl.sh restart"
echo "로그:   ${SUPPORT}/ctl.sh logs"
