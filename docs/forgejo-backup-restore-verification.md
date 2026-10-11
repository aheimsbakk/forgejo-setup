# Forgejo Backup And Restore Verification

Measured results for the backup script, the dump format, the restore
procedure and the global encryption key. The instance setup and the CI
measurements are in `docs/forgejo-operations-verification.md`; the
problems found along the way are in `docs/forgejo-footguns.md`.

## Registry blobs out of the dump (change 37)

Two runs on the same day, with 18 registry blobs live in
`/srv/forgejo/gitea/packages` (22 MB) for both.

- Full dump `forgejo-dump-1791750707.zip`: 85,498,046 bytes, 3007
  entries, 18 files under `data/packages/` totalling 22,446,394 bytes
  uncompressed.
- Dump after the change `forgejo-dump-1791751798.zip`: 63,054,363 bytes,
  2989 entries, 0 files under `data/packages/`. The run logs
  `cmd/dump.go:374:runDump() [I] Skipping package data`.
- What a dump is made of (full run, uncompressed): `repos/` 63.7 MB over
  2045 files, `data/packages/` 22.4 MB over 18 files, `data/gitea.db`
  plus `-wal` 7.4 MB, `forgejo-db.sql` 1.4 MB — 95.1 MB total. The
  registry is the second largest part, not the first.
- The package records survive the skip: `forgejo-db.sql` in the new dump
  still holds 1 `package`, 8 `package_version`, 21 `package_file`,
  18 `package_blob` and 50 `package_property` rows. A restore therefore
  has records without files.
- Listing a dump without unzip: `grep -c data/packages <dump>.zip`
  returns 0 for the new dump and 36 for the full one. Zip entry names are
  stored uncompressed, so the target needs no `unzip` (it has none;
  `python3` is available).
- Retention held: 6 dumps before the run, 7 after, nothing deleted.
- Not tested: restoring a dump that lacks the blobs. The expected result
  from the schema is a registry that lists versions and fails their
  pulls; the package cleanup rules are the operator's way to clear the
  records. See the restore drill below — it measured this.

## Restore drill (documentation fix, no target change)

Method: the newest dump (`forgejo-dump-1791751798.zip`, the first one
without registry blobs) was unpacked to a scratch data dir
`/tmp/rt/data` and started in a throwaway container `rt-forgejo` of the
same image, published on `127.0.0.1:3001` only. The live instance and its
data dir were not touched. Container and scratch dir removed afterwards;
`forgejo` and `forgejo-runner` were still `Up` and `/api/v1/user` still
returned 200 after the drill.

- Dump shape: four top-level entries — `app.ini`, `data/`, `repos/`,
  `forgejo-db.sql`. No `restore.sh`. 73 repository directories.
- Paths read from the dump's own `app.ini`: `WORK_PATH = /data/gitea`,
  `APP_DATA_PATH = /data/gitea`, `[repository] ROOT =
  /data/git/repositories`, `[database] PATH = /data/gitea/gitea.db`.
  So `data/` → `/srv/forgejo/gitea/` and `repos/` →
  `/srv/forgejo/git/repositories/`.
- First start failed: `mustInitCtx … ssh.Init(ctx) failed: inspect
  authorized_keys failed: open /data/git/.ssh/authorized_keys: permission
  denied`. Cause: the tree was started before it was chowned, and the
  image had created `/data/git/.ssh` as `root` mode 700. The dump does not
  contain `git/.ssh`. Pre-creating it and `chown -R 1000:1000` over the
  data dir fixed it; the second start was clean.
- Database: `PING DATABASE sqlite3` then `ORM engine initialization
  successful` from the copied `gitea.db` plus `gitea.db-wal` and
  `gitea.db-shm`. No `[E]` or `[F]` lines in the start log.
- Serving: `/` returned 200 and `/api/v1/version` returned
  `16.0.5+gitea-1.22.0`.
- Repositories: `/api/v1/repos/search` listed the restored repos;
  `git ls-remote http://127.0.0.1:3001/agent/container-build-test.git`
  returned `ad049345c1395cc9cc633a208f23ec516fa4c70d refs/heads/main`,
  the commit the pipeline pushed.
