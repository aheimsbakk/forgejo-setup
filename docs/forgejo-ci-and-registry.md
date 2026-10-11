# Forgejo CI And Container Registry

How the Actions runner, the container registry, access from job
containers and mirrored workflow actions are set up on the instance. The
problems found on the way are in `docs/forgejo-footguns.md`; the measured
results are in `docs/forgejo-operations-verification.md`.

## Container registry (build, push, use)

The instance serves an OCI registry at `/v2/` under the same host and
certificate as the web UI. A pipeline can build an image, push it there,
and a later job can run inside it. Verified with the kept repositories
`agent/container-build-test` (build and push) and
`agent/container-use-test` (use).

- Build: install `buildah` in the job (`apt-get`) and use
  `redhat-actions/buildah-build@v3` in `base-image` + `content` mode.
  `Containerfile` builds with `RUN` do not work in this runner; see
  `docs/forgejo-footguns.md`.
- Push: `buildah push --authfile <file>`. buildah 1.28 has no
  `--password-stdin`, and an authfile keeps the token out of the process
  list. The credential is a user token with `write:package` stored as a
  repository secret; secrets are set through
  `PUT /api/v1/repos/<owner>/<repo>/actions/secrets/<NAME>` with
  plaintext `data` (this instance has no public-key route: that path
  answers 405).
- Use: `jobs.<id>.container.image: forgejo.local/<owner>/<repo>:<tag>`.
  The host daemon pulls it, so change 36 is required. No
  `container.credentials` are needed when the package is public, which it
  is by inheritance from the repository the image name matches.
- Job image consequences: the runner replaces the image entrypoint with
  `tail -f /dev/null` and picks the shell by probing the image, so a
  bash-free image such as Alpine runs steps with `sh -e`. An image
  without git or node cannot run JavaScript actions or `actions/checkout`.
- Pin job images by tag rather than digest: the registry serves Docker
  v2 manifests and reports a `Docker-Content-Digest` that differs from
  the local image id.

## CI runner (same box)

Operator decision: the Actions runner shares the machine with Forgejo.
Accepted risks and applied mitigations:

- The Docker socket is mounted into the runner container only. Job
  containers never receive it. Socket access is root-equivalent on the
  host; this is the main residual risk of the same-box design.
- No privileged jobs, no docker-in-docker (`privileged: false`).
  Container images in pipelines are built with buildah inside jobs.
- Job containers get `--memory=1g --cpus=1`; runner capacity is 2
  (machine has 2 vCPUs, 4 GB RAM, no swap — do not raise capacity).
- The runner publishes no ports; it only dials the instance, over HTTPS.
- The runner and its job containers pin the instance certificate
  (`/etc/ssl/certs/forgejo-lan.crt`, plus `GIT_SSL_CAINFO` and
  `NODE_EXTRA_CA_CERTS` in the job environment). The runner's `insecure`
  option stays `false`: verification is never turned off.
- Recommended but NOT configured: disable or gate workflows from fork
  pull requests. Only accounts the admin creates can push, so the
  current exposure is trusted users only.
- Off-machine copies of `/srv/forgejo-backups` are strongly advised
  with CI on the box: a compromised job could reach the backups.

## Access from job containers

Verified with a throwaway repository; no per-workflow setup was needed
for git.

- The instance certificate is mounted into every job container at
  `/etc/ssl/certs/forgejo-lan.crt` and `GIT_SSL_CAINFO` points there,
  so `git` over HTTPS works out of the box. Checked with an anonymous
  `git ls-remote` and with the Actions token
  (`git -c http.extraheader="AUTHORIZATION: bearer $GITHUB_TOKEN"`).
- `GIT_SSL_CAINFO` only covers git. What else trusts the instance
  depends on the image:
  - OpenSSL-based tools (curl, wget, git) already trust it in Debian
    job images, because the certificate sits in `/etc/ssl/certs`.
    Tested: `curl` returned 200 and `git ls-remote` worked with the
    mount alone, the file name made no difference, and the same file
    mounted outside that directory was rejected.
  - Node keeps its own CA store. It failed with
    `DEPTH_ZERO_SELF_SIGNED_CERT` even after `update-ca-certificates`,
    and returned 200 with
    `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/forgejo-lan.crt`. The runner now
    sets that variable for every job container (change 29), so Node needs
    no per-workflow setup. The variable is additive: the same job read
    `https://registry.npmjs.org/` and got status 200.
  - Python `requests` reads the `certifi` bundle rather than the system
    one, so it needs `REQUESTS_CA_BUNDLE`. That one cannot be set for all
    jobs: it replaces the whole trust store, which would break
    verification of public hosts — the same failure mode as
    `SSL_CERT_FILE` on the runner. Set it per job, pointing at a bundle
    that also holds the public CAs.
- Running `update-ca-certificates` in a job adds the certificate to the
  bundle file (142 entries to 143) and changes nothing for Node. It
  needs root, and it only lasts for that one job container.
- Both addresses work in job containers: the LAN address, and
  `forgejo.local`, which the runner writes into every job container's
  `/etc/hosts` through `--add-host` (change 27). The certificate names
  both, so TLS verification passes either way. Since change 30 the
  canonical URL is the name, so the clone URLs Forgejo hands out — and
  the URLs Actions checkouts use — are name-based and resolve through
  that pin. If the LAN address changes, update `/opt/forgejo/.env` and
  the `--add-host` entry in `/srv/forgejo-runner/config.yaml` together.
- Job containers reach the instance and the internet. Verified: the
  runner downloaded `actions/checkout` from `data.forgejo.org`, a job
  pulled `node:20-bookworm` from the container registry, and
  `apt-get install` worked inside a job.
- Host paths other than the certificate are not mountable: the runner
  only allows what `valid_volumes` lists.

## Workflow actions (mirrored on the instance)

- Since change 32 `DEFAULT_ACTIONS_URL=self`: a reference without a
  host, e.g. `uses: actions/checkout@v4`, is cloned from
  `https://forgejo.local/actions/checkout`. Every action a workflow
  uses must exist as a repository on the instance; the operator keeps
  the mirrors (e.g. the `actions` organization). The mirror must be
  public: the runner clones actions anonymously.
- A full URL in `uses:` (`uses: https://github.com/owner/repo@v4`)
  bypasses the setting. It still verifies: the runner's git bundle
  keeps the public CAs next to the instance certificate.
- The runner downloads actions with git inside the runner container.
  That container's `GIT_SSL_CAINFO` points at a merged bundle (public
  CAs + instance certificate) built at every start; the loose file in
  `/etc/ssl/certs` only covers the Go daemon.
- Changing `DEFAULT_ACTIONS_URL` does not invalidate
  `/srv/forgejo-runner/.cache`: delete it afterwards, or cached clones
  keep pointing at the previous host.
- JavaScript actions (e.g. `actions/checkout@v4`) need `node` in the
  job image, and git for the checkout itself. Since changes 33-34 the
  default image `node:24-bookworm` has both, so `runs-on: docker`
  needs no per-workflow image choice for them.
