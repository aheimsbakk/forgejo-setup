---
topic: "Fresh-install gaps the playbook had to fix, measured on the test host"
importance: high
category: warning
tags: [ansible, fresh-install, runner, timezone, certs, restore, admin-user]
created: 2026-11-06T19:45:00Z
model: kompis/qwen3.8-flash-next-iq3_s
---

A fresh convergence on the test host exposed four gaps the
production-converged playbook hid. All are fixed in `ansible/` and
documented in `ansible/docs/development-notes.md`:

- `/etc/timezone`: `podman kube play` fails on a missing hostPath, but
  podman also leaves an empty DIRECTORY there where it once created
  one (seen on production). The task creates the file only when the
  path is absent; `copy` into an existing directory aborts the run.
- Runner `register` needs `--user 0 --userns=host` (the global
  userns setting remaps a plain `podman run` root off host uid 0, so
  `.runner` is not writable), plus `--add-host` and a cert mount, and
  a 300 s timeout for the first node image pull.
- `admin` is a reserved username in Forgejo 16; the recipe default
  admin is now `siteadmin`.
- Fetched certs are per inventory host (`ansible/certs/<host>/`); the
  test inventory names its host `forgejo-test` inside a group
  `forgejo` so `site.yml` still matches and the copies cannot
  overwrite each other.

Restore-drill checks: create the API token AFTER the restore (the
dump predates any earlier token), and a CLI-generated token only
works as the basic-auth password, never in the
`Authorization: token` header.
