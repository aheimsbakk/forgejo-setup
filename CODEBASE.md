# Codebase

Concrete mapping from `BLUEPRINT.md` components to physical files.

## Structure

```
/work
├── README.md                        user documentation (product use)
├── CONTRIBUTING.md                  developer guide: scripts, playbook, conventions
├── BLUEPRINT.md                     architecture specification
├── CODEBASE.md                      this file
├── CHANGELOG.md                     version history (Keep a Changelog)
├── VERSION                          current version string
├── .env                             test credentials (gitignored, mode 600)
├── .env.example                     test credentials template
├── .gitignore                       ignores tmp/, .env, .venv/, ansible/hosts.yml
├── ansible/                         playbook component: the reproduce procedure
│   ├── ansible.cfg                  inventory path, accept-new host keys, python3
│   ├── requirements.txt             pinned ansible-core version
│   ├── requirements-lint.txt        pinned ansible-lint version
│   ├── site.yml                     entry point: imports the four task files
│   ├── hosts.yml                    parameter store (gitignored)
│   ├── hosts.yml.example            parameter store template
│   ├── group_vars/all.yml           tracked settings: images, paths, limits
│   ├── tasks/
│   │   ├── base.yml                 hostname, apt, podman, dirs, Avahi  [tag base]
│   │   ├── forgejo.yml              pods, cert, key, timers, asserts    [tag forgejo]
│   │   ├── runner.yml               registration, job config            [tag runner]
│   │   └── verify.yml               one-shot backup/cleanup/probe       [tag verify]
│   ├── templates/
│   │   ├── kube/forgejo.yaml.j2     Forgejo app pod definition
│   │   ├── kube/runner.yaml.j2      Actions runner pod definition
│   │   ├── containers.conf.j2       engine defaults: job userns and DNS
│   │   └── runner-config.yaml.j2    runner job configuration (full file)
│   └── files/                       deployed verbatim to /opt/forgejo/
│       ├── gen-cert.sh              certificate component: self-signed cert
│       ├── backup.sh                backup component: dump + retention
│       ├── cleanup.sh               disk cleanup: unused images, containers
│       ├── forgejo-backup.service   backup activation (oneshot unit)
│       ├── forgejo-backup.timer     backup schedule (daily, catch-up)
│       ├── forgejo-cleanup.service  cleanup activation (oneshot unit)
│       └── forgejo-cleanup.timer    cleanup schedule (daily, catch-up)
├── docs/
│   ├── forgejo-install-recipe.md    recipe component: parameters,
│   │                                decisions, change register
│   ├── forgejo-install-steps.md     playbook runbook: how to converge a target
│   ├── forgejo-footguns.md          configuration traps: symptom and fix
│   ├── forgejo-ci-and-registry.md   runner, registry, job access, actions
│   ├── forgejo-operations.md        backup, restore, cleanup, cert trust
│   ├── forgejo-restore.md           restore procedure for a dump
│   ├── forgejo-operations-verification.md
│   │                                verification results per change set
│   ├── forgejo-backup-restore-verification.md
│   │                                backup, dump format, restore drill,
│   │                                encryption key measurements
│   ├── forgejo-podman-migration-verification.md
│   │                                podman migration measurements and
│   │                                post-teardown checks
│   ├── reports/                     dated investigation reports (history)
│   │   └── 2026-10-11-container-pipeline-build-push-use.md
│   │                                build -> push -> use test record
│   └── memory/                      agent session memory (INDEX.md, archive/)
├── tasks/                           task records; some are proposals,
│   │                                some record completed target work
│   ├── multiarch-buildah-builds.md  multi-architecture buildah builds
│   └── podman-migration.md          podman engine switch with kube definitions
├── templates/                       reusable repository templates
│   └── build-multiarch.yml          default multiarch image build action
└── scripts/
    ├── bump-version.sh              version bumping (patch|minor|major)
    ├── validate-changelog.sh        changelog format check
    └── verify_codebase_sync.sh      CODEBASE.md path validation
```

## Component -> path mapping

