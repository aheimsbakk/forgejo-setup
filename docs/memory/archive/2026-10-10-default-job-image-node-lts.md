---
topic: "Default job image is node:24-bookworm; the label lives in .runner"
importance: medium
category: decision
tags: [forgejo, actions, runner, labels, job-image]
created: 2026-10-10T10:54:43Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The runner's default job image comes from the registration label in
`/srv/forgejo-runner/.runner` (not `config.yaml`), now
`docker:docker://node:24-bookworm` (change 34) so mirrored JavaScript
actions work with plain `runs-on: docker`. Edit the label and restart
the runner; id and token survive. Node 20 went end-of-life 2026-04-30
— check a base image line's support status before choosing it, and
bump to the next LTS (node 26 becomes Active LTS 2026-10-28) as a
deliberate change.
