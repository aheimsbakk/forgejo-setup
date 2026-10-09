---
topic: "Forgejo runner certificate pinning: three footguns"
importance: medium
category: warning
tags: [forgejo, actions, runner, tls, volumes]
created: 2026-10-09T22:31:12Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The runner silently drops a `--volume` in `container.options` unless the
exact source path is listed in `valid_volumes`; an empty list allows
none. `GIT_SSL_CAINFO` must be an absolute path — a relative one breaks
`git push` while `git clone` still works. The instance certificate must
be mounted into `/etc/ssl/certs` inside the runner container: without it
the daemon exits with `x509: certificate signed by unknown authority`.
`SSL_CERT_FILE` is not the mechanism — git ignores it, so downloads of
third-party actions keep working whether it is set or not.
