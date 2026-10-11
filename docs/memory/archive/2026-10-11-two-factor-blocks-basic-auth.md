---
topic: "Two-factor on an account blocks all /api/v1 basic auth"
importance: medium
category: warning
tags: [forgejo, api, basic-auth, two-factor]
created: 2026-10-11T21:19:30Z
model: kompis/qwen3.8-flash-next-iq3_s
---

With a `two_factor` row on the account, every `/api/v1` basic-auth call
returns 401: the password is verified and `last_login` updates, then the
request is refused because the API cannot run the second step. The
operator removed two-factor from the admin account on 2026-10-11, so
basic auth works again and the reproduce procedure's basic-auth calls are
fine. Prefer `Authorization: token ...` in checks that must not depend on
the setting; tokens are stored hashed and survive a restore.
