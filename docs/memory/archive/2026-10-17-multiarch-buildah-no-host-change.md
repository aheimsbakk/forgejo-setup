---
topic: "Multi-arch buildah builds need no host change; only the manifest list is unproven"
importance: medium
category: pattern
tags: [forgejo, actions, buildah, multiarch, binfmt]
created: 2026-10-17T22:41:07Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Cross-architecture builds work in the no-`RUN` shape because buildah never
executes a binary from the image being built: `buildah from --platform`,
one container per architecture, then `buildah manifest create`/`add` and
`buildah push --all`. Running a foreign-architecture image is different: it
needs QEMU user-mode registered on the host, and although binfmt
registrations are global to the kernel, Debian's entries name
`/usr/bin/qemu-<arch>-static`, which must also exist inside the job
container unless the entry carries the `P` flag. A job cannot register
handlers itself, because `/proc/sys/fs/binfmt_misc` is empty inside job
containers. The proposal and its open questions are in
`tasks/multiarch-buildah-builds.md`.
