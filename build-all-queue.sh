#!/usr/bin/env bash
# build-all-queue.sh — Build all 1664 queued packages in dependency-tier order.
#
# Reads package lists from three tier files (relative to this script):
#   build-tier1-libs.txt     (289 libraries)
#   build-tier2-runtimes.txt (26 language runtimes / build tools)
#   build-tier3-tools.txt    (1349 tools and applications)
#
# Run from inside the termux-package-builder container:
#   docker exec -w /home/builder/termux-packages termux-package-builder \
#       bash build-all-queue.sh
#
# Builds are serialized because termux-package-build writes every package into
# one shared TERMUX_PREFIX before timestamp-based payload collection. Running
# packages concurrently can leak one package's files into another package.
# What to build is decided against the LIVE repo index (repo.json URL), not
# against the committed .built-packages/ markers: a package is skipped only
# when the published version equals the recipe's version, so an upstream
# merge makes exactly the stale packages rebuild. Debs already in output/
# count as built for this session (resumable).
# Per-package logs: output/pkg-logs/<pkg>.log
#
# Env knobs:
#   UPDATES_ONLY=1  only rebuild packages that are already published (skip
#                   never-published additions) -- run this first after a merge
#   DRY_RUN=1       log every BUILD/SKIP decision, launch nothing
#   PKG_TIMEOUT=8h  per-package wall-clock limit (GNU timeout syntax)

set -u
cd /home/builder/termux-packages

