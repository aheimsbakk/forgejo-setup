# Changelog

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
