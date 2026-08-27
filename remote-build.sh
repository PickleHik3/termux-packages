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
set -euo pipefail

IMAGE="${VAJ_BUILDER_IMAGE:-io-vaj-phase0a-builder:c9cc6b28}"
CONTAINER="${VAJ_BUILD_CONTAINER:-vaj-remote-builder}"
APT_REPO="${VAJ_APT_REPO:-PickleHik3/io-vaj-apt}"
RECIPES_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$RECIPES_DIR/output"
PUBLISH=1
PUBLISH_ALL=0
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

# --- build ---
# Marker for "what did THIS run produce". output/ is persistent and on a machine
# that has built before it can hold thousands of debs from earlier runs; handing
# all of them off would make publish.yml restage the entire history. -newer than
# this stamp catches both new debs and rebuilt ones that overwrote an existing
# filename, which a name-diff would miss.
RUN_MARKER="$(mktemp)"
case "$MODE" in
  queue)
    echo "[remote-build] running full build queue"
    docker exec "$CONTAINER" bash /home/builder/termux-packages/build-all-queue.sh
    ;;
  tier)
    echo "[remote-build] building tier file: $QUEUE_FILE"
    docker exec "$CONTAINER" bash -c "
      cd /home/builder/termux-packages
      while read -r pkg; do
        [ -z \"\$pkg\" ] && continue
        case \"\$pkg\" in \\#*) continue;; esac
        TERMUX_BUILD_IGNORE_LOCK=true ./build-package.sh -I -C -a aarch64 \"\$pkg\"
      done < '$QUEUE_FILE'
    "
    ;;
  pkgs)
    echo "[remote-build] building packages: ${PKGS[*]}"
    docker exec "$CONTAINER" bash -c "
      cd /home/builder/termux-packages
      for pkg in ${PKGS[*]}; do
        TERMUX_BUILD_IGNORE_LOCK=true ./build-package.sh -I -C -a aarch64 \"\$pkg\"
      done
    "
    ;;
esac

mapfile -t RUN_DEBS < <(find "$OUTPUT_DIR" -maxdepth 1 -name '*.deb' -newer "$RUN_MARKER" 2>/dev/null | sort)
rm -f "$RUN_MARKER"
DEB_COUNT="${#RUN_DEBS[@]}"
DIR_TOTAL="$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.deb' 2>/dev/null | wc -l)"
echo "[remote-build] this run produced $DEB_COUNT .deb file(s) ($DIR_TOTAL total in $OUTPUT_DIR)"
if [ "$PUBLISH_ALL" -eq 1 ]; then
  echo "[remote-build] --publish-all: handing off all $DIR_TOTAL deb(s) in $OUTPUT_DIR"
  mapfile -t RUN_DEBS < <(find "$OUTPUT_DIR" -maxdepth 1 -name '*.deb' 2>/dev/null | sort)
  DEB_COUNT="${#RUN_DEBS[@]}"
fi
[ "$DEB_COUNT" -gt 0 ] || { echo "[remote-build] no debs produced; nothing to hand off"; exit 0; }

# --- hand off to central publish ---
if [ "$PUBLISH" -eq 1 ]; then
  TS="$(date -u +%Y%m%d-%H%M%S)"
  TAG="staging-$TS"
  echo "[remote-build] creating staging prerelease $TAG on $APT_REPO"
  gh release create "$TAG" \
    -R "$APT_REPO" \
    --prerelease \
    --title "APT staging $TS" \
    --notes "Build artifacts from $(hostname) $(date -u +%FT%TZ). Consumed + deleted by publish.yml." \
    "${RUN_DEBS[@]}"
  echo "[remote-build] handed off. publish.yml will stage, sign, and publish, then delete $TAG."
else
  echo "[remote-build] --no-publish: debs left in $OUTPUT_DIR"
fi
