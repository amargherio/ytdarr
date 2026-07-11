#!/bin/bash

set -euo pipefail

readonly APP_USER="${YTDARR_APP_USER:-ytdarr}"
readonly APP_GROUP="${YTDARR_APP_GROUP:-ytdarr}"
readonly INSTALL_ROOT="${YTDARR_INSTALL_ROOT:-/opt/ytdarr}"
readonly STATE_ROOT="${YTDARR_STATE_ROOT:-/var/lib/ytdarr}"
readonly ENV_TARGET="${YTDARR_ENV_FILE:-/etc/ytdarr/ytdarr.env}"
readonly SERVICE_NAME="${YTDARR_SERVICE_NAME:-ytdarr}"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 SERVICE_FILE ENV_FILE" >&2
  exit 1
fi

readonly SERVICE_SOURCE="$1"
readonly ENV_SOURCE="$2"

if [[ "$EUID" -ne 0 ]]; then
  echo "provision-host.sh must run as root" >&2
  exit 1
fi

for command_name in curl ffmpeg sqlite3 systemctl yt-dlp; do
  command -v "$command_name" >/dev/null || {
    echo "Missing required host command: $command_name" >&2
    exit 1
  }
done

if ! getent group "$APP_GROUP" >/dev/null; then
  groupadd --system "$APP_GROUP"
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --gid "$APP_GROUP" --home-dir "$STATE_ROOT" --shell /usr/sbin/nologin "$APP_USER"
fi

install -d -o root -g "$APP_GROUP" -m 0750 "$INSTALL_ROOT" "$INSTALL_ROOT/versions"
install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "$STATE_ROOT" "$STATE_ROOT/backups"
install -d -o root -g "$APP_GROUP" -m 0750 "$(dirname "$ENV_TARGET")"
install -o root -g root -m 0644 "$SERVICE_SOURCE" "/etc/systemd/system/${SERVICE_NAME}.service"

if [[ ! -e "$ENV_TARGET" ]]; then
  install -o root -g "$APP_GROUP" -m 0640 "$ENV_SOURCE" "$ENV_TARGET"
else
  echo "Keeping existing $ENV_TARGET"
fi

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
echo "Provisioned ${SERVICE_NAME}; deploy a release before starting it"