| Blueprint component | Files |
|---|---|
| Playbook | `ansible/site.yml`, `ansible/tasks/base.yml`, `ansible/tasks/forgejo.yml`, `ansible/tasks/runner.yml`, `ansible/tasks/verify.yml`, `ansible/ansible.cfg`, `ansible/requirements.txt` |
| Recipe | `docs/forgejo-install-recipe.md`, `docs/forgejo-install-steps.md`, `docs/forgejo-footguns.md`, `docs/forgejo-ci-and-registry.md`, `docs/forgejo-operations.md`, `docs/forgejo-restore.md`, `docs/forgejo-operations-verification.md`, `docs/forgejo-backup-restore-verification.md`, `docs/forgejo-podman-migration-verification.md` |
| Service configuration | `ansible/templates/kube/forgejo.yaml.j2`, `ansible/templates/kube/runner.yaml.j2`, `ansible/templates/containers.conf.j2`, `ansible/templates/runner-config.yaml.j2`, `ansible/group_vars/all.yml` |
| Certificate | `ansible/files/gen-cert.sh`; exported copy `tmp/certs/forgejo.crt` (untracked) |
| Backup | `ansible/files/backup.sh`, `ansible/files/forgejo-backup.service`, `ansible/files/forgejo-backup.timer`; restore procedure `docs/forgejo-restore.md` |
| Disk cleanup | `ansible/files/cleanup.sh`, `ansible/files/forgejo-cleanup.service`, `ansible/files/forgejo-cleanup.timer`; grace record `/var/lib/forgejo-cleanup/unused-images.tsv` (on the target, untracked) |
| Parameter store | `ansible/hosts.yml` (untracked), `ansible/hosts.yml.example`, `ansible/group_vars/all.yml` |
| Discovery | `ansible/tasks/base.yml` (packages + Avahi interface pin) and `ansible/templates/runner-config.yaml.j2` (name mapping for job containers) |
| CI runner | `ansible/templates/kube/runner.yaml.j2`, `ansible/templates/runner-config.yaml.j2`, `ansible/tasks/runner.yml`; job settings `/srv/forgejo-runner/config.yaml` (on the target, generated) |
| Container pipeline | `docs/reports/2026-10-11-container-pipeline-build-push-use.md` (test record); target trust file `/etc/containers/certs.d/forgejo.local/forgejo.crt` (recipe change 43); test repositories `agent/container-build-test` and `agent/container-use-test` (on the instance) |
| Investigation reports | `docs/reports/` — dated records, written once and not maintained afterwards |
| Task records | `tasks/` — proposals or completed work records; not part of the deployed state unless copied by the playbook |
| Repository templates | `templates/build-multiarch.yml` — copied into new repositories as `.forgejo/workflows/build-multiarch.yml` or `.github/workflows/build-multiarch.yml` |

## Entry points

- Reproduce procedure: `ansible/site.yml` — the main "script" of the
  project, run from `ansible/` with the pinned `ansible-core`
  (`ansible/requirements.txt`) in a uv virtualenv.
  `docs/forgejo-install-steps.md` is the runbook;
  `docs/forgejo-install-recipe.md` holds the parameters, the decisions
  and the change register it implements.
- Pod start: `podman-kube@opt-forgejo-kube-forgejo.yaml.service` and
  `podman-kube@opt-forgejo-kube-runner.yaml.service` on the target. The
  instance name is the YAML path with `/` replaced by `-`.
- Certificate creation: `/opt/forgejo/gen-cert.sh` on the target
  (source: `ansible/files/gen-cert.sh`), run by the playbook before the
  first start and again before the certificate expires.
- Backup run: `/opt/forgejo/backup.sh` on the target (source:
  `ansible/files/backup.sh`), activated by the systemd timer units.
- Restore run: `docs/forgejo-restore.md` — a file copy of `data/` and
  `repos/` into the instance layout. Forgejo 16.0.5 has no restore
  command and its dumps carry no restore script.
- Encryption key: `/opt/forgejo/secrets/secret_key` on the target,
  generated by the playbook (tag `forgejo`) and mounted read-only at
  `/etc/forgejo/secret_key` by the app pod definition. It has no source
  file in this repository on purpose.
- Disk cleanup run: `/opt/forgejo/cleanup.sh` on the target (source:
  `ansible/files/cleanup.sh`), activated by the cleanup timer units.
- Version tooling: `scripts/bump-version.sh`,
  `scripts/validate-changelog.sh`, `scripts/verify_codebase_sync.sh`.

