# Contributing

Developer guide for this repo. User-facing product notes are in
`docs/forgejo-install-recipe.md`.

## Layout

- `docs/forgejo-install-recipe.md` — the recipe: every change applied to
  a target machine, in order, with commands and verification.
- `docs/forgejo-operations.md` — problems found, runner and backup setup,
  and how client devices trust the certificate.
- `docs/forgejo-operations-verification.md` — measured results for each
  change set: the commands run and what they returned.
- `forgejo/` — files deployed to a target machine under `/opt/forgejo/`.
- `.env` — real parameters (`IP`, `ADMIN_USER`, `ADMIN_PASSWORD`, `KEY`)
  for the current deployment. Gitignored, mode 600. Never commit it.
- `.env.example` — template for `.env` with placeholder values.

## Scripts and units

### Repo tooling (`scripts/`)

- `bump-version.sh [patch|minor|major]` — updates the `VERSION` file.
  Run once per finished task. Example: `scripts/bump-version.sh minor`.
- `validate-changelog.sh` — checks `CHANGELOG.md` has a section for the
  current `VERSION` with `why`/`model`/`tags` metadata. No arguments.
- `verify_codebase_sync.sh` — checks every repo path referenced in
  `CODEBASE.md` exists. Run after moving or renaming files.

### `forgejo/backup.sh`

Creates one Forgejo dump per run and keeps only the 7 newest in
`/srv/forgejo-backups`. Deploy to `/opt/forgejo/backup.sh` (mode 755)
on the target. No arguments. Run manually for testing:

```bash
ssh -i <key> root@<ip> 'systemctl start forgejo-backup.service'
```

Requires the `forgejo` container to be running.

### `forgejo/forgejo-backup.service` and `forgejo/forgejo-backup.timer`

systemd units that run `backup.sh` daily at 03:30 UTC and catch up after
downtime. Copy both to `/etc/systemd/system/` on the target, then:

```bash
systemctl daemon-reload && systemctl enable --now forgejo-backup.timer
```

### `forgejo/cleanup.sh`

Removes unused container images, stopped containers outside the compose
stack, unused networks and the build cache. An image is removed only
after 7 days with no container referencing it; that grace record lives
in `/var/lib/forgejo-cleanup/unused-images.tsv`. Volumes are never
touched, and the images named in the compose file are never removed.
Deploy to `/opt/forgejo/cleanup.sh` (mode 755). No arguments. Run
manually and read the log:

```bash
ssh -i <key> root@<ip> 'systemctl start forgejo-cleanup.service'
ssh -i <key> root@<ip> 'journalctl -u forgejo-cleanup.service -n 40'
```

The first run deletes nothing; it only starts the grace record.

### `forgejo/forgejo-cleanup.service` and `forgejo/forgejo-cleanup.timer`

systemd units that run `cleanup.sh` daily at 04:15 UTC — after the
03:30 backup — and catch up after downtime. Copy both to
`/etc/systemd/system/` on the target, then:

```bash
systemctl daemon-reload && systemctl enable --now forgejo-cleanup.timer
```

### `forgejo/gen-cert.sh`

Creates the self-signed TLS certificate Forgejo serves:
`/srv/forgejo-certs/forgejo.crt` and `forgejo.key`, valid 5 years, with
the LAN address, `127.0.0.1`, `forgejo.local`, `localhost` and the
hostname in the subject alternative names. No arguments; it reads
`LAN_IP` from `/opt/forgejo/.env`, so deploy the compose env file first
and run it before the first start. Re-running keeps an existing
certificate that still covers the current address.

```bash
scp -i <key> forgejo/gen-cert.sh root@<ip>:/opt/forgejo/
ssh -i <key> root@<ip> 'chmod 755 /opt/forgejo/gen-cert.sh && /opt/forgejo/gen-cert.sh'
scp -i <key> root@<ip>:/srv/forgejo-certs/forgejo.crt tmp/certs/forgejo.crt
```

The script prints the SHA-256 fingerprint; compare it when checking a
client pin. The key stays on the target — copy only the `.crt`.

### `forgejo/docker-compose.yml` and `forgejo/.env.example`

Forgejo service definition; all Forgejo config is in the compose file as
`FORGEJO__*` variables, including the HTTPS settings (`PROTOCOL`,
`CERT_FILE`, `KEY_FILE`, `REDIRECT_OTHER_PORT`). It also defines the
Actions runner service (socket mount for the runner daemon only,
`user: "0:0"`, no published ports, instance certificate mounted into
`/etc/ssl/certs`). Both services pin `forgejo.local` to `LAN_IP` with
`extra_hosts`, because the host resolver otherwise answers the name with
every address on the machine. Copy the compose file to `/opt/forgejo/`
and create `/opt/forgejo/.env` from `.env.example` (set `LAN_IP`, mode
600). Runner registration and mitigation steps are in the recipe.

## Conventions

- Log every change applied to a target machine in the recipe's
  "Changes applied" table, same day.
- Pin container image versions; never use `latest`.
- Never commit SSH keys, `.env` files, or credentials. `tmp/` and `.env`
  are gitignored.
- Never copy a target's `forgejo.key` into the repo or into a backup;
  only the `.crt` is shared.
