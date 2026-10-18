---
topic: "forgejo-runner generate-config sets env_file: .env; empty value stops the start warning"
importance: medium
category: warning
tags: [forgejo, actions, runner, config, env-file]
created: 2026-10-18T17:50:43Z
model: kompis/qwen3.8-flash-next-iq3_s
---

`forgejo-runner generate-config` writes `env_file: .env`. With no such
file in the daemon's working directory the first log line at every start
is `Missing env file ".env" is ignored` — a warning, and the runner
declares normally. Set the key to `""` to stop the lookup; job
environment belongs in `container.envs`. Regenerating the config also
brings back the template's sample `envs` entries (`A_TEST_ENV_NAME_1`,
`A_TEST_ENV_NAME_2`), which reach every job container — strip them in
the same pass.
