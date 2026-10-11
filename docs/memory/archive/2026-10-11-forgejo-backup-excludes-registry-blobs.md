---
topic: "Forgejo backup: dump excludes registry blobs, package rows stay"
importance: high
category: decision
tags: [forgejo, backup, dump, registry, retention]
created: 2026-10-11T20:53:02Z
model: kompis/qwen3.8-flash-next-iq3_s
---

`forgejo/backup.sh` runs `forgejo dump --skip-package-data`: registry
blobs are rebuildable by CI and were 22 MB of a 95 MB dump (85 MB zip to
63 MB). Daily dump at 03:30 UTC into `/srv/forgejo-backups`, 7 newest
kept; the operator adds the remote copy themselves. The database dump
still carries `package`/`package_blob` rows, so a restore lists versions
whose files are gone and their pulls fail — the operator's package
cleanup rules clear those records, and there is no API for the rules,
only the web UI. Check a dump with `grep -c data/packages <dump>.zip`
(expect 0; zip names are uncompressed and the target has no unzip).
