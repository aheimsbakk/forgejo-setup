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

Operator-side change (not on the target): the target address was added
to the operator's `known_hosts` by `StrictHostKeyChecking=accept-new`.

## Related documents

- `docs/forgejo-operations.md` — what was verified, the problems found,
  the CI runner and backup setup, and how client devices trust the
  certificate.

## Reproduce (full recipe)

Ask the operator for the parameters first. The script prompts for the
password so it never lands in shell history or this repo.

The change table records the first target's move from HTTP to HTTPS as
changes 18–23. The compose file in this repo is already HTTPS, so the
steps below reach that same state on a fresh machine in one pass.

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

# 6b. Certificate, before the first start: the compose file points at
# /srv/forgejo-certs and Forgejo will not start without it. The script
# reads LAN_IP from the .env written above and is safe to re-run.
scp -i $KEY forgejo/gen-cert.sh root@$IP:/opt/forgejo/
$SSH 'chmod 755 /opt/forgejo/gen-cert.sh && /opt/forgejo/gen-cert.sh'

# 7. Start
$SSH 'cd /opt/forgejo && docker-compose up -d'

# 8. Verify
$SSH 'ss -tlnp | grep -E ":80 |:443 |:2222 "'   # expect only the LAN IP

# 8b. Take the public certificate to the operator machine so clients and
# CI can pin it. The private key never leaves the target.
mkdir -p tmp/certs && scp -i $KEY root@$IP:/srv/forgejo-certs/forgejo.crt tmp/certs/forgejo.crt
CA=$PWD/tmp/certs/forgejo.crt
curl -s --cacert "$CA" -o /dev/null -w 'https: %{http_code}\n' "https://$IP/"          # expect 200
curl -s -o /dev/null -w 'http: %{http_code} -> %{redirect_url}\n' "http://$IP/"        # expect 307

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
# works with forgejo-runner register; pipe it via stdin). The instance
# URL is https: the stored address is what the runner dials later.
TOKEN=$(curl -s --cacert "$CA" -u "$ADMIN_USER:$ADMIN_PASSWORD" "https://$IP/api/v1/admin/runners/registration-token" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
printf '%s' "$TOKEN" | $SSH 'read -r T; cd /opt/forgejo && docker-compose run --rm -T runner forgejo-runner generate-config > /srv/forgejo-runner/config.yaml && docker-compose run --rm -T runner forgejo-runner register --config /data/config.yaml --instance https://'"$IP"'/ --token "$T" --labels "docker:docker://debian:bookworm" --no-interactive'

# 16. Runner config: capacity 2, per-job memory/CPU limits plus the
# certificate mounted into job containers, GIT_SSL_CAINFO for those
# containers, and the mount allow-list (valid_volumes: [] silently drops
# the mount).
$SSH 'sed -i "s|^  capacity: 1$|  capacity: 2|; s|^  options:$|  options: \"--memory=1g --cpus=1 --volume /srv/forgejo-certs/forgejo.crt:/etc/ssl/certs/forgejo-lan.crt:ro\"|; s|^  envs:$|  envs:\n    GIT_SSL_CAINFO: /etc/ssl/certs/forgejo-lan.crt|; s|^  valid_volumes: \[\]$|  valid_volumes:\n    - /srv/forgejo-certs/forgejo.crt|" /srv/forgejo-runner/config.yaml'
$SSH 'cd /opt/forgejo && docker-compose up -d runner'

# 17. Smoke test over HTTPS: push a workflow, expect a successful run.
# The job image debian:bookworm has no git, so the pin check runs in the
# runner image, which is already on the machine and has git.
# GIT_SSL_CAINFO must be an absolute path; a relative one breaks push.
curl -s --cacert "$CA" -u "$ADMIN_USER:$ADMIN_PASSWORD" -X POST "https://$IP/api/v1/user/repos" -H "Content-Type: application/json" -d '{"name":"ci-smoke-test","private":false,"auto_init":true,"default_branch":"main"}' >/dev/null
GIT_SSL_CAINFO="$CA" git clone -q "https://$ADMIN_USER:$ADMIN_PASSWORD@$IP/$ADMIN_USER/ci-smoke-test.git" /tmp/ci-smoke
mkdir -p /tmp/ci-smoke/.forgejo/workflows
cat > /tmp/ci-smoke/.forgejo/workflows/smoke.yml <<YML
name: smoke
on: [push]
jobs:
  plain:
    runs-on: docker
    steps:
      - run: echo hello
  ca-pin:
    runs-on: docker
    container:
      image: data.forgejo.org/forgejo/runner:13.1.0
    steps:
      - run: |
          test -f /etc/ssl/certs/forgejo-lan.crt
          git --version
          git ls-remote https://$IP/$ADMIN_USER/ci-smoke-test.git >/dev/null
          echo "git over https with pinned CA ok"
YML
git -C /tmp/ci-smoke add -A && git -C /tmp/ci-smoke -c user.email=ci@test -c user.name=ci commit -qm smoke && GIT_SSL_CAINFO="$CA" git -C /tmp/ci-smoke push -q origin main
sleep 30 && curl -s --cacert "$CA" -u "$ADMIN_USER:$ADMIN_PASSWORD" "https://$IP/api/v1/repos/$ADMIN_USER/ci-smoke-test/actions/runs" | sed -n 's/.*"status":"\([^"]*\)".*/first run: \1/p'
# clean up afterwards: DELETE /api/v1/repos/$ADMIN_USER/ci-smoke-test
```

