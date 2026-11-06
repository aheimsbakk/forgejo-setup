---
topic: "Spare Debian 13 test host approved for recipe verification"
importance: high
category: decision
tags: [deployment, testing, test-host, recipe, restore-drill]
created: 2026-11-06T18:12:12Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The operator made a second, fresh Debian 13 host available; its
parameters live in `ansible/hosts.test.yml` (untracked, same SSH key as
production). Recipe work (fresh convergence, admin/runner paths, verify
tag, restore drill) runs there, never on the production target. The
restore drill is self-contained on the test host; production dumps and
the production encryption key must not be copied to it. Because both
boxes share the LAN, the test host must override `lan_name` in its
inventory to avoid an mDNS clash with production.
