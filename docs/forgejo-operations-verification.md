# Forgejo Verification

Measured results for the instance installed by
`docs/forgejo-install-recipe.md`, grouped by the change set that produced
them. The problems found while reaching these results are in
`docs/forgejo-operations.md`.

## First run

- `curl http://<IP>/` returns HTTP 200, title
  `Forgejo: Beyond coding. We forge.`
- `ss -tlnp`: ports 80 and 2222 listen on `<IP>` only; no `[::]:80` or
  `[::]:2222` listener, so the public IPv6 address serves nothing.
- `ssh -p 2222 git@<IP>` reaches the Forgejo SSH server
  (`Permission denied (publickey)` — expected before any key is added).
- Container logs clean: SQLite initialized, web listening on 3000, SSH
  server on 2222, `AppURL(ROOT_URL)` matching the configured address.
- `getent ahostsv4 forgejo.local` returns the LAN address and
  `curl http://forgejo.local/` returns 200 (after changes 12–13).

## HTTPS, runner and backup (changes 18–23)

- `curl --cacert forgejo.crt https://<IP>/` returns HTTP 200, title
  `Forgejo: Beyond coding. We forge.`
- `curl http://<IP>/` returns 307 with `Location: https://<IP>/`. The
  redirect keeps the method, so old `http://` clone URLs keep working.
- `curl https://<IP>/` without `--cacert` fails: the self-signed
  certificate is rejected, which is the point — verification stays on
  everywhere.
- `ss -tlnp`: ports 80, 443 and 2222 listen on `<IP>` only; no `[::]`
  listener, so the public IPv6 address serves nothing.
- `ssh -p 2222 git@<IP>` still reaches the Forgejo SSH server
  (`Permission denied (publickey)`); the SSH path is untouched by TLS.
- Container logs clean: `Listen: https://0.0.0.0:3000`,
  `AppURL(ROOT_URL): https://<IP>/`, `Redirecting: 0.0.0.0:80`,
  `SSH server started on :2222`.
- Runner: log line `declared successfully` after the restart, runners
  API shows `idle`, and the `Declare` POST arrives on the https listener.
- CI: smoke run 5 `success` with both jobs `success`; the `ca-pin` job
  log shows `GIT_SSL_CAINFO=/etc/ssl/certs/forgejo-lan.crt`, the mounted
  certificate, and `git over https with pinned CA ok`.
- CI with external access: run 11 `success`. The runner downloaded
  `actions/checkout` from `data.forgejo.org`, the job pulled
  `node:20-bookworm` from the registry, and the checkout ran over HTTPS
  with the pinned certificate. A separate job installed `curl` with
  `apt-get` and read `/api/v1/version` from the instance.
- Runner trust is the mount: with the `/etc/ssl/certs` entry removed the
  daemon exits with `fail to invoke Declare … x509: certificate signed
  by unknown authority`; restored, it logs `declared successfully`.
- `SSL_CERT_FILE` on the runner changes nothing for actions: run 12 was
  `success` with the variable set, and `git ls-remote` inside the runner
  image still verified `data.forgejo.org` with `SSL_CERT_FILE` pointing
  at a nonexistent file.
- Backup: `systemctl start forgejo-backup.service` wrote a new dump; the
  newest dump holds 129 entries and none of them is the key or the
  certificate directory.
- `getent ahostsv4 forgejo.local` returns the LAN address and
  `curl --cacert forgejo.crt https://forgejo.local/` returns 200: the
  certificate covers the mDNS name as well as the address.

## Job name resolution (change 27)

- `getent ahostsv4 forgejo.local` inside a job container returns the LAN
  address alone. Without the option the same lookup returns every
  address of the machine: `192.168.1.40 172.18.0.1 172.17.0.1` on a
  user-defined network, and nothing at all on the default bridge.
  `resolvectl query forgejo.local` on the host reports
  `Data from: synthetic` for the same reason.
- CI run 15 `success`, both jobs green: `name-in-job` resolved the name
  and ran `git ls-remote https://forgejo.local/<owner>/ci-dns-test.git`;
  `node-by-name` read `/api/v1/version` from `https://forgejo.local/`
  with `NODE_EXTRA_CA_CERTS`.
- The runner itself is unaffected: `declared successfully` after the
  restart, runners API `idle`.
- Recipe step 16 was replayed against a fresh `generate-config` output
  and produced a file identical to the deployed
  `/srv/forgejo-runner/config.yaml`.

## Name pin and Node trust (changes 28–29)

- `docker exec forgejo getent ahostsv4 forgejo.local`, and the same in
  `forgejo-runner`, return the LAN address alone. Before the pin each
  returned three addresses: the LAN address, `172.18.0.1` and
  `172.17.0.1`.
- CI run 16 `success`, three jobs green:
  - `node-by-name` logged `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/forgejo-lan.crt`
    without setting it in the workflow, and fetched
    `https://forgejo.local/api/v1/version`.
  - `public-trust-intact` fetched `https://registry.npmjs.org/` with
    status 200, so the extra CA does not replace the public store.
  - `git-by-name` ran `git ls-remote https://forgejo.local/<owner>/…`.
