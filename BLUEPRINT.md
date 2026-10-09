# Blueprint

Language-agnostic specification for the Forgejo LAN install project.
The "product" is a reproducible deployment: documentation plus the exact
configuration files deployed to a target machine.

## System Goals

- Install Forgejo (self-hosted git forge) on a fresh Debian 13 machine
  using only an SSH private key and the machine's IP address.
- Serve the web UI over plain HTTP and git-over-SSH only on the LAN
  address; never on public interfaces.
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
- Backup component — dump creation, relocation out of the live data
  directory, retention trimming, scheduled activation.
- Parameter store component — per-deployment values (address, admin
  account, key path) kept outside version control.
- Discovery component — LAN name resolution and announcement.

## Data Flow

- Operator runs the reproduce procedure over SSH against the target.
- Parameters flow: parameter store -> reproduce procedure -> service
  configuration on the target.
- Forgejo writes all state to the host data directory; the backup
  component reads it through the application's own dump facility and
  writes zip files to a separate backup directory.
- The runner container dials the instance address; it publishes no
  ports.

## State Management

- Application state: single data directory on the host, owned by the
  container user identity.
- Backup state: at most 7 dump files; trimming is part of every backup
  run.
- Runner registration state: stored in the runner data directory on the
  host and in the instance database.
- Deployment parameters: one untracked environment file per checkout.

## Contracts

- Reproduce procedure: takes key path, target address, admin name and
  admin password; each step is idempotent or fails fast; verification
  steps follow every change.
- Service configuration: application settings are expressed only as
  environment-style variables in the service definition; the LAN
  address is the single injected variable.
- Backup contract: one run produces exactly one new dump file in the
  backup directory and leaves at most 7; the dump contains database,
  repositories, configuration and uploaded data.
- Error boundaries: access check first; every remote step is verified
  before the next one runs.

## Persistence

- Application database: embedded single-file database inside the data
  directory; no separate database server.
- Backups: zip archives named by creation time, retained by count.
- Parameter store: untracked file, restricted permissions, never
  committed.

## External Interfaces

- SSH (root) to the target; key-based only.
- Distribution package repositories for the container engine, Compose,
  and mDNS packages.
- Official container images for the application and the runner, pinned
  to stable versions.
- mDNS/multicast on the LAN for name discovery.
- Instance administration API for runner registration and smoke tests.

## Security Boundaries

- Published ports bind to the LAN address only.
- The container-engine socket reaches the runner daemon only, never
  job containers; no privileged jobs.
- Per-job CPU and memory ceilings; fixed runner concurrency.
- Secrets and credentials are never written to tracked files.
