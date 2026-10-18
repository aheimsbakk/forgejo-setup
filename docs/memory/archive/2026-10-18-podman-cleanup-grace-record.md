---
topic: "Podman disk cleanup: 7-day grace record, stack images protected"
importance: medium
category: decision
tags: [forgejo, podman, cleanup, disk, systemd]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

`forgejo/cleanup.sh` runs daily at 04:15 UTC, after the 03:30 backup,
and removes unused images, stopped containers outside the podman kube
stack, and unused networks. The engine's `--filter until=` matches image
build dates and container creation times, not last use, so the script
keeps its own first-seen-unused record in
`/var/lib/forgejo-cleanup/unused-images.tsv` and deletes only after 7
days. Protected images come from `image:` lines in `/opt/forgejo/kube/*.yaml`;
stack containers are recognized by the `PODMAN_SYSTEMD_UNIT` label;
volumes are never removed.