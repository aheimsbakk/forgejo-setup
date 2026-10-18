---
topic: "podman-kube restart semantics: teardown is clean, stock template does not restart"
importance: high
category: warning
tags: [podman, systemd, kube, restart, forgejo]
created: 2026-10-18T17:33:18Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The Debian 13 stock `podman-kube@.service` template has no `Restart=`.
Killing an app container stops the pod's service container, makes the
unit inactive, and runs `podman kube down`, which removes the pod.
`restartPolicy: Always` restarts containers only while the pod stays up;
it does not cover this teardown path. A manual `systemctl stop` of the
runner unit (measured 2026-10-18) runs the same teardown and leaves the
pod removed, so a systemd restart cycle starts from a clean slate.
systemd never applies `Restart=` after an explicit stop, so a drop-in
keeps operator stops intentional; that combination is untested here.
