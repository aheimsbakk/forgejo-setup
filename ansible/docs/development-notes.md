# Development Notes

Traps and patterns for anyone changing this playbook. Each entry is a
failure that actually happened on a deployed target; the templates and
tasks encode the fixes. Grouped by area.

## Playbook structure

- Lint from this directory: `.venv/bin/ansible-lint site.yml`. The few
  intentional deviations carry inline `# noqa` comments.
- Handlers do not work across `import_tasks`; every restart is a
  conditional task with `# noqa: no-handler` instead.
- Tags: `verify` carries `never`, so it only runs when asked. Keep new
  side-effecting one-shot tasks behind it.
- Target-side `curl`/`systemctl`/`getent` checks are commands, not
  modules, because they must run on the target (the `uri` module would
  connect from the control node and need the certificate there).
- Every verification is an `assert` with a named `fail_msg`. New checks
  must state the cause and the fix in the message.
- `lan_name` consistency binds several files: `group_vars/all.yml` (or
  a host override), `/opt/forgejo/.env` (`LAN_NAME`, written by the
  playbook), `gen-cert.sh` (reads it, never hardcode), the pod
  templates (`DOMAIN`, `SSH_DOMAIN`, `ROOT_URL`, `hostAliases`), and
  the runner config (`--add-host`). Change the value in the parameter
  store and re-run; the cert assert catches drift.
- Two machines on one LAN must not share `lan_name`/`static_hostname`:
  Avahi announces `<static_hostname>.local`, so defaults collide.

## Podman and systemd

- Both pod definitions mount `/etc/timezone`, and `podman kube play`
  fails to start a pod when a hostPath source is missing. Debian
  cloud/minimal images do not ship `/etc/timezone` (measured on a fresh
  Debian 13 cloud image). `base.yml` creates `Etc/UTC` only when the
  path is absent: podman also leaves an empty DIRECTORY at
  `/etc/timezone` on hosts where it auto-created the source (seen on
  both targets), and `copy` into an existing directory is an error.
  The app reads `/etc/localtime` instead, so the empty directory is
  harmless.
- `podman-kube@.service` uses `%I`, which turns every `-` back into
  `/`. The instance name is the YAML path with `/` replaced by `-`, so
  the kube YAML file names must not contain hyphens.
- `podman kube play` names containers `<pod>-<container>`: the app
  container is `forgejo-forgejo`, the runner container
  `forgejo-runner-forgejo-runner`. Scripts and execs must use those
  names.
- The stock template has no `Restart=`: a stopped unit stays down and
  the pod is removed. `restartPolicy: Always` only restarts containers
  while the pod service stays up.
- `podman kube play` ignores `containers.conf` `userns` — wanted for
  the app and runner pods (host uid semantics for uid 1000 bind
  mounts). The job-container namespace comes only from containers
  created through the Docker-compatible API, i.e. `userns="auto:size=65536"`.
- The flip side: a plain `podman run` on this engine inherits
  `userns=auto`, so its uid 0 is a subuid on the host and it cannot
  write root-owned bind mounts. One-shot maintenance containers
  (runner register, generate-config) need `--userns=host --user 0`.
- `userns="auto"` without a size can pick 1024 ids, which leaves out
  `_apt` (uid 65534) and breaks `apt-get` inside jobs. Keep the size.
- `podman image prune --filter until=` matches build date, and
  `container prune until=` matches creation time — neither is "last
  used". The engine stores no last-used time, which is why `cleanup.sh`
  keeps its own grace record.
- `podman image prune -a` removes the pinned stack images when the
  stack is stopped; `cleanup.sh` protects the images named in the kube
  YAML files.
- `podman images --format {{.ID}}` returns short ids; `podman image
  inspect --format {{.Id}}` returns full `sha256:` ids. Compare like
  with like, or images look unused.

## Forgejo settings

- The image runs its own OpenSSH on container port 22. With
  `START_SSH_SERVER=true` the built-in SSH server collides and the
  container crashes: listen on 2222 and publish `2222:2222`.
- `SSH_DOMAIN` forms the SSH clone URL, does not inherit `DOMAIN`, and
  defaults to `localhost`. Set it to the LAN name.
- The plain-HTTP listener must bind 8080 inside the container (uid 1000
  cannot bind <1024 under podman) while the host publishes 80.
- `CERT_FILE`/`KEY_FILE` default to paths relative to `CustomPath`,
  which is inside the data dir and inside every dump. Keep absolute
  paths outside `/srv/forgejo`.
- `LOCAL_ROOT_URL` defaults to `https://localhost:3000/`: the
  certificate must name `localhost`, `127.0.0.1` and the hostname, or
  Forgejo rejects its own requests.
