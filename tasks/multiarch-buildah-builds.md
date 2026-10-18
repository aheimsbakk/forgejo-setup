# Multi-architecture image builds with buildah

Status: template created 2026-10-18; target repository update pending.
The template is one workflow file intended to replace the three current
build workflows in `agent/container-build-test`. Recorded 2026-10-17.
The host facts below predate the podman migration; see
`docs/forgejo-podman-migration-verification.md` for the current
job-container shape.

## What this task is

Build a container image for more than one CPU architecture in CI on this
instance, publish the architectures under one tag in the instance's
container registry, and optionally run a job inside a foreign-architecture
image.

## Host facts measured 2026-10-17

| Item | Value |
|---|---|
| Host architecture | x86_64 |
| CPU / RAM / swap | 2 vCPU / 3 GB / none |
| Free disk | 32 GB of 40 GB |
| QEMU user-mode | not installed; Debian 13 candidate `1:10.0.13+ds-0+deb13u1`, depends on `qemu-user` + `qemu-user-binfmt` |
| binfmt_misc | mounted, `status: enabled`; only a `python3.13` handler registered |
| binfmt config | `/usr/lib/binfmt.d/` holds `python3.13.conf` only; `/etc/binfmt.d/` empty; `systemd-binfmt.service` present |
| Job container | no `CAP_SYS_ADMIN`, seccomp blocks `unshare`, `/dev/fuse` absent, `/proc/sys/fs/binfmt_misc` empty |
| Job container limits | `--memory=1g --cpus=1`, `privileged: false`, `docker_host: "-"`, capacity 2 |
| `valid_volumes` | `/srv/forgejo-certs/forgejo.crt` only |
| buildah | Debian 13 candidate `1.39.3`; the verified pipeline used `1.28.2` |

## Findings

### 1. Building for another architecture needs no host change

The only build shape that works on this runner is `buildah from` +
`buildah copy` + `buildah commit` (the action's `base-image` + `content`
mode). That shape never runs a binary from the image being built, so it
never needs CPU emulation. Selecting another architecture is a pull-time
choice plus metadata:

- `buildah from --platform linux/arm64 <base>` selects the arm64 manifest.
- `buildah copy` and `buildah commit` do not depend on the architecture.
- One working container per architecture, joined into a manifest list and
  pushed with `buildah push --all`.

### 2. A Containerfile build cannot be made multi-architecture

`RUN` is impossible in job containers: both isolation modes call
`unshare(CLONE_NEWNS)` and the container holds no `CAP_SYS_ADMIN`. Adding
QEMU would not change that. Multi-architecture work must stay inside the
no-`RUN` shape.

### 3. The manifest list is the unverified part

Nothing on this instance has ever received a manifest list. Unverified:

- whether Forgejo 16.0.5 accepts `buildah push --all`,
- what the package page shows for a multi-architecture tag,
- whether deleting such a tag removes every architecture.

This is the first thing to measure, because everything else in the
pipeline is already proven.

### 4. Running a foreign-architecture image is a separate question

Building arm64 and running arm64 are different requirements. Running needs
QEMU user-mode registered on the host. The kernel side is ready:
binfmt_misc is mounted and enabled, and registrations are global to the
kernel rather than per container. Two obstacles remain:

- A job cannot register handlers itself: `/proc/sys/fs/binfmt_misc` is
  empty inside job containers.
- Debian's entries name `/usr/bin/qemu-<arch>-static`, which exists on the
  host and not in the job image. Either the job installs
  `qemu-user-static`, or the static binaries are bind-mounted, which means
  opening a new path in `valid_volumes`.

Whether Debian's entries carry the `P` flag (interpreter opened at
registration time) decides whether the second obstacle applies. Not
measured.

### 5. Storage cost is small and transient

`vfs` unpacks each architecture's layer chain separately and copies each
working container's root filesystem, with no sharing between them. Two
architectures therefore cost about twice one architecture. That storage
lives in the job container's writable layer and disappears when the runner
removes the container. At the base size used in the verified pipeline
(`alpine:3.20`, 8.1 MB image, 3.7 MB layer) the cost is tens of megabytes
per job. It is not a blocker.

### 6. The real cost is time

Each job pulls and unpacks both platforms from scratch; nothing is reused
between jobs. Two architectures double that work on a 2 vCPU machine with
no swap and runner capacity 2.

## Two scopes

| Scope | Host change | Status of the parts |
|---|---|---|
| A: build and push several architectures under one tag | none | build, push and credential path already proven single-architecture; only the manifest list is new |
| B: also run a job inside a foreign-architecture image | install QEMU user-mode, and solve interpreter reachability | pull and run are proven for the host architecture only |

Start with A. B is only worth doing if a pipeline must execute the
foreign-architecture image rather than just publish it.

## Non-goals

- A persistent buildah storage volume shared between jobs. It would need a
  new entry in `valid_volumes`, which is the gate that keeps jobs from
  mounting host paths, and it would make build state shared between jobs of
  different repositories.
- Changing the storage driver. `overlay` needs `mount()` (EPERM) and
  `fuse-overlayfs` needs `/dev/fuse` (absent) plus `mount()`.
- Privileged jobs or Docker-in-Docker.

## Open questions

1. Does Forgejo 16.0.5 accept and serve an OCI image index, and does its
   package UI and deletion handle it?
2. Do the `_CONTAINERS_ROOTLESS_UID=1000`, `vfs`-only and no-`RUN` findings
   still hold on buildah 1.39.3?
3. Do Debian 13's `qemu-user-binfmt` entries set the `P` flag?
4. Where do per-architecture base images come from: `docker.io` per
   platform, or mirrored into the instance registry? Mirroring also removes
   Docker Hub rate limits from the picture.
5. Which job image carries buildah: the current `apt-get install buildah`
   into `node:24-bookworm`, a `node:24-trixie` job image with buildah 1.39,
   or `quay.io/buildah/stable`? The last is on the host as `:latest`, which
    breaks the pin rule, and `cleanup.sh` does not protect it because it is
    not named in the kube definitions.

## Proposed steps

1. Measure the registry: assemble a two-architecture manifest list by hand
   with `buildah manifest create` / `add` / `push --all` and check what the
   package page and an anonymous pull report.
2. Add a multi-architecture job to `agent/container-build-test`, triggered
   manually, keeping the existing single-architecture job intact.
3. Verify the published tag from three places: the host engine, a job
   container, and the package page.
4. Re-check the three buildah workarounds on buildah 1.39.3 before changing
   the job image.
5. Only if Scope B is wanted: install `qemu-user-static`, then measure
   whether the interpreter must also be present inside the job container.

## Constraints that stay in force

- Images pinned by tag; never `:latest`.
- Push needs a user token with `write:package` in a repository secret; the
  Actions token cannot push.
- Every action a workflow uses must exist as a mirrored repository on the
  instance (`DEFAULT_ACTIONS_URL=self`).
- Runner capacity stays 2; the machine has 2 vCPU, 3 GB and no swap.
- No privileged jobs, no engine socket in job containers.
- Job containers pin the instance certificate; verification stays on.

## Evidence

- `docs/reports/2026-10-11-container-pipeline-build-push-use.md` — the
  single-architecture build, push and run cycle, and the buildah limits.
- `docs/forgejo-ci-and-registry.md` — registry access, job container trust,
  `valid_volumes`.
- `docs/memory/archive/2026-10-18-buildah-in-podman-job-containers.md`
  — user namespace size, `CAP_SYS_ADMIN`, AppArmor, and `vfs`.
- `docs/memory/archive/2026-10-11-actions-token-cannot-push-packages.md` —
  the push credential requirement.
