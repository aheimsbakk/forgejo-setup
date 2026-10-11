# Forgejo Operations

Day-2 notes for the instance installed by
`docs/forgejo-install-recipe.md`: the problems found, how the Actions
runner, the container registry and the backups are set up, and how client
devices and the Docker daemon trust the certificate. The measured results
behind each change set are in
`docs/forgejo-operations-verification.md`.

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
  an image that has it. Change 33 made the default `node:20-bookworm`
  and change 34 moved it to `node:24-bookworm` (Node 20 went
  end-of-life 2026-04-30; its image is frozen and gets no security
  fixes). The default lives in the runner's registration file
  `/srv/forgejo-runner/.runner`, not in `config.yaml`. When picking an
  image line, check its support status first.
- A `run:` step written as one unquoted scalar containing `: ` (for
  example `echo "… CA: ok"`) breaks workflow parsing. The run then shows
  a single failed job named after the commit message, with
  `runs_on: []` and no logs at all. Use a block scalar (`run: |`).
- Inside job containers `<hostname>.local` did not reach the machine
  reliably. Two paths, two failures. On the default bridge a container
  asks the LAN router, and no DNS server has a `.local` zone: the lookup
  returns nothing (`ENOTFOUND` for Node). On a user-defined network —
  compose services and the per-job networks the runner creates — Docker
  forwards to the host's systemd-resolved, which answers the machine's
  own mDNS name *synthetically* with every address it has: the LAN
  address first, then `172.18.0.1`, `172.17.0.1` and the link-local IPv6
  addresses. Connections then fail or land on a bridge gateway. Fixed by
  change 27: `--add-host=forgejo.local:<IP>` puts the name in every job
  container's `/etc/hosts`, which the resolver reads before it queries
  DNS, so the answer is the LAN address alone.
- The runner and Forgejo containers resolved `<hostname>.local` to all of
  the machine's addresses (LAN address first, then the Docker bridge
  gateways), because they get the host resolver's synthetic answer.
  Nothing in the stack uses the name — the runner dials the address in
  `.runner`, Forgejo calls itself through `localhost` — so this was a
  hazard, not a fault. Change 28 pins the name with `extra_hosts` on both
  compose services; the lookup now returns the LAN address alone.
- `/srv/forgejo-runner/config.yaml` is generated. Re-running
  `forgejo-runner generate-config` on a live target wipes the
  `capacity`, `options`, `envs` and `valid_volumes` edits, including the
  `--add-host` entry; recipe step 16 has to be replayed after it.
- `docker image prune --filter until=168h` does not mean "unused for a
  week". `until` matches the image's build date, so a freshly pulled
  image is usually months old and is deleted the day it arrives.
  `docker container prune --filter until=` matches the container's
  creation time, not the time it stopped. Docker keeps no last-used
  time, so `cleanup.sh` maintains its own grace record.
- `docker image prune -a` also removes the pinned stack images when the
  compose stack is stopped, because nothing references them then.
  `cleanup.sh` protects the images named in the compose file.
- Forgejo serves one canonical URL (`ROOT_URL`) and warns every client
  whose Host header differs from it: "This Forgejo instance is
  configured to be served on …". There is no host allow-list, so
  browsing by the other host always shows the banner. Change 30 makes
  the mDNS name canonical; the address still serves content and git,
  browsers just see the warning there.
- The runner's Go client and the runner's git have different trust
  stores. The Go daemon trusts the loose certificate in
  `/etc/ssl/certs`; git (OpenSSL) reads the `ca-certificates.crt`
  bundle and rejects the instance with `SSL certificate OpenSSL verify
  result: self-signed certificate (18)`. That matters because the
  runner downloads workflow actions with git. The runner image is
  Alpine without `update-ca-certificates`, so the compose command
  builds a merged bundle (public CAs + instance certificate) at every
  start and `GIT_SSL_CAINFO` points at it.
- The runner's action cache (`/srv/forgejo-runner/.cache/act`) is not
  invalidated when `DEFAULT_ACTIONS_URL` changes: cached clones keep
  the old remote. Delete the directory after changing the setting.
