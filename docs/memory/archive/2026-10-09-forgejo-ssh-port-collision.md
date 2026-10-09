---
topic: "Forgejo container SSH port collision inside the image"
importance: medium
category: warning
tags: [forgejo, docker, ssh, port-collision]
created: 2026-10-09T18:40:41Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The official Forgejo image runs OpenSSH on port 22 inside the container.
Setting `FORGEJO__server__START_SSH_SERVER=true` with
`SSH_LISTEN_PORT=22` crashes the container (`bind: address already in
use`). Use `SSH_LISTEN_PORT=2222` and publish `2222:2222` instead.