- `SECRET_KEY` can sit empty with no warning and no generated value.
  `SECRET_KEY` and `SECRET_KEY_URI` are mutually exclusive; keep the
  ini value empty and use the file mount.
- Dotted ini sections in env names escape as `_0X2E_` (see
  `FORGEJO__ui_0X2E_user__REPO_PAGING_NUM`).
- `forgejo dump` refuses to run as root (`-u 1000`), needs `-w /data`,
  aborts when `/data/git/repositories` is missing (fresh install), and
  writes `forgejo-dump-<timestamp>.zip`. `forgejo admin user create`
  requires `--email`; `.invalid` is the correct placeholder domain
  (`.local` is reserved for mDNS).
- `admin` is a reserved username in Forgejo 16: account creation fails
  with `CreateUser: name is reserved`. The default operator account
  name in `group_vars/all.yml` is `siteadmin`; pick any name that is
  not in Forgejo's reserved list.
- Forgejo serves one canonical `ROOT_URL` and warns clients that use
  any other Host. There is no host allow-list; the name is canonical
  and the address shows a banner.
- Forgejo 16 has no file-creation API; push files with git. Two-factor
  on an account blocks all basic-auth API calls — use tokens.

## Actions runner

- Runner v13: register with `--token` (not `--registration-token`),
  after `generate-config` created the config file. Use the deprecated
  `GET /api/v1/admin/runners/registration-token`; the newer per-runner
  API token does not work with `register`. Failed registrations leave
  stale runner entries; delete them via
  `DELETE /api/v1/admin/actions/runners/<id>` before retrying.
  Identify the live entry by the numeric `id` field inside
  `/srv/forgejo-runner/.runner`, which equals the admin API entry's
  `id`; the entry's `name` is the registration container's hostname
  and matches nothing local.
- The runner image runs as uid 1000 and cannot read the root-owned
  podman socket: the runner pod runs as root for that mount only. The
  same uid matters the other way: `register` must run with `--user 0`,
  or it cannot write `.runner` into the root-owned runner dir. Keep
  runner-dir ownership root:root (the daemon pod is root too).
- `/srv/forgejo-runner/config.yaml` is normally generated, but
  re-running `generate-config` wipes every mitigation. This recipe
  deploys the full `templates/runner-config.yaml.j2` instead — edit the
  template, never re-generate on a target.
- `generate-config` writes `env_file: .env`; a missing file logs
  `Missing env file ".env" is ignored` on every start. The template
  sets it to `""` and deletes the sample `A_TEST_ENV_NAME_*` envs,
  which the runner otherwise passes to every job.
- The runner's Go daemon trusts the loose file in `/etc/ssl/certs`;
  its git (OpenSSL) needs a CA bundle. The pod command builds a merged
  bundle at every start and points `GIT_SSL_CAINFO` at it. A relative
  `GIT_SSL_CAINFO` works for clone and fails for push — absolute only.
  Do not set `SSL_CERT_FILE`: readers treat it as the whole store.
- The default job image label lives in `/srv/forgejo-runner/.runner`,
  not in `config.yaml`. The current pin `node:24-bookworm` has git and
  node; check support status before moving it.
- Inside jobs, `<hostname>.local` is unreliable over DNS (nothing serves
  `.local`; systemd-resolved answers the machine's own name
  synthetically with every address). The `--add-host=` entry in the
  runner config and `hostAliases` on both pods pin the name to the LAN
  address alone.
- The registration container in `runner.yml` is subject to the same
  trap: it dials the canonical name, so it needs `--add-host` and the
  instance certificate mounted into `/etc/ssl/certs` (the runner's Go
  client reads loose files there), and a hard `timeout` — unresolved
  name lookup hangs `forgejo-runner register` forever. This task never
  ran on the first target because the runner was registered before the
  playbook took over.
- A `run:` step written as one unquoted scalar containing `: ` breaks
  workflow parsing with no logs at all. Use block scalars (`run: |`).
- On a fresh install the runner pod starts (tag `forgejo`) before
  registration (tag `runner`), and an unregistered runner daemon exits,
  leaving its container not running. Checks that exec into the runner
  container therefore belong in `runner.yml` after registration, never
  in `forgejo.yml`; the runner pod restart there is conditional on
  registration or config change, not on config change alone.

## Certificates and trust stores

- Four separate trust stores, one file, four places: system store per
  client device, `/etc/ssl/certs` inside runner and job containers,
  the runner's git bundle, and the engine's
  `/etc/containers/certs.d/<lan_name>/forgejo.crt`. The engine store is
  read by extension: `.crt` is a root, `.cert`/`.key` are a client pair,
  anything else is ignored.
- Regenerating the certificate invalidates all four; the playbook never
  regenerates over a still-valid pair.
