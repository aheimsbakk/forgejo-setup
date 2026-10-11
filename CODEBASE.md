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
│   ├── forgejo-install-recipe.md    recipe component: parameters,
│   │                                decisions, change register
│   ├── forgejo-install-steps.md     reproduce procedure: commands in order
│   ├── forgejo-footguns.md          configuration traps: symptom and fix
│   ├── forgejo-ci-and-registry.md   runner, registry, job access, actions
│   ├── forgejo-operations.md        backup, restore, cleanup, cert trust
│   ├── forgejo-restore.md           restore procedure for a dump
│   ├── forgejo-operations-verification.md
│   │                                verification results per change set
│   ├── forgejo-backup-restore-verification.md
│   │                                backup, dump format, restore drill,
│   │                                encryption key measurements
│   ├── reports/                     dated investigation reports (history)
│   │   └── 2026-10-11-container-pipeline-build-push-use.md
│   │                                build -> push -> use test record
│   └── memory/                      agent session memory (INDEX.md, archive/)
├── forgejo/                         service configuration component
│   ├── docker-compose.yml           Forgejo app + Actions runner definitions
│   ├── .env.example                 per-target LAN address template
│   ├── gen-cert.sh                  certificate component: self-signed cert
│   ├── backup.sh                    backup component: dump + retention
│   ├── forgejo-backup.service       backup activation (oneshot unit)
│   ├── forgejo-backup.timer         backup schedule (daily, catch-up)
│   ├── cleanup.sh                   disk cleanup: unused images, containers
│   ├── forgejo-cleanup.service      cleanup activation (oneshot unit)
│   └── forgejo-cleanup.timer        cleanup schedule (daily, catch-up)
└── scripts/
    ├── bump-version.sh              version bumping (patch|minor|major)
    ├── validate-changelog.sh        changelog format check
    └── verify_codebase_sync.sh      CODEBASE.md path validation
```

## Component -> path mapping

| Blueprint component | Files |
|---|---|
| Recipe | `docs/forgejo-install-recipe.md`, `docs/forgejo-install-steps.md`, `docs/forgejo-footguns.md`, `docs/forgejo-ci-and-registry.md`, `docs/forgejo-operations.md`, `docs/forgejo-operations-verification.md`, `docs/forgejo-backup-restore-verification.md` |
| Service configuration | `forgejo/docker-compose.yml`, `forgejo/.env.example` |
| Certificate | `forgejo/gen-cert.sh`; exported copy `tmp/certs/forgejo.crt` (untracked) |
| Backup | `forgejo/backup.sh`, `forgejo/forgejo-backup.service`, `forgejo/forgejo-backup.timer`; restore procedure `docs/forgejo-restore.md` |
| Disk cleanup | `forgejo/cleanup.sh`, `forgejo/forgejo-cleanup.service`, `forgejo/forgejo-cleanup.timer`; grace record `/var/lib/forgejo-cleanup/unused-images.tsv` (on the target, untracked) |
| Parameter store | `.env` (untracked), `.env.example`, `forgejo/.env.example` |
| Discovery | recipe change 12–13 (packages + Avahi interface pin) and change 27 (name mapping for job containers) |
| CI runner | `forgejo/docker-compose.yml` (runner service), recipe changes 14–17, 20–23 and 27; job settings `/srv/forgejo-runner/config.yaml` (on the target, generated) |
| Container pipeline | `docs/reports/2026-10-11-container-pipeline-build-push-use.md` (test record); target trust file `/etc/docker/certs.d/forgejo.local/forgejo.crt` (recipe change 36); test repositories `agent/container-build-test` and `agent/container-use-test` (on the instance) |
| Investigation reports | `docs/reports/` — dated records, written once and not maintained afterwards |

## Entry points

- Reproduce procedure: `docs/forgejo-install-steps.md` — the main
  "script" of the project. `docs/forgejo-install-recipe.md` holds the
  parameters, the decisions and the change register it implements.
- Certificate creation: `/opt/forgejo/gen-cert.sh` on the target
  (source: `forgejo/gen-cert.sh`); run it before the first start and
  again before the certificate expires.
- Backup run: `/opt/forgejo/backup.sh` on the target (source:
  `forgejo/backup.sh`), activated by the systemd timer units.
- Restore run: `docs/forgejo-restore.md` — a file copy of `data/` and
  `repos/` into the instance layout. Forgejo 16.0.5 has no restore
  command and its dumps carry no restore script.
- Encryption key: `/opt/forgejo/secrets/secret_key` on the target,
  created by step 6c of the reproduce procedure and mounted read-only at
  `/etc/forgejo/secret_key` by the compose file. It has no source file in
  this repository on purpose.
- Disk cleanup run: `/opt/forgejo/cleanup.sh` on the target (source:
  `forgejo/cleanup.sh`), activated by the cleanup timer units.
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
  to `tmp/certs/` (gitignored) for client and CI pinning, and to
  `/etc/docker/certs.d/forgejo.local/forgejo.crt` so the Docker daemon
  trusts the instance's own registry (recipe change 36). The daemon picks
  these files by extension, so the `.crt` suffix is required.
- Cleanup state on the target: `/var/lib/forgejo-cleanup/` holds the
  unused-image grace record. It contains image ids and dates only, and
  is never copied into the repo.
- Encryption key state on the target: `/opt/forgejo/secrets/` (mode 750)
  and `secret_key` inside it (mode 640, `root:1000`). The value is
  generated on the target by `forgejo generate secret SECRET_KEY`, is
  referenced from the compose file only as
  `SECRET_KEY_URI=file:/etc/forgejo/secret_key`, and is never copied into
  the repo or into a dump.

## Language rationale

- Bash was chosen for `backup.sh` because it orchestrates existing
  remote commands (container exec, file moves, retention trimming)
  without adding a runtime dependency to the target. The registry
  exclusion is a `forgejo dump` flag (`--skip-package-data`), not an
  `app.ini` setting, so it lives in the script and cannot be set from the
  compose file.
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
- `cleanup.sh` is bash for the same reason as `backup.sh`: it drives
  existing docker CLI calls and adds no runtime to the target. The
  7-day grace is tracked in a small TSV file because Docker's `until=`
  filter matches image build dates and container creation times rather
  than last use, and the engine stores no last-used timestamp. The
  protected image list is read from the compose file at run time so a
  version bump cannot leave the stack unprotected.
