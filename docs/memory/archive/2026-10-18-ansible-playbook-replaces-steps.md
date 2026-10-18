---
topic: "Reproduce procedure is now the Ansible playbook in ansible/"
importance: high
category: decision
tags: [ansible, deployment, playbook, idempotent, uv]
created: 2026-10-18T18:53:10Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The bash reproduce procedure was replaced by `ansible/site.yml`
(ansible-core 2.21.5 pinned in `ansible/requirements.txt`, installed
with uv into `.venv/`). No collections; any future collection must be
declared in `ansible/requirements.yml` with an exact version and
confirmed with the operator first. The playbook converges a running
system: `--check --diff` verifies the live configuration, a second
apply reports changed=0 (proven on the 192.168.1.40 target 2026-10-18).
Admin credentials are optional (no vault): tasks needing them skip
when `forgejo_admin_password` is undefined. Parameter store moved from
repo-root `.env` to gitignored `ansible/hosts.yml`; the `forgejo/`
directory moved into `ansible/files/` and `ansible/templates/`.
Restart enforcement for the podman-kube units stays on hold.
