---
topic: "buildah in podman job containers: userns size, SYS_ADMIN, AppArmor"
importance: high
category: warning
tags: [forgejo, actions, buildah, job-containers, podman]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Server-side `userns="auto:size=65536"` in `/etc/containers/containers.conf`
applies to runner-created job containers over the Docker-compatible API;
`podman kube play` ignores it. Nested buildah `RUN` also needs
`--cap-add SYS_ADMIN` and `--security-opt apparmor=unconfined` because
Debian's container AppArmor profile denies `userns_create` and `mount`.
`vfs` storage stays required; `_CONTAINERS_ROOTLESS_UID` is no longer
needed.