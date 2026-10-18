# Contributing

Developer guide for this repo. User-facing product notes are in
`README.md`.

## Layout

- `docs/forgejo-install-recipe.md` — the recipe: parameters, decisions,
  and every change applied to a target machine, in order.
- `docs/forgejo-install-steps.md` — the reproduce procedure: the commands,
  in order, that rebuild the instance on a fresh machine.
- `docs/forgejo-footguns.md` — problems found, each with the symptom and
  the fix.
- `docs/forgejo-ci-and-registry.md` — the Actions runner, the container
  registry, access from job containers, mirrored workflow actions.
- `docs/forgejo-operations.md` — backup and restore, disk cleanup, and how
  client devices and the engine trust the certificate.
- `docs/forgejo-operations-verification.md` — measured results for each
  change set: the commands run and what they returned.
- `docs/forgejo-backup-restore-verification.md` — the same for the backup
  script, the dump format, the restore drill and the global encryption
  key.
- `docs/forgejo-podman-migration-verification.md` — measurements for the
  Docker-to-podman migration and the post-teardown checks.
- `tasks/` — task records. Some are proposals; some record completed
  target work. They are not part of the state deployed to a target
  machine unless the reproduce procedure copies them.
- `templates/` — reusable files copied into new repositories, not deployed
  to the Forgejo target machine.
- `forgejo/` — files deployed to a target machine under `/opt/forgejo/`.
- `.env` — real parameters (`IP`, `LAN_RESOLVER`, `ADMIN_USER`,
  `ADMIN_PASSWORD`, `KEY`) for the current deployment. Gitignored, mode
  600. Never commit it.
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
`/srv/forgejo-backups`. The dump leaves out container registry blobs
(`forgejo dump --skip-package-data`): CI rebuilds the images and they
dominate dump size. Deploy to `/opt/forgejo/backup.sh` (mode 755) on the
target. No arguments. Run manually for testing:

```bash
ssh -i <key> root@<ip> 'systemctl start forgejo-backup.service'
```

Requires the `forgejo-forgejo` container to be running. To check what a dump
holds, grep the zip entry names — they are stored uncompressed, and the
target has no unzip:

```bash
ssh -i <key> root@<ip> 'grep -c data/packages $(ls -1t /srv/forgejo-backups/forgejo-dump-*.zip | head -1)'
```

Expect `0`. The command exits non-zero when it finds nothing, which is
the pass case. A non-zero count means the flag was dropped.

### `forgejo/forgejo-backup.service` and `forgejo/forgejo-backup.timer`

systemd units that run `backup.sh` daily at 03:30 UTC and catch up after
downtime. Copy both to `/etc/systemd/system/` on the target, then:

```bash
systemctl daemon-reload && systemctl enable --now forgejo-backup.timer
```

### `forgejo/cleanup.sh`

Removes unused container images, stopped containers outside the podman
kube stack, and unused networks. An image is removed only after 7 days
with no container referencing it; that grace record lives in
`/var/lib/forgejo-cleanup/unused-images.tsv`. Volumes are never touched,
and the images named in the kube YAML files are never removed.
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
`LAN_IP` from `/opt/forgejo/.env`, so deploy the target env file first
and run it before the first start. Re-running keeps an existing
certificate that still covers the current address.

```bash
scp -i <key> forgejo/gen-cert.sh root@<ip>:/opt/forgejo/
ssh -i <key> root@<ip> 'chmod 755 /opt/forgejo/gen-cert.sh && /opt/forgejo/gen-cert.sh'
scp -i <key> root@<ip>:/srv/forgejo-certs/forgejo.crt tmp/certs/forgejo.crt
```

The script prints the SHA-256 fingerprint; compare it when checking a
client pin. The key stays on the target — copy only the `.crt`.

### `forgejo/kube/`, `forgejo/containers.conf`, and `forgejo/.env.example`

`forgejo/kube/forgejo.yaml` and `forgejo/kube/runner.yaml` are the pod
definitions. All Forgejo config is in the app pod as `FORGEJO__*`
variables, including the HTTPS settings (`PROTOCOL`, `CERT_FILE`,
`KEY_FILE`, `REDIRECT_OTHER_PORT`). The runner pod mounts the podman
socket for the runner daemon only, runs as root for that socket access,
publishes no ports, and mounts the instance certificate into
`/etc/ssl/certs`. Both pods pin `forgejo.local` with `hostAliases`,
because the host resolver otherwise answers the name with every address
on the machine.

`forgejo/containers.conf` goes to `/etc/containers/containers.conf`. It
sets `userns="auto:size=65536"` for runner-created job containers and a
LAN resolver for container DNS. The reproduce procedure replaces the
placeholder resolver address.

Copy the kube files to `/opt/forgejo/kube/`, replace the placeholder LAN
address, and create `/opt/forgejo/.env` from `.env.example` (set
`LAN_IP`, mode 600). Start the pods with:

```bash
systemctl start podman-kube@opt-forgejo-kube-forgejo.yaml.service
systemctl start podman-kube@opt-forgejo-kube-runner.yaml.service
systemctl enable podman-kube@opt-forgejo-kube-forgejo.yaml.service
systemctl enable podman-kube@opt-forgejo-kube-runner.yaml.service
```

Runner registration and mitigation steps are in the recipe.

## Conventions

- Log every change applied to a target machine in the recipe's
  "Changes applied" table, same day.
- Pin container image versions; never use `latest`.
- Never commit SSH keys, `.env` files, or credentials. `tmp/` and `.env`
  are gitignored.
- Never copy a target's `forgejo.key` into the repo or into a backup;
  only the `.crt` is shared.
