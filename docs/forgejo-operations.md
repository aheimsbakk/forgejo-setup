# Forgejo Operations

Day-2 notes for the instance installed by
`docs/forgejo-install-recipe.md`: what was verified after each change,
the problems found, how the Actions runner and the backups are set up,
and how client devices trust the certificate.

## Verification (first run)

- `curl http://<IP>/` returns HTTP 200, title
  `Forgejo: Beyond coding. We forge.`
- `ss -tlnp`: ports 80 and 2222 listen on `<IP>` only; no `[::]:80` or
  `[::]:2222` listener, so the public IPv6 address serves nothing.
- `ssh -p 2222 git@<IP>` reaches the Forgejo SSH server
  (`Permission denied (publickey)` — expected before any key is added).
- Container logs clean: SQLite initialized, web listening on 3000, SSH
  server on 2222, `AppURL(ROOT_URL)` matching the configured address.
- `getent ahostsv4 forgejo.local` returns the LAN address and
  `curl http://forgejo.local/` returns 200 (after changes 12–13).

## Verification (HTTPS, changes 18–23)

- `curl --cacert forgejo.crt https://<IP>/` returns HTTP 200, title
  `Forgejo: Beyond coding. We forge.`
- `curl http://<IP>/` returns 307 with `Location: https://<IP>/`. The
  redirect keeps the method, so old `http://` clone URLs keep working.
- `curl https://<IP>/` without `--cacert` fails: the self-signed
  certificate is rejected, which is the point — verification stays on
  everywhere.
- `ss -tlnp`: ports 80, 443 and 2222 listen on `<IP>` only; no `[::]`
  listener, so the public IPv6 address serves nothing.
- `ssh -p 2222 git@<IP>` still reaches the Forgejo SSH server
  (`Permission denied (publickey)`); the SSH path is untouched by TLS.
- Container logs clean: `Listen: https://0.0.0.0:3000`,
  `AppURL(ROOT_URL): https://<IP>/`, `Redirecting: 0.0.0.0:80`,
  `SSH server started on :2222`.
- Runner: log line `declared successfully` after the restart, runners
  API shows `idle`, and the `Declare` POST arrives on the https listener.
- CI: smoke run 5 `success` with both jobs `success`; the `ca-pin` job
  log shows `GIT_SSL_CAINFO=/etc/ssl/certs/forgejo-lan.crt`, the mounted
  certificate, and `git over https with pinned CA ok`.
- CI with external access: run 11 `success`. The runner downloaded
  `actions/checkout` from `data.forgejo.org`, the job pulled
  `node:20-bookworm` from the registry, and the checkout ran over HTTPS
  with the pinned certificate. A separate job installed `curl` with
  `apt-get` and read `/api/v1/version` from the instance.
- Runner trust is the mount: with the `/etc/ssl/certs` entry removed the
  daemon exits with `fail to invoke Declare … x509: certificate signed
  by unknown authority`; restored, it logs `declared successfully`.
- `SSL_CERT_FILE` on the runner changes nothing for actions: run 12 was
  `success` with the variable set, and `git ls-remote` inside the runner
  image still verified `data.forgejo.org` with `SSL_CERT_FILE` pointing
  at a nonexistent file.
- Backup: `systemctl start forgejo-backup.service` wrote a new dump; the
  newest dump holds 129 entries and none of them is the key or the
  certificate directory.
- `getent ahostsv4 forgejo.local` returns the LAN address and
  `curl --cacert forgejo.crt https://forgejo.local/` returns 200: the
  certificate covers the mDNS name as well as the address.

## Footguns found

- The Forgejo image runs its own OpenSSH daemon on port 22 *inside* the
  container. With `START_SSH_SERVER=true` and `SSH_LISTEN_PORT=22`, the
  built-in SSH server collides with it and the container crashes
  (`bind: address already in use`). Fix: `SSH_LISTEN_PORT=2222` and
  publish `2222:2222`. The compose file in this repo already reflects that.
- `forgejo dump` refuses to run as root: use
  `docker exec -u 1000 -w /data forgejo forgejo dump`. Without `-w /data`
  it tries to write to `/` and gets `permission denied`.
- `forgejo dump` aborts with `Failed to include repositories` when
  `/data/git/repositories` does not exist yet (fresh install, no repos).
  Create it before dumping. The backup script does.
