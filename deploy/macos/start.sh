#!/bin/bash
set -euo pipefail
umask 077

SUPPORT="${HOME}/Library/Application Support/cokacremote"
ENV_FILE="${COKACREMOTE_ENV_FILE:-${SUPPORT}/env}"
PROXY_JS="${SUPPORT}/oauth-alias-proxy.mjs"

export LANG="${LANG:-en_US.UTF-8}"
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "cokacremote: missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

APP_HOME="${COKACREMOTE_HOME:-}"
NODE_BIN="${COKACREMOTE_NODE:-$(command -v node || true)}"

if [[ -z "$APP_HOME" ]]; then
  echo "cokacremote: COKACREMOTE_HOME is not set in $ENV_FILE" >&2
  exit 1
fi

if [[ ! -x "$NODE_BIN" ]]; then
  echo "cokacremote: node not found: ${NODE_BIN:-<empty>}" >&2
  exit 1
fi

if [[ ! -f "${APP_HOME}/dist/src/server.js" ]]; then
  echo "cokacremote: missing build output: ${APP_HOME}/dist/src/server.js" >&2
  exit 1
fi

if [[ ! -f "$PROXY_JS" ]]; then
  echo "cokacremote: missing alias proxy: $PROXY_JS" >&2
  exit 1
fi

cd "$APP_HOME"

"$NODE_BIN" dist/src/server.js &
backend_pid=$!

for _ in $(seq 1 50); do
  if curl -fsS --max-time 1 "http://127.0.0.1:${MCP_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$backend_pid" 2>/dev/null; then
    echo "cokacremote: backend exited before becoming healthy" >&2
    exit 1
  fi
  sleep 0.1
done

export MCP_ALIAS_HOST="${MCP_ALIAS_HOST:-127.0.0.1}"
export MCP_ALIAS_PORT="${MCP_ALIAS_PORT:-3000}"
"$NODE_BIN" "$PROXY_JS" &
proxy_pid=$!

cleanup() {
  kill -TERM "$proxy_pid" "$backend_pid" 2>/dev/null || true
  wait "$proxy_pid" "$backend_pid" 2>/dev/null || true
}
trap cleanup INT TERM

wait "$proxy_pid" "$backend_pid"
cleanup
