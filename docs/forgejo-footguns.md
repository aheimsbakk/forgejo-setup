# Forgejo Footguns

Configuration traps found while setting up the instance, each with the
symptom and the fix. The setup steps are in
`docs/forgejo-install-recipe.md`; the runner, registry and job-container
setup is in `docs/forgejo-ci-and-registry.md`; the measured results are in
`docs/forgejo-operations-verification.md` and
`docs/forgejo-backup-restore-verification.md`.

- The Forgejo image runs its own OpenSSH daemon on port 22 *inside* the
  container. With `START_SSH_SERVER=true` and `SSH_LISTEN_PORT=22`, the
  built-in SSH server collides with it and the container crashes
  (`bind: address already in use`). Fix: `SSH_LISTEN_PORT=2222` and
  publish `2222:2222`. The pod definition in this repo already reflects
  that.
- The SSH clone URL in the UI and the repository API is built from
  `[server] SSH_DOMAIN`, which does not inherit `DOMAIN` and defaults
  to `localhost`. With only `DOMAIN` set, every clone/push hint reads
  `ssh://git@localhost:2222/...` (recipe change 49). Fix:
  `FORGEJO__server__SSH_DOMAIN=forgejo.local` in the pod definition.
- `forgejo dump` refuses to run as root: use
  `podman exec -u 1000 -w /data forgejo-forgejo forgejo dump`. Without `-w /data`
  it tries to write to `/` and gets `permission denied`.
- `forgejo dump` aborts with `Failed to include repositories` when
  `/data/git/repositories` does not exist yet (fresh install, no repos).
  Create it before dumping. The backup script does.
- The dump file is named `forgejo-dump-<timestamp>.zip`, not `dump-*`.
- `forgejo admin user create` requires `--email`; without it: `email is
  not set`. With no mail server, any placeholder address works.
- Avahi announces every interface by default, including podman bridges.
  Without `allow-interfaces=<lan-if>`, `<hostname>.local` can resolve to
  `172.18.0.1` and connections fail. Pin it to the LAN interface.
- Runner v13 renamed the register flag: `--token`, not
  `--registration-token`. `register` also needs an existing config file:
  run `generate-config` first.
- The token from `POST /api/v1/admin/actions/runners` (new API) does not
  work with `forgejo-runner register`. Use the deprecated global token:
  `GET /api/v1/admin/runners/registration-token`.
- The runner image runs as uid 1000 and cannot read the root-owned
  podman socket. The runner pod sets `runAsUser: 0` and
  `runAsGroup: 0` for that mount.
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
- `generate-config` writes `env_file: .env`. When the daemon's working
  directory has no such file, its first log line is
  `Missing env file ".env" is ignored` — a warning, and the runner
  declares normally, but it makes every start look like a fault. Set the
  key to an empty value to stop the lookup; job environment belongs in
  `container.envs` (change 46). The same generated block also keeps the
  template's sample entries `A_TEST_ENV_NAME_1` and `A_TEST_ENV_NAME_2`
  in `envs`, which the runner passes to every job container; delete them
  in the same pass that sets `env_file` (change 47).
- `GIT_SSL_CAINFO` with a relative path works for `git clone` and fails
  for `git push` with `Problem with the SSL CA cert (path? access
  rights?)`. Always give an absolute path.
- The HTTP redirector answers with 307, so a runner whose `.runner`
  file still holds an `http://` address keeps working — at the cost of
  one redirect per request. Switch the address instead of relying on it.
- A minimal job image such as `debian:bookworm` or Alpine has no git:
  the runner then runs steps with `sh`, and `actions/checkout` cannot
  run in it. Change 33 made the default `node:20-bookworm`
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
  pod services and the per-job networks the runner creates — the engine
  can forward to the host's systemd-resolved, which answers the machine's
  own mDNS name *synthetically* with every address it has: the LAN
  address first, then bridge gateways and link-local IPv6 addresses.
  Connections then fail or land on a bridge gateway. Fixed by change 27:
  `--add-host=forgejo.local:<IP>` puts the name in every job container's
  `/etc/hosts`, which the resolver reads before it queries DNS, so the
  answer is the LAN address alone.
- The runner and Forgejo containers resolved `<hostname>.local` to all of
  the machine's addresses (LAN address first, then bridge gateways),
  because they got the host resolver's synthetic answer. Nothing in the
  stack uses the name — the runner dials the address in `.runner`,
  Forgejo calls itself through `localhost` — so this was a hazard, not a
  fault. Change 28 pins the name with `extra_hosts` on both services;
  under podman the same pin is `hostAliases` on both pods, and the lookup
  returns the LAN address alone.
- `/srv/forgejo-runner/config.yaml` is generated. Re-running
  `forgejo-runner generate-config` on a live target wipes the
  `capacity`, `options`, `envs` and `valid_volumes` edits, including the
  `--add-host` entry; recipe step 16 has to be replayed after it.
