# Forgejo Install Recipe

Goal: install Forgejo on a Debian 13 machine. Inputs: an SSH private key
with root access, and the machine's IP address. Every change made to the
target is recorded here so the install can be reproduced on a fresh
machine.

The first run used a real LAN address and a real admin username. Both are
anonymized in this document; supply your own values when reusing it.

## Parameters (ask the operator before starting)

Real values for the current deployment live in the repo-root `.env`
(gitignored, mode 600). Copy `.env.example` to start. The reproduce
script loads `.env` and only prompts for what is missing.

| Parameter | Used for | Example (documentation range) |
|-----------|----------|-------------------------------|
| `IP` | target address, port bindings, name pins | `192.0.2.40` |
| `ADMIN_USER` | Forgejo admin account | `admin` |
| `ADMIN_PASSWORD` | Forgejo admin password; never committed | (set in `.env`) |
| `KEY` | SSH private key path | `tmp/ssh/id_ed2219` |

## Baseline (observed before changes)

- Debian GNU/Linux 13 (trixie), kernel 6.12.x, x86-64, QEMU/KVM VM
- Provisioned by cloud-init; hostname unset; no swap
- Only `ssh` listening besides systemd stubs; no workload installed
- The machine may also have a public IPv6 address; the LAN-only binding
  below must not be relaxed.
- The SSH key was already authorized for `root` on the first target. On a
  fresh machine, install it first with `ssh-copy-id -i <key>.pub root@<ip>`.

## Decisions

- Forgejo runs in Docker, using the official image
  `codeberg.org/forgejo/forgejo`, pinned to a stable release (16.0.5).
- Docker engine and Compose come from Debian packages (`docker.io`,
  `docker-compose`); no third-party apt repos.
- Access: HTTPS only, LAN only. No domain, no public exposure. The
  certificate is self-signed (created on the target by `gen-cert.sh`) and
  pinned by every client: browsers, git clients, the runner and the job
  containers. Plain HTTP answers redirects to HTTPS and nothing else.
- Certificate lives in `/srv/forgejo-certs`, outside the data dir, so
  `forgejo dump` never contains the private key. Only the `.crt` leaves
  the machine.
- Published ports bind to the LAN IPv4 address, never `0.0.0.0`, because
  the host also has a public IPv6 address.
- Storage: bind mount `/srv/forgejo` on the host to `/data` in the
  container; built-in SQLite; no separate database server.
- All Forgejo configuration lives in `forgejo/docker-compose.yml` as
  `FORGEJO__*` environment variables. The LAN IP is the only variable,
  supplied by `/opt/forgejo/.env`.
- The hostname is `forgejo`, so the mDNS name is `forgejo.local`. That
  name appears in six places: the hostname, the certificate subject
  alternative names, the compose `extra_hosts` pin, the runner's
  `--add-host` option, the canonical `ROOT_URL`/`DOMAIN`, and the
  runner's registered instance URL. A different hostname means changing
  all six.
- The canonical web URL is `https://forgejo.local/`, not the address.
  Forgejo warns every client that arrives under a host other than
  `ROOT_URL`, and there is no host allow-list. The name is canonical
  because clients use it (mDNS on the LAN, pins inside containers);
  the address still serves content and git, browsers just see the
  warning there.
- Container disk use is bounded by a daily cleanup job: images unused
  for 7 days, stopped containers outside the compose stack, unused
  networks and the build cache. Volumes are never removed, and the
  images named by the compose file are never removed.
- Workflow actions are fetched from the instance itself
  (`DEFAULT_ACTIONS_URL=self`): a `uses:` reference without a host is
  cloned from this instance's repositories. The operator mirrors every
  action a workflow uses into a repository here (e.g. the `actions`
  organization, public so the runner can clone it anonymously). Full
  URLs in `uses:` bypass the setting.
- The default job image is `node:24-bookworm` (runner label
  `docker:docker://node:24-bookworm`): it has node and git, so
  mirrored JavaScript actions like `actions/checkout` work without
  per-workflow image choice. The line is the Active LTS at install
  time; Node 20 reached end-of-life 2026-04-30 and was replaced by
  change 34.