# Prevent accidental multiple instances writing to the same log/output.
PIDFILE="/tmp/build-all-queue.pid"
if [[ -e "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "ERROR: build-all-queue.sh already running (PID $(cat "$PIDFILE")). Exiting."
    exit 1
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

LOG="output/build-all-queue.log"
OUTDIR="output"
PKG_LOGS="output/pkg-logs"
RESULTS_DIR="/tmp/build-results-$$"
MAX_JOBS=1
MAKE_JOBS=$(( $(nproc) + 1 ))  # one over nproc hides I/O stalls, more just throttles

# ---------------------------------------------------------------------------
# Stale .la purge.
#
# build-package.sh -I sets RM_ALL_PKGS_BUILT_MARKER_AND_INSTALL_FILES=false, so
# every package built earlier in the run leaves its whole staging install in the
# shared prefix -- including the .la files that only belong in a -static
# subpackage and are therefore absent on a real install.
#
# libtool notices them. Where upstream records a plain `-lfoo` it writes the
# absolute path of the leaked libfoo.la into the next package's
# dependency_libs, and that path never exists at install time, so every libtool
# consumer downstream dies with "... is not a valid libtool archive".
# Measured 2026-08-29: 78 published packages, 364 bad references. libseccomp
# built earlier in a run was enough to poison libmagic; libSM.la poisoned by
# libuuid.la took out libvips and dmtx-utils.
#
# Serial builds did not fix this -- it is prefix persistence across packages,
# not concurrency. Purge before every build so libtool sees what upstream sees.
# ---------------------------------------------------------------------------
STATIC_LA_LIST="vaj-static-la.txt"
TERMUX_PREFIX_DIR="/data/data/$(awk -F'"' '/^TERMUX_APP__PACKAGE_NAME=/{print $2; exit}' scripts/properties.sh)/files/usr"

purge_static_la() {
    [[ -f "$STATIC_LA_LIST" && -d "$TERMUX_PREFIX_DIR" ]] || return 0
    local rel
    while IFS= read -r rel; do
        [[ -z "$rel" || "$rel" == \#* ]] && continue
        rm -f "$TERMUX_PREFIX_DIR/$rel"
    done < "$STATIC_LA_LIST"
}

TIER1="build-tier1-libs.txt"
TIER2="build-tier2-runtimes.txt"
TIER3="build-tier3-tools.txt"

for f in "$TIER1" "$TIER2" "$TIER3"; do
    [[ -f "$f" ]] || { echo "ERROR: missing $f"; exit 1; }
done

mkdir -p "$PKG_LOGS" "$RESULTS_DIR"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

# ---------------------------------------------------------------------------
# Install flock-wrapped apt into /home/builder/bin so concurrent builds
# don't collide on the dpkg lock. build-package.sh inherits PATH.
# ---------------------------------------------------------------------------
mkdir -p /home/builder/bin
cat > /home/builder/bin/apt << 'APTEOF'
#!/bin/bash
exec flock -w 300 /tmp/apt-build.lock /usr/bin/apt "$@"
APTEOF
chmod +x /home/builder/bin/apt
export PATH="/home/builder/bin:$PATH"

# ---------------------------------------------------------------------------
# Published versions from the live repo index -- the source of truth for
# "is this already done". Abort if it cannot be fetched: without it every
# package would look stale and the run would rebuild the whole catalogue.
# ---------------------------------------------------------------------------
REPO_URL=$(sed -nE 's/^\s*"url":\s*"([^"]+)".*/\1/p' repo.json | head -1)
REPO_DIST=$(sed -nE 's/^\s*"distribution":\s*"([^"]+)".*/\1/p' repo.json | head -1)
REPO_COMP=$(sed -nE 's/^\s*"component":\s*"([^"]+)".*/\1/p' repo.json | head -1)
PUBLISHED_TSV="$OUTDIR/published.tsv"
mkdir -p "$OUTDIR"
log "=== Fetching published index from $REPO_URL ($REPO_DIST/$REPO_COMP) ==="
if ! curl -fsSL --retry 3 "$REPO_URL/dists/$REPO_DIST/$REPO_COMP/binary-aarch64/Packages.gz" \
        | gzip -dc | awk '/^Package:/{p=$2} /^Version:/{print p, $2}' | sort -u > "$PUBLISHED_TSV" \
        || [[ ! -s "$PUBLISHED_TSV" ]]; then
    log "ERROR: could not fetch the published index; refusing to guess what is stale"
    exit 1
fi
declare -A PUBLISHED=()
while read -r _n _v; do PUBLISHED[$_n]=$_v; done < "$PUBLISHED_TSV"
log "Published index: ${#PUBLISHED[@]} packages"

# Debs already in output/ were built by an earlier (interrupted) run.
declare -A SESSION_BUILT=()
shopt -s nullglob
for deb in "$OUTDIR"/*.deb; do
    fname="${deb##*/}"
    name="${fname%%_*}"
    rest="${fname#*_}"
    ver="${rest%%_*}"
    [[ -z "$name" || -z "$ver" ]] && continue
    SESSION_BUILT[$name]=$ver
done
shopt -u nullglob
log "Already in output/: ${#SESSION_BUILT[@]} packages"

declare -A EXCLUDED=()
if [[ -f build-exclusions.txt ]]; then
    while IFS= read -r _n; do
        [[ -z "$_n" || "$_n" == \#* ]] && continue
        EXCLUDED[${_n%% *}]=1
    done < build-exclusions.txt
fi

declare -a PASS_LIST=() FAIL_LIST=() SKIP_LIST=()

# ---------------------------------------------------------------------------
# Collect finished job results from RESULTS_DIR and log them.
# ---------------------------------------------------------------------------
collect_results() {
    local rf _pkg _status
    for rf in "$RESULTS_DIR"/result_*; do
        [[ -f "$rf" ]] || continue
        IFS=: read -r _pkg _status < "$rf"
        rm -f "$rf"
        if [[ "$_status" == "PASS" ]]; then
            log "PASS  $_pkg"
            PASS_LIST+=("$_pkg")
        else
            log "FAIL  $_pkg"
            FAIL_LIST+=("$_pkg")
        fi
    done
}

# ---------------------------------------------------------------------------
# Wait until fewer than MAX_JOBS background jobs are running.
# ---------------------------------------------------------------------------
wait_for_slot() {
    while [[ $(jobs -rp | wc -l) -ge $MAX_JOBS ]]; do
        wait -n 2>/dev/null || true
        collect_results
    done
}

# ---------------------------------------------------------------------------
# Wait for all background jobs to finish and collect every result.
# ---------------------------------------------------------------------------
wait_all() {
    wait
    collect_results
}

# ---------------------------------------------------------------------------
# Launch one package build in the background.
# ---------------------------------------------------------------------------
launch() {
    local pkg="$1"
    (
        # Drop .la files leaked into the shared prefix by earlier packages in
        # this run before libtool can bake their paths into this one.
        purge_static_la
        # -I downloads dependencies from the VAJ repo (repo.json) instead of
        # building them; a dependency version the repo lacks is built and
        # lands in output/ like any other package. -C frees disk as it goes.
        # A hung build (dotnet9.0 sat 1.5 h at 0 % CPU on a zombie MSBuild
        # server) must not stall the whole queue: bound every package.
        if timeout -k 60 "${PKG_TIMEOUT:-8h}" \
             ./build-package.sh -I -C -a aarch64 -j"$MAKE_JOBS" "$pkg" >> "$PKG_LOGS/$pkg.log" 2>&1; then
            printf '%s:PASS\n' "$pkg" > "$RESULTS_DIR/result_${pkg}"
        else
            printf '%s:FAIL\n' "$pkg" > "$RESULTS_DIR/result_${pkg}"
        fi
    ) &
}

# Cheap recipe version read for the skip test below. Handles the common
# TERMUX_PKG_VERSION="x" / TERMUX_PKG_REVISION=n shape; anything fancier
# (arrays, variables) returns empty and the package falls through to
# build-package.sh, which does the authoritative already-built check itself.
recipe_version() {
    local f="packages/$1/build.sh" v r
    [[ -f "$f" ]] || return 0
    v=$(sed -nE 's/^TERMUX_PKG_VERSION=["'"'"']?([^"'"'"' $]+)["'"'"']?\s*$/\1/p' "$f" | head -1)
    [[ -z "$v" || "$v" == *'$'* || "$v" == '('* ]] && return 0
    r=$(sed -nE 's/^TERMUX_PKG_REVISION=["'"'"']?([0-9]+)["'"'"']?\s*$/\1/p' "$f" | head -1)
    printf '%s%s' "$v" "${r:+-$r}"
}

build() {
    local pkg="$1" want have
    if [[ -n "${EXCLUDED[$pkg]:-}" ]]; then
        log "SKIP  $pkg (build-exclusions.txt)"
        SKIP_LIST+=("$pkg"); return 0
    fi
    if [[ ! -d "packages/$pkg" ]]; then
        log "SKIP  $pkg (no recipe -- removed upstream or a subpackage)"
        SKIP_LIST+=("$pkg"); return 0
    fi
    want=$(recipe_version "$pkg")
    have="${PUBLISHED[$pkg]:-}"
    if [[ -z "$have" && -n "${UPDATES_ONLY:-}" ]]; then
        log "SKIP  $pkg (never published; UPDATES_ONLY)"
        SKIP_LIST+=("$pkg"); return 0
    fi
    if [[ -n "$want" ]]; then
        if [[ "$have" == "$want" ]]; then
            log "SKIP  $pkg ($want published)"
            SKIP_LIST+=("$pkg"); return 0
        fi
        if [[ "${SESSION_BUILT[$pkg]:-}" == "$want" ]]; then
            log "SKIP  $pkg ($want already in output/)"
            SKIP_LIST+=("$pkg"); return 0
        fi
    fi
    if [[ -n "${DRY_RUN:-}" ]]; then
        log "BUILD $pkg (${have:-unpublished} -> ${want:-?})"
        PASS_LIST+=("$pkg"); return 0
    fi
    wait_for_slot
    collect_results
    log "START $pkg (${have:-unpublished} -> ${want:-?})"
    launch "$pkg"
}

TOTAL=$(( $(wc -l < "$TIER1") + $(wc -l < "$TIER2") + $(wc -l < "$TIER3") ))
log "=== build-all-queue START (parallel MAX_JOBS=$MAX_JOBS make_jobs=$MAKE_JOBS) — $TOTAL packages ==="

log "--- Tier 1: Libraries ($(wc -l < "$TIER1") packages) ---"
while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    build "$pkg"
done < "$TIER1"
wait_all

log "--- Tier 2: Language runtimes and build tools ($(wc -l < "$TIER2") packages) ---"
while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    build "$pkg"
done < "$TIER2"
wait_all

log "--- Tier 3: Tools and applications ($(wc -l < "$TIER3") packages) ---"
while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    build "$pkg"
done < "$TIER3"
wait_all

# Published packages that no tier file lists must still get their updates.
declare -A QUEUED=()
for f in "$TIER1" "$TIER2" "$TIER3"; do
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        QUEUED[$pkg]=1
    done < "$f"
done
EXTRA=()
for pkg in "${!PUBLISHED[@]}"; do
    [[ -n "${QUEUED[$pkg]:-}" ]] && continue
    [[ -d "packages/$pkg" ]] || continue
    EXTRA+=("$pkg")
done
log "--- Tier 4: Published packages missing from the tier files (${#EXTRA[@]} packages) ---"
for pkg in $(printf '%s\n' "${EXTRA[@]}" | sort); do
    build "$pkg"
done
wait_all

log "=== build-all-queue DONE ==="
log "PASS  (${#PASS_LIST[@]}): ${PASS_LIST[*]:-none}"
log "FAIL  (${#FAIL_LIST[@]}): ${FAIL_LIST[*]:-none}"
log "SKIP  (${#SKIP_LIST[@]}): ${SKIP_LIST[*]:-none}"

rm -rf "$RESULTS_DIR"

# Let the caller (remote-build.sh) see that something failed; the debs that
# did build are still in output/ and still get handed off.
[[ ${#FAIL_LIST[@]} -eq 0 ]]
