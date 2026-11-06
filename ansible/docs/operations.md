# Operations

Day-2 notes for an instance installed by this playbook: certificate
trust and renewal, backups, and disk cleanup. Restore is in
`docs/restore.md`; the Actions runner and registry are in
`docs/ci-and-registry.md`.

## Client trust (one time per device)

Every device that connects must trust the certificate once, or it will
reject the instance. The playbook fetches the public half to
`certs/<inventory-host>/forgejo.crt` in this folder (per host, so
several instances do not overwrite each other's copy). Check the
fingerprint first:

```bash
openssl x509 -in certs/forgejo/forgejo.crt -noout -fingerprint -sha256
```

and compare it with what `gen-cert.sh` printed when it created the
certificate.

1. Copy `forgejo.crt` to the device.
2. Add it to that device's trust store:
   - Debian/Ubuntu: `cp forgejo.crt /usr/local/share/ca-certificates/forgejo-lan.crt && sudo update-ca-certificates`
   - Windows: `certutil -addstore ROOT forgejo.crt` (elevated), or
     import it under "Trusted Root Certification Authorities"
   - macOS: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain forgejo.crt`
   - Android / iOS: install the certificate as a trusted CA from the
     device settings
3. For a single git repository instead of the whole system:
   `git -C <repo> config http.sslCAInfo /absolute/path/forgejo.crt`
4. Verify: `curl https://<lan_name>/` returns 200 without any insecure
   flag. Browse by that name: the address also serves, but the web UI
   shows a mismatch warning there because the name is the canonical URL.

Browsers accept the certificate on first use instead, but the warning
returns whenever the certificate is regenerated.

## Certificate

- Created on the target by `/opt/forgejo/gen-cert.sh`, which the
  playbook deploys and runs. The private key never leaves the machine.
- Subject alternative names: LAN address, `127.0.0.1`, the LAN name,
  `localhost`, and the hostname. Forgejo calls itself through
  `LOCAL_ROOT_URL`, so the certificate must name loopback hosts too.
- Valid five years. An existing pair that still covers the current
  address and name is kept; the script is safe to re-run.
- Renewal invalidates every pin: re-run `gen-cert.sh` and re-import the
  new `.crt` on each device, the runner container, and the engine's
  `/etc/containers/certs.d/<lan_name>/forgejo.crt`.
- `gen-cert.sh` reads `LAN_IP` and `LAN_NAME` from `/opt/forgejo/.env`,
  which the playbook writes. Keep that file in sync by re-running the
  playbook instead of editing it by hand.

## Backup

- Daily at 03:30 UTC via `forgejo-backup.timer` (systemd,
  `Persistent=true` so a missed run fires at next boot).
- `forgejo dump` produces one zip per run: SQLite database,
  repositories, config, LFS data. Zips are named
  `forgejo-dump-<timestamp>.zip` and moved to `/srv/forgejo-backups`.
- Retention: exactly the 7 newest; `backup.sh` deletes the rest.
- Container registry blobs are left out (`--skip-package-data`): CI
  rebuilds the images and the blobs dominate dump size. The package
  records stay in the database, so after a restore the registry lists
  versions whose files are gone and pulls return 404. Package cleanup
  rules (web UI: owner settings → packages → cleanup rules) clear those
  records; the pipeline re-pushes the images it needs.
- Check a dump left the blobs out (zip entry names are stored
  uncompressed, so the target needs no unzip):

  ```bash
  grep -c data/packages /srv/forgejo-backups/<dump>.zip   # expect 0
  ```

- Run one by hand:

  ```bash
  systemctl start forgejo-backup.service
  ```

- Not in any dump, by design: the TLS private key (`/srv/forgejo-certs`)
  and the global encryption key (`/opt/forgejo/secrets/secret_key`,
  mode 640 `root:1000`). Both need backups of their own. Losing the
  encryption key makes the encrypted values in the database — a
  two-factor seed among them — unreadable forever.
- Backups stay on the machine. Same-machine backups survive bad writes,
  not disk loss; copy `/srv/forgejo-backups` off-box yourself. With the
  Actions runner on the box this matters: a compromised job could reach
  the backups.

## Disk cleanup

- Daily at 04:15 UTC via `forgejo-cleanup.timer` — after the backup, so
  a restore point exists before anything is deleted.
- Removes: untagged images; tagged images no container references, once
  unused for 7 days; containers outside the podman kube stack stopped
  7 days or more; unused networks older than 7 days.
- Never removes: volumes (job data), stack containers, and any image
  named by `/opt/forgejo/kube/*.yaml` — the protected list is read from
  those files at run time, so it follows version bumps.
- Grace tracking: `/var/lib/forgejo-cleanup/unused-images.tsv` records
  the day each unused image was first seen; rewritten every run. The
  engine's own `until=` filter matches build dates, not last use, so it
  cannot do this. The first cleanup run deletes nothing; it only starts
  the record.
- Each run logs `podman system df` before and after:
  `journalctl -u forgejo-cleanup.service`.
- A run that cannot read the kube directory removes nothing and fails.

## Known gaps

- The stock `podman-kube@.service` template has no `Restart=` setting.
  If the pod service stops (manual stop, or the host's unit fails), it
  stays down until an operator starts it. The leading fix — a drop-in
  with `Restart=always` and `RestartSec=10` — is untested, so the
  playbook does not apply one.
- Off-machine backup copies are the operator's job.
