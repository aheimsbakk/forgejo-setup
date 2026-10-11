# Memory Index

| topic | category | importance | tags | expires | file |
|---|---|---|---|---|---|
| Forgejo install recipe project | decision | high | forgejo, deployment, recipe, ssh | | archive/2026-10-09-forgejo-install-recipe-project.md |
| Forgejo container SSH port collision inside the image | warning | medium | forgejo, docker, ssh, port-collision | | archive/2026-10-09-forgejo-ssh-port-collision.md |
| Forgejo backup design: daily dump, 7 kept, remote copy later | decision | medium | forgejo, backup, systemd, retention | | archive/2026-10-09-forgejo-backup-design.md |
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