## Specs and conventions

- Target platform: Debian 13 (trixie), amd64, containerized workloads.
- Control environment: `uv` virtualenv (`.venv/`, gitignored) with the
  `ansible-core` version pinned in `ansible/requirements.txt`. No
  collections; the rule for adding one lives in `CONTRIBUTING.md`.
- Languages: Ansible YAML for the playbook; Jinja2 templates for
  rendered configuration; shell (bash) for the scripts deployed
  verbatim; YAML for systemd units; Markdown for procedure and product
  documentation.
- Naming: kebab-case files; `forgejo-backup.*` units match their
  service name; playbook task files carry one tag each.
- Deployment convention: the playbook renders `ansible/templates/`
  with the parameters from `ansible/hosts.yml` and copies
  `ansible/files/` verbatim to `/opt/forgejo/`, except
  `containers.conf.j2`, which renders to
  `/etc/containers/containers.conf`. The rendered kube YAML files are
  the source of application configuration on the target.
- TLS state on the target: `/srv/forgejo-certs/forgejo.crt` and
  `forgejo.key`. The key never leaves the machine; the `.crt` is copied
  to `tmp/certs/` (gitignored) for client and CI pinning, and to
  `/etc/containers/certs.d/forgejo.local/forgejo.crt` so the engine
  trusts the instance's own registry (recipe change 43). The engine picks
  these files by extension, so the `.crt` suffix is required.
- Cleanup state on the target: `/var/lib/forgejo-cleanup/` holds the
  unused-image grace record. It contains image ids and dates only, and
  is never copied into the repo.
- Encryption key state on the target: `/opt/forgejo/secrets/` (mode 750)
  and `secret_key` inside it (mode 640, `root:1000`). The value is
  generated on the target by `forgejo generate secret SECRET_KEY`, is
  referenced from the app pod definition only as
  `SECRET_KEY_URI=file:/etc/forgejo/secret_key`, and is never copied into
  the repo or into a dump.

## Language rationale

- Ansible (core only, no collections) was chosen for the reproduce
  procedure because the target state is declarative and the old bash
  procedure's sed chains were not idempotent and reported nothing when
  they no-op'd. Jinja2 templates replace every sed: the LAN address,
  the resolver, the Avahi interface pin and the six runner-config
  edits are rendered, not patched. `--check --diff` verifies a running
  target without touching it. The full `ansible` metapackage was
  rejected to keep the control environment small.
- The runner job configuration is a full template
  (`runner-config.yaml.j2`) of the `generate-config` output for the
  pinned runner version, not generate-plus-sed: re-running
  `generate-config` on a target would wipe the mitigations, and the
  template makes the file reviewable in one place.
- Bash was chosen for `backup.sh` because it orchestrates existing
  remote commands (container exec, file moves, retention trimming)
  without adding a runtime dependency to the target. The registry
  exclusion is a `forgejo dump` flag (`--skip-package-data`), not an
  `app.ini` setting, so it lives in the script and cannot be set from the
  pod definition.
- `gen-cert.sh` is also bash and calls the `openssl` already shipped by
  Debian. Generating the certificate on the target keeps the private key
  off the operator's machine and off the network, and avoids adding a
  local CA tool to the deployment.
- Kubernetes pod YAML plus the stock `podman-kube@.service` template
  keeps each service in one reviewable file and avoids quadlet. The
  operator chose this shape because podman kube play gives the app and
  runner host uid semantics while `containers.conf` gives runner-created
  job containers a user namespace. The template's `%I` is path-encoded,
  so the YAML file names must not contain hyphens.
- The LAN address is literal in the kube YAML because `podman kube play`
  has no variable interpolation. The reproduce procedure replaces the
  placeholder address after copying the files.
- systemd timer units were chosen over cron because the base image has
  no cron and timers provide boot catch-up (`Persistent=true`).
- `cleanup.sh` is bash for the same reason as `backup.sh`: it drives
  existing podman CLI calls and adds no runtime to the target. The
  7-day grace is tracked in a small TSV file because the engine's
  `until=` filter matches image build dates and container creation times
  rather than last use, and the engine stores no last-used timestamp. The
  protected image list is read from the kube YAML files at run time so a
  version bump cannot leave the stack unprotected.
