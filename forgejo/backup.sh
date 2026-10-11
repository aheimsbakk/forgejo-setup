#!/bin/bash
# Daily consistent Forgejo backup using the built-in dump command.
# The zip contains the SQLite database, repositories, config and LFS
# data, so it is a restore point, not just the database.
# Container registry blobs are excluded (--skip-package-data): CI
# rebuilds the images, and they were 22 MB of a 95 MB dump on the first
# target. The database still holds the package rows, so a restore lists
# package versions whose files are absent; the owner's package cleanup
# rules remove those entries after a restore or a CI run.
# Remote copy of /srv/forgejo-backups is handled separately by the
# operator.
set -euo pipefail

BACKUP_DIR=/srv/forgejo-backups
RETENTION=7 # keep the newest N dumps

mkdir -p "$BACKUP_DIR"

# The dump (forgejo-dump-<timestamp>.zip) is written to the exec
# working dir; force it to /data (the live data dir), which is
# /srv/forgejo on the host. Run as the container's uid (1000):
# Forgejo refuses to run as root, and uid 1000 cannot write "/".
# Move the zip out so the data dir stays clean and backups survive a
# data-dir wipe.
# forgejo dump aborts if the repositories dir does not exist yet (fresh
# install, no repos). Create it idempotently before dumping.
docker exec -u 1000 forgejo mkdir -p /data/git/repositories
docker exec -u 1000 -w /data forgejo forgejo dump --skip-package-data >/dev/null
find /srv/forgejo -maxdepth 1 -name 'forgejo-dump-*.zip' -exec mv {} "$BACKUP_DIR/" \;

# Keep exactly the newest RETENTION dumps; delete the rest.
# mapfile avoids a pipefail failure when the dir holds no dumps yet.
mapfile -t old_dumps < <(ls -1t "$BACKUP_DIR"/forgejo-dump-*.zip 2>/dev/null |
	tail -n +$((RETENTION + 1)))
if ((${#old_dumps[@]} > 0)); then
	rm -- "${old_dumps[@]}"
fi
