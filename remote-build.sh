#!/usr/bin/env bash
# remote-build.sh — Build VAJ packages on any machine and hand the .deb output
# off to the central publish pipeline (GitHub Actions on PickleHik3/io-vaj-apt).
#
# Builds use `-I -C`, as upstream Termux CI does: -I downloads prebuilt
# dependencies instead of building them, -C cleans built packages on low disk.
# Dependencies come from repo.pathayam.xyz (see repo.json) -- never from
# packages.termux.dev, whose debs carry the com.termux prefix.
#
# This machine needs ONLY:
#   - docker with the frozen builder image loaded (io-vaj-phase0a-builder:c9cc6b28)
#   - a checkout of these recipes on branch io-vaj-package
#   - gh authenticated (a GitHub PAT with repo scope) -- NO GPG key, NO R2 creds
#
# One-time image load (transfer vaj-builder.tar.zst from the primary host first):
#   zstd -dc vaj-builder.tar.zst | docker load
#
# Usage:
#   ./remote-build.sh                       # full queue (build-all-queue.sh, ~1660 pkgs)
#   ./remote-build.sh build-tier1-libs.txt  # one tier file
#   ./remote-build.sh --pkgs zsh jq bc      # named packages
#   ./remote-build.sh ... --no-publish      # build only, skip the staging handoff
#   ./remote-build.sh ... --publish-all     # hand off EVERY deb in output/, not just this run's
#   ./remote-build.sh ... --handoff-every N # in queue mode, also hand off finished debs every N
#                                           # minutes while the queue runs (default 60; 0 = end only)
#
# Queue mode honours UPDATES_ONLY=1, DRY_RUN=1, PKG_TIMEOUT and QUEUE_RECIPE_DIRS
# (see build-all-queue.sh).
set -euo pipefail

IMAGE="${VAJ_BUILDER_IMAGE:-io-vaj-phase0a-builder:c9cc6b28}"
CONTAINER="${VAJ_BUILD_CONTAINER:-vaj-remote-builder}"
APT_REPO="${VAJ_APT_REPO:-PickleHik3/io-vaj-apt}"
RECIPES_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$RECIPES_DIR/output"
PUBLISH=1
PUBLISH_ALL=0
HANDOFF_EVERY=60
MODE="queue"
declare -a PKGS=()
QUEUE_FILE="build-all-queue.sh"

# --- parse args ---
while [ $# -gt 0 ]; do
  case "$1" in
    --no-publish) PUBLISH=0; shift ;;
    # Escape hatch for handing off a pre-existing output/ (e.g. debs built before
    # this flag existed). Publishes every deb in the directory -- confirm the
    # contents first.
    --publish-all) PUBLISH_ALL=1; shift ;;
    --handoff-every) HANDOFF_EVERY="$2"; shift 2 ;;
    --pkgs) MODE="pkgs"; shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do PKGS+=("$1"); shift; done ;;
    *.txt) MODE="tier"; QUEUE_FILE="$1"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- preflight ---
command -v docker >/dev/null || { echo "ERROR: docker not found" >&2; exit 1; }
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "ERROR: builder image '$IMAGE' not loaded." >&2
  echo "  Transfer vaj-builder.tar.zst from the primary host, then:" >&2
  echo "  zstd -dc vaj-builder.tar.zst | docker load" >&2
  exit 1
