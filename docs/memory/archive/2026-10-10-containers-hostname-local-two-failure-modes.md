---
topic: "Containers and <hostname>.local: two failure modes, one fix"
importance: medium
category: warning
tags: [forgejo, actions, dns, job-containers, runner]
created: 2026-10-10T00:38:36Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Default-bridge containers ask the LAN router, which has no `.local`
zone, so the lookup returns nothing. Containers on a user-defined
network (compose services, the runner's per-job networks) go through
Docker's embedded DNS to systemd-resolved, which answers the host's own
mDNS name *synthetically* with every address on the machine: the LAN
address plus `172.18.0.1`, `172.17.0.1` and the link-local IPv6
addresses. Both are fixed by writing the pair into `/etc/hosts`, which
the resolver reads before DNS: `extra_hosts` on the compose services,
and `--add-host=forgejo.local:<LAN_IP>` in `container.options` of
`/srv/forgejo-runner/config.yaml`. Re-running `forgejo-runner
generate-config` wipes the runner option; replay recipe step 16
afterwards.
