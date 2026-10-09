#!/bin/bash
# Verify every repo path referenced in CODEBASE.md exists on disk.
# Usage: scripts/verify_codebase_sync.sh
set -euo pipefail

CODEBASE="CODEBASE.md"
if [ ! -f "$CODEBASE" ]; then
	echo "CODEBASE.md not found in $(pwd)" >&2
	exit 1
fi

missing=0
# Backtick-wrapped tokens that look like repo-relative paths.
while IFS= read -r path; do
	if [ ! -e "$path" ]; then
		echo "missing: $path" >&2
		missing=1
	fi
done < <(grep -oE '`(docs|forgejo|scripts|tmp)/[A-Za-z0-9._/-]+`' "$CODEBASE" | tr -d '`' | sort -u)

if [ "$missing" -eq 0 ]; then
	echo "CODEBASE.md paths all exist"
fi
exit "$missing"
