#!/bin/bash

set -euo pipefail

OUTPUT=""
HOST=""
RUNTIME="container"
PORT="4000"
FORCE="false"

usage() {
  echo "Usage: $0 --output PATH --host HOST [--runtime container|native] [--port PORT] [--force]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --runtime)
      RUNTIME="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUTPUT" || -z "$HOST" ]]; then
  usage >&2
  exit 1
fi

if [[ "$HOST" =~ [[:space:]#] ]]; then
  echo "HOST must not contain whitespace or #" >&2
  exit 1
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
  echo "PORT must be between 1 and 65535" >&2
  exit 1
fi

case "$RUNTIME" in
  container) DATABASE_PATH="/data/ytdarr.db" ;;
  native) DATABASE_PATH="/var/lib/ytdarr/ytdarr.db" ;;
  *)
    echo "RUNTIME must be container or native" >&2
    exit 1
    ;;
esac

if [[ -e "$OUTPUT" && "$FORCE" != "true" ]]; then
  echo "$OUTPUT already exists; pass --force to replace it" >&2
  exit 1
fi

command -v openssl >/dev/null || {
  echo "openssl is required" >&2
  exit 1
}

umask 077
mkdir -p "$(dirname "$OUTPUT")"
TEMP_FILE="$(mktemp "${OUTPUT}.XXXXXX")"
trap 'rm -f "$TEMP_FILE"' EXIT

SECRET_KEY_BASE="$(openssl rand -base64 48 | tr -d '\n')"
TOKEN_SIGNING_SECRET="$(openssl rand -base64 48 | tr -d '\n')"

cat >"$TEMP_FILE" <<EOF
DATABASE_PATH=$DATABASE_PATH
SECRET_KEY_BASE=$SECRET_KEY_BASE
TOKEN_SIGNING_SECRET=$TOKEN_SIGNING_SECRET
PHX_SERVER=true
PHX_HOST=$HOST
ALLOWED_HOSTS=$HOST
PORT=$PORT
POOL_SIZE=5
EOF

mv -f "$TEMP_FILE" "$OUTPUT"
trap - EXIT
echo "Created $OUTPUT with mode 0600"