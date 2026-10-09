---
topic: "Forgejo install recipe project"
importance: high
category: decision
tags: [forgejo, deployment, recipe, ssh]
created: 2026-10-09T18:25:33Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Project goal: a general recipe that installs Forgejo on a Debian 13 machine
given only an SSH key and an IP. Every change to the target must be logged
in `docs/forgejo-install-recipe.md` as it happens. First target: LAN
address and key in the repo-root `.env` (gitignored); hostname set to
`forgejo`.
