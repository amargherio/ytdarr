#!/usr/bin/env bash
set -euo pipefail
archive="${1:?Archive required}"
scripts="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
version="${2:?Release version required}"
bash "$scripts/validate-native.sh" "$archive" "$archive.sha256" "$version"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir "$root/release"
tar -xzf "$archive" -C "$root/release"
export NATIVE_SMOKE_ROOT="$root" DATABASE_PATH="$root/ytdarr.db" PHX_HOST=localhost PHX_SERVER=true
export SECRET_KEY_BASE='native-smoke-only-not-a-production-secret-0000000000000000000000000000'
export TOKEN_SIGNING_SECRET='native-smoke-only-not-a-production-secret-0000000000000000000000000000'
export PORT="${NATIVE_SMOKE_PORT:-45873}"
unset YTDARR_YOUTUBE_API_KEY YTDARR_IMPORT_ROOTS
"$root/release/bin/migrate"
"$root/release/bin/ytdarr" eval "Code.eval_file(\"$scripts/native-smoke.exs\")"
