---
topic: "Forgejo SECRET_KEY stays empty; set it with SECRET_KEY_URI and a file mount"
importance: high
category: decision
tags: [forgejo, secrets, compose, backup, restore]
created: 2026-10-11T21:45:00Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Forgejo leaves `[security] SECRET_KEY` empty and never warns: the instance
ran 30 hours that way with no log line. Set it with
`SECRET_KEY_URI=file:/etc/forgejo/secret_key` plus a read-only single-file
mount of `/opt/forgejo/secrets/secret_key` (directory 750, file 640
`root:1000`, so the container's uid 1000 reads it). The two options are
mutually exclusive, so the empty `SECRET_KEY` line in `app.ini` must stay
empty. Generate the value with `docker run --rm --entrypoint
/usr/local/bin/forgejo <image> generate secret SECRET_KEY`; it works
before the first start and produces 43 bytes. The key file sits outside
`/srv/forgejo`, so no dump contains it and it needs its own backup.
Measured while checking that: a dump's `app.ini` does carry `INTERNAL_TOKEN`
and `[oauth2] JWT_SECRET` unchanged — only `SECRET_KEY` and the database
`PASSWD` are blanked. Dumps are mode 600 owned by uid 1000.
