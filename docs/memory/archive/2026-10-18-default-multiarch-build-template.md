---
topic: "Default multiarch build template uses buildah manifest and latest tag"
importance: medium
category: decision
tags: [forgejo, actions, buildah, multiarch, template]
created: 2026-10-18T01:47:51Z
model: kompis/qwen3.8-flash-next-iq3_s
---

`templates/build-multiarch.yml` is the default image-build workflow for
new repositories. It replaces the three current build workflows in
`agent/container-build-test`: `build.yml`, `multiarch.yml`, and
`containerfile.yml`. It builds `amd64` and `arm64`, pushes the
architecture images as `latest-amd64` and `latest-arm64`, then pushes
the manifest list as `latest`. The
manifest list is assembled from registry references because buildah
1.28.2 on the Forgejo runner does not send a local manifest list with
`push --all`. The same file can run on GitHub and Forgejo by choosing
the runner and registry from `github.server_url`. Forgejo still needs a
`REGISTRY_TOKEN` user token with `write:package`.