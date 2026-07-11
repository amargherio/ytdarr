#!/bin/bash

set -Eeuo pipefail

readonly APP_USER="${YTDARR_APP_USER:-ytdarr}"
readonly APP_GROUP="${YTDARR_APP_GROUP:-ytdarr}"
readonly INSTALL_ROOT="${YTDARR_INSTALL_ROOT:-/opt/ytdarr}"
readonly STATE_ROOT="${YTDARR_STATE_ROOT:-/var/lib/ytdarr}"
readonly ENV_FILE="${YTDARR_ENV_FILE:-/etc/ytdarr/ytdarr.env}"
readonly SERVICE_NAME="${YTDARR_SERVICE_NAME:-ytdarr}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 TARGET_VERSION" >&2
  exit 1
fi

readonly TARGET_VERSION="$1"
readonly TARGET_DIR="$INSTALL_ROOT/versions/$TARGET_VERSION"
readonly CURRENT_LINK="$INSTALL_ROOT/current"

if [[ "$EUID" -ne 0 ]]; then
  echo "rollback-release.sh must run as root" >&2
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Release $TARGET_VERSION is not installed" >&2
  exit 1
fi

backup_dir="$(find "$STATE_ROOT/backups" -mindepth 1 -maxdepth 1 -type d \
  -name "from-${TARGET_VERSION}-to-*" -printf '%T@ %p\n' \
  | sort -rn \
  | head -n 1 \
  | cut -d' ' -f2-)"

if [[ -z "$backup_dir" || ! -f "$backup_dir/ytdarr.db" ]]; then
  echo "No database backup is available for release $TARGET_VERSION" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${DATABASE_PATH:?DATABASE_PATH must be set in $ENV_FILE}"
PORT="${PORT:-4000}"

systemctl stop "${SERVICE_NAME}.service"
rm -f "$DATABASE_PATH" "${DATABASE_PATH}-wal" "${DATABASE_PATH}-shm"
install -o "$APP_USER" -g "$APP_GROUP" -m 0640 "$backup_dir/ytdarr.db" "$DATABASE_PATH"

for suffix in wal shm; do
  if [[ -f "$backup_dir/ytdarr.db-$suffix" ]]; then
    install -o "$APP_USER" -g "$APP_GROUP" -m 0640 \
      "$backup_dir/ytdarr.db-$suffix" "${DATABASE_PATH}-$suffix"
  fi
done

ln -sfn "$TARGET_DIR" "$CURRENT_LINK.rollback"
mv -Tf "$CURRENT_LINK.rollback" "$CURRENT_LINK"
systemctl start "${SERVICE_NAME}.service"

for _attempt in $(seq 1 30); do
  if curl --fail --silent --show-error "http://127.0.0.1:${PORT}/health/ready" >/dev/null; then
    echo "Rolled back Ytdarr to $TARGET_VERSION"
    exit 0
  fi

  sleep 2
done

echo "Release $TARGET_VERSION did not become ready after rollback" >&2
exit 1