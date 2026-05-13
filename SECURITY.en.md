# Security Policy

Language: [中文](SECURITY.md) | [English](SECURITY.en.md)

## Supported Versions

Security fixes are handled on the latest released version of VancePay.

## Reporting a Vulnerability

Please report security issues privately through GitHub Security Advisories if the project is hosted on GitHub, or contact the maintainer through the repository owner profile.

Do not open a public issue with exploitable details, tokens, private server configuration, or player data.

When reporting, include:

- affected version or commit
- resource configuration relevant to the issue
- clear reproduction steps
- expected impact

## Secrets

Keep KOOK credentials, VanceFiveMLog API keys, database credentials, and server-specific convars in `server.cfg` or your deployment secret store. Do not commit them to this repository.
