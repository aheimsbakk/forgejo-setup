---
topic: "Multi-arch buildah manifest lists work after podman migration"
importance: medium
category: pattern
tags: [forgejo, actions, buildah, multiarch, binfmt]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Cross-architecture builds still need no host change in the no-`RUN`
shape: `buildah from --platform`, one container per architecture, then
`buildah manifest create`/`add` and `buildah push --all`. The manifest
list is now proven: `:multiarch` pulls anonymously and reports `amd64`
and `arm64`. Running a foreign-architecture image is different: it needs
QEMU user-mode registered on the host, and Debian's entries name
`/usr/bin/qemu-<arch>-static`, which must also exist inside the job
container unless the entry carries the `P` flag.