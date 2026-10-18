---
topic: "Restart enforcement for the podman-kube units: on hold, leading fix known"
importance: high
category: decision
tags: [podman, systemd, restart, forgejo, on-hold]
created: 2026-10-18T17:40:18Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Operator put restart enforcement for the two `podman-kube@` units on
hold on 2026-10-18; no fix is scheduled. The agreed leading fix is a
drop-in with `Restart=always` and `RestartSec=10` on both units —
`Restart=on-failure` is wrong because `kube play` exits 0 on the crash
path. Before applying it, test that `ExecStop=podman kube down` does not
fail against an already half-removed pod, which would leave the unit in
`failed`. Do not leave an untested drop-in on a target.