- The dump file is named `forgejo-dump-<timestamp>.zip`, not `dump-*`.
- `forgejo admin user create` requires `--email`; without it: `email is
  not set`. With no mail server, any placeholder address works.
- Avahi announces every interface by default, including Docker bridges.
  Without `allow-interfaces=<lan-if>`, `<hostname>.local` can resolve to
  `172.18.0.1` and connections fail. Pin it to the LAN interface.
- Runner v13 renamed the register flag: `--token`, not
  `--registration-token`. `register` also needs an existing config file:
  run `generate-config` first.
- The token from `POST /api/v1/admin/actions/runners` (new API) does not
  work with `forgejo-runner register`. Use the deprecated global token:
  `GET /api/v1/admin/runners/registration-token`.
- The runner image runs as uid 1000 and cannot read the root-owned
  Docker socket. The compose file sets `user: "0:0"` for it.
- Forgejo 16 has no file-creation API (`/files/...` is 404); push files
  with git.
- Failed `forgejo-runner register` attempts can leave runner entries
  registered on the server. Delete them via
  `DELETE /api/v1/admin/actions/runners/<id>` before retrying.
- Forgejo calls itself through `LOCAL_ROOT_URL`, which defaults to
  `https://localhost:3000/` once `PROTOCOL=https` and `HTTP_ADDR` is
  `0.0.0.0`. A certificate that names only the LAN address makes
  Forgejo reject its own requests, so `gen-cert.sh` also puts
  `localhost`, `127.0.0.1` and the hostname in the SAN list.
- `CERT_FILE`/`KEY_FILE` are relative to `CustomPath`, which is inside
  the data dir and therefore inside every dump. Use absolute paths and
  keep the key outside `/srv/forgejo`.
- The runner trusts the instance only because the certificate is mounted
  into `/etc/ssl/certs`. Remove that mount and the daemon exits with
  `fail to invoke Declare … x509: certificate signed by unknown
  authority`.
- `SSL_CERT_FILE` is not used, and the usual warning about it does not
  apply here. Tested: setting it on the runner left third-party action
  downloads working, because the runner downloads actions with git, and
  git ignores the variable — pointing it at a nonexistent file still
  verified `data.forgejo.org`. It stays unset anyway: programs that do
  read it treat it as the whole trust store, which would leave the
  runner able to verify only this instance.
- The runner filters every job-container volume through `valid_volumes`.
  With `valid_volumes: []` a `--volume` in `container.options` is
  dropped with `[…] is not a valid volume, will be ignored` and the job
  runs without the file. List the exact source path.
- `GIT_SSL_CAINFO` with a relative path works for `git clone` and fails
  for `git push` with `Problem with the SSL CA cert (path? access
  rights?)`. Always give an absolute path.
- The HTTP redirector answers with 307, so a runner whose `.runner`
  file still holds an `http://` address keeps working — at the cost of
  one redirect per request. Switch the address instead of relying on it.
- The `debian:bookworm` job image has no git. A job that runs git needs
  an image that has it; `data.forgejo.org/forgejo/runner:13.1.0` is
  already on the machine and carries git 2.54.
- A `run:` step written as one unquoted scalar containing `: ` (for
  example `echo "… CA: ok"`) breaks workflow parsing. The run then shows
  a single failed job named after the commit message, with
  `runs_on: []` and no logs at all. Use a block scalar (`run: |`).
- Inside job containers `<hostname>.local` does not reach the machine.
  Docker's embedded DNS answers `.local` names itself, and the host
  resolver sends back link-local IPv6 addresses or the bridge gateway,
  so connections fail or land on the wrong address. Workflows must use
  the LAN address.

## CI runner (same box)

Operator decision: the Actions runner shares the machine with Forgejo.
Accepted risks and applied mitigations:

- The Docker socket is mounted into the runner container only. Job
  containers never receive it. Socket access is root-equivalent on the
  host; this is the main residual risk of the same-box design.
- No privileged jobs, no docker-in-docker (`privileged: false`).
  Container images in pipelines are built with buildah inside jobs.
- Job containers get `--memory=1g --cpus=1`; runner capacity is 2
  (machine has 2 vCPUs, 4 GB RAM, no swap — do not raise capacity).
