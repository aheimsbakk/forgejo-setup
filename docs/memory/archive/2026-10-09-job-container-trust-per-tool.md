---
topic: "Job container trust: the /etc/ssl/certs mount covers OpenSSL tools, not Node"
importance: medium
category: pattern
tags: [forgejo, actions, tls, ca-certificates, job-containers]
created: 2026-10-09T22:42:44Z
model: kompis/qwen3.8-flash-next-iq3_s
---

In Debian-based job images a certificate file placed in `/etc/ssl/certs`
is enough for OpenSSL-based tools (curl, wget, git) — the file name does
not matter, and the same file mounted elsewhere is rejected. Node keeps
its own CA store and needs `NODE_EXTRA_CA_CERTS`; Python `requests`
reads the `certifi` bundle and needs `REQUESTS_CA_BUNDLE`. Running
`update-ca-certificates` inside a job does not help Node and only lasts
for that container.
