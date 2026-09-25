# Security policy

## Supported versions

Security fixes are developed on the current default branch and, when applicable, included in the next release. Use the latest published release; older releases are not routinely patched. No fixed response or release timeline is guaranteed.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/amargherio/ytdarr/security/advisories/new). If that option is unavailable, email [margherio.adam@gmail.com](mailto:margherio.adam@gmail.com) with the subject `Ytdarr security report`. Do not open a public issue or publish exploit details before coordinating disclosure.

Include the affected version or commit, deployment configuration, impact, reproduction steps, and any proof of concept. Remove real credentials, personal data, and media from the report. Reports involving dependencies are welcome when you can describe an impact on Ytdarr.

Maintainers will review the report, request details if needed, and coordinate remediation and disclosure with you. Please allow time for a fix before publishing; no response-time or bounty commitment is offered. Avoid accessing other people's systems or data and avoid disruptive testing.

## Deployment boundary

Ytdarr is intended for a trusted network. Its management routes are not protected merely by the presence of sign-in routes. Keep it on a LAN or VPN, or use an externally authenticated TLS reverse proxy; do not expose it directly to the public Internet. Protect API keys, signing secrets, SQLite data, backups, and media mounts. See the [deployment security guide](https://amargherio.github.io/ytdarr/docs/unreleased/operations/security/) for current configuration and limitations.
