# Contributing

Developer guide for this repo. User-facing product notes are in
`docs/forgejo-install-recipe.md`.

## Layout

- `docs/forgejo-install-recipe.md` — the recipe: every change applied to
  a target machine, in order, with commands and verification.
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

### `forgejo/docker-compose.yml` and `forgejo/.env.example`

Forgejo service definition; all Forgejo config is in the compose file as
`FORGEJO__*` variables. It also defines the Actions runner service
(socket mount for the runner daemon only, `user: "0:0"`, no published
ports). Copy the compose file to `/opt/forgejo/` and create
`/opt/forgejo/.env` from `.env.example` (set `LAN_IP`, mode 600).
Runner registration and mitigation steps are in the recipe.

## Conventions

- Log every change applied to a target machine in the recipe's
  "Changes applied" table, same day.
- Pin container image versions; never use `latest`.
- Never commit SSH keys, `.env` files, or credentials. `tmp/` and `.env`
  are gitignored.
