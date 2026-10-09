# Blueprint

Language-agnostic specification for the Forgejo LAN install project.
The "product" is a reproducible deployment: documentation plus the exact
configuration files deployed to a target machine.

## System Goals

- Install Forgejo (self-hosted git forge) on a fresh Debian 13 machine
  using only an SSH private key and the machine's IP address.
- Serve the web UI over HTTPS and git-over-SSH only on the LAN address;
  never on public interfaces. The certificate is self-signed and pinned by
  the clients that connect (browsers, git clients, CI). Plain HTTP serves
  redirects to HTTPS only.
- Keep a daily, full, self-contained restore point with bounded
  retention (7 newest).
- Provide CI (Forgejo Actions) with a runner on the same machine under
  explicit resource limits.
- Record every change applied to a target so the install is auditable
  and repeatable.

## Component Hierarchy

- Recipe component — ordered, parameterized change log and reproduce
  procedure; the entry point of the whole system.
- Service configuration component — declarative definitions of the
  Forgejo app container and the Actions runner container, including
  port bindings, storage mounts and all application settings.
- Certificate component — self-signed key and certificate generation on
  the target, storage in a dedicated host directory, and export of the
  public certificate so clients and CI can pin it.
- Backup component — dump creation, relocation out of the live data
  directory, retention trimming, scheduled activation.
- Parameter store component — per-deployment values (address, admin
  account, key path) kept outside version control.
- Discovery component — LAN name resolution and announcement.

## Data Flow

- Operator runs the reproduce procedure over SSH against the target.
- Parameters flow: parameter store -> reproduce procedure -> service
  configuration on the target.
- The certificate component writes a private key and a certificate to a
  dedicated host directory; the service configuration mounts that
  directory read-only. The public half travels back to the operator and
  from there to client devices, the runner container and job containers.
- Forgejo writes all state to the host data directory; the backup
  component reads it through the application's own dump facility and
  writes zip files to a separate backup directory.
- The runner container dials the instance over HTTPS; it publishes no
  ports.

## State Management

- Application state: single data directory on the host, owned by the
  container user identity.
- Certificate state: one key and certificate pair per deployment, valid
  five years. Regenerating it is a deliberate act: clients and CI that
  pinned the previous pair stop trusting the instance until they are
  updated.
- Backup state: at most 7 dump files; trimming is part of every backup
  run.
- Runner registration state: stored in the runner data directory on the
  host and in the instance database. It also records the instance
  address, so its scheme must match what the instance serves.
- Deployment parameters: one untracked environment file per checkout.

## Contracts

- Reproduce procedure: takes key path, target address, admin name and
  admin password; each step is idempotent or fails fast; verification
  steps follow every change.
- Service configuration: application settings are expressed only as
  environment-style variables in the service definition; the LAN
  address is the single injected variable. TLS settings point at the
  certificate directory; the plain HTTP listener only redirects to
  HTTPS. The runner and its job containers receive a read-only copy of
  the certificate and are told to trust it.
- Certificate contract: one run leaves a private key and a certificate
  in the certificate directory. The certificate names the LAN address,
  the LAN name and the loopback names in its subject alternative names,
  and is valid for five years. A run that finds an existing pair changes
  nothing. The key is readable only by the container user identity.
- Backup contract: one run produces exactly one new dump file in the
  backup directory and leaves at most 7; the dump contains database,
  repositories, configuration and uploaded data.
- Error boundaries: access check first; every remote step is verified
  before the next one runs.

## Persistence

- Application database: embedded single-file database inside the data
  directory; no separate database server.
- Certificate and private key: their own host directory, outside the
  application data directory, so application dumps never contain the
  key.
- Backups: zip archives named by creation time, retained by count.
- Parameter store: untracked file, restricted permissions, never
  committed.

## External Interfaces

- SSH (root) to the target; key-based only.
- HTTPS on the LAN address for the web UI, git-over-HTTP and the
  administration API. The certificate is self-signed; every client pins
  it.
- HTTP on the LAN address answers redirects to HTTPS and nothing else.
- Distribution package repositories for the container engine, Compose,
  and mDNS packages.
- Official container images for the application and the runner, pinned
  to stable versions.
- Public HTTPS hosts for Actions: the runner downloads third-party
  actions, so it keeps the public trust store next to the pinned
  certificate.
- mDNS/multicast on the LAN for name discovery.
- Instance administration API for runner registration and smoke tests.

## Security Boundaries

- Published ports bind to the LAN address only.
- The web listener serves TLS only. The plain HTTP listener answers
  redirects and never serves content or repository data.
- The private key stays on the target and is readable only by the
  container user identity; only the public certificate leaves the
  machine.
- Clients, the runner and job containers pin the certificate. The
  runner's option to skip certificate verification stays off.
- The container-engine socket reaches the runner daemon only, never
  job containers; no privileged jobs.
- Per-job CPU and memory ceilings; fixed runner concurrency.
- Secrets and credentials are never written to tracked files.
