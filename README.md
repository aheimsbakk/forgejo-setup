# Forgejo LAN Install

A tested recipe and deployment files for running [Forgejo](https://forgejo.org),
a self-hosted git forge, in Docker on a Debian 13 machine. The instance is
reachable over plain HTTP from the local network only.

What it gives you:

- Forgejo 16.0.5 (pinned) in Docker, started on boot
- Web UI on port 80 and git-over-SSH on port 2222, bound to the LAN
  address only — never to the public interfaces of the machine
- A daily full backup (database, repositories, config) that keeps the
  7 newest restore points
- A step-by-step install recipe you can rerun on any fresh Debian 13
  machine with nothing but an SSH key and an IP

## Quick start

You need: a Debian 13 machine on your network, and SSH private key access
as root on it.

1. Clone this repo on the machine you run SSH from.
2. Open `docs/forgejo-install-recipe.md` and follow the
   "Reproduce (full recipe)" section top to bottom. It asks for the
   target IP, an admin username, and an admin password.
3. When it finishes, open `http://<target-ip>/` in a browser and sign in
   with the admin account you chose.

## Using the instance

- Web UI: `http://<target-ip>/` — or `http://forgejo.local/` from any
  device on the LAN (mDNS discovery)
- Clone over HTTP: `http://<target-ip>/<owner>/<repo>.git`
- Clone over SSH: `ssh://git@<target-ip>:2222/<owner>/<repo>.git`
- New accounts: registration is off. The admin creates accounts under
  Site Administration, or with:
  ```bash
  ssh -i <key> root@<target-ip> \
    'docker exec -u 1000 forgejo forgejo admin user create --username <name> --password <pw> --email <name>@forgejo.lan'
  ```

## CI/CD

Forgejo Actions is enabled. A runner shares the machine with the
instance: workflows with `runs-on: docker` run in Debian bookworm
containers, two jobs at a time, each limited to 1 CPU and 1 GB RAM.
Build container images with buildah inside jobs; docker-in-docker and
privileged jobs are not available.

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
- Restore steps: see the "Backup" section of
  `docs/forgejo-install-recipe.md`.

## Configuration

- The only per-machine setting is the LAN address, in
  `/opt/forgejo/.env` on the instance (`LAN_IP=<your-lan-ip>`).
- All other Forgejo settings live in `/opt/forgejo/docker-compose.yml`
  as `FORGEJO__*` variables. After editing:
  ```bash
  ssh -i <key> root@<target-ip> 'cd /opt/forgejo && docker-compose up -d'
  ```
- There is no HTTPS. The instance is meant for the local network only.

## Contributing

Development notes, scripts, and repo conventions: `CONTRIBUTING.md`.
