# Podman Migration Verification

Measurements behind recipe changes 39–45 (Docker → podman, compose →
kube pod YAML). Taken on the live target 2026-10-18. Each section is a
question from `tasks/podman-migration.md` and what was observed.

## Open question 1 — does the user namespace apply to runner-created containers?

Yes, server-side. `/etc/containers/containers.conf` with
`[containers] userns="auto:size=65536"` applies to every container
created over the Docker-compatible API, which is how the runner creates
job containers.

| Probe | Result |
|---|---|
| compat API, no config | `uid_map 0 0 4294967295` (initial namespace), `unshare` EPERM |
| `userns="auto"` (no size) | namespace applied but sized 1024 ids — apt inside a job fails: `_apt` (uid 65534) unmapped, `setgroups (22: Invalid argument)` |
| `userns="auto:size=65536"` | `uid_map 0 100000 65536`; apt works inside the job |
| `podman kube play` pod | initial namespace (`0 0 4294967295`) — containers.conf `userns` is not applied, so the app/runner pods keep host uid semantics and the uid 1000 bind mounts work unchanged |
| docker CLI `--userns=auto` | rejected client-side (`invalid USER mode`); the runner binary embeds the same parser, so the runner cannot pass it — the server-side default is the only path |
| subuid pool | the `containers` system user owns auto allocations; `/etc/subuid`/`/etc/subgid` ship empty; without a range: `not enough unused IDs in user namespace` |

## Open question 2 — does nested buildah work with a namespace?

Yes, with two additions. A job container with the auto namespace plus
`--cap-add SYS_ADMIN` and `--security-opt apparmor=unconfined`:

| Probe | Result |
|---|---|
| userns only, default caps | `unshare` EPERM — the default capability set has no CAP_SYS_ADMIN |
| + `--cap-add SYS_ADMIN` | still EPERM — Debian's AppArmor profile `containers-default-0.62.2` (enforce) denies `userns_create` and `mount` (audit lines confirm) |
| + `apparmor=unconfined` | `unshare -m` OK, tmpfs mount OK |
| buildah 1.28.2 (Debian bookworm, in `node:24-bookworm`), `vfs` | `buildah run` OK; `buildah bud` with two `RUN` steps OK |
| default storage inside the job | fails: kernel rejects overlay-on-overlay, fallback `fuse-overlayfs` needs `/dev/fuse` (absent) — `vfs` stays the storage driver |
| `_CONTAINERS_ROOTLESS_UID` workaround | no longer needed: the job runs as uid 0 inside its own namespace, buildah never re-execs |

CI proof on the live instance (run ids from the API):
- `containerfile-build` (run 73): the repo Containerfile with
  `RUN apk add --no-cache curl` built end to end; `buildah run` in the
  built image printed the copied payload and `curl 8.14.1`.
- `podman-job-checklist` (run 74/76): job `uid_map 0 296608 65536`,
  `CapEff 00000000802405fb` (SYS_ADMIN set), `attr/current unconfined`,
  `UNSHARE_OK`, `MOUNT_OK`, `forgejo.local` → LAN address,
  `GIT_SSL_CAINFO`/`NODE_EXTRA_CA_CERTS` set, git/curl/node all verify
  the pinned certificate, memory limit 1073741824.

## Open question 3 — port binding in kube YAML

`hostIP` on `containerPort` is honored: a probe pod with
`hostIP: 127.0.0.1, hostPort: 18080` bound to `127.0.0.1:18080` only.
The production pods bind 443/80/2222 to the LAN address; `ss` shows no
other address. `hostNetwork` was not used.

## Open question 4 — restart semantics (measured; on hold)

The stock template has no `Restart=`. Upstream
`contrib/systemd/system/podman-kube@.service.in` is `Type=notify`,
`NotifyAccess=all`, `TimeoutStopSec=70`, so systemd's default
`Restart=no` applies and a `Restart=` drop-in is a valid override.
Measured with `podman kill forgejo-forgejo`:

- the app container stops;
- the pod's `-service` container exits, so the unit goes `inactive`;
- `ExecStop` runs `podman kube down`, which removes the pod;
- nothing restarts: `https` returns 000 until the unit is started again.

Containers do carry `restartPolicy=always` (the kube default), and it
does restart a container that exits on its own while the pod stays up
(observed as a 92-restart crash loop during a bad config). It does not
survive the service-container teardown path.

Options, not yet applied:
1. drop-in `Restart=always` on both units — systemd restarts the unit,
   `kube play --replace` recreates the pod; closest to today's
   `restart: unless-stopped`;
2. `restartPolicy` in the YAML plus `podman-restart.timer` — delayed;
   does not cover the teardown path measured above;
3. none — manual start after a crash (a deliberate behaviour change).

Re-tested 2026-10-18 on the runner unit, still with the stock template:
`systemctl stop` and `podman kill forgejo-runner-forgejo-runner` both
deactivate the unit and leave the pod removed. `kube play` exits 0, so
the unit reads as a clean stop and `Restart=on-failure` would not fire —
option 1 needs `Restart=always`. With `RestartSec=10` the default start
limit (5 starts per 10 s) does not trip. The untested risk in option 1
is `ExecStop=podman kube down` running against an already half-removed
pod on the crash path; if it exits non-zero the unit can land in
`failed`. **Status: on hold, no fix scheduled.**

## Open question 7 — registry trust path

`/etc/containers/certs.d/forgejo.local/forgejo.crt` works (anonymous
pull of `forgejo.local/agent/container-build-test:multiarch`). The
extension rule carries over: renaming the file to `forgejo.pem` makes
the same pull fail `x509: certificate signed by unknown authority`.

## Open question 8 — runner registration

Engine-independent. `.runner` and `config.yaml` were kept untouched
apart from the `options` line; the runner declared successfully against
the same instance registration with no re-registration.

## Coexistence gotchas (temporary, removed with Docker)

- Docker's iptables `FORWARD` chain (policy DROP) dropped podman bridge
  traffic; netavark's own nft table allows it, but the iptables chain
  decides first. A `DOCKER-USER` accept for podman's `10/8` space was
  needed for the measurement window. Gone after the purge; `FORWARD`
  policy set back to ACCEPT.
- Purging `runc` (a Docker dependency) left already-created pause
  containers unremovable ("runtime runc is missing"); `apt-get install
  runc`, remove the stragglers, purge again. New containers use `crun`.
- `nft flush ruleset` also clears netavark's live rules; recreate the
  pods afterwards.

## Post-teardown verification (2026-10-18, after change 45)

- `which docker` empty; `/var/lib/docker`, `/etc/docker` gone; only the
  `inet netavark` nft table remains; `FORWARD` policy ACCEPT.
- `https://forgejo.local/` 200, `https://<IP>/` 200, `http://<IP>/` 307
  to `https://forgejo.local/`, `/api/v1/version` 16.0.5, certificate
  SANs and expiry unchanged, SSH 2222 answers, ports on the LAN address
  only.
- Runner `declared successfully`; CI `podman-job-checklist` run 76 and
  `use-pushed-image` run 77 both success (anonymous pull of the
  instance registry image through the new trust path).
- `forgejo-backup.service` and `forgejo-cleanup.service` start cleanly;
  new dump present; grace records only for genuinely unused images.
- Multi-architecture tag `:multiarch` pulls anonymously and reports
  `amd64` + `arm64` in its manifest list — the manifest-list push that
  `tasks/multiarch-buildah-builds.md` listed as unproven now works.
