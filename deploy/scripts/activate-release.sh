#!/bin/bash

set -Eeuo pipefail

readonly APP_USER="${YTDARR_APP_USER:-ytdarr}"
readonly APP_GROUP="${YTDARR_APP_GROUP:-ytdarr}"
readonly INSTALL_ROOT="${YTDARR_INSTALL_ROOT:-/opt/ytdarr}"
readonly STATE_ROOT="${YTDARR_STATE_ROOT:-/var/lib/ytdarr}"
readonly ENV_FILE="${YTDARR_ENV_FILE:-/etc/ytdarr/ytdarr.env}"
readonly SERVICE_NAME="${YTDARR_SERVICE_NAME:-ytdarr}"
readonly RETENTION="${YTDARR_RELEASE_RETENTION:-3}"
readonly VERSIONS_DIR="$INSTALL_ROOT/versions"
readonly CURRENT_LINK="$INSTALL_ROOT/current"

usage() {
  echo "Usage: $0 [--dry-run] RELEASE_TARBALL CHECKSUM_FILE VERSION" >&2
}

dry_run="false"
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run="true"
  shift
fi

if [[ $# -ne 3 ]]; then
  usage
  exit 1
fi

ARCHIVE="$(readlink -f "$1")"
CHECKSUM="$(readlink -f "$2")"
readonly VERSION="$3"
readonly RELEASE_DIR="$VERSIONS_DIR/$VERSION"
readonly ARCHIVE CHECKSUM

if [[ "$EUID" -ne 0 && "$dry_run" != "true" ]]; then
  echo "activate-release.sh must run as root" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 1
fi

if [[ ! -r "$ENV_FILE" ]]; then
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi

if [[ -e "$RELEASE_DIR" ]]; then
  echo "Release $VERSION is already installed" >&2
  exit 1
fi

for command_name in curl runuser sha256sum systemctl tar; do
  command -v "$command_name" >/dev/null || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

checksum_dir="$(dirname "$CHECKSUM")"
checksum_name="$(basename "$CHECKSUM")"
(
  cd "$checksum_dir"
  sha256sum --check "$checksum_name"
)

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${DATABASE_PATH:?DATABASE_PATH must be set in $ENV_FILE}"
PORT="${PORT:-4000}"

previous_target=""
previous_version="none"
if [[ -L "$CURRENT_LINK" ]]; then
  previous_target="$(readlink -f "$CURRENT_LINK")"
  previous_version="$(basename "$previous_target")"
fi

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
readonly BACKUP_DIR="$STATE_ROOT/backups/from-${previous_version}-to-${VERSION}-${TIMESTAMP}"
readonly TIMESTAMP

if [[ "$dry_run" == "true" ]]; then
  echo "Dry run: no changes will be made"
  echo "Would make $INSTALL_ROOT and $(dirname "$ENV_FILE") world-readable"
  echo "Would extract $ARCHIVE into $RELEASE_DIR with owner root:$APP_GROUP and world-readable permissions"
  echo "Would stop ${SERVICE_NAME}.service"

  if [[ -f "$DATABASE_PATH" ]]; then
    echo "Would back up $DATABASE_PATH and any WAL/SHM files to $BACKUP_DIR"
  else
    echo "Would create $BACKUP_DIR; no existing database would be backed up"
  fi

  echo "Would ensure the database directory exists: $(dirname "$DATABASE_PATH")"
  echo "Would run database migrations: $RELEASE_DIR/bin/migrate (as $APP_USER)"
  echo "Would atomically point $CURRENT_LINK to $RELEASE_DIR"
  echo "Would start ${SERVICE_NAME}.service and check http://127.0.0.1:${PORT}/health/ready"
  echo "Would retain the newest $RETENTION release directories and database backups"
  exit 0
fi

chmod -R a+rX "$INSTALL_ROOT" "$(dirname "$ENV_FILE")"

database_existed="false"
switched="false"

restore_database() {
  rm -f "$DATABASE_PATH" "${DATABASE_PATH}-wal" "${DATABASE_PATH}-shm"

  if [[ "$database_existed" == "true" ]]; then
    install -o "$APP_USER" -g "$APP_GROUP" -m 0640 "$BACKUP_DIR/ytdarr.db" "$DATABASE_PATH"

    for suffix in wal shm; do
      if [[ -f "$BACKUP_DIR/ytdarr.db-$suffix" ]]; then
        install -o "$APP_USER" -g "$APP_GROUP" -m 0640 \
          "$BACKUP_DIR/ytdarr.db-$suffix" "${DATABASE_PATH}-$suffix"
      fi
    done
  fi
}

rollback_on_error() {
  trap - ERR
  echo "Activation failed; restoring the previous release" >&2
  systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  restore_database

  if [[ -n "$previous_target" ]]; then
    ln -sfn "$previous_target" "$CURRENT_LINK.rollback"
    mv -Tf "$CURRENT_LINK.rollback" "$CURRENT_LINK"
    systemctl start "${SERVICE_NAME}.service" || true
  elif [[ "$switched" == "true" ]]; then
    rm -f "$CURRENT_LINK"
  fi

  rm -rf "$RELEASE_DIR"
  exit 1
}

trap rollback_on_error ERR

install -d -o root -g "$APP_GROUP" -m 0755 "$RELEASE_DIR"
tar -xzf "$ARCHIVE" -C "$RELEASE_DIR"
chown -R root:"$APP_GROUP" "$RELEASE_DIR"
chmod -R a+rX "$RELEASE_DIR"

systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true

install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "$BACKUP_DIR"
if [[ -f "$DATABASE_PATH" ]]; then
  database_existed="true"
  install -o "$APP_USER" -g "$APP_GROUP" -m 0640 "$DATABASE_PATH" "$BACKUP_DIR/ytdarr.db"

  for suffix in wal shm; do
    if [[ -f "${DATABASE_PATH}-$suffix" ]]; then
      install -o "$APP_USER" -g "$APP_GROUP" -m 0640 \
        "${DATABASE_PATH}-$suffix" "$BACKUP_DIR/ytdarr.db-$suffix"
    fi
  done
fi

install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "$(dirname "$DATABASE_PATH")"
runuser -u "$APP_USER" -- "$RELEASE_DIR/bin/migrate"

ln -sfn "$RELEASE_DIR" "$CURRENT_LINK.next"
mv -Tf "$CURRENT_LINK.next" "$CURRENT_LINK"
switched="true"

systemctl start "${SERVICE_NAME}.service"

ready="false"
for _attempt in $(seq 1 30); do
  if curl --fail --silent --show-error "http://127.0.0.1:${PORT}/health/ready" >/dev/null; then
    ready="true"
    break
  fi

  sleep 2
done

if [[ "$ready" != "true" ]]; then
  echo "Release $VERSION did not become ready" >&2
  false
fi

trap - ERR

find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
  | sort -rn \
  | awk -v keep="$RETENTION" 'NR > keep {sub(/^[^ ]+ /, ""); print}' \
  | while IFS= read -r old_release; do
      [[ "$old_release" == "$(readlink -f "$CURRENT_LINK")" ]] || rm -rf "$old_release"
    done

find "$STATE_ROOT/backups" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
  | sort -rn \
  | awk -v keep="$RETENTION" 'NR > keep {sub(/^[^ ]+ /, ""); print}' \
  | xargs --no-run-if-empty rm -rf

echo "Activated Ytdarr $VERSION"