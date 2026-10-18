---
topic: "Forgejo Actions runner on same box, mitigations applied"
importance: high
category: decision
tags: [forgejo, actions, runner, security, same-box]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Operator chose the Actions runner on the same VM as Forgejo
(`data.forgejo.org/forgejo/runner:13.1.0`). Mitigations: podman socket
only in the runner container, `capacity: 2`, job limits
`--memory=1g --cpus=1`, `privileged: false` (no engine-in-engine —
images built with buildah). Fork-PR gating is documented but not
configured. Do not raise capacity: the VM has 2 vCPUs, 4 GB RAM, no
swap.