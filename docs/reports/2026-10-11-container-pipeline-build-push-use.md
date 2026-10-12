# Container workflow end-to-end test

Recorded 2026-10-11. Point-in-time record; the durable findings were
merged into `docs/forgejo-operations.md` (footguns, "Container registry
(build, push, use)") and `docs/forgejo-operations-verification.md`
(change 36), and two short entries went to `docs/memory/archive/`.

Test of the build -> push -> use cycle for container images on the Forgejo
instance: build an image in CI with `redhat-actions/buildah-build`, push it
to the Forgejo container registry with `buildah push`, then run a job in a
second repository inside that image.

Scope: the test itself changed no product documentation. The host change it
led to — the Docker daemon's registry trust file — is recipe change 36 and
is documented there. Test repositories are kept, not deleted.

## Environment

| Item | Value |
|---|---|
| Instance | `https://forgejo.local/` (LAN `<IP>`), Forgejo `16.0.5+gitea-1.22.0` |
| Operator access | API token for user `agent` (id 2), SSH root to the target |
| Runner | `forgejo-runner` 13.1.0, same box, label `docker:docker://node:24-bookworm`, capacity 2, job containers `--memory=1g --cpus=1`, `privileged: false`, no Docker socket in jobs |
| Actions source | `DEFAULT_ACTIONS_URL=self`; mirrored action repos must exist on the instance |
| CA | `tmp/certs/forgejo.crt`; job containers get it at `/etc/ssl/certs/forgejo-lan.crt` |

## Phase 1: build and push (passed)

Repository `agent/container-build-test`, run 29, job 41, commit
`228973761e81596d5d6fad3b2d2b8a0e7940bcff`.

Image in the registry:

| Field | Value |
|---|---|
| Reference | `forgejo.local/agent/container-build-test:228973761e81596d5d6fad3b2d2b8a0e7940bcff` |
| Manifest digest | `sha256:6f915181dc08c0003f6752bfb6d26b815214744885b53b8c8bc3f0bce0e3fd8f` |
| Size | 8.1 MB, one squashed layer (3.7 MB) |
| Config | `amd64`, entrypoint `/bin/sh`, labels `org.opencontainers.image.title`, `...revision`, `io.buildah.version=1.28.2` |
| Tags | only the commit SHA tag; `latest` was built locally but not pushed |

The workflow that produced it (`agent/container-build-test`,
`.forgejo/workflows/build.yml`):

```yaml
env:
  _CONTAINERS_ROOTLESS_UID: 1000
  BUILDAH_ISOLATION: chroot
jobs:
  build:
    runs-on: docker
    steps:
      - uses: actions/checkout@v4
      - name: install buildah and pin vfs storage
        run: |
          apt-get update -qq
          DEBIAN_FRONTEND=noninteractive apt-get install -y -qq buildah >/dev/null
          printf '[storage]\ndriver = "vfs"\ngraphroot = "/var/lib/containers/storage"\nrunroot = "/run/containers/storage"\n' > /etc/containers/storage.conf
      - name: image reference
        id: ref
        run: |
          REG="${GITHUB_SERVER_URL#https://}"
          echo "registry=$REG" >> "$GITHUB_OUTPUT"
          echo "image=$REG/$GITHUB_REPOSITORY" >> "$GITHUB_OUTPUT"
      - uses: redhat-actions/buildah-build@v3
        with:
          image: ${{ steps.ref.outputs.image }}
          tags: ${{ github.sha }} latest
          base-image: docker.io/library/alpine:3.20
          content: |
            payload.txt
            hello/
          entrypoint: /bin/sh
          disable-fuse-overlayfs: true
      - name: push to the instance registry
        env:
          REGISTRY_TOKEN: ${{ secrets.REGISTRY_TOKEN }}
        run: |
          REG="${{ steps.ref.outputs.registry }}"
          printf '{"auths":{"%s":{"auth":"%s"}}}' "$REG" "$(printf '%s:%s' "$GITHUB_ACTOR" "$REGISTRY_TOKEN" | base64 -w0)" > /tmp/buildah-auth.json
          buildah push --authfile /tmp/buildah-auth.json "${{ steps.build.outputs.image-with-tag }}"
          rm -f /tmp/buildah-auth.json
```

Nothing in the workflow hardcodes the host, the owner, the repository name
or the tag: they come from `GITHUB_SERVER_URL`, `GITHUB_REPOSITORY`,
`GITHUB_ACTOR` and `github.sha`.

## Findings

### 1. The first token could not create repositories

Measured with probes where a 403 names the missing scope and a 404 means
the scope is present.

| Capability | Probe | First token | Second token |
|---|---|---|---|
| `read:user` | `GET /api/v1/user` | ok | ok |
| `write:package` | `POST /v2/.../blobs/uploads/` | 202 | 202 |
| `write:repository` | `PATCH /api/v1/repos/agent/probe-nonexistent` | 404 (present) | present |
| `write:user` | `POST /api/v1/user/repos` | 403 missing | ok |

Admin fallback was not available: Basic auth with the `.env` password
returns 401, `Basic authorization is not allowed while having security
keys enrolled`. `forgejo admin` has no repository-creation subcommand.

### 2. The Actions token cannot push images, and there is no short-lived registry token

Inside a job, with the instance CA pinned:

- `GET /v2/` with `GITHUB_TOKEN` (Basic) -> 200
- `POST /v2/<name>/blobs/uploads/` with `GITHUB_TOKEN` -> **401**
- `ACTIONS_ID_TOKEN_REQUEST_URL` is empty and
  `ACTIONS_ID_TOKEN_REQUEST_TOKEN` has length 0: OIDC is off, so Forgejo
  gives the job no registry credential equivalent to GitLab's
  `CI_REGISTRY_TOKEN`.

Forgejo does mint a registry token for the job, but it carries no push
permission. Measured inside a job (run 33, job 45):

| Credential | `/v2/token` | Token payload | Blob upload |
|---|---|---|---|
| `GITHUB_TOKEN` (Basic) | 200, 159 bytes | `{"UserID":-2,"Scope":""}` | 401 (Bearer and Basic) |
| user token in `REGISTRY_TOKEN` | 200, 317 bytes | `{"UserID":2,"Scope":"write:package,..."}` | 202 (Bearer and Basic) |

Forgejo 16.0.5 source explains the empty scope:

- `routers/api/packages/api.go:855` — the `/v2/` auth chain includes
  `auth_method.ActionTaskToken{PermitBasic: true}`, so the Actions token
  does authenticate. That is why `GET /v2/` returns 200.
- `services/auth/method/action_task_token.go:46` — it authenticates as
  `user_model.NewActionsUser()`: the built-in `forgejo-actions` user,
  `ActionsUserID = -2`, with no access-token scope.
- `routers/api/packages/api.go:46` `reqPackageAccess(Write)` — with no
  scope present the scope branch is skipped and the final gate is
  `ctx.Package.AccessMode < accessMode && !ctx.IsUserSiteAdmin()` -> 401.
- `services/packages/perm.go:18` `DeterminePackageAccessMode` — for a
  user-owned package the Actions user is not the owner, so it gets
  `AccessModeRead`. The function contains the upstream comment
  `// TODO: ActionUser permission check`: this path is not implemented.
- `GetActionRepoPermission` does grant an Actions task write access to its
  own repository, but it is called only from
  `routers/web/repo/githttp.go:199` (git HTTP). It is not used by the
  package API, so repo write does not extend to the registry.

A repository secret (`REGISTRY_TOKEN`, a user token with package write) is
the only working push credential.

### 3. curl in the Debian job image does not trust the instance

`curl https://forgejo.local/v2/` failed with exit code 60 (certificate
verification) even though `/etc/ssl/certs/forgejo-lan.crt` is mounted.
OpenSSL needs a hashed entry in the trust store, not a loose file. Passing
`--cacert /etc/ssl/certs/forgejo-lan.crt` made the same call return 200.

Go tools behave differently: buildah and the runner trust the loose file,
because Go parses every file in `/etc/ssl/certs`.

### 4. buildah insists on a user namespace, and seccomp blocks it

Job container identity: uid 0, `uid_map 0 0 4294967295` (initial user
namespace), `CapEff 00000000a80425fb` (Docker default caps, no
`CAP_SYS_ADMIN`), seccomp filter active, no `/dev/fuse`.

Every buildah subcommand except `version`, `help` and `mount` calls
`unshare.MaybeReexecUsingUserNamespace(false)`
(`cmd/buildah/main.go:150`). In containers/storage that path returns early
for root only when `CAP_SYS_ADMIN` is held; otherwise it re-execs into a
new user namespace. Docker's default seccomp returns EPERM:

```
Error during unshare(CLONE_NEWUSER): Operation not permitted
```

This happens before any storage or isolation choice, so it is independent
of the driver.

### 5. Skipping the re-exec makes buildah work unprivileged

`MaybeReexecUsingUserNamespace` returns early when `Geteuid()==0` and
`GetRootlessUID()>0`, and `GetRootlessUID()` reads
`_CONTAINERS_ROOTLESS_UID`. Setting it to 1000 in the job environment
keeps buildah in the current namespace. `pull` then succeeded.

Side effect: `IsRootless()` also becomes true, so buildah uses rootless
storage paths (`/root/.local/share/containers/storage`,
`/var/tmp/containers-user-1000/...`) unless `--root`/`--runroot` or
`storage.conf` say otherwise.

### 6. Only `vfs` storage works; `RUN` cannot run

- `--storage-driver overlay`: `mount ... operation not permitted`.
- fuse-overlayfs: no `/dev/fuse` in the job container.
- `vfs`: works.

`RUN` steps fail under both isolation modes because
`bind.SetupIntermediateMountNamespace` calls `unshare(CLONE_NEWNS)`
(`bind/mount.go:38`, reached from `chroot/run_common.go:467`):

```
error running subprocess: creating new mount namespace for [...]: operation not permitted
```

So a Containerfile build is impossible in this runner. The working shape
is the action's no-`RUN` mode: `base-image` + `content`, which becomes
`buildah from` + `buildah copy` + `buildah config` + `buildah commit`.

### 7. Smaller items

- buildah 1.28 takes the container name only through `--name`; a second
  positional argument gives `too many arguments specified`. The action
  already reads the name from stdout, so it is unaffected.
- `jq` is not in `node:24-bookworm`; a step using it failed with exit 127.
- `buildah login` in 1.28 has no `--password-stdin`. An `--authfile` with
  a generated `{"auths":{...}}` file keeps the token out of the process
  list.
- The action's `disable-fuse-overlayfs: true` skips its fuse-overlayfs
  override, which is what we want here.
- The OCI endpoint ignores the API token header
  (`Authorization: token ...` -> 401) and accepts Basic auth
  (`-u agent:<token>` -> 200).

### 8. Secrets API shape

- `GET /api/v1/repos/<owner>/<repo>/actions/secrets/public-key` -> 405;
  the route only allows PUT and DELETE, so it is treated as a secret name.
  There is no public-key endpoint to seal a value against.
- `PUT .../actions/secrets/<NAME>` with `{"data":"<plaintext>"}` -> 201.
  Forgejo accepts the value directly; no libsodium sealing needed.
- `GET .../actions/secrets` -> 200 with the list.

### 9. Registry visibility and the host daemon

The package is public: it inherits the visibility of the repository the
image name matches (`agent/container-build-test`), and the anonymous pull
path works.

A plain anonymous `GET /v2/.../manifests/<sha>` returns 401, which is the
OCI auth challenge, not a refusal. Following the challenge proves public
access:

```
WWW-Authenticate: Bearer realm="https://forgejo.local/v2/token",service="container_registry",scope="*"
GET /v2/token?service=container_registry&scope=*      (no credentials) -> token, 159 bytes
GET .../manifests/<sha>   with Authorization: Bearer  -> 200
GET .../blobs/<layer>     with Authorization: Bearer  -> 200, 3738564 bytes
```

An earlier note in this file called the package private. That was wrong:
the 401 was read without following the token flow.

- The package page shows the pull command
  `docker pull forgejo.local/agent/container-build-test:<sha>`.
- No package API route answered on this instance
  (`/api/v1/packages/...` and the user/org variants all 404).
- On the target, `docker pull` of that image fails at TLS, before any
  authorization question:
  `tls: failed to verify certificate: x509: certificate signed by unknown
  authority`. `/etc/docker/certs.d` does not exist and the system trust
  store has no copy of the instance certificate.
- The runner can send registry credentials for a job image pull
  (`act/container/docker/pull.go` reads `container.credentials` from the
  workflow, or a Docker config file the runner process can read), but for
  this package none are needed.

## Phase 2: run a job inside the pushed image (passed)

Host change applied on 2026-10-11 (recipe change 36):

```
mkdir -p /etc/docker/certs.d/forgejo.local
cp /srv/forgejo-certs/forgejo.crt /etc/docker/certs.d/forgejo.local/forgejo.crt
```

No daemon restart. The fingerprint matches the exported copy
`tmp/certs/forgejo.crt`.

The file keeps the name `forgejo.crt`, which this setup uses for the same
certificate everywhere else. The daemon keys on the extension rather than
a fixed name: with the local image deleted before each pull,
`forgejo.local/forgejo.crt` succeeded, `forgejo.local/ca.pem` failed with
the x509 error, and removing the directory failed the same way. `ca.crt`
is only the name Docker's documentation and error text suggest.

Repository `agent/container-use-test`, `.forgejo/workflows/use.yml`:

```yaml
jobs:
  use:
    runs-on: docker
    container:
      image: forgejo.local/agent/container-build-test:ad049345c1395cc9cc633a208f23ec516fa4c70d
```

No `container.credentials`: the package is public, and the pull log shows
`username=` (run 40, after every local copy of the image was deleted on
the target).

Result: run 40, job 52, `success`. The job ran inside the Alpine image
built by phase 1 — `/payload.txt` and `/greeting.txt` printed their build
context content, `NAME="Alpine Linux"`, `uid=0`.

Two runner behaviours the test exposed:

- The runner replaces the image entrypoint:
  `docker create … entrypoint=["tail" "-f" "/dev/null"]`. The image's
  `/bin/sh` entrypoint is not used for the job.
- With no `shell:` set, the runner probes the container
  (`command -v bash`) and uses `sh -e` when bash is absent
  (`act/runner/step_run.go:240-252`). A minimal image therefore works,
  but an image without git or node cannot run `actions/checkout` or any
  JavaScript action.

## Build fixes found while reaching phase 2

- `redhat-actions/buildah-build@v3` has no `content-path` input.
  `src/index.ts` calls `cli.copy(containerId, content)`, and
  `src/buildah.ts` builds `buildah copy <ctr> <items…>`, so buildah reads
  the **last** entry as the destination. `content: payload.txt, hello/`
  produced `/hello/payload.txt` and never copied `hello/`. Listing the
  destination explicitly (`payload/payload.txt`, `payload/greeting.txt`,
  `/`) produced the intended `/payload.txt` and `/greeting.txt`.
- The push step originally pushed only `steps.build.outputs.image-with-tag`
  (one tag). It now pushes the commit tag and `latest` explicitly.
- Final image:
  `forgejo.local/agent/container-build-test:ad049345c1395cc9cc633a208f23ec516fa4c70d`,
  manifest digest `sha256:81a4c91cb19b0a1493ec6161d9da1b4bfcd11a1bc4706dd1b50741ff53c4b90d`,
  7807650 bytes, entrypoint `[/bin/sh]`.

## Artifacts left on the instance

| Item | State |
|---|---|
| `agent/container-build-test` | kept, public: build workflow, build context (`payload/`), probe workflows removed |
| `agent/container-use-test` | kept, public: job runs inside the pushed image |
| Package `agent/container-build-test` | public (anonymous pull verified); tags: five commit tags from the test iterations plus `latest` |
| Repository secret `REGISTRY_TOKEN` | set on `container-build-test` |
| Probe secret `PROBE_TOKEN` | created during testing, deleted |
| Abandoned OCI upload session | from a scope probe; no package created |
| Target file `/etc/docker/certs.d/forgejo.local/forgejo.crt` | added (recipe change 36); copy of the instance certificate, mode 644; the `.crt` suffix is what the daemon keys on |
