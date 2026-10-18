# Forgejo Install Steps

The reproduce procedure for the instance described in
`docs/forgejo-install-recipe.md`: the commands, in order, that bring a
fresh Debian 13 machine to the state the change table records. The
problems found along the way are in `docs/forgejo-footguns.md`.

Ask the operator for the parameters first. The script prompts for the
password so it never lands in shell history or this repo.

The engine is podman; the app and the runner are Kubernetes pod YAML
started by the stock `podman-kube@.service` template (changes 39–45).
The change table records the first target's move from HTTP to HTTPS as
changes 18–23 and from Docker to podman as changes 39–45; the files in
this repo are already in the final state, so the steps below reach it on
a fresh machine in one pass.

```bash
# 0. Collect parameters. Real values live in the gitignored .env at the
# repo root (see .env.example); anything missing is prompted for.
[ -f .env ] && set -a && . ./.env && set +a
KEY=${KEY:-tmp/ssh/id_ed22519}          # path to the SSH private key
[ -n "${IP:-}" ]            || read -r -p "Target IP: " IP
[ -n "${LAN_RESOLVER:-}" ]  || read -r -p "LAN resolver IP: " LAN_RESOLVER
[ -n "${ADMIN_USER:-}" ]    || read -r -p "Admin username: " ADMIN_USER
[ -n "${ADMIN_PASSWORD:-}" ]|| read -s -p "Admin password: " ADMIN_PASSWORD; echo
ADMIN_PASS=${ADMIN_PASSWORD:-$ADMIN_PASS}
SSH="ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new root@$IP"

# 0b. Check access (fails fast if the key is not authorized)
$SSH 'whoami'

# 1. Set hostname
$SSH 'hostnamectl set-hostname forgejo'

# 2. Make the hostname locally resolvable
$SSH 'printf "127.0.1.1\tforgejo\n" >> /etc/hosts'

# 3. Apply pending security upgrades
$SSH 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y'

# 4. podman engine from Debian, plus catatonit (podman builds the local
# pause image with it; kube play fails without it). Enable the
# Docker-compatible API socket: the Actions runner talks to the engine
# through it.
$SSH 'apt-get install -y podman catatonit && systemctl enable --now podman.socket'

# 4b. Engine defaults (change 39): job containers get a user namespace
# (the size must be explicit: plain "auto" sizes too small and breaks
# apt inside jobs) and containers get the LAN resolver directly (the
# host's systemd-resolved stub is unreachable from a container
# namespace). The `containers` system user owns the auto-namespace id
# pool; Debian ships /etc/subuid and /etc/subgid empty.
scp -i $KEY forgejo/containers.conf root@$IP:/etc/containers/containers.conf
$SSH "sed -i 's/192\\.0\\.2\\.1/$LAN_RESOLVER/' /etc/containers/containers.conf"
$SSH 'grep -q "^containers:" /etc/subuid || { printf "root:100000:4294867296\ncontainers:100000:4294867296\n" > /etc/subuid; printf "root:100000:4294867296\ncontainers:100000:4294867296\n" > /etc/subgid; }'

# 5. Data directories owned by the container user (uid/gid 1000)
$SSH 'mkdir -p /srv/forgejo /srv/forgejo-runner /opt/forgejo/kube && chown 1000:1000 /srv/forgejo'

# 6. Deploy the pod definitions and the target address record. The kube
# YAML carries the LAN address literally (podman kube play has no
# variable interpolation): replace the address from the repo default
# with this target's. /opt/forgejo/.env (mode 600) stays the record
# gen-cert.sh reads.
scp -i $KEY forgejo/kube/forgejo.yaml forgejo/kube/runner.yaml root@$IP:/opt/forgejo/kube/
$SSH 'sed -i "s/192\.0\.2\.40/'"$IP"'/g" /opt/forgejo/kube/*.yaml'
printf 'LAN_IP=%s\n' "$IP" | $SSH 'cat > /opt/forgejo/.env && chmod 600 /opt/forgejo/.env'

# 6b. Certificate, before the first start: the pod definitions point at
# /srv/forgejo-certs and Forgejo will not start without it. The script
# reads LAN_IP from the .env written above and is safe to re-run.
scp -i $KEY forgejo/gen-cert.sh root@$IP:/opt/forgejo/
$SSH 'chmod 755 /opt/forgejo/gen-cert.sh && /opt/forgejo/gen-cert.sh'

# 6c. Global encryption key, before the first start: the pod definition
# mounts /opt/forgejo/secrets/secret_key into the container and sets
# SECRET_KEY_URI. Forgejo exits at startup if the file is missing, or if
# SECRET_KEY and SECRET_KEY_URI both have a value. The value is generated
# by Forgejo itself and is never printed.
$SSH 'mkdir -m 750 -p /opt/forgejo/secrets && podman run --rm --entrypoint /usr/local/bin/forgejo codeberg.org/forgejo/forgejo:16.0.5 generate secret SECRET_KEY > /opt/forgejo/secrets/secret_key && chown root:1000 /opt/forgejo/secrets/secret_key && chmod 640 /opt/forgejo/secrets/secret_key'

# 7. Start both pods through the systemd template. The instance name is
# the YAML path with / replaced by -; the file names must not contain
# hyphens, because %I turns every - back into / (change 40).
$SSH 'systemctl start podman-kube@opt-forgejo-kube-forgejo.yaml.service podman-kube@opt-forgejo-kube-runner.yaml.service'
$SSH 'systemctl enable podman-kube@opt-forgejo-kube-forgejo.yaml.service podman-kube@opt-forgejo-kube-runner.yaml.service'

# 8. Verify: the three published ports bind to the LAN address only.
$SSH "ss -tlnp | grep -E '$IP:(443|80|2222) '"

# 8b. Take the public certificate to the operator machine so clients and
# CI can pin it. The private key never leaves the target.
mkdir -p tmp/certs && scp -i $KEY root@$IP:/srv/forgejo-certs/forgejo.crt tmp/certs/forgejo.crt
CA=$PWD/tmp/certs/forgejo.crt
curl -s --cacert "$CA" -o /dev/null -w 'https: %{http_code}\n' "https://$IP/"          # expect 200
curl -s -o /dev/null -w 'http: %{http_code} -> %{redirect_url}\n' "http://$IP/"        # expect 307

# 9. Daily backup: script + systemd timer, keep 7 newest dumps
scp -i $KEY forgejo/backup.sh forgejo/forgejo-backup.service forgejo/forgejo-backup.timer root@$IP:/opt/forgejo/
$SSH 'chmod +x /opt/forgejo/backup.sh && cp /opt/forgejo/forgejo-backup.{service,timer} /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now forgejo-backup.timer'

# 10. Test one backup run. The dump leaves the container registry blobs
# out (`--skip-package-data` in the script): CI rebuilds the images. Zip
# entry names are stored uncompressed, so grep reads the file list
# without unzip on the target. Expect the "no registry blobs" line.
$SSH 'systemctl start forgejo-backup.service && ls -la /srv/forgejo-backups/ && D=$(ls -1t /srv/forgejo-backups/forgejo-dump-*.zip | head -1) && { grep -q data/packages "$D" && echo "FAIL: registry blobs in $D" || echo "ok: no registry blobs in $D"; }'

# 11. Create the admin account (email is required; placeholder domain
# ok). The placeholder uses `.invalid` (RFC 6761: never deliverable);
# `.local` is reserved for mDNS and must not appear in email addresses.
# Credentials travel on stdin so special characters cannot break the
# remote command line and never appear in the process list. The
# container is forgejo-forgejo: kube play names containers <pod>-<name>.
printf '%s\n%s\n' "$ADMIN_USER" "$ADMIN_PASS" |
  $SSH 'read -r U; read -r P; podman exec -u 1000 forgejo-forgejo forgejo admin user create --username "$U" --password "$P" --email "$U@forgejo.invalid" --admin'

# 12. mDNS LAN discovery: libnss-mdns resolves .local names,
# avahi-daemon announces <hostname>.local. Restrict avahi to the LAN
# interface so the machine is not announced on podman bridges. This
# covers host-side lookups only: containers get their own answers from
# the host resolver, which lists every address of the machine (see
# step 16 and change 27).
$SSH 'apt-get install -y libnss-mdns avahi-daemon'
$SSH 'DEV=$(ip -o route get '"$IP"' | sed -n "s/.* dev \([^ ]*\).*/\1/p"); sed -i "/^\[server\]/a allow-interfaces=$DEV" /etc/avahi/avahi-daemon.conf && systemctl restart avahi-daemon'

# 13. Verify mDNS (run on the target; LAN clients need their own mDNS
# client, which desktop OSes have built in)
$SSH 'getent ahostsv4 forgejo.local'   # expect the LAN address

# 14. Runner registration (change 41): generate the config and register
# with the deprecated global token (the one that works with
# forgejo-runner register; pipe it via stdin). The instance URL is the
# canonical name: the stored URL is what the runner dials later, and the
# pod's hostAliases pin resolves the name inside the runner container.
TOKEN=$(curl -s --cacert "$CA" -u "$ADMIN_USER:$ADMIN_PASSWORD" "https://$IP/api/v1/admin/runners/registration-token" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
printf '%s' "$TOKEN" | $SSH 'read -r T; podman run --rm -v /srv/forgejo-runner:/data data.forgejo.org/forgejo/runner:13.1.0 forgejo-runner generate-config > /srv/forgejo-runner/config.yaml && podman run --rm -v /srv/forgejo-runner:/data data.forgejo.org/forgejo/runner:13.1.0 forgejo-runner register --config /data/config.yaml --instance https://forgejo.local/ --token "$T" --labels "docker:docker://node:24-bookworm" --no-interactive'

# 16. Runner config: capacity 2, per-job memory/CPU limits, the
# namespaced CAP_SYS_ADMIN and the apparmor exception that let nested
# buildah RUN work inside the job's user namespace (change 42), the
# certificate mounted into job containers, GIT_SSL_CAINFO and
# NODE_EXTRA_CA_CERTS for those containers, the LAN name written into
# every job container's hosts file (containers get the host resolver's
# synthetic answer for .local, which lists every address of the
# machine), and the mount allow-list (valid_volumes: [] silently drops
# the mount). env_file is turned off: generate-config points it at .env,
# and a daemon whose working directory has no such file logs
# `Missing env file ".env" is ignored` at every start. Job environment
# comes from envs above, so the file is not wanted; an empty value means
# the runner does not look (change 46). The template's two sample `envs`
# entries are deleted: the runner passes them to every job container
# (change 47).
$SSH 'sed -i "s|^  capacity: 1$|  capacity: 2|; s|^  options:$|  options: \"--memory=1g --cpus=1 --cap-add SYS_ADMIN --security-opt apparmor=unconfined --volume /srv/forgejo-certs/forgejo.crt:/etc/ssl/certs/forgejo-lan.crt:ro --add-host=forgejo.local:'"$IP"'\"|; s|^  envs:$|  envs:\n    GIT_SSL_CAINFO: /etc/ssl/certs/forgejo-lan.crt\n    NODE_EXTRA_CA_CERTS: /etc/ssl/certs/forgejo-lan.crt|; s|^  valid_volumes: \[\]$|  valid_volumes:\n    - /srv/forgejo-certs/forgejo.crt|; s|^  env_file: \.env$|  env_file: \"\"|; /^    A_TEST_ENV_NAME_[12]: /d" /srv/forgejo-runner/config.yaml'

# 16b. Verify the edits landed. The seds in step 16 match the generated
# defaults: if a runner version changes generate-config output, they do
# nothing and report nothing. Expect 5, and one address per lookup. The
# sample env entries must be gone, so the last line prints the ok text.
$SSH 'grep -cE "^  capacity: 2$|add-host=forgejo.local|NODE_EXTRA_CA_CERTS:|^  valid_volumes:|^  env_file: \"\"$" /srv/forgejo-runner/config.yaml'
$SSH '! grep -q "A_TEST_ENV_NAME" /srv/forgejo-runner/config.yaml && echo "ok: sample job env entries gone"'
$SSH 'podman exec forgejo-forgejo getent ahostsv4 forgejo.local; podman exec forgejo-runner-forgejo-runner getent ahostsv4 forgejo.local'

# 17. Smoke test over HTTPS: push a workflow, expect a successful run.
# The default job image is node:24-bookworm (changes 33-34), which has
# git and node. The ca-pin job pins the runner image, which also has
# git, to prove the mount there too; the ca-pin and node-trust jobs
# also prove the name pin and the inherited Node CA variable (changes
# 27-29): both address the instance by name.
# GIT_SSL_CAINFO must be an absolute path; a relative one breaks push.
curl -s --cacert "$CA" -u "$ADMIN_USER:$ADMIN_PASSWORD" -X POST "https://$IP/api/v1/user/repos" -H "Content-Type: application/json" -d '{"name":"ci-smoke-test","private":false,"auto_init":true,"default_branch":"main"}' >/dev/null
GIT_SSL_CAINFO="$CA" git clone -q "https://$ADMIN_USER:$ADMIN_PASSWORD@$IP/$ADMIN_USER/ci-smoke-test.git" /tmp/ci-smoke
mkdir -p /tmp/ci-smoke/.forgejo/workflows
cat > /tmp/ci-smoke/.forgejo/workflows/smoke.yml <<YML
name: smoke
on: [push]
jobs:
  plain:
    runs-on: docker
    steps:
      - run: echo hello
  ca-pin:
    runs-on: docker
    container:
      image: data.forgejo.org/forgejo/runner:13.1.0
    steps:
      - run: |
          test -f /etc/ssl/certs/forgejo-lan.crt
          git --version
          getent ahostsv4 forgejo.local
          git ls-remote https://forgejo.local/$ADMIN_USER/ci-smoke-test.git >/dev/null
          echo "git over https by name with pinned CA ok"
  node-trust:
    runs-on: docker
    container:
      image: node:24-bookworm
    steps:
      - run: |
          node -e 'fetch("https://forgejo.local/api/v1/version").then(r => r.text()).then(t => console.log("node by name ok", t.trim())).catch(e => { console.error("FAIL", e.cause ? e.cause.code : e.message); process.exit(1); })'
YML
git -C /tmp/ci-smoke add -A && git -C /tmp/ci-smoke -c user.email=ci@test -c user.name=ci commit -qm smoke && GIT_SSL_CAINFO="$CA" git -C /tmp/ci-smoke push -q origin main
sleep 30 && curl -s --cacert "$CA" -u "$ADMIN_USER:$ADMIN_PASSWORD" "https://$IP/api/v1/repos/$ADMIN_USER/ci-smoke-test/actions/runs" | sed -n 's/.*"status":"\([^"]*\)".*/first run: \1/p'
# clean up afterwards: DELETE /api/v1/repos/$ADMIN_USER/ci-smoke-test

# 18. Daily disk cleanup: script + systemd timer. 04:15 UTC is after the
# 03:30 backup, so a restore point exists before anything is deleted.
# The first run only starts the 7-day grace record; it deletes nothing
# until an image has been unused for a full week.
scp -i $KEY forgejo/cleanup.sh forgejo/forgejo-cleanup.service forgejo/forgejo-cleanup.timer root@$IP:/opt/forgejo/
$SSH 'chmod +x /opt/forgejo/cleanup.sh && cp /opt/forgejo/forgejo-cleanup.{service,timer} /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now forgejo-cleanup.timer'

# 19. Test one cleanup run and confirm the timer is armed
$SSH 'systemctl start forgejo-cleanup.service && systemctl list-timers forgejo-cleanup.timer'

# 20. Engine registry trust on the host (change 43). The engine pulls
# every job image, so it must verify the instance certificate when a
# pipeline pushes an image to the instance registry and a later job uses
# it. podman reads per-registry trust from
# /etc/containers/certs.d/<registry>/; the runner's /etc/ssl/certs
# mount covers the runner's Go client and the job containers, not the
# engine. Files in that directory are picked by extension: only *.crt
# is trusted as a registry CA (measured: renaming to .pem breaks
# verification). Keep the name forgejo.crt.
$SSH 'mkdir -p /etc/containers/certs.d/forgejo.local && cp /srv/forgejo-certs/forgejo.crt /etc/containers/certs.d/forgejo.local/forgejo.crt && chmod 644 /etc/containers/certs.d/forgejo.local/forgejo.crt'
# Probe without an image in the registry: an x509 error means the trust
# file is missing, misnamed (no .crt suffix) or wrong; "manifest unknown"
# or 401 means TLS passed.
$SSH 'podman pull forgejo.local/library/does-not-exist:latest 2>&1 | tail -1'
```
