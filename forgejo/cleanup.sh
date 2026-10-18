#!/bin/bash
# Daily podman disk cleanup for the Forgejo box.
#
# Why: CI jobs pull a new image per workflow, and crashed jobs leave
# stopped containers behind, so the container store only ever grows.
#
# Removes, and nothing else:
#   - untagged (dangling) images
#   - tagged images no container references, after GRACE_DAYS unused days
#   - containers outside the stack, stopped for GRACE_DAYS or more
#   - unused networks older than GRACE_DAYS
# Volumes are never touched: they can hold job data.
#
# Why the grace period is tracked here instead of by podman: the
# `until=` prune filter matches an image's build date, not the last time
# it was used. A pulled image is usually months old, so `until=168h`
# would delete it the day it arrives. This script records the day an
# image was first seen unused and deletes it only after GRACE_DAYS.
# Containers have the same problem: `until=` matches creation time, not
# the time the container stopped, so its stop time is read directly.
#
# There is no build-cache step: buildah (used inside job containers)
# keeps no engine-side build cache like Docker's buildx.
set -euo pipefail

GRACE_DAYS=7
KUBE_DIR=/opt/forgejo/kube
STATE_DIR=/var/lib/forgejo-cleanup
STATE_FILE="$STATE_DIR/unused-images.tsv" # image id <TAB> first seen unused

now_epoch=$(date -u +%s)
today=$(date -u +%Y-%m-%d)
mkdir -p "$STATE_DIR"

echo "== podman disk usage before =="
podman system df

# Images the stack needs, read from the kube definitions so the protected
# list cannot drift from them. An empty or unreadable result must stop
# the run: pruning without protection could delete the pinned app images.
stack_images=$(grep -h '^\s*image:' "$KUBE_DIR"/*.yaml 2>/dev/null |
	awk '{print $2}')
if [ ! -d "$KUBE_DIR" ] || [ -z "$stack_images" ]; then
	echo "Could not read image list from $KUBE_DIR; removing nothing." >&2
	exit 1
fi

# --- stopped containers -------------------------------------------------
# Containers belonging to the stack are never removed, even when
# stopped: the operator may have taken the stack down on purpose. Every
# container created by podman-kube@<unit> carries the PODMAN_SYSTEMD_UNIT
# label, including the pod's -service and -infra helpers.
stack_containers=$(podman ps -a --filter label=PODMAN_SYSTEMD_UNIT --format '{{.ID}}')

for cid in $(podman ps -a --filter status=exited --filter status=created --format '{{.ID}}'); do
	if printf '%s\n' "$stack_containers" | grep -qx "$cid"; then
		continue
	fi
	# FinishedAt is "0001-01-01" for a container that never started;
	# such a container holds nothing and counts as old. The runner
	# removes its own job containers, so a container can disappear
	# between the listing and the inspect; skip those.
	if ! finished=$(podman inspect --format '{{.State.FinishedAt}}' "$cid" 2>/dev/null); then
		continue
	fi
	finished_day=${finished%%T*}
	finished_epoch=$(date -ud "$finished_day" +%s)
	if ((now_epoch - finished_epoch >= GRACE_DAYS * 86400)); then
		name=$(podman inspect --format '{{.Name}}' "$cid" 2>/dev/null || echo "/$cid")
		if podman rm "$cid" >/dev/null; then
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
podman image prune -f >/dev/null

# Image ids referenced by any container, running or stopped.
in_use=$(podman ps -a --format '{{.Image}}' | sort -u |
	while read -r ref; do
		[ -n "$ref" ] && podman image inspect --format '{{.Id}}' "$ref" 2>/dev/null || true
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
		if podman rmi "$id" >/dev/null 2>&1; then
			echo "removed image $ref (unused since $first)"
		else
			echo "kept image $ref: in use again" >&2
			state_next+=("$id"$'\t'"$first")
		fi
	else
		state_next+=("$id"$'\t'"$first")
	fi
done < <(podman images --format '{{.Id}} {{.Repository}}:{{.Tag}}')

# Rewrite the record: images that are in use again or gone drop out, so
# the file stays bounded by the number of images on disk.
if ((${#state_next[@]} > 0)); then
	printf '%s\n' "${state_next[@]}" >"$STATE_FILE"
else
	: >"$STATE_FILE"
fi

# --- networks ------------------------------------------------------------
# Pod and job networks are attached to their containers while those
# exist, so they are never reported as unused. The kube pod network is
# recreated by kube play when absent, so pruning it between runs is
# harmless; the until filter keeps young networks anyway.
podman network prune -f --filter "until=$((GRACE_DAYS * 24))h" >/dev/null

echo "== podman disk usage after =="
podman system df
