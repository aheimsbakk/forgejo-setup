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
| `IP` | target address, port bindings, `ROOT_URL` | `192.0.2.40` |
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
- Access: HTTP only, LAN only. No TLS, no domain, no public exposure.
- Published ports bind to the LAN IPv4 address, never `0.0.0.0`, because
  the host also has a public IPv6 address.
- Storage: bind mount `/srv/forgejo` on the host to `/data` in the
  container; built-in SQLite; no separate database server.
- All Forgejo configuration lives in `forgejo/docker-compose.yml` as
  `FORGEJO__*` environment variables. The LAN IP is the only variable,
  supplied by `/opt/forgejo/.env`.

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

Operator-side change (not on the target): the target address was added
to the operator's `known_hosts` by `StrictHostKeyChecking=accept-new`.

## Verification (first run)

- `curl http://<IP>/` returns HTTP 200, title
  `Forgejo: Beyond coding. We forge.`
- `ss -tlnp`: ports 80 and 2222 listen on `<IP>` only; no `[::]:80` or
  `[::]:2222` listener, so the public IPv6 address serves nothing.
- `ssh -p 2222 git@<IP>` reaches the Forgejo SSH server
  (`Permission denied (publickey)` — expected before any key is added).
- Container logs clean: SQLite initialized, web listening on 3000, SSH
  server on 2222, `AppURL(ROOT_URL)` matching the configured address.
- `getent ahostsv4 forgejo.local` returns the LAN address and
  `curl http://forgejo.local/` returns 200 (after changes 12–13).

## Footguns found

- The Forgejo image runs its own OpenSSH daemon on port 22 *inside* the
  container. With `START_SSH_SERVER=true` and `SSH_LISTEN_PORT=22`, the
  built-in SSH server collides with it and the container crashes
  (`bind: address already in use`). Fix: `SSH_LISTEN_PORT=2222` and
  publish `2222:2222`. The compose file in this repo already reflects that.
- `forgejo dump` refuses to run as root: use
  `docker exec -u 1000 -w /data forgejo forgejo dump`. Without `-w /data`
  it tries to write to `/` and gets `permission denied`.
- `forgejo dump` aborts with `Failed to include repositories` when
  `/data/git/repositories` does not exist yet (fresh install, no repos).
  Create it before dumping. The backup script does.
- The dump file is named `forgejo-dump-<timestamp>.zip`, not `dump-*`.
- `forgejo admin user create` requires `--email`; without it: `email is
  not set`. With no mail server, any placeholder address works.
- Avahi announces every interface by default, including Docker bridges.
  Without `allow-interfaces=<lan-if>`, `<hostname>.local` can resolve to
  `172.18.0.1` and connections fail. Pin it to the LAN interface.
- Runner v13 renamed the register flag: `--token`, not
  `--registration-token`. `register` also needs an existing config file:
  run `generate-config` first.
- The token from `POST /api/v1/admin/actions/runners` (new API) does not
  work with `forgejo-runner register`. Use the deprecated global token:
  `GET /api/v1/admin/runners/registration-token`.
- The runner image runs as uid 1000 and cannot read the root-owned
  Docker socket. The compose file sets `user: "0:0"` for it.
- Forgejo 16 has no file-creation API (`/files/...` is 404); push files
  with git.
- Failed `forgejo-runner register` attempts can leave runner entries
  registered on the server. Delete them via
  `DELETE /api/v1/admin/actions/runners/<id>` before retrying.

## CI runner (same box)

Operator decision: the Actions runner shares the machine with Forgejo.
Accepted risks and applied mitigations:

- The Docker socket is mounted into the runner container only. Job
  containers never receive it. Socket access is root-equivalent on the
  host; this is the main residual risk of the same-box design.
- No privileged jobs, no docker-in-docker (`privileged: false`).
  Container images in pipelines are built with buildah inside jobs.
- Job containers get `--memory=1g --cpus=1`; runner capacity is 2
  (machine has 2 vCPUs, 4 GB RAM, no swap — do not raise capacity).
