---
topic: "Forgejo deployment constraints: podman, LAN-only HTTPS"
importance: high
category: decision
tags: [forgejo, podman, lan-only, https, deployment]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Forgejo runs in rootful podman from the official image, reachable from
the LAN only. The app and runner are Kubernetes pod YAML under
`/opt/forgejo/kube/`, started by the stock `podman-kube@.service`
template. Published ports bind to the LAN IPv4 address (never 0.0.0.0)
because the host also has a public IPv6 address. HTTPS uses a
self-signed certificate created on the target by `forgejo/gen-cert.sh`
(5 years; SAN: LAN IP, 127.0.0.1, forgejo.local, localhost, hostname);
browsers, git clients, the runner and job containers pin it. Port 80
serves redirects only. Docker is removed.