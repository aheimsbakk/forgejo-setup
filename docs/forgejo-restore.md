# Restore a Forgejo dump

Restores an instance from a dump made by `/opt/forgejo/backup.sh`. Run
the steps on the target over SSH.

Forgejo 16.0.5 has no restore command, and its dumps contain no
`restore.sh`. A dump holds four top-level entries. Restoring is a file
copy:

| Dump entry | Goes to |
|---|---|
| `data/` | `/srv/forgejo/gitea/` (`APP_DATA_PATH`) |
| `repos/` | `/srv/forgejo/git/repositories/` (`[repository] ROOT`) |
| `app.ini` and `data/conf/app.ini` | not used — the compose file rewrites the settings into `conf/app.ini` at every start |
| `forgejo-db.sql` | not used with SQLite |

The SQLite database arrives inside `data/` as `gitea.db` together with
`gitea.db-wal` and `gitea.db-shm`. Copy all three; the app replays the
log at start. `forgejo-db.sql` exists to move the instance to another
database engine: it calls the app's own `unistr()` function 6145 times,
so `sqlite3` rejects it with `no such function: unistr`.

## Before you start

- The dump's `app.ini` and its copy at `data/conf/app.ini` both have
  `SECRET_KEY` and `PASSWD` blanked. That costs nothing here: the compose
  file sets `SECRET_KEY_URI=file:/etc/forgejo/secret_key` and mounts that
  file read-only, and the image writes every `FORGEJO__*` variable into
  `conf/app.ini` at each start. So the settings and the key come from the
  compose file and from `/opt/forgejo/secrets/secret_key`, not from the
  dump. That key file is in no dump and not in git. It needs its own
  backup, and a restore onto a new machine needs it copied there by hand —
  without it the values the database stores encrypted, a two-factor seed
  among them, cannot be read.
- The certificate is not in the dump. On the same machine it is already
  in `/srv/forgejo-certs`. On a new machine run `gen-cert.sh` and re-pin
  every client.
- The runner keeps its registration in `/srv/forgejo-runner`, outside the
  dump. On the same machine it reconnects on its own; on a new machine
  register it again.
- Container registry blobs are not in a dump (see change 37). The
  restored registry lists the old versions and pulling one returns 404.
  Package cleanup rules clear the records; CI re-pushes the images.

## Steps

1. Stop the app. The runner can stay up; it only loses its connection.

   ```bash
   docker-compose -f /opt/forgejo/docker-compose.yml stop forgejo
   ```

2. Move the live data dir aside. It is your fallback.

   ```bash
   mv /srv/forgejo /srv/forgejo.old
   ```

3. Unpack the dump and copy it into the layout the app expects. The
   target has no `unzip`; Debian 13 ships `python3`.

   ```bash
   D=/srv/forgejo-backups/forgejo-dump-<timestamp>.zip
   rm -rf /tmp/restore && mkdir -p /tmp/restore
   python3 -m zipfile -e "$D" /tmp/restore
   mkdir -p /srv/forgejo/gitea /srv/forgejo/git/repositories
   cp -a /tmp/restore/data/. /srv/forgejo/gitea/
   cp -a /tmp/restore/repos/. /srv/forgejo/git/repositories/
   ```

4. Put the config with the real secrets back. Step 3 copied the dump's
   blank-key `app.ini`; this replaces it.

   ```bash
   cp /srv/forgejo.old/gitea/conf/app.ini /srv/forgejo/gitea/conf/app.ini
   ```

5. Hand the tree to the container user before the first start. If
   `/srv/forgejo/git/.ssh` does not exist, the image creates it as root
   and the app stops at start with `inspect authorized_keys failed: open
   /data/git/.ssh/authorized_keys: permission denied`.

   ```bash
   chown -R 1000:1000 /srv/forgejo
   ```

6. Start the app and check it answers:

   ```bash
   docker-compose -f /opt/forgejo/docker-compose.yml start forgejo
   curl -s --cacert /srv/forgejo-certs/forgejo.crt https://forgejo.local/api/v1/version
   ```

7. Check the two things a file copy can get wrong: the database and the
   repositories. A user token works whatever the account settings are.
   Password basic auth returns 401 while the account has two-factor
   enabled, because the API cannot run the second step.

   ```bash
   GIT_SSL_CAINFO=/srv/forgejo-certs/forgejo.crt \
     git ls-remote https://forgejo.local/<owner>/<repo>.git
   curl -s --cacert /srv/forgejo-certs/forgejo.crt \
     -H "Authorization: token <token>" \
     "https://forgejo.local/api/v1/repos/search?limit=5"
   ```

   The certificate variable is needed on the target itself: the machine
   does not trust its own self-signed certificate through the system
   store.

8. When the checks pass, remove the fallback: `rm -rf /srv/forgejo.old`.

## What a restore does not bring back

- Container registry blobs: records without files, pulls return 404.
- The TLS private key, by design. A restore onto a new machine needs
  `gen-cert.sh` and new pins on every client.
- The `SECRET_KEY` file at `/opt/forgejo/secrets/secret_key`, also by
  design. Copy it to the new machine before the first start, or the app
  exits at startup.
- Runner registration, job cache and `/srv/forgejo-runner` in general.

## Tested state

These steps were run against a scratch copy of a real dump on the target,
in a throwaway container on `127.0.0.1:3001`; the measured results are in
the "Restore drill" section of
`docs/forgejo-backup-restore-verification.md`. They have not been run
against the live data dir.