- `podman image prune --filter until=168h` does not mean "unused for a
  week". `until` matches the image's build date, so a freshly pulled
  image is usually months old and is deleted the day it arrives.
  `podman container prune --filter until=` matches the container's
  creation time, not the time it stopped. The engine keeps no last-used
  time, so `cleanup.sh` maintains its own grace record.
- `podman image prune -a` also removes the pinned stack images when the
  pod stack is stopped, because nothing references them then.
  `cleanup.sh` protects the images named in the kube YAML files.
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
   Alpine without `update-ca-certificates`, so the runner pod command
   builds a merged bundle (public CAs + instance certificate) at every
   start and `GIT_SSL_CAINFO` points at it.
- The runner's action cache (`/srv/forgejo-runner/.cache/act`) is not
  invalidated when `DEFAULT_ACTIONS_URL` changes: cached clones keep
  the old remote. Delete the directory after changing the setting.
- The engine has its own registry trust store: files in
  `/etc/containers/certs.d/<registry-host>/`. The runner's `/etc/ssl/certs`
  mount and the job containers' `GIT_SSL_CAINFO` /
  `NODE_EXTRA_CA_CERTS` do not cover it. Without a certificate there, a
  job whose `container.image` comes from the instance registry fails
  before any authorization question: `podman pull … tls: failed to
  verify certificate: x509: certificate signed by unknown authority`.
  Change 43 put the certificate there as
  `/etc/containers/certs.d/forgejo.local/forgejo.crt` — the same file name
  this setup uses elsewhere, not Docker's example name `ca.crt`.
- That directory is read by extension, not by fixed name: `*.crt` is
  added to the engine's trust roots, `*.cert`/`*.key` are a client
  certificate pair and must be paired, and any other name is ignored.
  Measured on the target: `forgejo.crt` pulls fine, `forgejo.pem` fails
  with the same x509 error. The suffix is load-bearing; the stem is free.
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
- `buildah` inside a podman job container needs a user namespace,
  `CAP_SYS_ADMIN`, and an AppArmor exception. Set
  `userns="auto:size=65536"` in `/etc/containers/containers.conf`; add
  `--cap-add SYS_ADMIN --security-opt apparmor=unconfined` to the
  runner's `container.options`. `vfs` storage stays required because
  overlay-on-overlay is rejected and `/dev/fuse` is absent. The old
  `_CONTAINERS_ROOTLESS_UID=1000` workaround is no longer needed: the job
  runs as uid 0 inside its own namespace, so buildah does not re-exec.
- `redhat-actions/buildah-build@v3` has no `content-path` input. Its
   `src/index.ts` calls `cli.copy(containerId, content)`, so the `content`
   list goes straight to `buildah copy` and buildah reads the **last**
   entry as the destination. Listing `payload.txt` and `hello/` copied the
   file into `/hello/` and never copied the directory. Name the
   destination explicitly as the last entry.
- `[security] SECRET_KEY` can sit empty and the instance runs anyway: no
  warning, and the value is not generated for you (it stayed empty across
  30 hours of uptime and several restarts). Set it through
  `SECRET_KEY_URI=file:/etc/forgejo/secret_key` with a read-only file
  mount. The two options are mutually exclusive — the config cheat sheet
  says the app exits at startup if both have a value — so the empty
  `SECRET_KEY` line in `app.ini` has to stay empty.
- `podman-kube@.service` uses `%I`, which turns every `-` back into `/`.
  The instance name is the YAML path with `/` replaced by `-`, so the YAML
  file names must not contain hyphens. `forgejo-runner.yaml` would resolve
  to `forgejo/runner.yaml` and fail.
- `podman kube play` ignores `containers.conf` `userns`. That is useful
  for the app and runner pods, which need host uid semantics for uid 1000
  bind mounts, but it means the job-container namespace comes only from
  containers created through the Docker-compatible API.
- `userns="auto"` without a size can be too small. Debian job images can
  size the namespace to 1024 ids, which leaves out `_apt` (uid 65534) and
  breaks `apt-get` inside jobs. Use `userns="auto:size=65536"`.
- The stock `podman-kube@.service` template has no `Restart=`. Killing an
  app container stops the pod's service container, makes the unit
  inactive, and runs `podman kube down`. The pod is removed and nothing
  restarts it. `restartPolicy: Always` only restarts containers while the
  pod stays up.
- `podman kube play` names containers `<pod>-<container>`. The app
  container is `forgejo-forgejo`; the runner container is
  `forgejo-runner-forgejo-runner`. Scripts that exec into containers must
  use those names.
- `podman images --format {{.ID}}` returns short ids, while
  `podman image inspect --format {{.Id}}` returns full `sha256:` ids.
  Cleanup must compare the same form; mixing them silently makes images
  look unused.
