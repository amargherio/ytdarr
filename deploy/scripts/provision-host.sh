#!/bin/bash

set -euo pipefail

readonly APP_USER="${YTDARR_APP_USER:-ytdarr}"
readonly APP_GROUP="${YTDARR_APP_GROUP:-ytdarr}"
readonly INSTALL_ROOT="${YTDARR_INSTALL_ROOT:-/opt/ytdarr}"
readonly STATE_ROOT="${YTDARR_STATE_ROOT:-/var/lib/ytdarr}"
readonly ENV_TARGET="${YTDARR_ENV_FILE:-/etc/ytdarr/ytdarr.env}"
readonly SERVICE_NAME="${YTDARR_SERVICE_NAME:-ytdarr}"

usage() {
  echo "Usage: $0 [--dry-run] SERVICE_FILE ENV_FILE" >&2
}

dry_run="false"
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run="true"
  shift
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

readonly SERVICE_SOURCE="$1"
readonly ENV_SOURCE="$2"

if [[ "$EUID" -ne 0 && "$dry_run" != "true" ]]; then
  echo "provision-host.sh must run as root" >&2
  exit 1
fi

for command_name in curl ffmpeg sqlite3 systemctl yt-dlp; do
  command -v "$command_name" >/dev/null || {
    echo "Missing required host command: $command_name" >&2
    exit 1
  }
done

if [[ "$dry_run" == "true" ]]; then
  echo "Dry run: no changes will be made"

  if getent group "$APP_GROUP" >/dev/null; then
    echo "Would keep existing group: $APP_GROUP"
  else
    echo "Would create system group: $APP_GROUP"
  fi

  if id "$APP_USER" >/dev/null 2>&1; then
    echo "Would keep existing user: $APP_USER"
  else
    echo "Would create system user: $APP_USER (group: $APP_GROUP, home: $STATE_ROOT)"
  fi

  echo "Would ensure directories: $INSTALL_ROOT, $INSTALL_ROOT/versions, $STATE_ROOT, $STATE_ROOT/backups, $(dirname "$ENV_TARGET")"
  echo "Would make $INSTALL_ROOT and $(dirname "$ENV_TARGET") world-readable"
  echo "Would install systemd service: $SERVICE_SOURCE -> /etc/systemd/system/${SERVICE_NAME}.service"

  if [[ -e "$ENV_TARGET" ]]; then
    echo "Would keep existing environment file: $ENV_TARGET"
  else
    echo "Would install environment file: $ENV_SOURCE -> $ENV_TARGET"
  fi

  echo "Would reload systemd and enable ${SERVICE_NAME}.service"
  exit 0
fi

if ! getent group "$APP_GROUP" >/dev/null; then
  groupadd --system "$APP_GROUP"
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --gid "$APP_GROUP" --home-dir "$STATE_ROOT" --shell /usr/sbin/nologin "$APP_USER"
fi

install -d -o root -g "$APP_GROUP" -m 0755 "$INSTALL_ROOT" "$INSTALL_ROOT/versions"
install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "$STATE_ROOT" "$STATE_ROOT/backups"
install -d -o root -g "$APP_GROUP" -m 0755 "$(dirname "$ENV_TARGET")"
install -o root -g root -m 0644 "$SERVICE_SOURCE" "/etc/systemd/system/${SERVICE_NAME}.service"

if [[ ! -e "$ENV_TARGET" ]]; then
  install -o root -g "$APP_GROUP" -m 0644 "$ENV_SOURCE" "$ENV_TARGET"
else
  echo "Keeping existing $ENV_TARGET"
fi

chmod -R a+rX "$INSTALL_ROOT" "$(dirname "$ENV_TARGET")"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
echo "Provisioned ${SERVICE_NAME}; deploy a release before starting it"