- Browsing shows 50 repositories per page (`EXPLORE_PAGING_NUM=50` in
  `[ui]`, `REPO_PAGING_NUM=50` in `[ui.user]`; defaults are 20 and 15).
  A repository listing is one indexed SQL query plus a total count, so
  a larger page only makes the HTML response bigger.
- The instance registry is part of the pipeline: a job builds an image,
  pushes it to `forgejo.local/<owner>/<repo>`, and a later job runs
  inside it. Two things follow. The Docker daemon on the host must trust
  the instance certificate for its own registry
  (`/etc/docker/certs.d/forgejo.local/forgejo.crt`, change 36), because the
  daemon performs every job-image pull. And pushing needs a user token
  with `write:package` kept in a repository secret: the Actions token
  authenticates against the registry but cannot write packages.

## Changes applied (first run, anonymized)

| # | Date | Change | Command (on target) | Verified by |
|---|------|--------|---------------------|-------------|
| 1 | 2026-10-09 | Static hostname set to `forgejo` | `hostnamectl set-hostname forgejo` | `hostnamectl status` shows `Static hostname: forgejo` |
| 2 | 2026-10-09 | Hostname made locally resolvable | `printf "127.0.1.1\tforgejo\n" >> /etc/hosts` | `getent hosts forgejo` returns `127.0.1.1` |
| 3 | 2026-10-09 | All pending stable-security upgrades applied (`liblzma5`, `xz-utils`, `libpng16-16t64`) | `apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y` | `apt list --upgradable` empty; `/var/run/reboot-required` absent |
| 4 | 2026-10-09 | Docker engine and Compose installed from Debian repos; service enabled at boot | `apt-get install -y docker.io docker-compose && systemctl enable --now docker` | `docker --version` 26.1.5; `docker-compose --version` 2.26.1; `systemctl is-enabled docker` = enabled |
| 5 | 2026-10-09 | Data dir created, owned by uid/gid 1000 (unused on host) | `mkdir -p /srv/forgejo /opt/forgejo && chown 1000:1000 /srv/forgejo` | `ls -ld /srv/forgejo` shows `1000 1000` |
| 6 | 2026-10-09 | Compose config deployed to `/opt/forgejo`; `.env` holds `LAN_IP`, mode 600 | copy `forgejo/docker-compose.yml`; write `/opt/forgejo/.env` | `ls -la /opt/forgejo` |
| 7 | 2026-10-09 | Forgejo 16.0.5 container started; restart policy `unless-stopped` | `cd /opt/forgejo && docker-compose up -d` | verification below |
| 8 | 2026-10-09 | Backup script deployed; backup dir created | copy `forgejo/backup.sh` to `/opt/forgejo/` (mode 755); dir `/srv/forgejo-backups` created by the script | manual run produced a dump zip |
| 9 | 2026-10-09 | Daily backup timer installed and enabled (03:30 UTC, catches up after downtime) | copy `forgejo-backup.service` + `forgejo-backup.timer` to `/etc/systemd/system/`; `systemctl daemon-reload && systemctl enable --now forgejo-backup.timer` | `systemctl list-timers` shows next run |
| 10 | 2026-10-09 | Retention tested: exactly the 7 newest dumps are kept | create 8 dummy dumps, run `/opt/forgejo/backup.sh` | 9 + 1 new files reduced to 7 newest |
| 11 | 2026-10-09 | Admin account `<ADMIN_USER>` created (email placeholder `<ADMIN_USER>@forgejo.lan`; password never recorded) | `docker exec -u 1000 forgejo forgejo admin user create --username <ADMIN_USER> --password '<pw>' --email <ADMIN_USER>@forgejo.lan --admin` | `forgejo admin user list` shows the admin; API basic-auth `/api/v1/user` returns `"is_admin":true` |
| 12 | 2026-10-09 | mDNS LAN discovery installed: `libnss-mdns` (resolves `.local`) + `avahi-daemon` (announces the machine); NSS `hosts` line gained `mdns4_minimal` via the package postinst | `apt-get install -y libnss-mdns avahi-daemon` | `grep ^hosts: /etc/nsswitch.conf` shows `mdns4_minimal`; `systemctl is-enabled avahi-daemon` = enabled |
| 13 | 2026-10-09 | Avahi restricted to the LAN interface (`allow-interfaces=enp1s0` in `/etc/avahi/avahi-daemon.conf`) | `sed -i "/^\[server\]/a allow-interfaces=enp1s0" /etc/avahi/avahi-daemon.conf && systemctl restart avahi-daemon` | `getent ahostsv4 forgejo.local` returns the LAN address; `curl http://forgejo.local/` returns 200 |
| 14 | 2026-10-09 | Forgejo Actions runner (same box, operator decision) added to the compose stack: `data.forgejo.org/forgejo/runner:13.1.0`, no published ports, Docker socket mounted for the runner daemon only | copy updated `forgejo/docker-compose.yml`; `mkdir /srv/forgejo-runner`; `docker-compose up -d runner` | `docker ps` shows `forgejo-runner` up; admin runners API shows it `idle` |
| 15 | 2026-10-09 | Runner registered with the instance (global registration token, label `docker:docker://debian:bookworm`) | `forgejo-runner generate-config > /srv/forgejo-runner/config.yaml`; `forgejo-runner register --config /data/config.yaml --instance http://<IP>/ --token '<reg-token>' --labels docker:docker://debian:bookworm --no-interactive` (token piped via stdin) | `POST /api/v1/admin/actions/runners` flow cleaned of stale entries; runner listed `idle` |
| 16 | 2026-10-09 | Runner mitigations in `/srv/forgejo-runner/config.yaml`: `capacity: 2`, job containers limited with `options: "--memory=1g --cpus=1"`, `privileged: false` (default, no dind) | `sed -i` on the two keys; container runs as root only for socket access | `grep -E "capacity|options:" config.yaml`; smoke test below |
| 17 | 2026-10-09 | CI smoke test: repo `ci-smoke-test` created, workflow pushed (`.forgejo/workflows/smoke.yml`, `runs-on: docker`), then repo deleted | git push over HTTP; `GET /api/v1/repos/<ADMIN_USER>/ci-smoke-test/actions/runs` | run 1 `status: success` |
| 18 | 2026-10-09 | Self-signed TLS certificate created on the target: `/srv/forgejo-certs/forgejo.{crt,key}`, SAN = LAN IP + `127.0.0.1` + `forgejo.local` + `localhost` + hostname, 1825 days; key mode 600 owned by uid/gid 1000 | copy `forgejo/gen-cert.sh` to `/opt/forgejo/`; `/opt/forgejo/gen-cert.sh` | `openssl x509 -in /srv/forgejo-certs/forgejo.crt -noout -enddate -ext subjectAltName` shows the SAN list and a 2031 expiry |
| 19 | 2026-10-09 | Forgejo switched to HTTPS: `PROTOCOL=https`, `CERT_FILE`/`KEY_FILE` point at the mounted cert dir, `ROOT_URL=https://<IP>/`, port 443 published, port 80 kept as a redirect (`REDIRECT_OTHER_PORT=true`, `PORT_TO_REDIRECT=80`) | copy updated `forgejo/docker-compose.yml`; `cd /opt/forgejo && docker-compose up -d` | `curl --cacert forgejo.crt https://<IP>/` returns 200; `curl http://<IP>/` returns 307 to the https URL; `ss -tlnp` shows 80, 443 and 2222 on `<IP>` only |
| 20 | 2026-10-09 | Runner trusts the instance certificate: `/srv/forgejo-certs/forgejo.crt` mounted read-only at `/etc/ssl/certs/forgejo-lan.crt` in the runner container; `insecure` stays `false` | copy updated `forgejo/docker-compose.yml`; `docker-compose up -d` | runner log `declared successfully`; admin runners API lists it `idle` |
| 21 | 2026-10-09 | Runner registration address switched from `http://` to `https://` in `/srv/forgejo-runner/.runner` (token and runner id kept) | `sed -i` on the `address` field; `docker restart forgejo-runner` | runners API shows `idle`; Forgejo's log shows the runner's `Declare` POST arriving on the https listener directly |
| 22 | 2026-10-09 | Job containers pinned to the same certificate: `GIT_SSL_CAINFO` added to runner `envs`, cert mounted read-only through `container.options`, and the path added to `valid_volumes` | `sed`/edit of `/srv/forgejo-runner/config.yaml`; `docker restart forgejo-runner` | smoke job logged `GIT_SSL_CAINFO=/etc/ssl/certs/forgejo-lan.crt` and `git ls-remote https://<IP>/…` succeeded |
| 23 | 2026-10-09 | CI smoke test over HTTPS: repo `ci-smoke-https` (public) with jobs `plain` and `ca-pin` (job image `data.forgejo.org/forgejo/runner:13.1.0`, which has git), then repo deleted | git clone/push over https with `GIT_SSL_CAINFO`; `GET /api/v1/repos/<ADMIN_USER>/ci-smoke-https/actions/runs` | run 5 `success`; jobs 7 and 8 `success` |
| 24 | 2026-10-09 | Daily disk cleanup script deployed (7-day grace for unused images, stack images protected from the compose file) | copy `forgejo/cleanup.sh` to `/opt/forgejo/` (mode 755) | first run exit 0, deleted nothing, wrote a grace record for the 2 unused job images |
| 25 | 2026-10-09 | Cleanup timer installed and enabled (04:15 UTC, catches up after downtime) | copy `forgejo-cleanup.service` + `forgejo-cleanup.timer` to `/etc/systemd/system/`; `systemctl daemon-reload && systemctl enable --now forgejo-cleanup.timer` | `systemctl list-timers` shows next run `Sat 2026-10-10 04:15 UTC` |
| 26 | 2026-10-09 | Removal paths proved with throwaway objects | `docker create --name cleanup-probe debian:bookworm true`; empty tar imported as `cleanup-probe:scratch`; grace date back-dated in `/var/lib/forgejo-cleanup/unused-images.tsv`; `systemctl start forgejo-cleanup.service` | both probes removed in one run; stack images, running containers, `forgejo_default` network and the two job images inside grace untouched |
| 27 | 2026-10-10 | Job containers can resolve `forgejo.local`: `--add-host=forgejo.local:<IP>` added to the runner's `container.options`, so the name lands in every job container's `/etc/hosts` | `sed -i` on the `options` key of `/srv/forgejo-runner/config.yaml`; `docker restart forgejo-runner` | CI run 15 `success`: `getent ahostsv4 forgejo.local` returned `<IP>` inside the job, `git ls-remote https://forgejo.local/...` succeeded, and a `node:20-bookworm` job read `/api/v1/version` by name; without the option the lookup also returns the Docker bridge addresses `172.18.0.1` and `172.17.0.1` |
| 28 | 2026-10-10 | Instance name pinned in the app and runner containers too: `extra_hosts: forgejo.local:<IP>` on both compose services | copy updated `forgejo/docker-compose.yml`; `cd /opt/forgejo && docker-compose up -d` | `docker exec forgejo getent ahostsv4 forgejo.local`, and the same in `forgejo-runner`, return the LAN address alone instead of three addresses; `curl --cacert forgejo.crt https://<IP>/` returns 200; runner log `declared successfully` |
| 29 | 2026-10-10 | Node trusts the instance in job containers with no per-workflow setup: `NODE_EXTRA_CA_CERTS` added to the runner's `container.envs` | `sed -i` on the `envs` block of `/srv/forgejo-runner/config.yaml`; `docker restart forgejo-runner` | CI run 16 `success`: a job logged `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/forgejo-lan.crt` without setting it in the workflow and fetched `https://forgejo.local/api/v1/version`; another job read `https://registry.npmjs.org/` with status 200, so public trust is intact; `git ls-remote` by name still ok |
| 30 | 2026-10-10 | Canonical URL switched from the address to the name: `DOMAIN=forgejo.local`, `ROOT_URL=https://forgejo.local/` in the compose file; the runner's registered address in `/srv/forgejo-runner/.runner` switched to `https://forgejo.local/` (token and runner id kept) | copy updated `forgejo/docker-compose.yml`; `cd /opt/forgejo && docker-compose up -d`; `sed -i` on the `address` field of `/srv/forgejo-runner/.runner`; `docker restart forgejo-runner` | `curl --cacert forgejo.crt https://forgejo.local/` returns 200 and the page embeds `appUrl: 'https://forgejo.local/'` (the mismatch banner is injected client-side by comparing the browser host with this value, so curl never shows it); `https://<IP>/` still returns 200; `curl http://<IP>/` now redirects to `https://forgejo.local/`; container log shows `AppURL(ROOT_URL): https://forgejo.local/` and `Redirecting: 0.0.0.0:80 to https://forgejo.local`; runner log `declared successfully`, runners API `idle` |
| 31 | 2026-10-10 | Admin account email placeholder changed from `<ADMIN_USER>@forgejo.lan` to `<ADMIN_USER>@forgejo.invalid`: `.local` is reserved for mDNS (RFC 6762) and must not appear in email addresses; `.invalid` is the RFC 6761 never-deliverable placeholder | `PATCH /api/v1/admin/users/<ADMIN_USER>` with `{"email":"<ADMIN_USER>@forgejo.invalid"}` | `forgejo admin user list` shows the new address |
| 32 | 2026-10-10 | Actions served by the instance: `DEFAULT_ACTIONS_URL=self` in the compose file; the runner container builds a merged CA bundle (public CAs + instance cert) at start and points `GIT_SSL_CAINFO` at it, so its git verifies the instance when downloading actions; the runner's action cache cleared | copy updated `forgejo/docker-compose.yml`; `cd /opt/forgejo && docker-compose up -d`; `rm -rf /srv/forgejo-runner/.cache` | `app.ini` shows `DEFAULT_ACTIONS_URL = self`; job log shows `git clone 'https://forgejo.local/actions/checkout' # ref=v4`; the cache clone's remote is `https://forgejo.local/actions/checkout`; smoke run `success` with `uses: actions/checkout@v4` against the mirrored `actions/checkout` repo (job image `node:20-bookworm`), repo deleted after |
| 33 | 2026-10-10 | Default job image switched from `debian:bookworm` to `node:20-bookworm`: the runner's registration label in `/srv/forgejo-runner/.runner` changed to `docker:docker://node:20-bookworm` (runner id and token kept) | `sed -i` on the label line of `/srv/forgejo-runner/.runner`; `docker restart forgejo-runner` | runner log `declared successfully`; smoke run 21 `success` with `runs-on: docker` and no `container.image`: log shows `Start image=node:20-bookworm`, `actions/checkout@v4` ran (git 2.39.5), `node --version` printed `v20.20.2`; repo deleted after |
| 34 | 2026-10-10 | Default job image moved to the Active LTS line: label `docker:docker://node:24-bookworm` — Node 20 reached end-of-life 2026-04-30, its image is frozen at 20.20.2 and gets no security fixes | `sed -i` on the label line of `/srv/forgejo-runner/.runner`; `docker restart forgejo-runner` | runner log `declared successfully`; smoke run 22 `success`: `Start image=node:24-bookworm`, `node --version` printed `v24.21.0`, `actions/checkout@v4` ran (git 2.39.5); repo deleted after; `node:20-bookworm` now unused and will be reclaimed by the daily cleanup after its grace period |
| 35 | 2026-10-10 | Browsing pagination raised to 50 repos per page: `FORGEJO__ui__EXPLORE_PAGING_NUM=50` and `FORGEJO__ui_0X2E_user__REPO_PAGING_NUM=50` in the compose file (`_0X2E_` is the environment-to-ini escape for the dot in the `[ui.user]` section) | copy updated `forgejo/docker-compose.yml`; `cd /opt/forgejo && docker-compose up -d` | `app.ini` shows `EXPLORE_PAGING_NUM = 50` in `[ui]` and `REPO_PAGING_NUM = 50` in `[ui.user]`; the explore page and the user profile page each render 50 repo cards |
| 36 | 2026-10-11 | Docker on the host trusts the instance's own registry: `/etc/docker/certs.d/forgejo.local/forgejo.crt`, a copy of `/srv/forgejo-certs/forgejo.crt`. The daemon pulls every job image, including images the pipeline pushed to the instance registry, and it reads its trust from this directory, not from the runner's `/etc/ssl/certs` mount. The file keeps the `forgejo.crt` name used everywhere else in this setup; the daemon selects these files by extension, so the `.crt` suffix is required and `ca.crt` is only Docker's documented example name | `mkdir -p /etc/docker/certs.d/forgejo.local && cp /srv/forgejo-certs/forgejo.crt /etc/docker/certs.d/forgejo.local/forgejo.crt` (mode 644; no daemon restart needed) | `docker pull forgejo.local/agent/container-build-test:<tag>` succeeds after the local copy is deleted; before the file the same command failed with `x509: certificate signed by unknown authority`, and the same copy renamed to `ca.pem` fails the same way; the file's SHA-256 certificate fingerprint matches `tmp/certs/forgejo.crt`; CI run 40 then pulled the image with `username=` (no credentials) and the job ran inside it |
| 37 | 2026-10-11 | Backup dumps leave out the container registry blobs: `/opt/forgejo/backup.sh` now runs `forgejo dump --skip-package-data`. The images are rebuildable by CI and were the second largest part of a dump. The package records stay in the database, so a restore lists versions whose files are absent; the package owner's cleanup rules (web UI only, no API route) clear those records and CI re-pushes the images | copy updated `forgejo/backup.sh` to `/opt/forgejo/` (mode 755); `/opt/forgejo/backup.sh` | dump log line `Skipping package data`; new dump 63,054,363 bytes against 85,498,046 for a full dump taken the same day; `grep -c data/packages` returns 0 on the new dump and 36 on the full one; `package`/`package_version`/`package_file`/`package_blob` rows still present in `forgejo-db.sql` (1/8/21/18) |
| 38 | 2026-10-11 | `SECRET_KEY` was empty in `app.ini`, so the instance had no stable key for the data Forgejo encrypts at rest. Set with `FORGEJO__security__SECRET_KEY_URI=file:/etc/forgejo/secret_key` and a read-only single-file mount of `/opt/forgejo/secrets/secret_key` (directory 750, file 640 `root:1000`, so the container's uid 1000 reads it). The value comes from `forgejo generate secret SECRET_KEY` and sits outside the data dir: it is in no dump and not in the tracked compose file. `SECRET_KEY` and `SECRET_KEY_URI` must not both have a value | copy updated `forgejo/docker-compose.yml`; create the key file (step 6c); `cd /opt/forgejo && docker-compose up -d forgejo` | `app.ini` shows `SECRET_KEY_URI = file:/etc/forgejo/secret_key` with `SECRET_KEY` still empty; `docker exec -u 1000 forgejo sh -c "wc -c < /etc/forgejo/secret_key"` returns 43; app log has no `[E]`/`[F]` lines; `/api/v1/version` 200, basic auth 200, token auth 200, `git ls-remote` over HTTPS returns `ad049345c139…`; the runner logged 3 `failed to fetch task` errors during the recreate and 0 afterwards |

Operator-side change (not on the target): the target address was added
to the operator's `known_hosts` by `StrictHostKeyChecking=accept-new`.

## Related documents

- `docs/forgejo-install-steps.md` — the commands, in order, that rebuild
  the instance on a fresh machine.
- `docs/forgejo-footguns.md` — the problems found, each with the symptom
  and the fix.
- `docs/forgejo-ci-and-registry.md` — the Actions runner, the container
  registry, access from job containers, and mirrored workflow actions.
- `docs/forgejo-operations.md` — backup and restore, disk cleanup, and how
  client devices and the Docker daemon trust the certificate.
- `docs/forgejo-restore.md` — how to bring an instance back from a dump.
- `docs/forgejo-operations-verification.md` — what each change set was
  checked against, with the observed output.
- `docs/forgejo-backup-restore-verification.md` — the same measurements
  for the backup script, the dump format, the restore drill and the
  global encryption key.
- `docs/reports/` — dated records of investigations, kept as history and
  not maintained afterwards. The container pipeline record is
  `docs/reports/2026-10-11-container-pipeline-build-push-use.md`.

## Reproduce

The commands, in order, are in `docs/forgejo-install-steps.md`. Ask the
operator for the parameters first; the script prompts for the password so
it never lands in shell history or this repo. The change table records the
first target's move from HTTP to HTTPS as changes 18-23; the compose file
in this repo is already HTTPS, so the steps reach that same state on a
fresh machine in one pass.
