# Memory Index

| topic | category | importance | tags | expires | file |
|---|---|---|---|---|---|
| Forgejo install recipe project | decision | high | forgejo, deployment, recipe, ssh | | archive/2026-10-09-forgejo-install-recipe-project.md |
| Forgejo container SSH port collision inside the image | warning | medium | forgejo, docker, ssh, port-collision | | archive/2026-10-09-forgejo-ssh-port-collision.md |
| Forgejo backup: dump excludes registry blobs, package rows stay | decision | high | forgejo, backup, dump, registry, retention | | archive/2026-10-11-forgejo-backup-excludes-registry-blobs.md |
| Forgejo SECRET_KEY stays empty; set it with SECRET_KEY_URI and a file mount | decision | high | forgejo, secrets, compose, backup, restore | | archive/2026-10-11-forgejo-secret-key-file.md |
| Forgejo Actions runner on same box, mitigations applied | decision | high | forgejo, actions, runner, security, same-box | | archive/2026-10-09-forgejo-runner-same-box.md |
| Forgejo deployment constraints: Docker, LAN-only HTTPS | decision | high | forgejo, docker, lan-only, https, deployment | | archive/2026-10-09-forgejo-docker-lan-only-https.md |
| Forgejo runner certificate pinning: three footguns | warning | medium | forgejo, actions, runner, tls, volumes | | archive/2026-10-09-forgejo-runner-cert-pinning-footguns.md |
| Job container trust: /etc/ssl/certs covers OpenSSL tools, runner sets NODE_EXTRA_CA_CERTS | pattern | medium | forgejo, actions, tls, ca-certificates, job-containers | | archive/2026-10-10-job-container-trust-per-tool.md |
| Docker disk cleanup: 7-day grace record, stack images protected | decision | medium | forgejo, docker, cleanup, disk, systemd | | archive/2026-10-09-docker-cleanup-grace-record.md |
| Containers and <hostname>.local: two failure modes, one fix | warning | medium | forgejo, actions, dns, job-containers, runner | | archive/2026-10-10-containers-hostname-local-two-failure-modes.md |
| Forgejo URL mismatch banner is client-side; canonical URL is the name | warning | medium | forgejo, root-url, dns, verification, banner | | archive/2026-10-10-canonical-url-banner-is-client-side.md |
| Email placeholders: use .invalid, never .local | warning | low | forgejo, email, mdns, rfc6761 | | archive/2026-10-10-email-placeholder-invalid-not-local.md |
| Runner git and Go have separate trust stores; merged CA bundle at start | warning | high | forgejo, actions, runner, tls, ca-bundle | | archive/2026-10-10-runner-git-vs-go-trust.md |
| DEFAULT_ACTIONS_URL=self: mirrored public repos, cache and node gotchas | decision | medium | forgejo, actions, mirror, runner-cache, node | | archive/2026-10-10-default-actions-url-self.md |
| Default job image is node:24-bookworm; the label lives in .runner | decision | medium | forgejo, actions, runner, labels, job-image | | archive/2026-10-10-default-job-image-node-lts.md |
| FORGEJO__ env vars: dotted ini sections need _0X2E_ escape | pattern | medium | forgejo, docker, env-vars, app-ini, pagination | | archive/2026-10-10-env-to-ini-dot-escape.md |
| Actions token cannot push container images; use a user token secret | warning | high | forgejo, actions, registry, packages, token | | archive/2026-10-11-actions-token-cannot-push-packages.md |
| buildah in unprivileged job containers: rootless uid, vfs, no RUN | warning | high | forgejo, actions, buildah, job-containers, seccomp | | archive/2026-10-11-buildah-in-unprivileged-job-containers.md |
| Forgejo dump restore: no restore.sh, blanked SECRET_KEY, git/.ssh owner | warning | high | forgejo, backup, restore, sqlite, secret-key | | archive/2026-10-11-forgejo-dump-restore-footguns.md |
| Two-factor on an account blocks all /api/v1 basic auth | warning | medium | forgejo, api, basic-auth, two-factor | | archive/2026-10-11-two-factor-blocks-basic-auth.md |
