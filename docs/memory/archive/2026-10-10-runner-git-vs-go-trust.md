---
topic: "Runner git and Go have separate trust stores; merged CA bundle at start"
importance: high
category: warning
tags: [forgejo, actions, runner, tls, ca-bundle]
created: 2026-10-10T10:29:15Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The runner downloads workflow actions with git, which (OpenSSL) reads
the `ca-certificates.crt` bundle, not the loose certificate in
`/etc/ssl/certs` that only the Go daemon reads. Action clones from the
self-signed instance fail with `SSL certificate OpenSSL verify result:
self-signed certificate (18)`. The runner image is Alpine without
`update-ca-certificates`; the compose command concatenates the bundle
plus the instance cert into `/tmp/ca-bundle.crt` at every start and
sets `GIT_SSL_CAINFO` for the runner container.
