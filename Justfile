default:
    @just --list

app_version := "0.1.0"

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
    MIX_ENV=prod mix compile
    MIX_ENV=prod mix assets.deploy
    MIX_ENV=prod mix release --overwrite
    @echo "Release built at _build/prod/rel/ytdarr/releases/ytdarr-{{app_version}}/ytdarr.tar.gz"

clean-release: && release
    rm -rf _build/prod/rel/ytdarr
    @echo "Cleaned release directory"

gen-secret:
    mix phx.gen.secret

### Deploys
# deploy the tarball archive to a remote server
deploy host user="ytdarr" path="/opt/ytdarr":
    rsync -avP _build/prod/rel/ytdarr/releases/ytdarr-{{app_version}}/ytdarr.tar.gz {{user}}@{{host}}:{{path}}

build-and-deploy: release
    rsync -avP _build/prod/rel/ytdarr/releases/ytdarr-{{app_version}}/ytdarr.tar.gz user@remote-server:/opt/ytdarr

remote-restart host user="ytdarr" path="/opt/ytdarr":
    read -p "Password: " -s password
    ssh -tt {{user}}@{{host}} 'bash -l -s' << 'ENDSSH'
    sudo -S -i -u ytdarr << ENDSUDO
    $password
    cd {{path}}
    tar -xzf ytdarr.tar.gz
    systemctl restart ytdarr
    ENDSUDO
    ENDSSH
    