- The Docker daemon has its own registry trust store: files in
  `/etc/docker/certs.d/<registry-host>/`. The runner's `/etc/ssl/certs`
  mount and the job containers' `GIT_SSL_CAINFO` /
  `NODE_EXTRA_CA_CERTS` do not cover it. Without a certificate there, a
  job whose `container.image` comes from the instance registry fails
  before any authorization question: `docker pull … tls: failed to
  verify certificate: x509: certificate signed by unknown authority`.
  Change 36 put the certificate there as
  `/etc/docker/certs.d/forgejo.local/forgejo.crt` — the same file name
  this setup uses elsewhere, not Docker's example name `ca.crt`. No
  daemon restart is needed.
- That directory is read by extension, not by fixed name
  (`registry/registry.go` `ReadCertsDirectory`): `*.crt` is added to the
  daemon's trust roots, `*.cert`/`*.key` are a client certificate pair
  and must be paired, and any other name is ignored. Measured on the
  target: `forgejo.crt` pulls fine, `ca.pem` fails with the same x509
  error. The suffix is load-bearing; the stem is free. The base directory
  is a compile-time constant on Linux (`/etc/docker/certs.d`), with no
  daemon flag to move it in 26.1.5.
- A 401 from the OCI endpoints is the authentication challenge, not a
  refusal. `GET /v2/…/manifests/<tag>` returns 401 with a
  `WWW-Authenticate: Bearer realm="…/v2/token"` header; fetching a token
  from that realm without credentials returns one, and the manifest and
  blobs then return 200. Reading the first 401 as "private" is wrong.
- The Actions token authenticates against the registry (`GET /v2/` with
  `GITHUB_TOKEN` returns 200) but cannot push. The registry token Forgejo
  mints for the job carries `UserID:-2` — the built-in `forgejo-actions`
  user — and an empty `Scope`, and `DeterminePackageAccessMode` gives
  that user read at most; the function carries the upstream comment
  `// TODO: ActionUser permission check`. The write permission the
  Actions token does have on its own repository is implemented in
  `GetActionRepoPermission`, which only the git HTTP handler calls.
  Pushing needs a user token with `write:package`, kept in a repository
  secret.
- `buildah` inside a job container needs three things: the environment
  variable `_CONTAINERS_ROOTLESS_UID=1000` (otherwise it re-execs into a
  user namespace and seccomp returns `unshare(CLONE_NEWUSER): Operation
  not permitted`), `vfs` storage (`mount()` is EPERM and there is no
  `/dev/fuse`), and no `RUN` instructions (both isolation modes call
  `unshare(CLONE_NEWNS)` and fail).
- `redhat-actions/buildah-build@v3` has no `content-path` input. Its
  `src/index.ts` calls `cli.copy(containerId, content)`, so the `content`
  list goes straight to `buildah copy` and buildah reads the **last**
  entry as the destination. Listing `payload.txt` and `hello/` copied the
  file into `/hello/` and never copied the directory. Name the
  destination explicitly as the last entry.

## Container registry (build, push, use)

The instance serves an OCI registry at `/v2/` under the same host and
certificate as the web UI. A pipeline can build an image, push it there,
and a later job can run inside it. Verified with the kept repositories
`agent/container-build-test` (build and push) and
`agent/container-use-test` (use).

- Build: install `buildah` in the job (`apt-get`) and use
  `redhat-actions/buildah-build@v3` in `base-image` + `content` mode.
  `Containerfile` builds with `RUN` do not work in this runner; see the
  footgun list.
- Push: `buildah push --authfile <file>`. buildah 1.28 has no
  `--password-stdin`, and an authfile keeps the token out of the process
  list. The credential is a user token with `write:package` stored as a
  repository secret; secrets are set through
  `PUT /api/v1/repos/<owner>/<repo>/actions/secrets/<NAME>` with
  plaintext `data` (this instance has no public-key route: that path
  answers 405).
