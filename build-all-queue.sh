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
# Fully resumable: pre-populates .built-packages from output/ on every start.
# Per-package logs: output/pkg-logs/<pkg>.log

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
BUILT_DIR=".built-packages"
PKG_LOGS="output/pkg-logs"
RESULTS_DIR="/tmp/build-results-$$"
MAX_JOBS=1
MAKE_JOBS=7  # container is capped at --cpus 6; quota+1 hides I/O stalls, more just throttles

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
# Pre-populate .built-packages from all existing output/ .debs.
# ---------------------------------------------------------------------------
log "=== Pre-populating .built-packages from output/ ==="
mkdir -p "$BUILT_DIR"
shopt -s nullglob
for deb in "$OUTDIR"/*.deb; do
    fname="${deb##*/}"
    name="${fname%%_*}"
    rest="${fname#*_}"
    ver="${rest%%_*}"
    [[ -z "$name" || -z "$ver" ]] && continue
    echo "$ver" > "$BUILT_DIR/$name"
done
shopt -u nullglob
log "Pre-populated $(ls "$BUILT_DIR" | wc -l) entries in $BUILT_DIR"

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
        if ./build-package.sh -j"$MAKE_JOBS" "$pkg" >> "$PKG_LOGS/$pkg.log" 2>&1; then
            printf '%s:PASS\n' "$pkg" > "$RESULTS_DIR/result_${pkg}"
        else
            printf '%s:FAIL\n' "$pkg" > "$RESULTS_DIR/result_${pkg}"
        fi
    ) &
}

build() {
    local pkg="$1"
    if [[ -e "$BUILT_DIR/$pkg" ]]; then
        log "SKIP  $pkg"
        SKIP_LIST+=("$pkg")
        return 0
    fi
    wait_for_slot
    collect_results
    log "START $pkg"
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

log "=== build-all-queue DONE ==="
log "PASS  (${#PASS_LIST[@]}): ${PASS_LIST[*]:-none}"
log "FAIL  (${#FAIL_LIST[@]}): ${FAIL_LIST[*]:-none}"
log "SKIP  (${#SKIP_LIST[@]}): ${SKIP_LIST[*]:-none}"

rm -rf "$RESULTS_DIR"
