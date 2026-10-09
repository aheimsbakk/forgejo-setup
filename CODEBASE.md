# Codebase

Concrete mapping from `BLUEPRINT.md` components to physical files.

## Structure

```
/work
├── README.md                        user documentation (product use)
├── CONTRIBUTING.md                  developer guide: scripts, conventions
├── BLUEPRINT.md                     architecture specification
├── CODEBASE.md                      this file
├── CHANGELOG.md                     version history (Keep a Changelog)
├── VERSION                          current version string
├── .env                             parameter store (gitignored, mode 600)
├── .env.example                     parameter store template
├── .gitignore                       ignores tmp/, .env
├── docs/
│   ├── forgejo-install-recipe.md    recipe component: change log + reproduce
│   ├── forgejo-operations.md        verification, footguns, runner, backup,
│   │                                client certificate trust
│   └── memory/                      agent session memory (INDEX.md, archive/)
├── forgejo/                         service configuration component
│   ├── docker-compose.yml           Forgejo app + Actions runner definitions
│   ├── .env.example                 per-target LAN address template
│   ├── gen-cert.sh                  certificate component: self-signed cert
│   ├── backup.sh                    backup component: dump + retention
│   ├── forgejo-backup.service       backup activation (oneshot unit)
│   └── forgejo-backup.timer         backup schedule (daily, catch-up)
└── scripts/
    ├── bump-version.sh              version bumping (patch|minor|major)
    ├── validate-changelog.sh        changelog format check
    └── verify_codebase_sync.sh      CODEBASE.md path validation
```

## Component -> path mapping

| Blueprint component | Files |
|---|---|
| Recipe | `docs/forgejo-install-recipe.md`, `docs/forgejo-operations.md` |
| Service configuration | `forgejo/docker-compose.yml`, `forgejo/.env.example` |
| Certificate | `forgejo/gen-cert.sh`; exported copy `tmp/certs/forgejo.crt` (untracked) |
| Backup | `forgejo/backup.sh`, `forgejo/forgejo-backup.service`, `forgejo/forgejo-backup.timer` |
| Parameter store | `.env` (untracked), `.env.example`, `forgejo/.env.example` |
| Discovery | recipe change 12–13 (packages + Avahi interface pin) |
| CI runner | `forgejo/docker-compose.yml` (runner service), recipe changes 14–17 and 20–23 |

## Entry points

- Reproduce procedure: "Reproduce (full recipe)" section of
  `docs/forgejo-install-recipe.md` — the main "script" of the project.
- Certificate creation: `/opt/forgejo/gen-cert.sh` on the target
  (source: `forgejo/gen-cert.sh`); run it before the first start and
  again before the certificate expires.
- Backup run: `/opt/forgejo/backup.sh` on the target (source:
  `forgejo/backup.sh`), activated by the systemd timer units.
- Version tooling: `scripts/bump-version.sh`,
  `scripts/validate-changelog.sh`, `scripts/verify_codebase_sync.sh`.

## Specs and conventions

- Target platform: Debian 13 (trixie), amd64, containerized workloads.
- Languages: shell (bash) for the backup and utility scripts; YAML for
  service definitions and systemd units; Markdown for all procedure and
  product documentation.
- Naming: kebab-case files; `forgejo-backup.*` units match their
  service name.
- Deployment convention: files under `forgejo/` are copied verbatim to
  `/opt/forgejo/` on the target; the compose file is the single source
  of application configuration.
- TLS state on the target: `/srv/forgejo-certs/forgejo.crt` and
  `forgejo.key`. The key never leaves the machine; the `.crt` is copied
  to `tmp/certs/` (gitignored) for client and CI pinning.

## Language rationale

- Bash was chosen for `backup.sh` because it orchestrates existing
  remote commands (container exec, file moves, retention trimming)
  without adding a runtime dependency to the target.
- `gen-cert.sh` is also bash and calls the `openssl` already shipped by
  Debian. Generating the certificate on the target keeps the private key
  off the operator's machine and off the network, and avoids adding a
  local CA tool to the deployment.
- Compose YAML (not a systemd-native container launch) keeps the two
  containers, their mounts and all application variables in one
  reviewable file, matching the "all configuration in the compose file"
  decision. TLS settings (`PROTOCOL`, `CERT_FILE`, `KEY_FILE`,
  `REDIRECT_OTHER_PORT`) follow the same rule, and the HTTP-to-HTTPS
  redirect uses Forgejo's own redirector instead of a second web server.
- systemd timer units were chosen over cron because the base image has
  no cron and timers provide boot catch-up (`Persistent=true`).