- The runner publishes no ports; it only dials the instance.
- Recommended but NOT configured: disable or gate workflows from fork
  pull requests. Only accounts the admin creates can push, so the
  current exposure is trusted users only.
- Off-machine copies of `/srv/forgejo-backups` are strongly advised
  with CI on the box: a compromised job could reach the backups.

## Backup

- Daily at 03:30 UTC via `forgejo-backup.timer` (systemd,
  `Persistent=true` so a missed run fires at next boot).
- `forgejo dump` produces one zip per run containing the SQLite
  database, repositories, config and LFS data — a full restore point.
- Zips are moved out of the live data dir to `/srv/forgejo-backups`.
- Retention: exactly the 7 newest dumps; the script deletes the rest.
- Remote copy of `/srv/forgejo-backups` is planned by the operator and
  not part of this setup. Same-VM backups survive bad writes, not disk
  loss.

Restore from a dump:

```bash
unzip forgejo-dump-<timestamp>.zip -d /tmp/forgejo-restore
cd /tmp/forgejo-restore
# restore.sh recreates config, data and database; run it as the
# container user after stopping the app, then start it again.
docker-compose -f /opt/forgejo/docker-compose.yml stop forgejo
docker run --rm -u 1000 -v /srv/forgejo:/data -v /tmp/forgejo-restore:/restore \
  -w /restore codeberg.org/forgejo/forgejo:16.0.5 ./restore.sh
docker-compose -f /opt/forgejo/docker-compose.yml start forgejo
```

Note: the restore procedure is documented but not yet tested end-to-end.

## Reproduce (full recipe)

Ask the operator for the parameters first. The script prompts for the
password so it never lands in shell history or this repo.

