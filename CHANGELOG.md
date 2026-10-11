# Changelog

## [0.7.0] - 2026-10-11

- **why:** Backups carried rebuildable container images, the instance had no global encryption key, and the documented restore procedure did not match what Forgejo 16.0.5 dumps contain.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, backup, restore, secrets, documentation

### Added

- `docs/forgejo-restore.md`: the restore procedure for a dump, verified by a restore drill on the target. Forgejo 16.0.5 has no restore command and its dumps carry no `restore.sh`
- Recipe change 38 and reproduce step 6c: create `/opt/forgejo/secrets/secret_key` before the first start, mode 640 `root:1000`
- `docs/forgejo-install-steps.md`, `docs/forgejo-footguns.md`, `docs/forgejo-ci-and-registry.md`, `docs/forgejo-backup-restore-verification.md`: topic files split out of the recipe and operations documents, which had passed 300 lines
- `docs/memory/archive/`: entries for the dump restore footguns, the empty `SECRET_KEY`, and two-factor blocking basic auth

### Changed

- `forgejo/backup.sh` now runs `forgejo dump --skip-package-data`. One dump went from 85,498,046 to 63,054,363 bytes; the package records stay in the database and cleanup rules clear them
- `forgejo/docker-compose.yml` sets `FORGEJO__security__SECRET_KEY_URI=file:/etc/forgejo/secret_key` and mounts that file read-only, so the key is in no dump and not in a tracked file
- Recipe change 37 and 38 rows, and the operations and verification sections, now carry the measured sizes, dump listings and restore-drill results

### Fixed

- The restore notes told the reader to run a `restore.sh` from the dump and to use `unzip`; neither exists on Forgejo 16.0.5 or on the target
- The verification record claimed the live `app.ini` had `SECRET_KEY` set; it held an empty value

### Security

- The global encryption key is set and stored outside the data directory, readable only by root and the container user
- Recorded that a dump's `app.ini` carries `INTERNAL_TOKEN` and `[oauth2] JWT_SECRET` unchanged; dumps are mode 600 and a remote copy needs encrypted storage

## [0.6.0] - 2026-10-11

- **why:** Pipelines could not hand container images to each other. A job can now build an image, push it to the instance registry, and a later job can run inside that image. The Docker daemon performs every job-image pull, so it needed its own copy of the instance certificate.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, registry, actions, buildah, tls

### Added

- Recipe change 36 and reproduce step 20: `/etc/docker/certs.d/forgejo.local/forgejo.crt` on the target, so the Docker daemon trusts the instance's own registry. No daemon restart needed
- `docs/forgejo-operations.md`: "Container registry (build, push, use)" section, plus footguns for daemon registry trust, the extension-based cert lookup, the Actions token's missing push rights, unprivileged buildah, and the `content` copy trap
- `docs/reports/2026-10-11-container-pipeline-build-push-use.md`: the full test record. Repositories `agent/container-build-test` and `agent/container-use-test` stay on the instance
- `docs/memory/archive/`: two warning entries — the Actions token cannot push packages, and buildah needs a rootless uid, `vfs` storage and no `RUN`
- `README.md`: the CI/CD section now names `node:24-bookworm` as the default job image, says actions resolve to mirrored repositories on the instance, and lists the container registry as something you can use

### Changed

- `CODEBASE.md`: added the `docs/reports/` component and the container pipeline mapping
- `docs/forgejo-operations.md`: the git-in-job footgun no longer reads as if the default job image lacks git

### Fixed

- The built image held its payload at the wrong path. `redhat-actions/buildah-build@v3` has no `content-path` input, so the last `content` entry became the destination for the others. The workflow now names `/` explicitly

## [0.5.0] - 2026-10-10

- **why:** The operator browses many repositories. The default page sizes (20 on explore, 15 on a profile) forced extra clicks, and a larger page costs almost nothing.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, ui, pagination

### Changed

