---
topic: "Forgejo deployment constraints: Docker, LAN-only HTTPS"
importance: high
category: decision
tags: [forgejo, docker, lan-only, https, deployment]
created: 2026-10-09T21:54:22Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Forgejo runs in Docker from the official image, reachable from the LAN
only. Published ports bind to the LAN IPv4 address (never 0.0.0.0)
because the host also has a public IPv6 address. HTTPS uses a
self-signed certificate created on the target by `forgejo/gen-cert.sh`
(5 years; SAN: LAN IP, 127.0.0.1, forgejo.local, localhost, hostname);
browsers, git clients, the runner and job containers pin it. Port 80
serves redirects only. No domain, no separate database server (SQLite
inside the data volume). This replaces the earlier no-TLS decision.