- Use: `jobs.<id>.container.image: forgejo.local/<owner>/<repo>:<tag>`.
  The host daemon pulls it, so change 36 is required. No
  `container.credentials` are needed when the package is public, which it
  is by inheritance from the repository the image name matches.
- Job image consequences: the runner replaces the image entrypoint with
  `tail -f /dev/null` and picks the shell by probing the image, so a
  bash-free image such as Alpine runs steps with `sh -e`. An image
  without git or node cannot run JavaScript actions or `actions/checkout`.
- Pin job images by tag rather than digest: the registry serves Docker
  v2 manifests and reports a `Docker-Content-Digest` that differs from
  the local image id.

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
  (`/etc/ssl/certs/forgejo-lan.crt`, plus `GIT_SSL_CAINFO` and
  `NODE_EXTRA_CA_CERTS` in the job environment). The runner's `insecure`
  option stays `false`: verification is never turned off.
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
  - Node keeps its own CA store. It failed with
    `DEPTH_ZERO_SELF_SIGNED_CERT` even after `update-ca-certificates`,
    and returned 200 with
    `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/forgejo-lan.crt`. The runner now
    sets that variable for every job container (change 29), so Node needs
    no per-workflow setup. The variable is additive: the same job read
    `https://registry.npmjs.org/` and got status 200.
  - Python `requests` reads the `certifi` bundle rather than the system
    one, so it needs `REQUESTS_CA_BUNDLE`. That one cannot be set for all
    jobs: it replaces the whole trust store, which would break
    verification of public hosts — the same failure mode as
    `SSL_CERT_FILE` on the runner. Set it per job, pointing at a bundle
    that also holds the public CAs.
- Running `update-ca-certificates` in a job adds the certificate to the
  bundle file (142 entries to 143) and changes nothing for Node. It
  needs root, and it only lasts for that one job container.
- Both addresses work in job containers: the LAN address, and
  `forgejo.local`, which the runner writes into every job container's
  `/etc/hosts` through `--add-host` (change 27). The certificate names
  both, so TLS verification passes either way. Since change 30 the
  canonical URL is the name, so the clone URLs Forgejo hands out — and
  the URLs Actions checkouts use — are name-based and resolve through
  that pin. If the LAN address changes, update `/opt/forgejo/.env` and
  the `--add-host` entry in `/srv/forgejo-runner/config.yaml` together.
- Job containers reach the instance and the internet. Verified: the
  runner downloaded `actions/checkout` from `data.forgejo.org`, a job
  pulled `node:20-bookworm` from the container registry, and
  `apt-get install` worked inside a job.
- Host paths other than the certificate are not mountable: the runner
  only allows what `valid_volumes` lists.

## Workflow actions (mirrored on the instance)

- Since change 32 `DEFAULT_ACTIONS_URL=self`: a reference without a
  host, e.g. `uses: actions/checkout@v4`, is cloned from
  `https://forgejo.local/actions/checkout`. Every action a workflow
  uses must exist as a repository on the instance; the operator keeps
  the mirrors (e.g. the `actions` organization). The mirror must be
  public: the runner clones actions anonymously.
- A full URL in `uses:` (`uses: https://github.com/owner/repo@v4`)
  bypasses the setting. It still verifies: the runner's git bundle
  keeps the public CAs next to the instance certificate.
- The runner downloads actions with git inside the runner container.
  That container's `GIT_SSL_CAINFO` points at a merged bundle (public
  CAs + instance certificate) built at every start; the loose file in
  `/etc/ssl/certs` only covers the Go daemon.
- Changing `DEFAULT_ACTIONS_URL` does not invalidate
  `/srv/forgejo-runner/.cache`: delete it afterwards, or cached clones
  keep pointing at the previous host.
- JavaScript actions (e.g. `actions/checkout@v4`) need `node` in the
  job image, and git for the checkout itself. Since changes 33-34 the
  default image `node:24-bookworm` has both, so `runs-on: docker`
  needs no per-workflow image choice for them.

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
