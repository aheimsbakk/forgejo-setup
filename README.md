# Forgejo LAN Install

A tested recipe and deployment files for running [Forgejo](https://forgejo.org),
a self-hosted git forge, in podman on a Debian 13 machine. The instance
serves HTTPS on the local network only.

What it gives you:

- Forgejo 16.0.5 (pinned) in podman, started on boot
- Web UI on port 443 over HTTPS, port 80 redirects to it, git-over-SSH
  on port 2222 — all bound to the LAN address only, never to the public
  interfaces of the machine
- A self-signed certificate created on the machine; every device that
  connects trusts it once
- A daily backup (database, repositories, config) that keeps the
  7 newest restore points; container images in the instance registry are
  left out because CI rebuilds them
- A daily disk cleanup that removes container images and stopped
  containers unused for a week
- An Ansible playbook that installs everything on a fresh Debian 13
  machine — and keeps a running machine converged — with nothing but
  an SSH key and an IP

## Quick start

You need: a Debian 13 machine on your network, and SSH private key access
as root on it.

1. Clone this repo on the machine you run SSH from.
2. Run the playbook as described in `docs/forgejo-install-steps.md`:
   create the parameter store from `ansible/hosts.yml.example` (target
   IP, LAN resolver, SSH key, admin account and password), then apply
   with `ansible-playbook site.yml`.
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
    'podman exec -u 1000 forgejo-forgejo forgejo admin user create --username <name> --password <pw> --email <name>@forgejo.invalid'
  ```

## CI/CD

Forgejo Actions is enabled. A runner shares the machine with the
instance: workflows with `runs-on: docker` run in `node:24-bookworm`
containers, two jobs at a time, each limited to 1 CPU and 1 GB RAM.
Build container images with buildah inside jobs. Containerfile `RUN`
steps work in the job's user namespace; engine-in-engine and privileged
jobs are not available.

- The instance certificate is already inside job containers at
  `/etc/ssl/certs/forgejo-lan.crt`, and `GIT_SSL_CAINFO` points there,
  so `git` over HTTPS works in jobs without extra setup.
- Inside workflows both `https://<target-ip>/` and
  `https://forgejo.local/` work: the runner writes the name into every
  job container's hosts file. Most command-line tools already trust the
  certificate from that directory, and `NODE_EXTRA_CA_CERTS` is set for
  every job; Python `requests` still needs its own variable — see
  "Access from job containers" in `docs/forgejo-ci-and-registry.md`.
- The default job image `node:24-bookworm` has git and node, so
  mirrored JavaScript actions work with no image choice. A minimal
  image such as Alpine has neither: the runner then runs steps with
  `sh`, and `actions/checkout` cannot run in it.
- Actions come from the instance: `uses: actions/checkout@v4` clones
  `https://forgejo.local/actions/checkout`, so every action a workflow
  uses must be mirrored here and public. A full URL in `uses:` still
  downloads from another forge. Jobs also pull images and install
  packages, so the machine needs outbound internet access.
- A job can build a container image, push it to the instance registry,
  and a later job can run inside it:
  `container.image: forgejo.local/<owner>/<repo>:<tag>`. Pushing needs
  a repository secret holding a user token that can write packages;
  the Actions token cannot. The default multiarch template is
  `templates/build-multiarch.yml`; it replaces the three current build
  workflows and pushes `latest`. The steps are in "Container registry
  (build, push, use)" and "Default multiarch build template" in
  `docs/forgejo-ci-and-registry.md`.

Recommendation: if you ever allow pull requests from forks, disable or
gate fork PR workflows in each repository's Actions settings. By default
they would run the contributor's code on your machine.

## Backups

- A backup runs daily at 03:30 UTC. Files land in
  `/srv/forgejo-backups/` on the instance machine; the 7 newest are kept.
- Run one by hand:
  ```bash
  ssh -i <key> root@<target-ip> 'systemctl start forgejo-backup.service'
  ```
- Container images pushed to the instance registry are not in a backup:
  they are the fastest-growing part of the disk and CI can rebuild them.
  After a restore the registry still lists those images, but pulling them
  fails until CI pushes them again or you delete the entries under
  owner settings → packages → cleanup rules.
- Backups stay on the same machine. Copy them off-site yourself if you
  need protection against disk loss.
- The TLS private key is not part of a backup; it lives in
  `/srv/forgejo-certs`. A restore needs a new certificate and new pins.
- Restore steps: `docs/forgejo-restore.md`.

## Disk space

CI pulls a new image per workflow, so the machine tidies up after
itself:

- A cleanup run happens daily at 04:15 UTC. It removes images no
  container has used for 7 days, containers outside the Forgejo stack
  that have been stopped for 7 days, and unused networks older than
  7 days.
- Volumes are never removed, and the Forgejo and runner images named in
  the pod definitions are never removed.
- Run it by hand and read what it did:
  ```bash
  ssh -i <key> root@<target-ip> 'systemctl start forgejo-cleanup.service'
  ssh -i <key> root@<target-ip> 'journalctl -u forgejo-cleanup.service -n 40'
  ```
- See what podman holds at any time:
  ```bash
  ssh -i <key> root@<target-ip> 'podman system df'
  ```

## Configuration

- The per-machine settings — LAN address, resolver, SSH key — live in
  `ansible/hosts.yml` (gitignored). The playbook renders them into the
  pod definitions, `/etc/containers/containers.conf`,
  `/opt/forgejo/.env` and the runner config, and restarts what
  changed. Change the address by editing `hosts.yml` and re-running
  the playbook.
- All other Forgejo settings live in
  `ansible/templates/kube/forgejo.yaml.j2` as `FORGEJO__*` variables.
  Edit the template, then re-run the playbook — or edit
  `/opt/forgejo/kube/forgejo.yaml` on the target and restart:
  ```bash
  ssh -i <key> root@<target-ip> \
    'systemctl restart podman-kube@opt-forgejo-kube-forgejo.yaml.service'
  ```
- The certificate and key are `/srv/forgejo-certs/forgejo.crt` and
  `forgejo.key`. Create or renew them with
  `ssh -i <key> root@<target-ip> '/opt/forgejo/gen-cert.sh'`; they are
  valid for 5 years. A renewal invalidates every existing pin, so
  re-import the new `.crt` on each device.
- The global encryption key is `/opt/forgejo/secrets/secret_key` on the
  instance. It is not in any dump and not in this repository, so it needs
  a backup of its own. Without it the instance cannot read the data it
  encrypts, and it will not start.

## Contributing

Development notes, scripts, and repo conventions: `CONTRIBUTING.md`.
