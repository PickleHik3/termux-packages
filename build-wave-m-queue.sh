#!/usr/bin/env bash
# build-wave-m-queue.sh — Wave M upgrade rebuild (2026-08-01).
# 265 recipes: every published recipe whose version changed after the
# upstream merge (1d01930..9880b61), plus fzf (new).
# Same mechanics as build-all-queue.sh: serialized builds, shared prefix,
# resumable via .built-packages (+ output/*.deb pre-populate).
# Stale wave debs were archived to output/pre-wave-m-20260801/ so the
# pre-populate step cannot false-skip an upgrade.
#
# Run:
#   docker exec -d termux-package-builder \
#       bash /home/builder/termux-packages/build-wave-m-queue.sh
# Progress: output/build-wave-m-queue.log ; per-pkg: output/pkg-logs/<pkg>.log

set -u
cd /home/builder/termux-packages

PIDFILE="/tmp/build-wave-m-queue.pid"
if [[ -e "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "ERROR: build-wave-m-queue.sh already running (PID $(cat "$PIDFILE")). Exiting."
    exit 1
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

LOG="output/build-wave-m-queue.log"
OUTDIR="output"
BUILT_DIR=".built-packages"
PKG_LOGS="output/pkg-logs"
RESULTS_DIR="/tmp/build-results-$$"
MAX_JOBS=1
MAKE_JOBS=6  # 12 thrashed the 11 GB WSL VM during big C++ link phases

TIER1="wave-m-tier1.txt"
TIER2="wave-m-tier2.txt"
TIER3="wave-m-tier3.txt"

for f in "$TIER1" "$TIER2" "$TIER3"; do
    [[ -f "$f" ]] || { echo "ERROR: missing $f"; exit 1; }
done

mkdir -p "$PKG_LOGS" "$RESULTS_DIR"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

mkdir -p /home/builder/bin
cat > /home/builder/bin/apt << 'APTEOF'
#!/bin/bash
exec flock -w 300 /tmp/apt-build.lock /usr/bin/apt "$@"
APTEOF
chmod +x /home/builder/bin/apt
export PATH="/home/builder/bin:$PATH"

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

wait_for_slot() {
    while [[ $(jobs -rp | wc -l) -ge $MAX_JOBS ]]; do
        wait -n 2>/dev/null || true
        collect_results
    done
}

wait_all() {
    wait
    collect_results
}

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
log "=== build-wave-m-queue START (MAX_JOBS=$MAX_JOBS make_jobs=$MAKE_JOBS) — $TOTAL packages ==="

log "--- Wave M Tier 1: libraries ($(wc -l < "$TIER1") packages) ---"
while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    build "$pkg"
done < "$TIER1"
wait_all

log "--- Wave M Tier 2: runtimes ($(wc -l < "$TIER2") packages) ---"
while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    build "$pkg"
done < "$TIER2"
wait_all

log "--- Wave M Tier 3: tools ($(wc -l < "$TIER3") packages) ---"
while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    build "$pkg"
done < "$TIER3"
wait_all

log "=== build-wave-m-queue DONE ==="
log "PASS  (${#PASS_LIST[@]}): ${PASS_LIST[*]:-none}"
log "FAIL  (${#FAIL_LIST[@]}): ${FAIL_LIST[*]:-none}"
log "SKIP  (${#SKIP_LIST[@]}): ${SKIP_LIST[*]:-none}"

rm -rf "$RESULTS_DIR"
