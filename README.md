# Forgejo LAN Install

A tested recipe and deployment files for running [Forgejo](https://forgejo.org),
a self-hosted git forge, in Docker on a Debian 13 machine. The instance
serves HTTPS on the local network only.

What it gives you:

- Forgejo 16.0.5 (pinned) in Docker, started on boot
- Web UI on port 443 over HTTPS, port 80 redirects to it, git-over-SSH
  on port 2222 — all bound to the LAN address only, never to the public
  interfaces of the machine
- A self-signed certificate created on the machine; every device that
  connects trusts it once
- A daily full backup (database, repositories, config) that keeps the
  7 newest restore points
- A daily disk cleanup that removes container images and stopped
  containers unused for a week
- A step-by-step install recipe you can rerun on any fresh Debian 13
  machine with nothing but an SSH key and an IP

## Quick start

You need: a Debian 13 machine on your network, and SSH private key access
as root on it.

1. Clone this repo on the machine you run SSH from.
2. Open `docs/forgejo-install-recipe.md` and follow the
   "Reproduce (full recipe)" section top to bottom. It asks for the
   target IP, an admin username, and an admin password.
3. Import the certificate (`tmp/certs/forgejo.crt`) on the device you
   browse from — the "Client trust" section of
   `docs/forgejo-operations.md` lists the command for each OS.
4. Open `https://forgejo.local/` in a browser and sign in with the
   admin account you chose. That name is the canonical URL; opening
   the address `https://<target-ip>/` shows a mismatch warning.

## Using the instance

- Web UI: `https://forgejo.local/` from any device on the LAN (mDNS
  discovery). This is the canonical URL. The address
  `https://<target-ip>/` also serves, but browsers show a mismatch
  warning there. Both names are in the certificate.
- Clone over HTTPS: `https://forgejo.local/<owner>/<repo>.git` (the
  address works too)
- Clone over SSH: `ssh://git@forgejo.local:2222/<owner>/<repo>.git`
  (first use asks you to accept the server host key)
- Old `http://` clone URLs keep working: the server answers with a
  redirect to the same address over HTTPS.
- New accounts: registration is off. The admin creates accounts under
  Site Administration, or with:
  ```bash
  ssh -i <key> root@<target-ip> \
    'docker exec -u 1000 forgejo forgejo admin user create --username <name> --password <pw> --email <name>@forgejo.invalid'
  ```

## CI/CD

Forgejo Actions is enabled. A runner shares the machine with the
instance: workflows with `runs-on: docker` run in Debian bookworm
containers, two jobs at a time, each limited to 1 CPU and 1 GB RAM.
Build container images with buildah inside jobs; docker-in-docker and
privileged jobs are not available.

- The instance certificate is already inside job containers at
  `/etc/ssl/certs/forgejo-lan.crt`, and `GIT_SSL_CAINFO` points there,
  so `git` over HTTPS works in jobs without extra setup.
- Inside workflows both `https://<target-ip>/` and
  `https://forgejo.local/` work: the runner writes the name into every
  job container's hosts file. Most command-line tools already trust the
  certificate from that directory, and `NODE_EXTRA_CA_CERTS` is set for
  every job; Python `requests` still needs its own variable — see
  "Access from job containers" in `docs/forgejo-operations.md`.
- The default job image (`debian:bookworm`) has no git. Pick an image
  that has it when a job needs git.
- Actions published on other forges are downloaded by the runner, and
  jobs can pull images and install packages, so the machine needs
  outbound internet access.

Recommendation: if you ever allow pull requests from forks, disable or
gate fork PR workflows in each repository's Actions settings. By default
they would run the contributor's code on your machine.

## Backups

- A full backup runs daily at 03:30 UTC. Files land in
  `/srv/forgejo-backups/` on the instance machine; the 7 newest are kept.
- Run one by hand:
  ```bash
  ssh -i <key> root@<target-ip> 'systemctl start forgejo-backup.service'
  ```
- Backups stay on the same machine. Copy them off-site yourself if you
  need protection against disk loss.
- The TLS private key is not part of a backup; it lives in
  `/srv/forgejo-certs`. A restore needs a new certificate and new pins.
- Restore steps: see the "Backup" section of
  `docs/forgejo-operations.md`.

## Disk space

CI pulls a new image per workflow, so the machine tidies up after
itself:

- A cleanup run happens daily at 04:15 UTC. It removes images no
  container has used for 7 days, containers outside the Forgejo stack
  that have been stopped for 7 days, unused networks, and build cache
  older than 7 days.
- Volumes are never removed, and the Forgejo and runner images named in
  the compose file are never removed.
- Run it by hand and read what it did:
  ```bash
  ssh -i <key> root@<target-ip> 'systemctl start forgejo-cleanup.service'
  ssh -i <key> root@<target-ip> 'journalctl -u forgejo-cleanup.service -n 40'
  ```
- See what Docker holds at any time:
  ```bash
  ssh -i <key> root@<target-ip> 'docker system df'
  ```

## Configuration

- The only per-machine setting is the LAN address, in
  `/opt/forgejo/.env` on the instance (`LAN_IP=<your-lan-ip>`).
- The runner repeats that address in
  `/srv/forgejo-runner/config.yaml` (`--add-host=forgejo.local:<ip>`),
  which is how job containers resolve the name. Change both when the
  address changes; the compose file derives its own pin from `LAN_IP`, so
  it follows automatically.
- All other Forgejo settings live in `/opt/forgejo/docker-compose.yml`
  as `FORGEJO__*` variables. After editing:
  ```bash
  ssh -i <key> root@<target-ip> 'cd /opt/forgejo && docker-compose up -d'
  ```
- The certificate and key are `/srv/forgejo-certs/forgejo.crt` and
  `forgejo.key`. Create or renew them with
  `ssh -i <key> root@<target-ip> '/opt/forgejo/gen-cert.sh'`; they are
  valid for 5 years. A renewal invalidates every existing pin, so
  re-import the new `.crt` on each device.

## Contributing

Development notes, scripts, and repo conventions: `CONTRIBUTING.md`.
