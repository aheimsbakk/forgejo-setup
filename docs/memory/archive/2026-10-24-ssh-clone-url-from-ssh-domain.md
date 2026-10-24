---
topic: "Forgejo SSH clone URL comes from SSH_DOMAIN, default localhost"
importance: high
category: warning
tags: [forgejo, ssh, clone-url, app-ini, server-config]
created: 2026-10-24T15:04:42Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The UI clone button and the repository API `ssh_url` are built from
`[server] SSH_DOMAIN`, which does not inherit `DOMAIN` and defaults to
`localhost`. With only `DOMAIN`/`ROOT_URL` set, every SSH clone hint reads
`ssh://git@localhost:2222/...`. Fix: set
`FORGEJO__server__SSH_DOMAIN=<LAN name>` in the pod definition; the
entrypoint rewrites `app.ini` after the pod restarts (recipe change 49,
verified 2026-10-24: `ssh_url` became `ssh://git@forgejo.local:2222/...`).
