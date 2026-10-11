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
- Keep a daily restore point with bounded retention (7 newest).
  Container registry blobs stay out of it: the pipeline rebuilds them and
  they dominate dump size.
- Provide CI (Forgejo Actions) with a runner on the same machine under
  explicit resource limits.
- Keep the container engine's disk use bounded: images, containers,
  networks and build cache that stay unused for a set grace period are
  removed on a daily schedule.
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
- Restore procedure — the backup's counterpart: a file copy that puts the
  dump's data and repositories back into the application layout, keeps
  the instance's own configuration and certificate, and verifies the
  database and the repositories afterwards. The application has no
  restore facility of its own, so the procedure owns the layout mapping.
- Disk cleanup component — scheduled removal of unused container
  engine objects (images, stopped containers, networks, build cache)
  once they have stayed unused through a grace period. The service
  definition is the source of truth for what must be kept.
- Parameter store component — per-deployment values (address, admin
  account, key path) kept outside version control.
- Discovery component — LAN name resolution and announcement. Multicast
  discovery does not reach container workloads, so the reproduce
  procedure also records the name-to-address mapping in the runner's
  job-container settings.

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
  writes zip files to a separate backup directory. The dump leaves out
  the container registry blobs; it keeps the package records that
  describe them.
- The runner container dials the instance over HTTPS; it publishes no
  ports. Workflow actions with a relative reference are downloaded from
  the instance itself, so every action a workflow uses must exist as a
  repository on the instance (operator-maintained mirrors).
- The disk cleanup component reads the service definition to learn
  which images the stack needs, reads the container engine's object
  list, and deletes only objects recorded as unused for the whole grace
  period. It writes its grace record to a host state directory.

## State Management

- Application state: single data directory on the host, owned by the
  container user identity.
- Certificate state: one key and certificate pair per deployment, valid
  five years. Regenerating it is a deliberate act: clients and CI that
  pinned the previous pair stop trusting the instance until they are
  updated.
- Backup state: at most 7 dump files; trimming is part of every backup
  run.
- Container registry state: blobs in the application data directory,
  records in the application database. The blobs are outside the dump, so
  the records outlive them after a restore until the owner's cleanup
  rules delete them.
- Runner registration state: stored in the runner data directory on the
  host and in the instance database. It also records the instance URL,
  so its scheme and host must match what the instance serves; it holds
  the canonical name.
- Container name mapping: the service definition pins the instance name
  to the LAN address taken from the parameter store, and the runner's
  job-container settings hold a separate copy of that pair. The copy
   must be updated whenever the address changes. The default actions
   URL is the instance itself: a workflow action reference without a
   host is fetched from the instance's own repositories.
- Deployment parameters: one untracked environment file per checkout.
- Cleanup grace state: one record per currently unused image, holding
  the day it was first seen unused. An image becomes removable only
  after the grace period has passed. The record is rewritten on every
  run, so it stays bounded by the number of images on the machine.

## Contracts

- Reproduce procedure: takes key path, target address, admin name and
  admin password; each step is idempotent or fails fast; verification
  steps follow every change.
- Service configuration: application settings are expressed only as
  environment-style variables in the service definition; the LAN
  address is the single injected variable. The canonical web address is
  the LAN name: the instance declares itself by name, so clients that
  reach it by name get no mismatch warning. The LAN address still
  serves content and git, but is not canonical. TLS settings point at
  the certificate directory; the plain HTTP listener only redirects to
  the canonical HTTPS URL. The runner and its job containers receive a
  read-only copy of the certificate and are told to trust it. The
  service definition and the job-container settings both map the
  instance name to the LAN address, so the name resolves where
  multicast discovery cannot reach.
- Certificate contract: one run leaves a private key and a certificate
  in the certificate directory. The certificate names the LAN address,
  the LAN name and the loopback names in its subject alternative names,
  and is valid for five years. A run that finds an existing pair changes
  nothing. The key is readable only by the container user identity.
- Encryption key contract: exactly one key file exists outside the
  application data directory, readable by the container user identity and
  named by path in the service definition. The configuration file carries
  the path and no value; the two settings are mutually exclusive, so a
  value in either place is the only form the application accepts. Losing
  the file makes the data the application encrypts at rest unreadable.
- Backup contract: one run produces exactly one new dump file in the
  backup directory and leaves at most 7; the dump contains database,
  repositories, configuration and uploaded data, but not the container
  registry blobs. The package records stay in the database, so a restore
  lists package versions whose files are absent. The package owner's
  cleanup rules clear those records; the pipeline re-pushes the images it
  needs.
- Restore procedure: takes one dump file. It restores the data and the
  repositories only: the service definition supplies the configuration at
  every start, and the encryption key comes from the key file outside the
  data directory. It hands the restored tree to the container user
  identity before the first start. It verifies that the application
  answers, that a repository can be read over git, and that a
  token-authenticated read through the administration API succeeds. The
  previous data directory stays in place as the fallback until those
  checks pass. The certificate, the encryption key file, the runner state
  and the registry blobs are out of scope.
- Disk cleanup contract: one run removes untagged images, images no
  container references that have been unused for the whole grace
  period, containers outside the stack that have been stopped for the
  whole grace period, and unused networks and build cache older than
  the grace period. It never removes volumes, and never removes an
  image named by the service definition. A run that cannot read the
  service definition removes nothing and fails.
- Error boundaries: access check first; every remote step is verified
  before the next one runs.

## Persistence

- Application database: embedded single-file database inside the data
  directory; no separate database server.
- Certificate and private key: their own host directory, outside the
  application data directory, so application dumps never contain the
  key.
- Global encryption key: one file in a host secrets directory outside the
  application data directory, referenced by path from the service
  definition and mounted read-only into the application. The
  configuration file holds no value for it, and no dump contains the
  file.
- Backups: zip archives named by creation time, retained by count.
- Container registry blobs: inside the application data directory, but
  kept out of the dump. They are rebuildable by the pipeline, so they are
  the one part of application state that a restore does not reproduce.
- Parameter store: untracked file, restricted permissions, never
  committed.
- Cleanup grace record: one small file in a host state directory
  outside the application data directory. It holds image identifiers
  and dates only, no secrets.

## External Interfaces

- SSH (root) to the target; key-based only.
- HTTPS on the LAN address for the web UI, git-over-HTTP and the
  administration API, canonically addressed by the LAN name. The
  certificate is self-signed; every client pins it.
- HTTP on the LAN address answers redirects to the canonical HTTPS URL
  and nothing else.
- Distribution package repositories for the container engine, Compose,
  and mDNS packages.
- Official container images for the application and the runner, pinned
  to stable versions.
- Public HTTPS hosts for container images: job images are pulled from
  public registries, so the public trust store stays next to the pinned
  certificate. Workflow actions are not fetched from public hosts: the
  default actions URL is the instance itself, and the operator mirrors
  the action repositories it needs onto the instance.
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
- Disk cleanup acts only on objects the container engine reports as
  unused. Volumes and the images named by the service definition are
  out of scope, so cleanup cannot delete job data or the stack itself.
- Secrets and credentials are never written to tracked files.