```bash
# 0. Collect parameters. Real values live in the gitignored .env at the
# repo root (see .env.example); anything missing is prompted for.
[ -f .env ] && set -a && . ./.env && set +a
KEY=${KEY:-tmp/ssh/id_ed2219}          # path to the SSH private key
[ -n "${IP:-}" ]            || read -r -p "Target IP: " IP
[ -n "${ADMIN_USER:-}" ]    || read -r -p "Admin username: " ADMIN_USER
[ -n "${ADMIN_PASSWORD:-}" ]|| read -s -p "Admin password: " ADMIN_PASSWORD; echo
ADMIN_PASS=${ADMIN_PASSWORD:-$ADMIN_PASS}
SSH="ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new root@$IP"

# 0b. Check access (fails fast if the key is not authorized)
$SSH 'whoami'

# 1. Set hostname
$SSH 'hostnamectl set-hostname forgejo'

# 2. Make the hostname locally resolvable
$SSH 'printf "127.0.1.1\tforgejo\n" >> /etc/hosts'

# 3. Apply pending security upgrades
$SSH 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y'

# 4. Docker engine + compose from Debian
$SSH 'apt-get install -y docker.io docker-compose && systemctl enable --now docker'

# 5. Data directory owned by the container user (uid/gid 1000)
$SSH 'mkdir -p /srv/forgejo /opt/forgejo && chown 1000:1000 /srv/forgejo'

# 6. Deploy compose config; LAN_IP goes into .env (mode 600)
scp -i $KEY forgejo/docker-compose.yml root@$IP:/opt/forgejo/docker-compose.yml
printf 'LAN_IP=%s\n' "$IP" | $SSH 'cat > /opt/forgejo/.env && chmod 600 /opt/forgejo/.env'

# 7. Start
$SSH 'cd /opt/forgejo && docker-compose up -d'

# 8. Verify
curl -s -o /dev/null -w '%{http_code}\n' "http://$IP/"   # expect 200
$SSH 'ss -tlnp | grep -E ":80 |:2222 "'                  # expect only the LAN IP

# 9. Daily backup: script + systemd timer, keep 7 newest dumps
scp -i $KEY forgejo/backup.sh forgejo/forgejo-backup.service forgejo/forgejo-backup.timer root@$IP:/opt/forgejo/
$SSH 'chmod +x /opt/forgejo/backup.sh && cp /opt/forgejo/forgejo-backup.{service,timer} /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now forgejo-backup.timer'

# 10. Test one backup run
$SSH 'systemctl start forgejo-backup.service && ls -la /srv/forgejo-backups/'

# 11. Create the admin account (email is required; placeholder domain ok).
# Credentials travel on stdin so special characters cannot break the
# remote command line and never appear in the process list.
printf '%s\n%s\n' "$ADMIN_USER" "$ADMIN_PASS" |
  $SSH 'read -r U; read -r P; docker exec -u 1000 forgejo forgejo admin user create --username "$U" --password "$P" --email "$U@forgejo.lan" --admin'

# 12. mDNS LAN discovery: libnss-mdns resolves .local names,
# avahi-daemon announces <hostname>.local. Restrict avahi to the LAN
# interface, or it also advertises Docker bridge addresses.
$SSH 'apt-get install -y libnss-mdns avahi-daemon'
$SSH 'DEV=$(ip -o route get '"$IP"' | sed -n "s/.* dev \([^ ]*\).*/\1/p"); sed -i "/^\[server\]/a allow-interfaces=$DEV" /etc/avahi/avahi-daemon.conf && systemctl restart avahi-daemon'

# 13. Verify mDNS (run on the target; LAN clients need their own mDNS
# client, which desktop OSes have built in)
$SSH 'getent ahostsv4 forgejo.local'   # expect the LAN address

# 14. Actions runner: deploy service, create data dir
scp -i $KEY forgejo/docker-compose.yml root@$IP:/opt/forgejo/docker-compose.yml
$SSH 'mkdir -p /srv/forgejo-runner'

# 15. Register the runner (deprecated global token is the one that
# works with forgejo-runner register; pipe it via stdin)
TOKEN=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" "http://$IP/api/v1/admin/runners/registration-token" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
printf '%s' "$TOKEN" | $SSH 'read -r T; cd /opt/forgejo && docker-compose run --rm -T runner forgejo-runner generate-config > /srv/forgejo-runner/config.yaml && docker-compose run --rm -T runner forgejo-runner register --config /data/config.yaml --instance http://'"$IP"'/ --token "$T" --labels "docker:docker://debian:bookworm" --no-interactive'

# 16. Mitigations: capacity 2, per-job memory/CPU limits, no privileged
$SSH 'sed -i "s/^  capacity: 1$/  capacity: 2/; s/^  options:$/  options: \"--memory=1g --cpus=1\"/" /srv/forgejo-runner/config.yaml'
$SSH 'cd /opt/forgejo && docker-compose up -d runner'

# 17. Smoke test: push a workflow, expect a successful run
curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -X POST "http://$IP/api/v1/user/repos" -H "Content-Type: application/json" -d '{"name":"ci-smoke-test","private":true,"auto_init":true,"default_branch":"main"}' >/dev/null
git clone -q "http://$ADMIN_USER:$ADMIN_PASSWORD@$IP/$ADMIN_USER/ci-smoke-test.git" /tmp/ci-smoke
mkdir -p /tmp/ci-smoke/.forgejo/workflows
printf 'name: smoke\non: [push]\njobs:\n  hello:\n    runs-on: docker\n    steps:\n      - run: echo hello\n' > /tmp/ci-smoke/.forgejo/workflows/smoke.yml
git -C /tmp/ci-smoke add -A && git -C /tmp/ci-smoke -c user.email=ci@test -c user.name=ci commit -qm smoke && git -C /tmp/ci-smoke push -q origin main
sleep 20 && curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" "http://$IP/api/v1/repos/$ADMIN_USER/ci-smoke-test/actions/runs" | sed -n 's/.*"status":"\([^"]*\)".*/first run: \1/p'
# clean up afterwards: DELETE /api/v1/repos/$ADMIN_USER/ci-smoke-test
```

## Pending

- Remote copy of `/srv/forgejo-backups` (operator will set up).
- Test the restore procedure end-to-end on a scratch machine.
