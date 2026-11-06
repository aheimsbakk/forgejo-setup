# CI And Container Registry

How the Actions runner, the container registry, mirrored workflow
actions and access from job containers work on an instance installed by
this playbook. Commands use `forgejo.local` as the instance name;
substitute your `lan_name` if you set a different one.

## Workflow actions must be mirrored first

`DEFAULT_ACTIONS_URL=self` (set in the app pod definition): a reference
without a host, e.g. `uses: actions/checkout@v4`, is cloned from
`https://forgejo.local/actions/checkout`. Every action a workflow uses
must therefore exist as a **public** repository on the instance — the
runner clones actions anonymously. The operator keeps the mirrors (for
example an `actions` organization mirroring the upstream repos).

- No mirror, no workflow: the first run fails cloning the action.
- A full URL in `uses:` (`uses: https://github.com/owner/repo@v4`)
  bypasses the setting and still verifies TLS: the runner's git bundle
  keeps the public CAs next to the instance certificate.
- Changing `DEFAULT_ACTIONS_URL` does not invalidate
  `/srv/forgejo-runner/.cache`: delete it afterwards, or cached clones
  keep pointing at the previous host.
- JavaScript actions (`actions/checkout@v4`) need `node` and git in the
  job image. The default job image `node:24-bookworm` has both, so
  `runs-on: docker` needs no per-workflow image choice. A minimal image
  (Alpine, plain Debian) has neither git nor node: the runner falls back
  to `sh` and `actions/checkout` cannot run.

## CI runner (same box)

The runner shares the machine with Forgejo. The playbook applies these
mitigations; keep them when editing templates:

- The podman socket is mounted into the runner container only. Job
  containers never receive it. Socket access is root-equivalent on the
  host; this is the main residual risk of the same-box design.
- No privileged jobs, no engine-in-engine. Job images are built with
  buildah inside jobs.
- Job containers get a user namespace (`userns="auto:size=65536"` in
  `/etc/containers/containers.conf`) and per-job
  `--memory=1g --cpus=1 --cap-add SYS_ADMIN --security-opt apparmor=unconfined`
  from the runner config; runner capacity is 2. These assume a 2 vCPU /
  4 GB machine; do not raise capacity beyond it.
- The runner publishes no ports; it only dials the instance over HTTPS.
- The runner and its job containers pin the instance certificate. The
  runner's `insecure` option stays `false`: verification is never
  turned off.
- Recommended but not configured: disable or gate workflows from fork
  pull requests. With registration disabled only admin-created accounts
  can push, so exposure is limited to trusted users — until you change
  that.

## Container registry (build, push, use)

The instance serves an OCI registry at `/v2/` under the same host and
certificate as the web UI. A pipeline can build an image, push it, and
a later job can run inside it.

- Build: use `repo-templates/build-multiarch.yml` for new repositories.
  It installs `buildah` in the job and drives the buildah CLI directly.
  Containerfile `RUN` steps work: the job gets a user namespace,
  `CAP_SYS_ADMIN`, and an AppArmor exception. The template hardcodes the
  registry name `forgejo.local` — replace it with your `lan_name`.
- Push: buildah 1.28 has no `--password-stdin`; the template writes a
  temporary authfile so the token stays out of the process list. The
  credential must be a **user token with `write:package`**, stored as a
  repository secret named `REGISTRY_TOKEN`. The automatic Actions token
  authenticates against the registry but cannot push — known upstream
  limitation. Secrets can be set through
  `PUT /api/v1/repos/<owner>/<repo>/actions/secrets/<NAME>` with
  plaintext `data` (this instance has no public-key route; that path
  answers 405).
- Use: `jobs.<id>.container.image: forgejo.local/<owner>/<repo>:<tag>`.
  The host engine pulls it, so the engine must trust the certificate:
  the playbook installs it at `/etc/containers/certs.d/<lan_name>/forgejo.crt`.
  The `.crt` suffix is load-bearing: that directory is read by
  extension, and other names are ignored. No `container.credentials`
  are needed when the package is public, which it is by inheritance
  from the repository the image name matches.
- A 401 from the OCI endpoints is the authentication challenge, not a
  refusal. Reading it as "private" is wrong.
- Job image consequences: the runner replaces the image entrypoint with
  `tail -f /dev/null` and picks the shell by probing, so a bash-free
  image runs steps with `sh -e`. Pin job images by tag rather than
  digest: the registry reports a `Docker-Content-Digest` that differs
  from the local image id.

## Access from job containers

- The instance certificate is mounted into every job container at
  `/etc/ssl/certs/forgejo-lan.crt` and `GIT_SSL_CAINFO` points there,
  so `git` over HTTPS works out of the box.
- What else trusts the instance depends on the tool inside the job:
  - OpenSSL-based tools (curl, wget, git) already trust it in Debian
    job images, because the file sits in `/etc/ssl/certs`.
  - Node keeps its own CA store. The runner sets
    `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/forgejo-lan.crt` for every job,
    so Node needs no per-workflow setup. The variable is additive:
    public hosts keep verifying.
  - Python `requests` reads the `certifi` bundle, not the system one.
    It needs `REQUESTS_CA_BUNDLE`, which must be set **per job**: as a
    global it replaces the whole trust store and breaks verification of
    public hosts.
  - Running `update-ca-certificates` inside a job helps nothing for
    Node and lasts only for that job container.
- Both addresses work inside jobs: the LAN address, and the name, which
  the runner writes into every job container's `/etc/hosts` through
  `--add-host`. The certificate names both. If the LAN address changes,
  re-run the playbook — it updates the pod definitions, the target env
  file, and the runner config together.
- Host paths other than the certificate are not mountable: the runner
  only allows volumes listed in `valid_volumes` in
  `/srv/forgejo-runner/config.yaml`. List the exact source path; an
  unlisted `--volume` is dropped with a warning and the job runs
  without the file.

## Smoke test

The playbook does not push repositories. To prove Actions end to end
after a fresh install, mirror `actions/checkout`, create a throwaway
repo in the web UI, push this workflow, and watch the run succeed:

```yaml
name: smoke
on: [push]
jobs:
  ca-pin:
    runs-on: docker
    steps:
      - run: |
          test -f /etc/ssl/certs/forgejo-lan.crt
          getent ahostsv4 forgejo.local
          git ls-remote https://forgejo.local/<owner>/<repo>.git >/dev/null
          echo "git over https by name with pinned CA ok"
```

Delete the repository afterwards.
