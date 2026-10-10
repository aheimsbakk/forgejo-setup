---
topic: "Email placeholders: use .invalid, never .local"
importance: low
category: warning
tags: [forgejo, email, mdns, rfc6761]
created: 2026-10-10T01:30:00Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Forgejo requires an email when creating accounts. The placeholder
domain is `<user>@forgejo.invalid` (RFC 6761: never deliverable),
changed from `forgejo.lan` in recipe change 31. Never use `.local` in
email addresses: RFC 6762 reserves it for mDNS. The target still has
an operator-created account `robot` with `robot@forgejo.local`; the
operator decides whether to change it.
