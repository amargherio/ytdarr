#!/usr/bin/env bash
set -euo pipefail
root="${1:?Source root required}"
output="${2:?Output directory required}"
cd "$root"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo 'Native releases currently require Linux x86_64' >&2; exit 1; }
source /etc/os-release
os_version="${VERSION_ID:-rolling}"
target="$ID-$os_version"
version="$(tr -d '\r\n' < VERSION)"
release="${MIX_BUILD_PATH:-_build/prod}/rel/ytdarr"
[[ -x "$release/bin/ytdarr" ]] || { echo "Missing assembled release: $release" >&2; exit 1; }
revision="${VCS_REF:-$(git rev-parse HEAD)}"
[[ "$revision" =~ ^[0-9a-f]{7,64}$ ]] || { echo 'VCS_REF must identify the source commit' >&2; exit 1; }
read -r _ glibc_version < <(getconf GNU_LIBC_VERSION)
otp_version="$(erl -noshell -eval 'io:put_chars(string:trim(element(2, file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"]))))), halt().')"
elixir_version="$(elixir -e 'IO.write(System.version())')"
printf 'format=1\nversion=%s\nos_id=%s\nos_version=%s\narch=x86_64\nglibc_version=%s\notp_version=%s\nelixir_version=%s\nsource_revision=%s\nbuild_date=%s\n' \
  "$version" "$ID" "$os_version" "$glibc_version" "$otp_version" "$elixir_version" "$revision" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$release/release-target"
mkdir -p "$output"
output="$(realpath "$output")"
archive="ytdarr-$version-linux-$target-x86_64.tar.gz"
tar -czf "$output/$archive" -C "$release" .
cp "$release/release-target" "$output/$archive.manifest"
(cd "$output" && sha256sum "$archive" > "$archive.sha256")
printf 'Native release: %s/%s\n' "$output" "$archive"
