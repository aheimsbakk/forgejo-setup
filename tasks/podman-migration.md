# Migrate Forgejo and the runner to podman with Kubernetes definitions

Status: done on the first target 2026-10-18. Restart enforcement remains
open. Recorded 2026-10-18.

## Result

The first target now runs podman only. The app and runner are started by
`podman-kube@.service`, job containers get a user namespace, nested
buildah `RUN` works, Docker is removed, and the post-teardown checks are
recorded in `docs/forgejo-podman-migration-verification.md`.

## What this task is

Replace Docker on the target with podman as the single container engine.
The Forgejo app and the Actions runner daemon are defined as Kubernetes
pod YAML kept under `/opt/forgejo/kube/` on the target (source:
`forgejo/kube/` in this repository, copied verbatim like every other
deployment file) and
started directly by the systemd template `podman-kube@.service` — no
quadlet. The template takes the YAML path through `%I`, so the instance
name is the path with `/` replaced by `-`: the units are
`podman-kube@opt-forgejo-kube-forgejo.yaml.service` and
`podman-kube@opt-forgejo-kube-forgejo-runner.yaml.service`. All
persistent data stays in place. The motivating goal: job containers gain
a user namespace, so buildah `RUN` works and Containerfile builds become
possible without privileged containers.

## Fixed decisions (operator)

- One engine only: podman. After verification, remove Docker packages,
  `/var/lib/docker` and `/etc/docker` completely.
- Forgejo and forgejo-runner: Kubernetes pod definitions, started via
  `podman-kube@.service` (rootful system instance).
- The kube YAML lives under `/opt/forgejo/kube/` on the target
  (`forgejo/kube/` in this repository), keeping all deployment files in
  one directory as the compose file did.
- No quadlet. The stock `podman-kube@.service` template is used
  directly. Verified from the Debian 13 podman 5.4.2 package:
  `ExecStart=podman kube play --replace --service-container=true %I`
  and `ExecStop=podman kube down %I`, so the instance name is the full
  YAML path with `/` escaped to `-`; no path override is needed.
  Enabling an instance creates the
  `/etc/systemd/system/default.target.wants/podman-kube@<escaped-path>.service`
  symlink (`WantedBy=default.target`). `/etc/containers/systemd/` stays
  empty so the quadlet generator, which podman enables by default,
  generates nothing.
- No systemd-user linger. No host account with uid 1000.
- Data must survive: every state directory is a host bind mount.

## Facts measured 2026-10-17/18

| Item | Value |
|---|---|
| State directories | `/srv/forgejo`, `/srv/forgejo-runner`, `/srv/forgejo-certs`, `/opt/forgejo/secrets`, `/var/lib/forgejo-cleanup` — all bind mounts, engine-independent |
| Data ownership | uid 1000; no host account exists or is needed for rootful engines |
| Runner engine access | Docker-compatible API only, via `DOCKER_HOST` |
| Job container today | initial user namespace, no CAP_SYS_ADMIN, `unshare` EPERM; `RUN` impossible (measured, both architectures) |
| Debian 13 podman | 5.4.2; `podman-kube@.service` verified from the package: `ExecStart=podman kube play --replace --service-container=true %I`, `ExecStop=podman kube down %I`, `WantedBy=default.target`, **no `Restart=`**; quadlet generator ships enabled; `userns=auto` supported |
| QEMU user-mode | installed 2026-10-17; binfmt flags `POF`, interpreter opened at registration |

## The userns decision (open question 1 decides the shape)

1. Preferred: rootful podman with `userns=auto` in `containers.conf`.
   Probe first: create a container through the Docker-compat API (as the
   runner does) and check whether the userns applies and whether nested
   buildah `RUN` then works. If yes: one rootful engine, no new user, no
   linger, no second instance.
2. Fallback: a second, rootless podman instance for job containers only,
   driven by a **system** unit with `User=<dedicated user>` running
   `podman system service --time=0 unix:/run/podman-jobs.sock`. No
   linger. The dedicated user needs subuid/subgid ranges; it is not and
   need not be uid 1000. The runner daemon (rootful) mounts that socket
   and sets `DOCKER_HOST` to it.

## Open questions (resolved except 4)

1. Does `userns=auto` (or `HostConfig.UsernsMode`) apply to containers
   the runner creates over the compat API? Measure before anything else.
2. Does nested buildah work inside a podman job container with a userns:
   storage driver (overlay in userns vs the `vfs` workaround), is the
   `_CONTAINERS_ROOTLESS_UID` workaround still needed, does `RUN` pass?
3. Port binding in kube YAML: does `podman kube play` honour `hostIP` on
   `containerPort` (or an annotation) so 443 and 22 bind to the LAN
   address only? `hostNetwork: true` is not acceptable — it would serve
   public interfaces.
