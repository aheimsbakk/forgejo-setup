---
topic: "Docker disk cleanup: 7-day grace record, stack images protected"
importance: medium
category: decision
tags: [forgejo, docker, cleanup, disk, systemd]
created: 2026-10-09T23:35:45Z
model: kompis/qwen3.8-flash-next-iq3_s
---

`forgejo/cleanup.sh` runs daily at 04:15 UTC, after the 03:30 backup,
and removes unused images, stopped containers outside the compose stack,
unused networks and build cache. Docker's `--filter until=` matches image
build dates and container creation times, not last use, so the script
keeps its own first-seen-unused record in
`/var/lib/forgejo-cleanup/unused-images.tsv` and deletes only after 7
days. Protected images come from `docker-compose config --images` at run
time; volumes are never removed.