- Authentication: a user token returned 200 on the restored instance and
  on the live one. Password basic auth returned 401 on both at drill
  time: the admin account had a `two_factor` row, so the password was
  verified (`last_login` moved) and the request was then refused — the
  API cannot run the second step. The operator removed two-factor later
  the same day; the same calls then returned 200 (`/api/v1/user`,
  `/api/v1/admin/users`, `POST /api/v1/admin/runners/registration-token`)
  and the `two_factor` table was empty. A token is the check that does
  not depend on this setting.
- Registry after change 37, measured on the restored instance: the tag
  list came back from the restored database with 7 tags (`latest` plus 6
  commit tags), and the layer blob
  `sha256:81a4c91cb19b0a1493ec6161d9da1b4bfcd11a1bc4706dd1b50741ff53c4b90d`
  returned 404. Records without files, as expected.
- Secrets: the dump's `app.ini` has `SECRET_KEY =` and `PASSWD =` empty,
  and so did the live `/srv/forgejo/gitea/conf/app.ini` — the instance had
  no global key at all. Change 38 below fixed that. The restored instance
  left the empty value in place and logged nothing about it. The restored
  database held 1 `two_factor` row (uid 1, the admin), 3
  `oauth2_application`, 3 `access_token`, 0 `login_source`, 0 `webhook`.
  Access tokens are stored hashed and kept working; a two-factor seed is
  the value that needs the global key, which is why the key now comes from
  a file outside the data dir.
- `forgejo-db.sql` is not a SQLite restore file: 6145 `unistr(` calls,
  and `sqlite3.executescript` fails with `no such function: unistr`.

## Global encryption key set (change 38)

Measured on the target, 2026-10-11.

- Before: `[security] SECRET_KEY` in `/srv/forgejo/gitea/conf/app.ini`
  held a value of length 0. `INTERNAL_TOKEN` (105) and `[oauth2]
  JWT_SECRET` (43) were set; only the global key was missing. Nothing in
  the database needed it: `two_factor`, `login_source` and `webhook` were
  all 0 rows after the operator turned two-factor off.
- Key file: `/opt/forgejo/secrets/secret_key`, 43 bytes, mode 640
  `root:1000`, parent directory mode 750. Generated inside the app
  container with `forgejo generate secret SECRET_KEY`. The reproduce
  procedure uses `docker run --rm --entrypoint /usr/local/bin/forgejo
  codeberg.org/forgejo/forgejo:16.0.5 generate secret SECRET_KEY`
  instead, because it runs before the first start; both produce 43 bytes.
- Config after: `app.ini` `[security]` shows `SECRET_KEY` length 0 and
  `SECRET_KEY_URI` length 28 (`file:/etc/forgejo/secret_key`). The image
  wrote the line itself at start: `Settings saved to:
  "/data/gitea/conf/app.ini"`.
- Read access: `docker exec -u 1000 forgejo sh -c "wc -c <
  /etc/forgejo/secret_key"` returned 43, so the container user reads the
  read-only mount.
- Health after `docker-compose up -d forgejo` recreated the container: 0
  `[E]`/`[F]` lines in the app log; `/api/v1/version` returned
  `16.0.5+gitea-1.22.0`; basic auth `/api/v1/user` 200; token auth 200;
  `/` 200; `http://` 307 to `https://forgejo.local/`; `git ls-remote` over
  HTTPS returned `ad049345c1395cc9cc633a208f23ec516fa4c70d`.
- Runner through the recreate: 3 `failed to fetch task` errors at the
  moment the app went down (`connection reset by peer`, `unexpected EOF`),
  0 afterwards, no restart needed.
- Dumps and the key: a fresh dump after the change has no entry whose name
  contains `secret_key`, and its `app.ini` carries only the 28-character
  path. `/opt/forgejo/secrets` is outside `/srv/forgejo`, so no dump holds
  the key.
- Secrets a dump does carry, found while checking the above: `app.ini` in
  the dump holds `INTERNAL_TOKEN` (105 characters) and `[oauth2]
  JWT_SECRET` (43), byte-identical to the live file. Only `SECRET_KEY` and
  the database `PASSWD` are blanked. Dumps are mode 600 owned by uid 1000
  in a root-owned directory, so they are access-controlled; a remote copy
  must go to encrypted storage.
- Not verified: no stored value is encrypted with the new key yet, so the
  measured effect is that the app loads it. The startup failure when both
  `SECRET_KEY` and `SECRET_KEY_URI` have a value is documented behaviour,
  not reproduced here.
