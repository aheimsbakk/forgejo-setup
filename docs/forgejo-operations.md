# Forgejo Operations

Day-2 notes for the instance installed by `docs/forgejo-install-recipe.md`:
backups and restores, disk cleanup, and how client devices and the Docker
daemon trust the certificate. The problems found are in
`docs/forgejo-footguns.md`; the runner, registry and job-container setup is
in `docs/forgejo-ci-and-registry.md`; the measured results are in
`docs/forgejo-operations-verification.md` and
`docs/forgejo-backup-restore-verification.md`.

## Backup

- Daily at 03:30 UTC via `forgejo-backup.timer` (systemd,
  `Persistent=true` so a missed run fires at next boot).
- `forgejo dump` produces one zip per run containing the SQLite
  database, repositories, config and LFS data.
- The container registry is left out: the script passes
  `--skip-package-data`. Measured here, one run went from 85 MB to 63 MB
  by dropping 18 registry blobs (22 MB uncompressed). Repositories are the
  larger part of a dump (64 MB here). CI rebuilds the images, so the
  blobs are the one part of application state a restore does not
  reproduce.
- The package records stay in the database dump. After a restore the
  registry lists versions whose files are gone and pulls for them fail.
  The package owner's cleanup rules clear those records, and the pipeline
  re-pushes the images it needs. Rules live in the web UI (owner settings
  → packages → cleanup rules); there is no API route, so they are not part
  of the reproduce procedure. Allowed values are fixed: keep 0, 1, 5, 10,
  25, 50 or 100 versions; remove versions older than 0, 7, 14, 30, 60, 90
  … days. The container type always keeps `latest`. The cleanup job
  (`cron.cleanup_packages`) is on by default.
- Check that a dump leaves the blobs out with
  `grep -c data/packages /srv/forgejo-backups/<dump>.zip` — expect `0`.
  Zip entry names are stored uncompressed, so the target needs no unzip.
- Zips are moved out of the live data dir to `/srv/forgejo-backups`.
- The TLS private key lives in `/srv/forgejo-certs`, outside the data
  dir, so dumps never contain it (checked against the newest dump).
  Restoring onto a new machine therefore needs a fresh certificate from
  `gen-cert.sh` and new pins on every client.
- The global `SECRET_KEY` lives in `/opt/forgejo/secrets/secret_key`
  (directory 750, file 640 `root:1000`), mounted read-only at
  `/etc/forgejo/secret_key` and named by `SECRET_KEY_URI`. `app.ini`
  keeps `SECRET_KEY` empty because the two options are mutually
  exclusive. Like the TLS key, this file is outside the data dir, so no
  dump contains it and it needs a backup of its own.
- Retention: exactly the 7 newest dumps; the script deletes the rest.
- Remote copy of `/srv/forgejo-backups` is planned by the operator and
  not part of this setup. Same-VM backups survive bad writes, not disk
  loss.

### Restore from a dump

The procedure is in `docs/forgejo-restore.md`: which dump entry goes
where, the config and certificate you must keep out of the copy, and the
checks that prove the database and the repositories came back.


## Disk cleanup

- Daily at 04:15 UTC via `forgejo-cleanup.timer` (`Persistent=true`),
  45 minutes after the backup, so a restore point exists before anything
  is deleted.
- Removes: untagged images; tagged images no container references, once
  they have been unused for 7 days; containers outside the compose stack
  stopped for 7 days or more; unused networks and the build cache older
  than 7 days.
- Never removes: volumes (they can hold job data), containers labelled
  as part of the compose stack, and any image named by
  `/opt/forgejo/docker-compose.yml`. The protected image list is read
  from the compose file at run time, so it follows version bumps.
- Grace tracking: `/var/lib/forgejo-cleanup/unused-images.tsv` records
  the day each unused image was first seen. An image is removed only
  after 7 days in that file. The file is rewritten every run, so it
  stays small.
- A run that cannot read the compose file removes nothing and exits 1.
- The first run deletes nothing; it only starts the grace record.
- Each run logs `docker system df` before and after:
  `journalctl -u forgejo-cleanup.service`.
- Verified on the first target (changes 24–26): the first run deleted
  nothing and wrote grace records for `debian:bookworm` and
  `node:20-bookworm`; a throwaway container and a throwaway image with
  a back-dated record were both removed in a later run; the stack
  images, the running containers and the `forgejo_default` network were
  untouched. `docker system df` showed 1.451 GB of images with
  1.212 GB (83%) reclaimable.


## Client trust (one time per device)

Every device that connects must trust the certificate once, or it will
reject the instance. Check the fingerprint first
(`openssl x509 -in forgejo.crt -noout -fingerprint -sha256`) and compare
it with what `gen-cert.sh` printed.

1. Copy `tmp/certs/forgejo.crt` to the device.
2. Add it to that device's trust store:
   - Debian/Ubuntu: `cp forgejo.crt /usr/local/share/ca-certificates/forgejo-lan.crt && sudo update-ca-certificates`
   - Windows: `certutil -addstore ROOT forgejo.crt` (elevated), or
     import it under "Trusted Root Certification Authorities"
   - macOS: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain forgejo.crt`
   - Android / iOS: install the certificate as a trusted CA from the
     device settings
3. For a single git repository instead of the whole system:
   `git -C <repo> config http.sslCAInfo /absolute/path/forgejo.crt`
4. Verify: `curl https://forgejo.local/` returns 200 without any
   insecure flag. Browse by that name: the address is not the canonical
   URL and shows a mismatch warning in the web UI (change 30).

Browsers accept the certificate on first use instead, but the warning
returns whenever the certificate is regenerated.

## Pending

- Remote copy of `/srv/forgejo-backups` (operator will set up).
- Test the restore procedure end-to-end on a scratch machine.
- Certificate renewal: the current certificate runs until 2031-10-08.
  Re-run `gen-cert.sh` before that date and re-pin every client, since a
  new certificate invalidates the old pins.