- After the compose recreate: `curl --cacert forgejo.crt https://<IP>/`
  returns 200, and the runner logs `declared successfully`.
- Recipe step 16 replayed against a fresh `generate-config` output again
  produced a file identical to the deployed config.

## Canonical URL by name (change 30)

- Container logs after the recreate: `AppURL(ROOT_URL):
  https://forgejo.local/` and `Redirecting: 0.0.0.0:80 to
  https://forgejo.local`.
- `curl --cacert forgejo.crt https://forgejo.local/` returns 200; the
  page embeds `appUrl: 'https://forgejo.local/'`. The mismatch banner
  is injected by the frontend JavaScript comparing the browser host
  with that value — the server-rendered HTML is identical for both
  hosts (diff: only a timing comment), so curl cannot show or hide the
  banner; a browser at `https://forgejo.local/` matches and shows
  nothing.
- `curl --cacert forgejo.crt https://<IP>/` still returns 200: the
  address serves, browsers just see the banner there.
- `curl http://<IP>/` returns 307 with `Location:
  https://forgejo.local/`.
- Runner: `.runner` address now `https://forgejo.local/`, log line
  `declared successfully` after the restart, runners API
  `"status":"idle"`.

## Email placeholder cleanup (change 31)

- `PATCH /api/v1/admin/users/<ADMIN_USER>` returned 200;
  `forgejo admin user list` shows `<ADMIN_USER>@forgejo.invalid`.
- The listing also showed a second, operator-created account `robot`
  with email `robot@forgejo.local`. `.local` is reserved for mDNS and
  should not appear in addresses; changing that account's email is the
  operator's call, not part of this change.

## Actions served by the instance (change 32)

- `app.ini` after the recreate: `[actions] DEFAULT_ACTIONS_URL = self`.
- Smoke workflow with `uses: actions/checkout@v4` against the mirrored
  public repo `actions/checkout` (anonymous `info/refs` request: 200):
  the job log shows `git clone 'https://forgejo.local/actions/checkout'
  # ref=v4` — the relative reference resolves to the instance.
- First attempt failed on runner-side trust: the Go daemon trusts the
  loose certificate in `/etc/ssl/certs`, but the runner's git (OpenSSL)
  reads the `ca-certificates.crt` bundle and reported `SSL certificate
  OpenSSL verify result: self-signed certificate (18)`. The runner
  image is Alpine without `update-ca-certificates`; the compose command
  now builds a merged bundle at start (120 certificates including the
  instance) and `GIT_SSL_CAINFO` points at it.
- Second attempt failed for an unrelated reason: `actions/checkout@v4`
  is a JavaScript action and the job image
  `data.forgejo.org/forgejo/runner:13.1.0` has no node
  (`exec: "node": executable file not found`). With `node:20-bookworm`
  (node + git) the run is `success`.
- The action cache holds bare clones with the old remote: before the
  change `/srv/forgejo-runner/.cache/act/*/*/config` pointed at
  `https://data.forgejo.org/actions/checkout`. After clearing the cache
  the new clone's remote is `https://forgejo.local/actions/checkout`.
- Runner after the recreate: `declared successfully`, runners API
  `idle`. Smoke repo `ci-actions-self` deleted afterwards; the throwaway
  push tooling under `/opt/ci-self` (including its credential file) was
  removed in the same session.

## Default job image node:20-bookworm (change 33)

- `/srv/forgejo-runner/.runner` label now `docker:docker://node:20-bookworm`;
  runner id and token unchanged, log `declared successfully` after the
  restart.
- Smoke workflow with `runs-on: docker` and no `container.image`: run
  21 `success`, job log shows `Start image=node:20-bookworm`,
  `actions/checkout@v4` ran with `git version 2.39.5`, and
  `node --version` printed `v20.20.2`.
- Side effect: `debian:bookworm` is now unused; the daily cleanup
  removes it after its 7-day grace period, as designed.
- Smoke repo `ci-default-image` and the `/opt/ci-self` push tooling
  deleted afterwards.

## Default job image on the Active LTS line (change 34)

- `/srv/forgejo-runner/.runner` label now `docker:docker://node:24-bookworm`;
  runner id and token unchanged, log `declared successfully` after the
  restart.
- Smoke workflow with `runs-on: docker` and no `container.image`: run
  22 `success`, job log shows `Start image=node:24-bookworm`,
  `node --version` printed `v24.21.0`, and `actions/checkout@v4` ran
  with `git version 2.39.5`. The image pull (1.14 GB) happened inside
  the job.
- Why: Node 20 reached end-of-life 2026-04-30; `node:20-bookworm` is
  frozen at 20.20.2 and receives no security fixes. Node 24 is the
  Active LTS line at this date (Maintenance from 2026-10-20, supported
  to 2028-04-30).
- `node:20-bookworm` (1.1 GB) is now unused; the daily cleanup reclaims
  it after its 7-day grace period.
- Smoke repo `ci-lts-image` and the `/opt/ci-self` push tooling deleted
  afterwards.
