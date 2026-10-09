#!/bin/bash
# Daily Docker disk cleanup for the Forgejo box.
#
# Why: CI jobs pull a new image per workflow, and crashed jobs leave
# stopped containers behind, so /var/lib/docker only ever grows.
#
# Removes, and nothing else:
#   - untagged (dangling) images
#   - tagged images no container references, after GRACE_DAYS unused days
#   - containers outside the compose stack, stopped for GRACE_DAYS or more
#   - unused networks and the build cache older than GRACE_DAYS
# Volumes are never touched: they can hold job data.
#
# Why the grace period is tracked here instead of by Docker: the
# `until=` prune filter matches an image's build date, not the last time
# it was used. A pulled image is usually months old, so `until=168h`
# would delete it the day it arrives. This script records the day an
# image was first seen unused and deletes it only after GRACE_DAYS.
# Containers have the same problem: `until=` matches creation time, not
# the time the container stopped, so its stop time is read directly.
set -euo pipefail

GRACE_DAYS=7
COMPOSE_FILE=/opt/forgejo/docker-compose.yml
STATE_DIR=/var/lib/forgejo-cleanup
STATE_FILE="$STATE_DIR/unused-images.tsv" # image id <TAB> first seen unused

now_epoch=$(date -u +%s)
today=$(date -u +%Y-%m-%d)
mkdir -p "$STATE_DIR"

echo "== docker disk usage before =="
docker system df

# Images the stack needs, read from the compose file so the protected
# list cannot drift from it. An empty or unreadable result must stop the
# run: pruning without protection could delete the pinned app images.
if ! stack_images=$(docker-compose -f "$COMPOSE_FILE" config --images 2>/dev/null); then
	echo "Could not read $COMPOSE_FILE; removing nothing." >&2
	exit 1
fi
if [ -z "$stack_images" ]; then
	echo "No images listed in $COMPOSE_FILE; removing nothing." >&2
	exit 1
fi

# --- stopped containers -------------------------------------------------
# Containers belonging to the compose stack are never removed, even when
# stopped: the operator may have taken the stack down on purpose.
stack_containers=$(docker ps -a --filter label=com.docker.compose.project --format '{{.ID}}')

for cid in $(docker ps -a --filter status=exited --filter status=created --format '{{.ID}}'); do
	if printf '%s\n' "$stack_containers" | grep -qx "$cid"; then
		continue
	fi
	# FinishedAt is "0001-01-01" for a container that never started;
	# such a container holds nothing and counts as old. The runner
	# removes its own job containers, so a container can disappear
	# between the listing and the inspect; skip those.
	if ! finished=$(docker inspect --format '{{.State.FinishedAt}}' "$cid" 2>/dev/null); then
		continue
	fi
	finished_day=${finished%%T*}
	finished_epoch=$(date -ud "$finished_day" +%s)
	if ((now_epoch - finished_epoch >= GRACE_DAYS * 86400)); then
		name=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null || echo "/$cid")
		if docker rm "$cid" >/dev/null; then
			echo "removed container ${name#/} (stopped since $finished_day)"
		else
			# The container can start again between the listing and
			# the removal; leave it and report.
			echo "could not remove container ${name#/}" >&2
		fi
	fi
done

# --- images -------------------------------------------------------------
# Untagged leftovers of interrupted builds cannot be referenced by any
# container, so they go immediately.
docker image prune -f >/dev/null

# Image ids referenced by any container, running or stopped.
in_use=$(docker ps -a --format '{{.Image}}' | sort -u |
	while read -r ref; do
		[ -n "$ref" ] && docker image inspect --format '{{.Id}}' "$ref" 2>/dev/null || true
	done |
	sort -u)

# Grace record from the previous run.
declare -A first_seen=()
if [ -f "$STATE_FILE" ]; then
	while IFS=$'\t' read -r id day; do
		[ -n "$id" ] && first_seen["$id"]=$day
	done <"$STATE_FILE"
fi

state_next=()
while read -r id ref; do
	if printf '%s\n' "$in_use" | grep -qx "$id"; then
		continue
	fi
	if printf '%s\n' "$stack_images" | grep -qxF "$ref"; then
		continue
	fi
	first=${first_seen["$id"]:-}
	if [ -z "$first" ]; then
		state_next+=("$id"$'\t'"$today")
		echo "unused image $ref: grace period starts"
		continue
	fi
	first_epoch=$(date -ud "$first" +%s)
	if (((now_epoch - first_epoch) / 86400 >= GRACE_DAYS)); then
		# The runner may have started using this image since the list
		# was built; rmi then fails and the image stays.
		if docker rmi "$id" >/dev/null 2>&1; then
			echo "removed image $ref (unused since $first)"
		else
			echo "kept image $ref: in use again" >&2
			state_next+=("$id"$'\t'"$first")
		fi
	else
		state_next+=("$id"$'\t'"$first")
	fi
done < <(docker images --format '{{.ID}} {{.Repository}}:{{.Tag}}')

# Rewrite the record: images that are in use again or gone drop out, so
# the file stays bounded by the number of images on disk.
if ((${#state_next[@]} > 0)); then
	printf '%s\n' "${state_next[@]}" >"$STATE_FILE"
else
	: >"$STATE_FILE"
fi

# --- networks and build cache ------------------------------------------
# Compose networks are attached to the stack's containers, so they are
# never reported as unused.
docker network prune -f --filter "until=$((GRACE_DAYS * 24))h" >/dev/null

# The build cache is normally empty here because job containers never
# get the Docker socket. Debian splits buildx into its own package, so
# the subcommand can be missing.
if docker builder prune --help >/dev/null 2>&1; then
	docker builder prune -f --filter "until=$((GRACE_DAYS * 24))h" >/dev/null
else
	echo "no 'docker builder' subcommand; skipped the build cache" >&2
fi

echo "== docker disk usage after =="
docker system df
