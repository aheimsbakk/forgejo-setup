#!/bin/bash
# Check CHANGELOG.md basics: heading, latest version matches VERSION,
# and the latest entry carries why/model/tags metadata.
# Usage: scripts/validate-changelog.sh
set -euo pipefail

fail=0

if [ ! -f CHANGELOG.md ]; then
	echo "CHANGELOG.md missing" >&2
	exit 1
fi
head -1 CHANGELOG.md | grep -q '^# Changelog$' || {
	echo "CHANGELOG.md must start with '# Changelog'" >&2
	fail=1
}

version="$(cat VERSION 2>/dev/null || echo unknown)"
grep -q "## \[$version\]" CHANGELOG.md || {
	echo "CHANGELOG.md has no section for VERSION $version" >&2
	fail=1
}

# Metadata bullets must appear in the newest (first) version section.
newest="$(awk '/^## \[/{c++} c==1{print} c==2{exit}' CHANGELOG.md)"
for key in why model tags; do
	echo "$newest" | grep -q "^- \*\*$key:\*\*" || {
		echo "latest changelog section is missing '$key' metadata" >&2
		fail=1
	}
done

[ "$fail" -eq 0 ] && echo "CHANGELOG.md OK for VERSION $version"
exit "$fail"
