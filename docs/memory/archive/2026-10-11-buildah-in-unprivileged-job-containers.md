---
topic: "buildah in unprivileged job containers: rootless uid, vfs, no RUN"
importance: high
category: warning
tags: [forgejo, actions, buildah, job-containers, seccomp]
created: 2026-10-11T20:05:02Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Job containers hold no `CAP_SYS_ADMIN` and Docker's default seccomp
returns EPERM for `unshare`, so buildah 1.28 dies with `Error during
unshare(CLONE_NEWUSER)`; set `_CONTAINERS_ROOTLESS_UID=1000` to make
`MaybeReexecUsingUserNamespace` return early. Only `vfs` storage works
(`mount()` is EPERM and there is no `/dev/fuse`), and `RUN` is impossible
because both isolation modes call `unshare(CLONE_NEWNS)` — build with
`base-image` plus `content` instead. `redhat-actions/buildah-build@v3`
has no `content-path` input: the `content` list goes straight to
`buildah copy`, so the last entry is the destination.
