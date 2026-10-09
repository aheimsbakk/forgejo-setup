---
topic: "Forgejo backup design: daily dump, 7 kept, remote copy later"
importance: medium
category: decision
tags: [forgejo, backup, systemd, retention]
created: 2026-10-09T18:53:27Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Daily backup runs `forgejo dump` (full restore point: DB, repos, config,
LFS) via systemd timer at 03:30 UTC into `/srv/forgejo-backups`, keeping
exactly the 7 newest. The operator will add the remote copy of that
directory themselves; do not build it.
