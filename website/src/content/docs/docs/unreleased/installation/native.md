---
title: Native systemd installation
description: Build and deploy the linux/amd64 Ytdarr OTP release to a provisioned systemd host.
sidebar:
  order: 3
---

The native target ships for **Linux amd64**. It requires a build host and a target host with `systemd`, `curl`, `sqlite3`, `yt-dlp`, and `ffmpeg`; the SSH deploy account needs key authentication and passwordless `sudo` for the supplied helpers. In released documentation, use the exact source tag shown in that page's version notice rather than cloning `main`.

> **Secret-file warning:** the native helpers do not preserve the generator's safe `0600` permissions. Provisioning installs the environment file as `0644` and makes its directory world-readable; every activation repeats that directory widening. Prefer the container route on a shared or untrusted multi-user machine.

## Provision and deploy

1. Build a release archive and generate a native environment file:

   ```sh
   just release
   just generate-env deploy/native.env ytdarr.example.com native 4000
   ```

2. Provision the target once:

   ```sh
   just install-host server.example.com deployer deploy/native.env
   ```

3. **Immediately after provisioning**, repair and verify the target environment-file permissions before any deployment:

   ```sh
   ssh deployer@server.example.com \
     "sudo chown root:ytdarr /etc/ytdarr/ytdarr.env && sudo chmod 0640 /etc/ytdarr/ytdarr.env && stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env"
   ```

   The expected output is `640 root:ytdarr`. If helper overrides change `YTDARR_ENV_FILE` or `YTDARR_APP_GROUP`, substitute those configured values.

4. Deploy, then repair the file **again immediately after every deployment attempt**, including a failed activation. This form preserves the deployment exit status while ensuring the repair runs:

   ```sh
   set +e
   just deploy server.example.com deployer
   deploy_status=$?
   set -e
   ssh deployer@server.example.com \
     "sudo chown root:ytdarr /etc/ytdarr/ytdarr.env && sudo chmod 0640 /etc/ytdarr/ytdarr.env && stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env"
   test "$deploy_status" -eq 0
   ```

   Repeat this repair sequence after every retry. The helpers expose the file during provisioning and activation, so do not defer it until the next maintenance window.

The archive and checksum are made under `_build/prod`. Deployment verifies the checksum, stops the service, backs up SQLite, migrates, switches `/opt/ytdarr/current`, starts the service, and waits for readiness. Versioned releases live under `/opt/ytdarr/versions`; persistent state and backups default to `/var/lib/ytdarr`.

## Verify and recover

Check `curl --fail http://server.example.com:4000/health/ready` through the host's intended trusted-network route and inspect `journalctl -u ytdarr`. The deployment scripts automatically restore the preceding release and database when migration or readiness fails. To explicitly restore a retained release and its pre-upgrade database, use:

```sh
just rollback server.example.com RETAINED_VERSION deployer
```

Native activation accepts prerelease suffixes; that does not make them stable releases. Review [backup and upgrades](../../operations/backup-and-upgrades/) before an update.