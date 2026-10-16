#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
target="${1:?Usage: smoke-native.sh host|TARGET}"
version="$(tr -d '\r\n' < VERSION)"
if [[ "$target" == host ]]; then
  source /etc/os-release
  target="$ID-${VERSION_ID:-rolling}"
  archive="$root/dist/native/$target/ytdarr-$version-linux-$target-x86_64.tar.gz"
  bash deploy/scripts/run-native-smoke.sh "$archive" "$version"
  exit 0
fi
base_image=''
while read -r candidate image; do [[ "$candidate" != "$target" ]] || base_image="$image"; done < deploy/native-targets.tsv
[[ -n "$base_image" ]] || { echo "Unsupported native target: $target" >&2; exit 1; }
engine="${CONTAINER_ENGINE:-}"
if [[ -z "$engine" ]]; then
  if command -v podman >/dev/null; then engine=podman; else engine=docker; fi
fi
archive="ytdarr-$version-linux-$target-x86_64.tar.gz"
"$engine" run --rm --platform linux/amd64 --network bridge \
  --volume "$root/dist/native/$target:/input:ro,Z" \
  --volume "$root/deploy/scripts:/smoke:ro,Z" \
  "localhost/ytdarr-native-runtime:$target" \
  bash /smoke/run-native-smoke.sh "/input/$archive" "$version"
