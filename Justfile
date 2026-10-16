default:
    @just --list

app_version := trim(read("VERSION"))

# Install deps and setup the DB
setup:
    mix setup

# Start phx server
server:
    mix phx.server

# Start interactive console with full app loaded
console:
    iex -S mix

fmt:
    mix format

precommit:
    mix precommit

## Testing
test *args:
    mix test {{args}}

test-file file:
    mix test {{file}}

test-failed:
    mix test --failed

## release
# Build a native archive for this host's exact distribution and version.
release:
    bash deploy/scripts/build-native.sh host

# Build one supported distribution in its matching container environment.
release-target target:
    bash deploy/scripts/build-native.sh "{{target}}"

# Build the complete supported native distribution matrix.
release-all:
    bash deploy/scripts/build-native.sh all

gen-secret:
    mix phx.gen.secret

### Deploys
# Generate an ignored runtime environment file.
generate-env output="deploy/.env" host="localhost" runtime="container" port="4000":
    deploy/scripts/generate-env.sh --output {{output}} --host {{host}} --runtime {{runtime}} --port {{port}}

# Provision a native systemd host. The SSH account needs passwordless sudo for these commands.
install-host host user env_file="deploy/.env":
    #!/usr/bin/env bash
    set -euo pipefail
    staging="/tmp/ytdarr-provision-{{app_version}}"
    ssh "{{user}}@{{host}}" "mkdir -p '$staging'"
    rsync -av deploy/ytdarr.service deploy/scripts/provision-host.sh "{{env_file}}" "{{user}}@{{host}}:$staging/"
    ssh "{{user}}@{{host}}" "sudo --non-interactive bash '$staging/provision-host.sh' '$staging/ytdarr.service' '$staging/$(basename "{{env_file}}")'"
    ssh "{{user}}@{{host}}" "rm -rf '$staging'"

# Deploy an existing, explicitly selected native archive; never builds implicitly.
deploy host user archive:
    #!/usr/bin/env bash
    set -euo pipefail
    archive="{{archive}}"
    [[ -f "$archive" && -f "$archive.sha256" ]] || { echo "Archive and checksum must already exist: $archive" >&2; exit 1; }
    archive_name="$(basename "$archive")"
    [[ "$archive_name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*\.tar\.gz$ ]] || { echo "Unsafe archive filename: $archive_name" >&2; exit 1; }
    staging="$(ssh "{{user}}@{{host}}" 'mktemp -d /tmp/ytdarr-deploy.XXXXXXXX')"
    rsync -avP "$archive" "$archive.sha256" deploy/scripts/activate-release.sh deploy/scripts/validate-native.sh "{{user}}@{{host}}:$staging/"
    ssh "{{user}}@{{host}}" "sudo --non-interactive bash '$staging/activate-release.sh' '$staging/$archive_name' '$staging/$archive_name.sha256' '{{app_version}}'"
    ssh "{{user}}@{{host}}" "rm -rf '$staging'"

# Restore a retained native release and its pre-upgrade database backup.
rollback host version user:
    #!/usr/bin/env bash
    set -euo pipefail
    staging="/tmp/ytdarr-rollback-{{version}}"
    ssh "{{user}}@{{host}}" "mkdir -p '$staging'"
    rsync -av deploy/scripts/rollback-release.sh "{{user}}@{{host}}:$staging/"
    ssh "{{user}}@{{host}}" "sudo --non-interactive bash '$staging/rollback-release.sh' '{{version}}'"
    ssh "{{user}}@{{host}}" "rm -rf '$staging'"

container-build:
    podman build --platform linux/amd64 -f deploy/Dockerfile --build-arg VERSION={{app_version}} -t localhost/ytdarr:{{app_version}} .
    