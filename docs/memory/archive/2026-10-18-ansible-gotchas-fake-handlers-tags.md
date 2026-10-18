---
topic: "Ansible gotchas hit during the playbook build: fake handlers, tags, globs, facts"
importance: medium
category: warning
tags: [ansible, idempotent, tags, check-mode]
created: 2026-10-18T18:53:10Z
model: kompis/qwen3.8-flash-next-iq3_s
---

In a plain playbook with `import_tasks`, tasks written at the end of
the file are NOT handlers — they run every pass and restart services;
use `register` + `when: x.changed` instead of `notify`. Tags on an
`import_tasks` do not skip the tasks by default; add the `never` tag
for opt-in groups like `verify`. The `command` module does not expand
globs (`ls *.zip` fails) — use `shell`. Network interfaces are
`ansible_facts['interfaces']`, not `['devices']` (block devices).
Read-only probes need `check_mode: false` so `--check` still verifies.
