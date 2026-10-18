# Forgejo Install Steps

The reproduce procedure for the instance described in
`docs/forgejo-install-recipe.md` is now the Ansible playbook in
`ansible/`. One command converges a fresh Debian 13 machine and a
running one; a second run reports no changes. The problems found along
the way are in `docs/forgejo-footguns.md`.

The playbook is idempotent and fails hard: every verification runs on
every pass, and a failed check stops the run with a named cause.

## What the playbook owns

- `ansible/site.yml` — the entry point; imports four task files
  (`base`, `forgejo`, `runner`, `verify`).
- `ansible/templates/` — the pod definitions, engine defaults and the
  runner job configuration, generated with this deployment's address.
- `ansible/files/` — the scripts and systemd units deployed verbatim.
- `ansible/hosts.yml` — the parameter store (gitignored): target
  address, LAN resolver, SSH key path. Copy `hosts.yml.example`.

## Run it

You need: a Debian 13 target, root SSH access with a key, and
[uv](https://docs.astral.sh/uv/) on the machine you run from.

1. Create the control environment (once per checkout):

   ```bash
   uv venv .venv
   uv pip install --python .venv/bin/python -r ansible/requirements.txt
   ```

2. Create the parameter store:

   ```bash
   cp ansible/hosts.yml.example ansible/hosts.yml
   ```

   Fill in `ansible_host`, `lan_ip`, `lan_resolver` and
   `ansible_private_key_file`. On a fresh machine, also set
   `forgejo_admin_user` and `forgejo_admin_password`: the playbook then
   creates the admin account and registers the runner. On a running
   instance leave them out; those tasks skip.

3. Verify the configuration without changing anything:

   ```bash
   cd ansible
   ../../.venv/bin/ansible-playbook site.yml --check --diff
   ```

   Expect `changed=0` on a converged machine. On a fresh machine the
   verification tasks fail until the resources exist — that is the
   fail-hard behaviour, not a bug.

4. Apply:

   ```bash
   ../../.venv/bin/ansible-playbook site.yml
   ```

5. Prove the operational jobs once:

   ```bash
   ../../.venv/bin/ansible-playbook site.yml --tags verify
   ```

   This runs one backup (and checks the dump leaves registry blobs
   out), one cleanup, and the engine's registry-trust probe.

The playbook fetches the public certificate to `tmp/certs/forgejo.crt`
on the control machine. Trust it on each client device: the "Client
trust" section of `docs/forgejo-operations.md`.

## Tags

- `base` — hostname, upgrades, podman, engine defaults, directories,
  Avahi.
- `forgejo` — pod definitions, certificate, encryption key, pods,
  timers, registry trust, all service asserts.
- `runner` — registration (fresh installs) and the job configuration.
- `verify` — one-shot backup/cleanup/probe runs; never runs unless you
  ask for it.

## Manual CI smoke test

The playbook does not push repositories. To prove Actions end to end,
create a throwaway repo in the web UI, push this workflow, and watch
the run succeed:

```yaml
name: smoke
on: [push]
jobs:
  ca-pin:
    runs-on: docker
    steps:
      - run: |
          test -f /etc/ssl/certs/forgejo-lan.crt
          getent ahostsv4 forgejo.local
          git ls-remote https://forgejo.local/<owner>/<repo>.git >/dev/null
          echo "git over https by name with pinned CA ok"
```

Delete the repository afterwards.
