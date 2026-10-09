---
topic: "Forgejo deployment constraints: Docker, LAN-only HTTP"
importance: high
category: decision
tags: [forgejo, docker, lan-only, deployment]
created: 2026-10-09T18:28:33Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Forgejo must run in Docker from the official Forgejo image, reachable over
plain HTTP from the LAN only. Bind published ports to the LAN IPv4 address
(never 0.0.0.0) because the host also has a public IPv6 address. No TLS,
no domain, no separate database server (SQLite inside the data volume).