- The runner publishes no ports; it only dials the instance, over HTTPS.
- The runner and its job containers pin the instance certificate
  (`/etc/ssl/certs/forgejo-lan.crt` plus `GIT_SSL_CAINFO`). The runner's
  `insecure` option stays `false`: verification is never turned off.
- Recommended but NOT configured: disable or gate workflows from fork
  pull requests. Only accounts the admin creates can push, so the
  current exposure is trusted users only.
- Off-machine copies of `/srv/forgejo-backups` are strongly advised
  with CI on the box: a compromised job could reach the backups.

## Access from job containers

Verified with a throwaway repository; no per-workflow setup was needed
for git.

- The instance certificate is mounted into every job container at
  `/etc/ssl/certs/forgejo-lan.crt` and `GIT_SSL_CAINFO` points there,
  so `git` over HTTPS works out of the box. Checked with an anonymous
  `git ls-remote` and with the Actions token
  (`git -c http.extraheader="AUTHORIZATION: bearer $GITHUB_TOKEN"`).
- `GIT_SSL_CAINFO` only covers git. What else trusts the instance
  depends on the image:
  - OpenSSL-based tools (curl, wget, git) already trust it in Debian
    job images, because the certificate sits in `/etc/ssl/certs`.
    Tested: `curl` returned 200 and `git ls-remote` worked with the
    mount alone, the file name made no difference, and the same file
    mounted outside that directory was rejected.
  - Node keeps its own CA store. It still failed with
    `DEPTH_ZERO_SELF_SIGNED_CERT` after `update-ca-certificates`, and
    returned 200 with `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/forgejo-lan.crt`.
  - Python `requests` reads the `certifi` bundle rather than the system
    one, so it needs `REQUESTS_CA_BUNDLE`.
- Running `update-ca-certificates` in a job adds the certificate to the
  bundle file (142 entries to 143) and changes nothing for Node. It
  needs root, and it only lasts for that one job container.
- Address jobs by the LAN IP. Inside a job container `forgejo.local`
  goes through Docker's embedded DNS to the host resolver and comes
  back as a link-local IPv6 address or the bridge gateway, so
  connections fail. The IP is in the certificate, so TLS is fine.
- Job containers reach the instance and the internet. Verified: the
  runner downloaded `actions/checkout` from `data.forgejo.org`, a job
  pulled `node:20-bookworm` from the container registry, and
  `apt-get install` worked inside a job.
- Host paths other than the certificate are not mountable: the runner
  only allows what `valid_volumes` lists.

## Backup

- Daily at 03:30 UTC via `forgejo-backup.timer` (systemd,
  `Persistent=true` so a missed run fires at next boot).
- `forgejo dump` produces one zip per run containing the SQLite
  database, repositories, config and LFS data — a full restore point.
- Zips are moved out of the live data dir to `/srv/forgejo-backups`.
- The TLS private key lives in `/srv/forgejo-certs`, outside the data
  dir, so dumps never contain it (checked against the newest dump).
  Restoring onto a new machine therefore needs a fresh certificate from
  `gen-cert.sh` and new pins on every client.
- Retention: exactly the 7 newest dumps; the script deletes the rest.
- Remote copy of `/srv/forgejo-backups` is planned by the operator and
  not part of this setup. Same-VM backups survive bad writes, not disk
  loss.

Restore from a dump:

```bash
unzip forgejo-dump-<timestamp>.zip -d /tmp/forgejo-restore
cd /tmp/forgejo-restore
# restore.sh recreates config, data and database; run it as the
# container user after stopping the app, then start it again.
docker-compose -f /opt/forgejo/docker-compose.yml stop forgejo
docker run --rm -u 1000 -v /srv/forgejo:/data -v /tmp/forgejo-restore:/restore \
  -w /restore codeberg.org/forgejo/forgejo:16.0.5 ./restore.sh
docker-compose -f /opt/forgejo/docker-compose.yml start forgejo
```

Note: the restore procedure is documented but not yet tested end-to-end.


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
4. Verify: `curl https://<IP>/` returns 200 without any insecure flag.

Browsers accept the certificate on first use instead, but the warning
returns whenever the certificate is regenerated.

## Pending

- Remote copy of `/srv/forgejo-backups` (operator will set up).
- Test the restore procedure end-to-end on a scratch machine.
- Certificate renewal: the current certificate runs until 2031-10-08.
  Re-run `gen-cert.sh` before that date and re-pin every client, since a
  new certificate invalidates the old pins.
