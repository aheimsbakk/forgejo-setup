---
topic: "podman-kube instance names encode YAML paths and reject hyphenated file names"
importance: medium
category: warning
tags: [podman, systemd, kube, paths, forgejo]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

`podman-kube@.service` passes `%I` directly to `podman kube play`, so the
instance name is the YAML path with `/` replaced by `-`. Because systemd
`%I` turns every `-` back into `/`, the YAML file names must not contain
hyphens. For `/opt/forgejo/kube/forgejo.yaml`, use
`podman-kube@opt-forgejo-kube-forgejo.yaml.service`.