- `forgejo/docker-compose.yml`: added `FORGEJO__ui__EXPLORE_PAGING_NUM=50` and `FORGEJO__ui_0X2E_user__REPO_PAGING_NUM=50` (recipe change 35). The explore page and user profile pages now list 50 repositories per page
- A repository listing is one indexed SQL query plus a total count; the count does not depend on page size, so the only growth is the HTML response

## [0.4.0] - 2026-10-10

- **why:** Workflows pulled actions from public forges. The operator mirrors every used action on the instance, so relative `uses:` references must resolve locally — and the default job image must be able to run them on a supported Node line.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, actions, runner, tls, job-image

### Added

- `FORGEJO__actions__DEFAULT_ACTIONS_URL=self` in `forgejo/docker-compose.yml`: `uses: actions/checkout@v4` now clones from the instance (recipe change 32). Mirrors must be public repos; full URLs in `uses:` still bypass the setting
- `docs/forgejo-operations.md`: "Workflow actions (mirrored on the instance)" section — mirror rule, anonymous clone requirement, cache invalidation, node/git needs

### Changed

- The runner container builds a merged CA bundle (public CAs + instance cert) at every start and sets `GIT_SSL_CAINFO`; its git now verifies the instance when downloading actions
- Default job image: `debian:bookworm` → `node:20-bookworm` (change 33) → `node:24-bookworm` (change 34, Active LTS; Node 20 went end-of-life 2026-04-30). The label lives in `/srv/forgejo-runner/.runner`; reproduce step 15 registers with the new label

### Fixed

- Action clones from the instance failed with `self-signed certificate (18)`: the runner's git (OpenSSL) reads the `ca-certificates.crt` bundle, not the loose file in `/etc/ssl/certs` that only the Go daemon reads
- Stale action cache after the URL change: `/srv/forgejo-runner/.cache` kept clones pointing at `data.forgejo.org`; cleared, and the gotcha documented


## [0.3.2] - 2026-10-10

- **why:** Browsing `https://forgejo.local/` showed a "configured to be served on …" warning, because `ROOT_URL` named the LAN address. Clients use the name, so the name must be canonical.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, root-url, dns, runner, email

### Fixed

- Browsing by `forgejo.local` no longer shows the canonical-URL warning: `DOMAIN` and `ROOT_URL` in `forgejo/docker-compose.yml` now name the instance by its mDNS name. The address still serves content and git; browsers see the warning there instead

### Changed

- The runner's registered instance URL (`/srv/forgejo-runner/.runner`, recipe step 15) switched to `https://forgejo.local/`; the compose `extra_hosts` pin resolves the name inside the runner container
- The port-80 redirector now sends clients to `https://forgejo.local/`
- Account email placeholder changed from `@forgejo.lan` to `@forgejo.invalid` (RFC 6761, never deliverable). `.local` is reserved for mDNS (RFC 6762) and must not appear in email addresses. Recipe change 31 updates the existing admin via the API
- `README.md`: browse and clone by `https://forgejo.local/`; the address is documented as the non-canonical alternative
- Recipe change 30 recorded; reproduce step 15 registers with `--instance https://forgejo.local/`

## [0.3.1] - 2026-10-10

- **why:** Inside containers the instance name resolved to the wrong address, so workflows had to use the LAN IP. The reproduce procedure also lacked checks that would catch a silent config failure.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, actions, dns, tls, runner

### Fixed

- `forgejo.local` resolves inside job containers: `--add-host=forgejo.local:<LAN_IP>` in the runner's `container.options` writes the name into each container's `/etc/hosts`, which the resolver reads before DNS
- Recipe step 16 now checks its own edits (step 16b). Its `sed` patterns match the generated defaults and do nothing, without failing, when `generate-config` output changes

### Added

