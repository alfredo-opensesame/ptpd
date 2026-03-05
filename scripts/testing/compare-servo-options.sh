#!/bin/bash
# compare-servo-options.sh
#
# Runs ptpd-app three times with different servo gains:
#   current  : kp=0.01,  ki=0.0001   (baseline)
#   option-a : kp=0.1,   ki=0.000001 (10x proportional, near-zero integral)
#   option-b : kp=0.1,   ki=0.001    (10x proportional, 10x integral)
#
# Usage: sudo ./scripts/testing/compare-servo-options.sh [duration_seconds]
# Results written to scripts/ptpd_logs/comparison_<timestamp>/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BINARY="${REPO_ROOT}/build-cmake/debug/src-app/ptpd-app"
RUN_DURATION="${1:-300}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${REPO_ROOT}/scripts/ptpd_logs/comparison_${TIMESTAMP}"
mkdir -p "${OUT_DIR}"

echo "======================================================"
echo "  ptpd servo gains three-way comparison"
echo "  Duration per run: ${RUN_DURATION}s"
echo "  Output dir: ${OUT_DIR}"
echo "======================================================"
echo ""

if [[ ! -x "${BINARY}" ]]; then
    echo "ERROR: binary not found: ${BINARY}"
    echo "Run: cmake --build build-cmake/debug --target ptpd-app"
    exit 1
fi

# Prevent the Mac from sleeping during the run.
# caffeinate -dims: inhibit display, idle, disk, and system sleep.
# It is re-exec'd with the same args so the rest of the script runs
# as a child of caffeinate (which releases the assertion on exit).
if [[ -z "${CAFFEINATED:-}" ]]; then
    exec env CAFFEINATED=1 caffeinate -dims "$0" "$@"
fi

# Keep the sudo token alive for the duration of the script
# (macOS default sudo timeout is 5 minutes; each run can be longer)
sudo -v
( while true; do sudo -v; sleep 60; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null; exit' INT TERM EXIT

# ---- Helper: run one configuration ----
run_config() {
    local label="$1"
    local conf="$2"
    local run_dir="${OUT_DIR}/${label}"
    mkdir -p "${run_dir}"

    local servo_log="${run_dir}/servo.csv"
    local swclock_log="${run_dir}/swclock.jsonl"
    local ptpd_log="${run_dir}/ptpd.log"
    local ptpd_csv="${run_dir}/ptpd_stats.csv"
    local pidfile="/tmp/ptpd-app-${label}.pid"

    # Remove stale lock + PID files from any previous run.
    # Also kill any lingering ptpd-app instances (from failed runs or
    # manual tests) — they hold port 319 and cause netInit to fail.
    sudo pkill -KILL -x ptpd-app 2>/dev/null || true
    sleep 1
    sudo rm -f /var/run/ptpd2.lock "${pidfile}" 2>/dev/null || true

    echo "------------------------------------------------------"
    echo "  Starting: ${label}  (${RUN_DURATION}s)"
    echo "  Config  : ${conf}"
    echo "------------------------------------------------------"

    # ptpd-app writes its own PID to pidfile immediately after startup
    sudo "${BINARY}" \
        -c "${conf}" \
        -f "${ptpd_log}" \
        -S "${ptpd_csv}" \
        --servo-log   "${servo_log}"   \
        --swclock-log "${swclock_log}" \
        --pidfile     "${pidfile}"     &

    # Wait for pidfile to appear (up to 5s)
    local i=0
    while [[ ! -s "${pidfile}" ]] && (( i < 5 )); do sleep 1; (( i++ )); done
    local pid
    pid=$(cat "${pidfile}" 2>/dev/null || echo "")
    echo "  ptpd-app PID: ${pid:-unknown}"

    # Sleep for the full run duration
    sleep "${RUN_DURATION}"

    # Send SIGTERM directly to ptpd-app (not the sudo wrapper)
    echo "  Stopping ${label} (PID ${pid})..."
    if [[ -n "${pid}" ]]; then
        sudo kill -TERM "${pid}" 2>/dev/null || true
    fi

    # Wait up to 30s for graceful exit, then force-kill
    i=0
    while (( i < 30 )) && sudo kill -0 "${pid}" 2>/dev/null; do
        sleep 1; (( i++ ))
    done
    if sudo kill -0 "${pid}" 2>/dev/null; then
        echo "  Force-killing ${label} (unresponsive to SIGTERM)..."
        sudo kill -KILL "${pid}" 2>/dev/null || true
    fi

    # Clean up PID file
    sudo rm -f "${pidfile}" 2>/dev/null || true

    echo "  Done: ${label}"
    echo ""
}

# ---- Run all three ----
run_config "current"  "${REPO_ROOT}/resources/ptpd-daemon-current.conf"
run_config "option-a" "${REPO_ROOT}/resources/ptpd-daemon-option-a.conf"
run_config "option-b" "${REPO_ROOT}/resources/ptpd-daemon-option-b.conf"

# ---- Generate summary ----
echo "======================================================"
echo "  Generating comparison summary..."
echo "======================================================"

python3 "${SCRIPT_DIR}/summarize-comparison.py" "${OUT_DIR}" | tee "${OUT_DIR}/comparison_summary.txt"

echo ""
echo "Results saved to: ${OUT_DIR}"
echo "Summary: ${OUT_DIR}/comparison_summary.txt"
