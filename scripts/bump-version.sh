#!/bin/bash
# Bump the version in VERSION (semver). Usage: scripts/bump-version.sh [patch|minor|major]
set -euo pipefail

BUMP="${1:-patch}"
if [ ! -f VERSION ]; then
	echo "0.0.0" >VERSION
fi
IFS=. read -r major minor patch <VERSION

case "$BUMP" in
major)
	major=$((major + 1))
	minor=0
	patch=0
	;;
minor)
	minor=$((minor + 1))
	patch=0
	;;
patch)
	patch=$((patch + 1))
	;;
*)
	echo "usage: $0 [patch|minor|major]" >&2
	exit 1
	;;
esac

echo "$major.$minor.$patch" >VERSION
echo "VERSION: $major.$minor.$patch"
