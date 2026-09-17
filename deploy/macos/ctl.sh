#!/bin/bash
set -euo pipefail

LABEL="${COKACREMOTE_LABEL:-com.feedback.codex-remote-mac}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"
DOMAIN="gui/${UID_NUM}"
SERVICE="${DOMAIN}/${LABEL}"
LOG_DIR="${HOME}/Library/Logs/cokacremote"
SUPPORT="${HOME}/Library/Application Support/cokacremote"
ENV_FILE="${COKACREMOTE_ENV_FILE:-${SUPPORT}/env}"
FUNNEL_PORT=3000

if [[ -f "$ENV_FILE" ]]; then
  FUNNEL_PORT="$(awk -F= '/^MCP_ALIAS_PORT=/{print $2; exit}' "$ENV_FILE" | tr -d '"')"
  FUNNEL_PORT="${FUNNEL_PORT:-3000}"
fi

usage() {
  echo "usage: $0 {start|stop|restart|status|logs|funnel|health}" >&2
  exit 1
}

is_loaded() {
  launchctl print "$SERVICE" >/dev/null 2>&1
}

cmd="${1:-}"
case "$cmd" in
  start)
    if is_loaded; then
      launchctl kickstart -k "$SERVICE"
    else
      launchctl bootstrap "$DOMAIN" "$PLIST"
    fi
    ;;
  stop)
    if is_loaded; then
      launchctl bootout "$DOMAIN" "$PLIST"
    fi
    ;;
  restart)
    if is_loaded; then
      launchctl kickstart -k "$SERVICE"
    else
      launchctl bootstrap "$DOMAIN" "$PLIST"
    fi
    ;;
  status)
    if is_loaded; then
      launchctl print "$SERVICE"
    else
      echo "$SERVICE is not loaded"
      exit 1
    fi
    ;;
  logs)
    mkdir -p "$LOG_DIR"
    tail -n 100 -F "${LOG_DIR}/stdout.log" "${LOG_DIR}/stderr.log"
    ;;
  funnel)
    tailscale funnel --bg --yes "$FUNNEL_PORT"
    tailscale funnel status
    ;;
  health)
    curl -fsS "http://127.0.0.1:${FUNNEL_PORT}/health"
    echo
    ;;
  *)
    usage
    ;;
esac
