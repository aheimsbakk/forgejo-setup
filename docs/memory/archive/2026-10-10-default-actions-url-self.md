---
topic: "DEFAULT_ACTIONS_URL=self: mirrored public repos, cache and node gotchas"
importance: medium
category: decision
tags: [forgejo, actions, mirror, runner-cache, node]
created: 2026-10-10T10:29:15Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Actions with a relative `uses:` now come from the instance itself
(`FORGEJO__actions__DEFAULT_ACTIONS_URL=self`); the operator mirrors
each action as a public repo (e.g. `actions/checkout`), because the
runner clones anonymously. After changing the setting, delete
`/srv/forgejo-runner/.cache` — cached clones keep the old remote.
JavaScript actions need `node` in the job image (`node:20-bookworm`
has node and git; the runner image has no node).
