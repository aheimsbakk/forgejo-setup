---
topic: "Actions token cannot push container images; use a user token secret"
importance: high
category: warning
tags: [forgejo, actions, registry, packages, token]
created: 2026-10-11T20:05:02Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The Actions `GITHUB_TOKEN` authenticates against the instance registry
(`GET /v2/` returns 200), but the registry token Forgejo mints for the job
carries `UserID:-2` and an empty `Scope`, so any write returns 401.
`DeterminePackageAccessMode` gives the built-in `forgejo-actions` user
read at most and still carries the upstream comment
`// TODO: ActionUser permission check`. Push with a user token that has
`write:package`, kept in a repository secret; OIDC is off on this
instance, so no short-lived registry credential exists.