4. Restart semantics without quadlet — **decision deferred to after the
   conversion** (operator). The stock template has no `Restart=`
   (systemd default is `no`), so nothing restarts by itself. Measure
   first what the unit even tracks: with `--service-container=true` the
   unit stays active while the pod is up — does a dead app container
   take the unit down (so `Restart=` fires), or does the pod stay up
   with the app dead? Then choose the enforcement layer: a drop-in
   adding `Restart=always` (immediate, faithful to today's
   `restart: unless-stopped`), or `restartPolicy` in the YAML plus the
   `podman-restart.timer` (delayed), or none (manual, a deliberate
   behaviour change). Until decided, the converted services run with
   the stock template and no restart enforcement. Engine options
   quadlet would have set (`--network`, `PodmanArgs`) must become
   podman annotations inside the kube YAML — confirm which annotations
   `podman kube play` honours.
5. Compose-to-kube mapping details: all `FORGEJO__*` env vars, restart
   policy, the read-only cert and secrets mounts, the runner's
   `valid_volumes` and `--add-host` settings (they live in
   `/srv/forgejo-runner/config.yaml`, unchanged).
6. `backup.sh` and `cleanup.sh`: rewrite `docker` calls to `podman`;
   cleanup must cover the podman store(s); the protected-image list must
   be read from the kube YAML instead of the compose file.
7. Registry trust: `/etc/docker/certs.d/forgejo.local/` moves to
   `/etc/containers/certs.d/forgejo.local/`; the daemon reads the new
   path — verify the `.crt` extension rule still applies.
8. Runner registration: `.runner` and the instance-side registration are
   engine-independent; confirm no re-registration is needed.

## Proposed steps

1. Install podman alongside Docker (temporary coexistence, measurement
   only). Probe open question 1 with a throwaway API-created container
   running `unshare -m true`.
2. Write the two kube YAML files under `forgejo/kube/` in the repository
   (deployed to `/opt/forgejo/kube/`); start with `systemctl start
   podman-kube@opt-forgejo-kube-forgejo.yaml.service` and
   `podman-kube@opt-forgejo-kube-forgejo-runner.yaml.service`; enable
   both (creates the `default.target.wants` symlinks); verify web UI,
   git over HTTPS and SSH, certificate, runner online.
3. Apply the chosen userns shape (1 or 2); run the job-container
   checklist: `valid_volumes` cert mount, `--add-host forgejo.local`,
   `--memory/--cpus`, `GIT_SSL_CAINFO`/`NODE_EXTRA_CA_CERTS`, anonymous
   pull of the job image from the instance registry.
4. Probe nested buildah: re-run the existing `multiarch.yml` and
   `containerfile.yml` workflows unchanged; record which workarounds are
   still needed.
5. Rewrite `backup.sh` and `cleanup.sh`; re-verify both timers.
6. Docker teardown: stop Docker containers, `docker system prune -a`,
   remove packages, delete `/var/lib/docker` and `/etc/docker`. Re-run
   the full verification afterwards.
7. Documentation: new recipe changes (engine install, kube definitions
   under `/opt/forgejo/kube/`, path-encoded template instances and
   restart handling, trust path, script rewrites, teardown), update
   `docs/forgejo-install-steps.md`, `docs/forgejo-ci-and-registry.md`,
   `docs/forgejo-footguns.md`, `BLUEPRINT.md` (Compose dependency ->
   podman + kube definitions), `CODEBASE.md`
   (`forgejo/docker-compose.yml` replaced by `forgejo/kube/*.yaml`),
   verification docs.

## Constraints that stay in force

- Ports bind to the LAN address only; never public interfaces.
- Self-signed certificate pinned by clients, runner and job containers;
  verification never off.
- No privileged job containers; no Docker/podman socket inside jobs.
- Images pinned by tag; cleanup bounded and stack-protective.
- Secrets never in tracked files; the encryption key stays outside the
  data directory.
- Runner capacity stays 2 (2 vCPU, 3 GB, no swap).

## Non-goals

- Quadlet in any form (`.container` units, `.kube` wrappers, generated
  units): the operator chose raw kube YAML plus the stock
  `podman-kube@.service` template, instantiated by path-encoded names.
- Rootless for the Forgejo app itself (rootful keeps uid 1000 and
  privileged-port semantics identical to today).
- Compose compatibility layer beyond what the migration needs.

## Evidence

- `tasks/multiarch-buildah-builds.md` — the `RUN` blocker and the
  measured multiarch state.
- `docs/reports/2026-10-11-container-pipeline-build-push-use.md` — the
  Docker-based pipeline this task replaces.
- `docs/memory/archive/2026-10-18-forgejo-podman-lan-only-https.md` —
  the deployment constraints this task preserves.
