#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
mapfile -t targets < <(while read -r target image; do [[ -z "$target" || "$target" == \#* ]] || printf '%s\n' "$target"; done < deploy/native-targets.tsv)
case "${1:-host}" in
  --list) printf '%s\n' "${targets[@]}"; exit 0 ;;
  --matrix)
    printf '{"target":['
    separator=''
    for target in "${targets[@]}"; do printf '%s"%s"' "$separator" "$target"; separator=,; done
    printf ']}\n'
    exit 0 ;;
  --help) echo 'Usage: build-native.sh [host|all|TARGET|--list|--matrix]'; exit 0 ;;
esac
[[ $# -le 1 ]] || { echo 'Expected a single target' >&2; exit 1; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo 'Native builds currently require a Linux x86_64 host' >&2; exit 1; }
if [[ "${1:-host}" == all ]]; then
  for target in "${targets[@]}" host; do bash "$0" "$target"; done
  exit 0
fi
if [[ "${1:-host}" == host ]]; then
  source /etc/os-release
  target="$ID-${VERSION_ID:-rolling}"
  export MIX_ENV=prod MIX_BUILD_PATH="$root/_build/native/$target/prod" MIX_DEPS_PATH="$root/_build/native/$target/deps"
  mix deps.get --only prod
  mix compile --warnings-as-errors
  mix assets.deploy
  mix release --overwrite
  bash deploy/scripts/package-native.sh "$root" "$root/dist/native/$target"
  exit 0
fi
target="$1"
base_image=''
while read -r candidate image; do [[ "$candidate" != "$target" ]] || base_image="$image"; done < deploy/native-targets.tsv
[[ -n "$base_image" ]] || { echo "Unsupported native target: $target (see --list)" >&2; exit 1; }
engine="${CONTAINER_ENGINE:-}"
if [[ -z "$engine" ]]; then
  if command -v podman >/dev/null; then engine=podman; else engine=docker; fi
fi
command -v "$engine" >/dev/null || { echo 'Install Podman or Docker, or set CONTAINER_ENGINE' >&2; exit 1; }
revision="${VCS_REF:-$(git rev-parse HEAD)}"
common=(--platform linux/amd64 --file deploy/Dockerfile --build-arg "BASE_IMAGE=$base_image")
"$engine" build "${common[@]}" --target runtime --tag "localhost/ytdarr-native-runtime:$target" .
"$engine" build "${common[@]}" --build-arg "VCS_REF=$revision" --build-arg "NATIVE_BUILD_JOBS=${NATIVE_BUILD_JOBS:-4}" --target artifacts --tag "localhost/ytdarr-native-artifacts:$target" .
container="$("$engine" create "localhost/ytdarr-native-artifacts:$target" /bin/true)"
trap '"$engine" rm -f "$container" >/dev/null' EXIT
mkdir -p "dist/native/$target"
"$engine" cp "$container:/out/." "dist/native/$target/"
echo "Native artifacts: dist/native/$target"
