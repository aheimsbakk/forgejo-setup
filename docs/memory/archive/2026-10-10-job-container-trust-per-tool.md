---
topic: "Job container trust: /etc/ssl/certs covers OpenSSL tools, runner sets NODE_EXTRA_CA_CERTS"
importance: medium
category: pattern
tags: [forgejo, actions, tls, ca-certificates, job-containers]
created: 2026-10-10T00:38:36Z
model: kompis/qwen3.8-flash-next-iq3_s
---

In Debian-based job images a certificate file placed in `/etc/ssl/certs`
is enough for OpenSSL-based tools (curl, wget, git) — the file name does
not matter, and the same file mounted elsewhere is rejected. Node keeps
its own CA store; the runner's `container.envs` now sets
`NODE_EXTRA_CA_CERTS` for every job, which is additive, so public HTTPS
still verifies. `REQUESTS_CA_BUNDLE` must not be set that way: it
replaces the whole trust store and breaks public sites, the same failure
mode as `SSL_CERT_FILE` on the runner. `update-ca-certificates` inside a
job does not help Node and only lasts for that container.