fi
if [ "$PUBLISH" -eq 1 ]; then
  command -v gh >/dev/null || { echo "ERROR: gh CLI not found (needed to hand off debs)" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: run 'gh auth login' first" >&2; exit 1; }
fi

# --- (re)create build container with recipes mounted ---
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
echo "[remote-build] starting container '$CONTAINER' from $IMAGE"
# fuse-overlayfs needs /dev/fuse + CAP_SYS_ADMIN; without them the build system
# silently fails to mount the prefix overlay and produces zero debs.
docker run -d --name "$CONTAINER" \
  --cap-add CAP_SYS_ADMIN --device /dev/fuse \
  --security-opt apparmor=unconfined \
  -v "$RECIPES_DIR:/home/builder/termux-packages" \
  "$IMAGE" sleep infinity >/dev/null

# --- trust the VAJ archive key ---
# -I verifies dists/stable/Release against Release.gpg with a plain `gpg --verify`
# against the build user's own keyring. The container is recreated on every run
# above, so the import has to happen here or every -I build fails with
# "Can't check signature: No public key".
echo "[remote-build] importing VAJ archive public key"
docker exec "$CONTAINER" gpg --batch --quiet --import \
  /home/builder/termux-packages/vaj-archive-key.asc

# --- hand off to central publish ---
# publish.yml runs under a concurrency group that keeps at most ONE pending
# run: a third staging release created while one publishes and one waits
# would get its run cancelled and sit unconsumed. So wait for the previous
# staging release to be consumed before creating the next one.
wait_for_staging_clear() {
  [ "$PUBLISH" -eq 1 ] || return 0
  local waited=0
  while [ -n "$(gh release list -R "$APT_REPO" --json tagName -q '.[] | select(.tagName | startswith("staging-")) | .tagName' 2>/dev/null)" ]; do
    if [ "$waited" -ge 3600 ]; then
      echo "[remote-build] WARNING: a staging-* release has been pending for an hour; handing off anyway" >&2
      return 0
    fi
    [ "$waited" -eq 0 ] && echo "[remote-build] previous staging release not yet consumed by publish.yml; waiting"
    sleep 60; waited=$((waited + 60))
  done
}

# Hand off every deb written since the last handoff. output/ is persistent and
# on a machine that has built before it can hold thousands of debs from earlier
# runs; -newer than the stamp catches both new debs and rebuilt ones that
# overwrote an existing filename, which a name diff would miss.
HANDOFF_STAMP="$OUTPUT_DIR/.last-handoff"
HANDOFF_TOTAL=0
handoff() {
  local label="$1" debs
  mapfile -t debs < <(find "$OUTPUT_DIR" -maxdepth 1 -name '*.deb' -newer "$HANDOFF_STAMP" 2>/dev/null | sort)
  if [ "$PUBLISH_ALL" -eq 1 ]; then
    mapfile -t debs < <(find "$OUTPUT_DIR" -maxdepth 1 -name '*.deb' 2>/dev/null | sort)
    PUBLISH_ALL=0   # only the first handoff of a run publishes history
  fi
  [ "${#debs[@]}" -gt 0 ] || { echo "[remote-build] $label: no new debs to hand off"; return 0; }
  local next_stamp; next_stamp="$(mktemp)"
  if [ "$PUBLISH" -eq 1 ]; then
    wait_for_staging_clear
    local ts tag; ts="$(date -u +%Y%m%d-%H%M%S)"; tag="staging-$ts"
    echo "[remote-build] $label: creating staging prerelease $tag on $APT_REPO with ${#debs[@]} deb(s)"
    if gh release create "$tag" -R "$APT_REPO" --prerelease --title "APT staging $ts" \
         --notes "Build artifacts from $(hostname) $(date -u +%FT%TZ) ($label). Consumed + deleted by publish.yml." \
         "${debs[@]}"; then
      HANDOFF_TOTAL=$((HANDOFF_TOTAL + ${#debs[@]}))
      mv "$next_stamp" "$HANDOFF_STAMP"
    else
      echo "[remote-build] ERROR: handoff of ${#debs[@]} deb(s) failed; they stay pending for the next handoff" >&2
      rm -f "$next_stamp"; BUILD_FAILED=1
    fi
  else
    # Not handed off, so still pending: leave the stamp where it was.
    echo "[remote-build] $label: --no-publish, ${#debs[@]} deb(s) left pending in $OUTPUT_DIR"
    rm -f "$next_stamp"
  fi
}

# --- build ---
# A failed package must not hide behind a successful docker exec: every mode
# below records failures and sets BUILD_FAILED, the debs that did build are
# still handed off, and the script exits non-zero at the very end.
BUILD_FAILED=0
mkdir -p "$OUTPUT_DIR"
: > "$OUTPUT_DIR/remote-build.results"
# First run on a machine: hand off only what this run writes (a primary host
# can hold thousands of historical debs in output/). Later runs keep the stamp
# so debs built after the last successful handoff of an interrupted run are
# still handed off instead of silently stranded.
[ -e "$HANDOFF_STAMP" ] || touch "$HANDOFF_STAMP"
case "$MODE" in
  queue)
    echo "[remote-build] running full build queue (UPDATES_ONLY=${UPDATES_ONLY:-} DRY_RUN=${DRY_RUN:-} PKG_TIMEOUT=${PKG_TIMEOUT:-8h} handoff every ${HANDOFF_EVERY}m)"
    docker exec -e UPDATES_ONLY="${UPDATES_ONLY:-}" -e DRY_RUN="${DRY_RUN:-}" \
      -e PKG_TIMEOUT="${PKG_TIMEOUT:-}" -e QUEUE_RECIPE_DIRS="${QUEUE_RECIPE_DIRS:-}" "$CONTAINER" \
      bash /home/builder/termux-packages/build-all-queue.sh &
    QUEUE_PID=$!
    if [ "$HANDOFF_EVERY" -gt 0 ]; then
      while kill -0 "$QUEUE_PID" 2>/dev/null; do
        for _ in $(seq "$HANDOFF_EVERY"); do kill -0 "$QUEUE_PID" 2>/dev/null || break; sleep 60; done
        kill -0 "$QUEUE_PID" 2>/dev/null && handoff "interim"
      done
    fi
    wait "$QUEUE_PID" || BUILD_FAILED=1
    ;;
  tier)
    echo "[remote-build] building tier file: $QUEUE_FILE"
    docker exec "$CONTAINER" bash -c "
      cd /home/builder/termux-packages
      failed=0
      while read -r pkg; do
        [ -z \"\$pkg\" ] && continue
        case \"\$pkg\" in \\#*) continue;; esac
        if TERMUX_BUILD_IGNORE_LOCK=true ./build-package.sh -I -C -a aarch64 \"\$pkg\"; then
          echo \"\$pkg:PASS\" >> output/remote-build.results
        else
          echo \"\$pkg:FAIL\" >> output/remote-build.results; failed=1
        fi
      done < '$QUEUE_FILE'
      exit \$failed
    " || BUILD_FAILED=1
    ;;
  pkgs)
    echo "[remote-build] building packages: ${PKGS[*]}"
    docker exec "$CONTAINER" bash -c "
      cd /home/builder/termux-packages
      failed=0
      for pkg in ${PKGS[*]}; do
        if TERMUX_BUILD_IGNORE_LOCK=true ./build-package.sh -I -C -a aarch64 \"\$pkg\"; then
          echo \"\$pkg:PASS\" >> output/remote-build.results
        else
          echo \"\$pkg:FAIL\" >> output/remote-build.results; failed=1
        fi
      done
      exit \$failed
    " || BUILD_FAILED=1
    ;;
esac

handoff "final"
if grep -q ':FAIL$' "$OUTPUT_DIR/remote-build.results" 2>/dev/null; then
  echo "[remote-build] FAILED packages: $(grep ':FAIL$' "$OUTPUT_DIR/remote-build.results" | cut -d: -f1 | tr '\n' ' ')"
fi
echo "[remote-build] done: $HANDOFF_TOTAL deb(s) handed off this run ($(find "$OUTPUT_DIR" -maxdepth 1 -name '*.deb' | wc -l) total in $OUTPUT_DIR)"
exit "$BUILD_FAILED"
