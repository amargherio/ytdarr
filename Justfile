default:
    @just --list

app_version := trim(read("VERSION"))
release_archive := "_build/prod/ytdarr-" + app_version + ".tar.gz"

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
# build prod release tarball
release:
    MIX_ENV=prod mix deps.get --only prod
    MIX_ENV=prod mix compile --warnings-as-errors
    MIX_ENV=prod mix assets.deploy
    MIX_ENV=prod mix release --overwrite
    cd _build/prod && sha256sum ytdarr-{{app_version}}.tar.gz > ytdarr-{{app_version}}.tar.gz.sha256
    @echo "Release built at {{release_archive}}"

clean-release:
    rm -rf _build/prod/rel/ytdarr _build/prod/ytdarr-{{app_version}}.tar.gz _build/prod/ytdarr-{{app_version}}.tar.gz.sha256
    just release

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

# Build and atomically deploy a native release with backup, migration, and health verification.
deploy host user: release
    #!/usr/bin/env bash
    set -euo pipefail
    staging="/tmp/ytdarr-deploy-{{app_version}}"
    ssh "{{user}}@{{host}}" "mkdir -p '$staging'"
    rsync -avP "{{release_archive}}" "{{release_archive}}.sha256" deploy/scripts/activate-release.sh "{{user}}@{{host}}:$staging/"
    ssh "{{user}}@{{host}}" "sudo --non-interactive bash '$staging/activate-release.sh' '$staging/ytdarr-{{app_version}}.tar.gz' '$staging/ytdarr-{{app_version}}.tar.gz.sha256' '{{app_version}}'"
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
    