# Changelog

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
