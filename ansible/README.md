# Forgejo LAN Install — Ansible Recipe

One Ansible playbook installs and maintains a [Forgejo](https://forgejo.org)
git forge in podman on a Debian 13 machine. It serves HTTPS on the local
network only, and needs nothing from the operator but the target's IP
and an SSH key. Re-running it keeps a running machine converged; a
`--check --diff` run verifies the configuration without changing it.

What the playbook sets up:

- Forgejo (version pinned in `group_vars/all.yml`) in a podman pod,
  started on boot
- Web UI on 443 (HTTPS), 80 redirects to it, git-over-SSH on 2222 —
  all bound to the LAN address only
- A self-signed certificate created on the target; clients pin it once
- A nightly backup that keeps the 7 newest dumps, and a nightly disk
  cleanup with a 7-day grace period
- A Forgejo Actions runner on the same machine, under CPU and memory
  limits
- Assertions that check every part of this after each run

## Prerequisites

- A Debian 13 (trixie) machine, amd64, with outbound internet (apt and
  container images). Debian's base image already has the `python3` and
  `openssl` this recipe uses.
- Root SSH access by key from the machine you run the playbook on.
- [uv](https://docs.astral.sh/uv/) on the control machine.
- At least 2 vCPUs and 4 GB RAM if you use the Actions runner; the job
  limits in `group_vars/all.yml` assume that size. Do not raise them
  beyond the machine.

## Quick start

Run from this directory:

```bash
uv venv .venv
uv pip install --python .venv/bin/python -r requirements.txt -r requirements-lint.txt
cp hosts.yml.example hosts.yml   # fill in address, resolver, SSH key path
.venv/bin/ansible-playbook site.yml --check --diff   # verify only
.venv/bin/ansible-playbook site.yml                  # apply
.venv/bin/ansible-playbook site.yml --tags verify    # one-shot checks
```

`hosts.yml` is gitignored and per-deployment: it holds the target
address, the LAN resolver, the SSH key path, and — for fresh installs
only — the admin account to create. `hosts.yml.example` documents every
parameter.

On a **fresh machine**, set `forgejo_admin_user` and
`forgejo_admin_password` in `hosts.yml`: the playbook then creates the
admin account and registers the runner. On a **running instance**,
leave them out; those tasks skip.

After the first apply, the public certificate sits in `certs/forgejo/forgejo.crt`
(named per inventory host; fetched by the playbook). Trust it on every
client device — see "Client trust" in `docs/operations.md`. The playbook
ends by asserting the HTTPS page answers and ports bind only to the LAN
address.

## Tags

| Tag | Covers |
|---|---|
| `base` | hostname, upgrades, podman, engine defaults, directories, Avahi |
| `forgejo` | pod definitions, certificate, encryption key, pods, timers, registry trust, service asserts |
| `runner` | runner registration (fresh installs) and job configuration |
| `verify` | one-shot backup/cleanup/probe runs; never runs unless asked |

## What this recipe does not do

- It does not mirror workflow actions. `DEFAULT_ACTIONS_URL=self` means
  every `uses: actions/...` must exist as a repository on the instance;
  mirror them first or no workflow runs. See `docs/ci-and-registry.md`.
- It does not restore a dump. Restore is a file copy described in
  `docs/restore.md`.
- It does not copy backups off the machine, and does not restart a pod
  whose service unit was stopped manually (`docs/operations.md`).
- The global encryption key it generates (`/opt/forgejo/secrets/secret_key`)
  is in no dump and not in git. Without it the instance cannot read the
  data it encrypts, and it will not start. Back it up separately.

## Documentation

- `docs/operations.md` — client trust, certificate renewal, backup and
  cleanup behaviour and scope
- `docs/restore.md` — restore a dump
- `docs/ci-and-registry.md` — Actions runner, container registry,
  mirrored actions, access from job containers
- `docs/development-notes.md` — traps and patterns for changing the
  playbook or templates
- `repo-templates/build-multiarch.yml` — workflow template to copy into
  new repositories

## Editing configuration

Per-deployment values live in `hosts.yml`; tracked defaults live in
`group_vars/all.yml` (image pins, limits, target paths). All Forgejo
application settings live in `templates/kube/forgejo.yaml.j2` as
`FORGEJO__*` variables. Edit, then re-run the playbook; it re-renders
and restarts the affected pod.
