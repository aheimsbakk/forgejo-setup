---
topic: "Containers and <hostname>.local: two failure modes, one fix"
importance: medium
category: warning
tags: [forgejo, actions, dns, job-containers, runner]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Default-bridge containers ask the LAN router, which has no `.local`
zone, so the lookup returns nothing. Containers on a user-defined
network can go through the host resolver, which answers the host's own
mDNS name *synthetically* with every address on the machine: the LAN
address plus bridge gateways and link-local IPv6 addresses. Both are
fixed by writing the pair into `/etc/hosts`, which the resolver reads
before DNS: `hostAliases` on the pods, and
`--add-host=forgejo.local:<LAN_IP>` in `container.options` of
`/srv/forgejo-runner/config.yaml`. Re-running `forgejo-runner
generate-config` wipes the runner option; replay recipe step 16
afterwards.