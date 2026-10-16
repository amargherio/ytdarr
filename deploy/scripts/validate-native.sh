#!/bin/bash

set -euo pipefail

fail() {
  echo "Native release rejected: $*" >&2
  exit 1
}

[[ $# -eq 3 ]] || fail "usage: $0 RELEASE_TARBALL CHECKSUM_FILE VERSION"
readonly ARCHIVE="$1" CHECKSUM="$2" RELEASE_VERSION="$3"
[[ -f "$ARCHIVE" && -r "$ARCHIVE" ]] || fail "unreadable archive: $ARCHIVE"
[[ -f "$CHECKSUM" && -r "$CHECKSUM" ]] || fail "unreadable checksum: $CHECKSUM"
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || fail "invalid requested version: $RELEASE_VERSION"

for command_name in sha256sum tar uname getconf sort; do
  command -v "$command_name" >/dev/null || fail "missing required command: $command_name"
done

# Bind the checksum to the supplied archive, never to another path named by a sidecar.
mapfile -t checksum_lines < "$CHECKSUM"
[[ ${#checksum_lines[@]} -eq 1 ]] || fail "checksum must contain exactly one entry"
checksum_line="${checksum_lines[0]}"
[[ "$checksum_line" =~ ^([a-fA-F0-9]{64})\ [\ \*](.+)$ ]] || fail "invalid SHA-256 checksum entry"
expected_digest="${BASH_REMATCH[1],,}"
[[ "${BASH_REMATCH[2]}" == "$(basename "$ARCHIVE")" ]] || fail "checksum names a different archive"
actual_digest="$(sha256sum -- "$ARCHIVE")"
[[ "${actual_digest%% *}" == "$expected_digest" ]] || fail "archive checksum mismatch"

# Accept tar's conventional ./ prefix, but require exactly one root metadata member.
members="$(tar -tzf "$ARCHIVE")" || fail "cannot list archive"
metadata_member=""
while IFS= read -r member; do
  if [[ "$member" == "release-target" || "$member" == "./release-target" ]]; then
    [[ -z "$metadata_member" ]] || fail "duplicate release-target metadata"
    metadata_member="$member"
  fi
done <<< "$members"
[[ -n "$metadata_member" ]] || fail "missing release-target metadata"
metadata="$(tar -xOzf "$ARCHIVE" -- "$metadata_member")" || fail "cannot read release-target metadata"

# Metadata is data, not a shell fragment. Unknown, duplicate, empty and malformed fields fail closed.
declare -A fields=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^([a-z_]+)=([[:graph:]]+)$ ]] || fail "malformed release-target metadata"
  key="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  case "$key" in
    format|version|os_id|os_version|arch|glibc_version|otp_version|elixir_version|source_revision|build_date) ;;
    *) fail "unknown metadata field: $key" ;;
  esac
  [[ ! -v "fields[$key]" ]] || fail "duplicate metadata field: $key"
  fields["$key"]="$value"
done <<< "$metadata"
for key in format version os_id os_version arch glibc_version otp_version elixir_version source_revision build_date; do
  [[ -v "fields[$key]" ]] || fail "missing metadata field: $key"
done
[[ "${fields[format]}" == "1" ]] || fail "unsupported metadata format"
[[ "${fields[version]}" == "$RELEASE_VERSION" ]] || fail "archive version ${fields[version]} does not match requested version $RELEASE_VERSION"
[[ "${fields[os_id]}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "invalid OS identifier"
[[ "${fields[os_version]}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid OS version"
[[ "${fields[arch]}" == "x86_64" ]] || fail "unsupported archive architecture"
[[ "${fields[glibc_version]}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)*$ ]] || fail "invalid glibc version"
[[ "${fields[otp_version]}" =~ ^[0-9][0-9A-Za-z.+_-]*$ ]] || fail "invalid OTP version"
[[ "${fields[elixir_version]}" =~ ^[0-9][0-9A-Za-z.+_-]*$ ]] || fail "invalid Elixir version"
[[ "${fields[source_revision]}" =~ ^[0-9a-fA-F]{7,64}$ ]] || fail "invalid source revision"
[[ "${fields[build_date]}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail "invalid build date"

[[ -r /etc/os-release ]] || fail "host has no /etc/os-release"
# This is the trusted host configuration, never artifact-provided shell code.
source /etc/os-release
host_os="${ID:-}"
host_version="${VERSION_ID:-rolling}"
host_arch="$(uname -m)"
[[ "${fields[os_id]}" == "$host_os" && "${fields[os_version]}" == "$host_version" ]] || fail "archive targets ${fields[os_id]}-${fields[os_version]}, host is $host_os-$host_version"
[[ "${fields[arch]}" == "$host_arch" ]] || fail "archive architecture ${fields[arch]} does not match host $host_arch"
host_glibc="$(getconf GNU_LIBC_VERSION)" || fail "host glibc version unavailable"
host_glibc="${host_glibc#glibc }"
[[ "$host_glibc" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)*$ ]] || fail "unrecognized host glibc version"
printf '%s\n%s\n' "${fields[glibc_version]}" "$host_glibc" | sort -V -C || fail "archive needs glibc ${fields[glibc_version]}, host has $host_glibc"

echo "Validated Ytdarr $RELEASE_VERSION for $host_os-$host_version-$host_arch (glibc $host_glibc)"
