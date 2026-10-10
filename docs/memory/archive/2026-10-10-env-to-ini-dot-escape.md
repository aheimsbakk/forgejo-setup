---
topic: "FORGEJO__ env vars: dotted ini sections need _0X2E_ escape"
importance: medium
category: pattern
tags: [forgejo, docker, env-vars, app-ini, pagination]
created: 2026-10-10T15:20:00Z
model: kompis/qwen3.8-flash-next-iq3_s
---

To set a key in a dotted ini section like `[ui.user]` via compose env vars,
escape the dot as `_0X2E_`: `FORGEJO__ui_0X2E_user__REPO_PAGING_NUM=50`.
A plain `__` there would create a wrong section. Verified live with
`EXPLORE_PAGING_NUM`/`REPO_PAGING_NUM` at 50 (recipe change 35); page size
costs are negligible (one indexed query plus a count).
