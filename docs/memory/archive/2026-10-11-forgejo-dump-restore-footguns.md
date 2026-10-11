---
topic: "Forgejo dump restore: no restore.sh, blanked SECRET_KEY, git/.ssh owner"
importance: high
category: warning
tags: [forgejo, backup, restore, sqlite, secret-key]
created: 2026-10-11T21:11:40Z
model: kompis/qwen3.8-flash-next-iq3_s
---

Forgejo 16.0.5 has no restore command and its dumps contain no
`restore.sh`; restore is a file copy of `data/` to `/srv/forgejo/gitea/`
and `repos/` to `/srv/forgejo/git/repositories/`. The dump's `app.ini`
blanks `SECRET_KEY` and `PASSWD`, which no longer matters for the key: the
compose file sets `SECRET_KEY_URI` and mounts `/opt/forgejo/secrets/secret_key`
read-only, and the image rewrites `conf/app.ini` from the environment at
every start. That key file is in no dump, so a restore needs it present or
the app exits at startup. Chown the restored tree to 1000:1000 before the
first start, otherwise the image creates `/data/git/.ssh` as root and the
app dies with `inspect authorized_keys failed: ... permission denied`.
`forgejo-db.sql` is not loadable by `sqlite3` (6145 `unistr()` calls); a
SQLite restore uses the copied `gitea.db` plus `-wal` and `-shm`.