- `extra_hosts: forgejo.local:<LAN_IP>` on both compose services, so the app and runner containers stop getting the host resolver's synthetic answer that lists the Docker bridge addresses
- `NODE_EXTRA_CA_CERTS` in the runner's `container.envs`, so Node in job containers trusts the instance with no per-workflow setup. Verified additive: public HTTPS still verifies
- Recipe smoke test (step 17) addresses the instance by name in the `ca-pin` job and adds a `node-trust` job
- `docs/forgejo-operations-verification.md`: verification results moved out of `docs/forgejo-operations.md`

### Changed

- Recipe step 12 comment corrected: the Avahi interface pin covers host-side announcement, not container lookups
- Decisions records that `forgejo.local` is coupled across the hostname, the certificate SAN list, the compose `extra_hosts` pin, and the runner `--add-host` option

## [0.3.0] - 2026-10-09

- **why:** CI pulls a new container image per workflow and crashed jobs leave stopped containers behind, so `/var/lib/docker` grew with nothing to reclaim it.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, docker, cleanup, disk, systemd

### Added

- `forgejo/cleanup.sh`: removes untagged images, images unused for 7 days, containers outside the compose stack stopped for 7 days, unused networks and build cache
- `forgejo/forgejo-cleanup.service` and `forgejo-cleanup.timer`: daily run at 04:15 UTC, after the 03:30 backup, with boot catch-up
- Grace record `/var/lib/forgejo-cleanup/unused-images.tsv`: an image goes only after 7 days with no container referencing it, because Docker's `until=` filter matches build dates, not last use
- Recipe changes 24–26, reproduce steps 18–19, and a "Disk space" section in `README.md`

### Security

- Volumes are never removed, and the images named in `docker-compose.yml` are read at run time and protected, so cleanup cannot delete job data or the stack itself

## [0.2.0] - 2026-10-09

- **why:** Web traffic, including login and clones, crossed the LAN in plain text. HTTPS with a pinned self-signed certificate closes that gap without exposing the machine.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, https, tls, actions, runner

### Added

- `forgejo/gen-cert.sh`: self-signed certificate covering the LAN address, `localhost`, `127.0.0.1` and the host names
- `docs/forgejo-operations.md`: verification results, footguns, job-container trust, backup and restore steps
- Certificate trust for CI: `GIT_SSL_CAINFO` plus a read-only certificate mount in job containers, listed in `valid_volumes`

### Changed

- `forgejo/docker-compose.yml`: Forgejo serves HTTPS on 443, port 80 only redirects, `ROOT_URL` uses `https://`
- Runner registration address switched from `http://` to `https://`

### Security

- All web traffic is encrypted; plain HTTP answers with a 307 redirect and nothing else
- The private key lives in `/srv/forgejo-certs`, outside the data directory, so backup dumps never contain it

## [0.1.0] - 2026-10-09

- **why:** First complete, reproducible Forgejo LAN deployment; the recipe, config files and tooling are captured so a fresh machine can be set up from an SSH key and an IP alone.
- **model:** kompis/qwen3.8-flash-next-iq3_s
- **tags:** forgejo, deployment, docker, backup, actions

### Added

- `docs/forgejo-install-recipe.md`: 17 logged changes, verification steps, footguns, and a parameterized reproduce procedure
- `forgejo/docker-compose.yml`: Forgejo 16.0.5 (LAN-only HTTP on 80, git-over-SSH on 2222) and the pinned Actions runner 13.1.0 with resource limits
- `forgejo/backup.sh` plus `forgejo-backup.service`/`.timer`: daily full dump, 7 newest kept
- `forgejo/backup.sh` creates the repositories directory before dumping, avoiding the fresh-install dump failure
- `.env`/`.env.example` parameter store; real values stay out of git
- mDNS discovery steps (`libnss-mdns`, Avahi pinned to the LAN interface)
- `README.md` (user guide) and `CONTRIBUTING.md` (developer guide)
- `scripts/bump-version.sh`, `scripts/validate-changelog.sh`, `scripts/verify_codebase_sync.sh`

### Fixed

- Runner registration flow documented after five failed attempts: correct flag (`--token`), config must exist first, and the deprecated global token is the one that works
