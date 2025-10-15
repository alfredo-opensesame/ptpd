#!/usr/bin/env bash
# test-ptpd-macos.sh
# Test connection to a PTP master on macOS (no build). Runs ptpd2 as slave-only,
# captures UDP 319/320, plots accuracy (mean) & precision (σ) from ptpd-stats.csv,
# and prints PASS/FAIL.

set -euo pipefail

# ---- CLI ----
IFACE=""
DURATION=10
NO_ADJUST=1
PTPD_PATH=""
MASTER_IP=""
DOMAIN=""        # optional; may be ignored by your ptpd
PLOT_UNIT="us"   # plotting unit (ns|us|ms|s). CSV is assumed in ns
CONF_FILE=""

# ---- Help function ----
show_help() {
    cat << EOF
ptpd-run-macos.sh - Test PTP master connectivity on macOS

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -i IFACE        Network interface (auto-detected if not specified)
    -t DURATION     Test duration in seconds (default: 10)
    -A              Allow clock adjustments (default: observe-only mode)
    -p PATH         Path to ptpd2 binary (auto-detected if not specified)
    -m MASTER_IP    Master IP address for ping test
    -d DOMAIN       PTP domain number
    -U UNIT         Plot unit: ns|us|ms|s (default: us)
    -f CONFIG       Configuration file for ptpd2
    -h, --help      Show this help message

EXAMPLES:
    $0                          # Auto-detect interface, 10s test
    $0 -i en0 -t 30            # Use en0, 30 second test
    $0 -i en0 -m 192.168.1.100 # Test with specific master IP
    $0 -p ./custom/ptpd2        # Use custom ptpd2 binary

OUTPUT:
    Creates timestamped directory in ./ptp_logs/ with:
    - ptpd.log          PTP daemon log
    - ptpd-stats.csv    Statistics CSV
    - ptp.pcap          Packet capture
    - offset_*.png      Plots (if matplotlib available)

EOF
}

# Handle --help before getopts
for arg in "$@"; do
    if [[ "$arg" == "--help" ]]; then
        show_help
        exit 0
    fi
done

while getopts ":i:t:Ap:m:d:U:f:h" opt; do
  case "$opt" in
    i) IFACE="$OPTARG" ;;
    t) DURATION="$OPTARG" ;;
    A) NO_ADJUST=0 ;;         # allow clock adjustments (omit -n)
    p) PTPD_PATH="$OPTARG" ;;
    m) MASTER_IP="$OPTARG" ;;
    d) DOMAIN="$OPTARG" ;;
    U) PLOT_UNIT="$OPTARG" ;; # output unit for plots/report
    f) CONF_FILE="$OPTARG" ;; # config file for ptpd2
    h) show_help; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; echo "Use -h or --help for usage information." >&2; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
  esac
done

# ---- UI helpers ----
cgreen=$(tput setaf 2 2>/dev/null || true); cred=$(tput setaf 1 2>/dev/null || true)
cyellow=$(tput setaf 3 2>/dev/null || true); cblue=$(tput setaf 4 2>/dev/null || true)
cbold=$(tput bold 2>/dev/null || true); creset=$(tput sgr0 2>/dev/null || true)
info(){ echo "${cblue}▶${creset} $*"; }
ok(){   echo "${cgreen}✓${creset} $*"; }
warn(){ echo "${cyellow}⚠${creset} $*"; }
err(){  echo "${cred}✖${creset} $*"; }

need(){ command -v "$1" >/dev/null 2>&1 || { err "Missing: $1"; exit 1; }; }

need tcpdump; need awk; need grep; need sed

# ---- Locate ptpd2 ----
if [[ -z "${PTPD_PATH}" ]]; then
  # Check for available binaries in preference order (VSCode Ninja builds first)
  if [[ -x "./build/ninja-debug-macos/src/ptpd2" ]]; then PTPD_PATH="./build/ninja-debug-macos/src/ptpd2"
  elif [[ -x "./build/ninja-release-macos/src/ptpd2" ]]; then PTPD_PATH="./build/ninja-release-macos/src/ptpd2"
  elif [[ -x "./build/ninja-gtest-macos/src/ptpd2" ]]; then PTPD_PATH="./build/ninja-gtest-macos/src/ptpd2"
  elif [[ -x "./macos/build-cmake/src/ptpd2" ]]; then PTPD_PATH="./macos/build-cmake/src/ptpd2"
  elif [[ -x "./build-cmake/src/ptpd2" ]]; then PTPD_PATH="./build-cmake/src/ptpd2"
  elif [[ -x "./build/src/ptpd2" ]]; then PTPD_PATH="./build/src/ptpd2"
  elif [[ -x "./macos/build/src/ptpd2" ]]; then PTPD_PATH="./macos/build/src/ptpd2"
  elif command -v ptpd2 >/dev/null 2>&1; then PTPD_PATH="$(command -v ptpd2)"
  else err "ptpd2 not found. Use -p <path> or build with ptpd-build-ninja-*-macos.sh, ptpd-build-cmake-macos.sh, or ptpd-build-macos.sh"; exit 2; fi
fi
[ -x "$PTPD_PATH" ] || { err "ptpd2 not executable: $PTPD_PATH"; exit 2; }

# ---- Choose interface ----
if [[ -z "$IFACE" ]]; then
  IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' || true)"
  [[ -n "$IFACE" ]] || { err "Could not autodetect interface. Use -i enX"; exit 2; }
  info "Autodetected interface: ${cbold}${IFACE}${creset}"
else
  info "Using interface: ${cbold}${IFACE}${creset}"
fi
if ! ifconfig "$IFACE" >/dev/null 2>&1; then err "Interface $IFACE not found"; exit 2; fi

# ---- Output dir ----
TS=$(date +"%Y%m%d_%H%M%S")
OUTDIR="./ptp_logs/${TS}"
mkdir -p "$OUTDIR"
LOG="$OUTDIR/ptpd.log"
CSV="$OUTDIR/ptpd-stats.csv"
PCAP="$OUTDIR/ptp.pcap"
TDUMP_TXT="$OUTDIR/tcpdump.txt"

info "Output dir       : ${cbold}$OUTDIR${creset}"
info "ptpd2            : ${cbold}$PTPD_PATH${creset}"
info "Duration         : ${cbold}${DURATION}s${creset}"
info "Clock adjust     : ${cbold}$([[ $NO_ADJUST -eq 1 ]] && echo 'NO (-n observe-only)' || echo 'YES')${creset}"

# ---- Preflight: stop any running ptpd2 and clear lock ----
existing_pids="$(pgrep -x ptpd2 || true)"
if [[ -n "$existing_pids" ]]; then
  info "Found running ptpd2 instance(s): $existing_pids — stopping…"
  sudo kill -TERM $existing_pids 2>/dev/null || true
  sleep 1
  still="$(pgrep -x ptpd2 || true)"
  if [[ -n "$still" ]]; then
    warn "ptpd2 still running; forcing stop: $still"
    sudo kill -KILL $still 2>/dev/null || true
    sleep 0.5
  fi
fi
if [[ -e /var/run/ptpd2.lock ]]; then
  info "Removing stale lock: /var/run/ptpd2.lock"
  sudo rm -f /var/run/ptpd2.lock || true
fi

# ---- Optional master reachability ----
if [[ -n "$MASTER_IP" ]]; then
  info "Pinging master $MASTER_IP…"
  if ping -c1 -W 1000 "$MASTER_IP" >/dev/null 2>&1; then ok "Master reachable via ICMP"
  else warn "Master did NOT reply to ping (could still be fine for PTP)"; fi
fi

# ---- Start sniff + ptpd ----
info "Starting tcpdump on $IFACE (UDP 319/320)…"
sudo -n true 2>/dev/null || info "sudo may prompt for password"
sudo tcpdump -i "$IFACE" -n -U '(udp port 319 or udp port 320)' -w "$PCAP" \
  >"$TDUMP_TXT" 2>"$TDUMP_TXT.err" &
TCPD_PID=$!

PTPD_ARGS=(-s -D -D -D -i "$IFACE"
           --global:log_file="$LOG"
           --global:statistics_file="$CSV"
           --global:statistics_update_interval=1)
[[ "$NO_ADJUST" -eq 1 ]] && PTPD_ARGS+=(-n)

# If a conf file is provided, pass it while still forcing global outputs for plotting
if [[ -n "${CONF_FILE:-}" ]]; then
  PTPD_ARGS+=(-c "$CONF_FILE")
fi

# Try domain via conf (some builds accept one of these keys)
CONF=""
if [[ -n "$DOMAIN" ]]; then
  CONF="$OUTDIR/ptpd2.conf"
  {
    echo "ptpengine:domainNumber $DOMAIN"
    echo "ptpengine:domain $DOMAIN"
  } > "$CONF"
  PTPD_ARGS+=(-f "$CONF")
  info "(Attempting domain=$DOMAIN via conf; your ptpd may ignore it if unsupported)"
fi

info "Launching ptpd2…"
sudo "$PTPD_PATH" "${PTPD_ARGS[@]}" &
PTPD_PID=$!

cleanup(){
  info "Stopping processes…"
  kill "$PTPD_PID" >/dev/null 2>&1 || true
  sudo kill "$TCPD_PID" >/dev/null 2>&1 || true
  sleep 0.5
  if [[ -e /var/run/ptpd2.lock ]]; then
    info "Clearing lock: /var/run/ptpd2.lock"
    sudo rm -f /var/run/ptpd2.lock || true
  fi
}
trap cleanup EXIT INT TERM

sleep "$DURATION"
cleanup

# ---- Analyze traffic & state ----
info "Analyzing…"
COUNT319=$(tcpdump -nn -r "$PCAP" 'udp port 319' 2>/dev/null | wc -l | awk '{print $1}')
COUNT320=$(tcpdump -nn -r "$PCAP" 'udp port 320' 2>/dev/null | wc -l | awk '{print $1}')

STATE_LINE=$(grep -E "Now in state: PTP_[A-Z_]+" "$LOG" | tail -n1 || true)
LAST_STATE=$(printf "%s" "$STATE_LINE" | sed -E 's/.*Now in state: PTP_([A-Z_]+).*/\1/' || true)
SAW_SLAVE=0
grep -q "Now in state: PTP_SLAVE" "$LOG" && SAW_SLAVE=1

BEST_LINE=$(grep -Ei 'Best master|becoming a slave|selected best master' "$LOG" | tail -n1 || true)
UNKNOWN_CFG=$(grep -i 'Unknown configuration entry' "$LOG" | tail -n1 || true)

echo
echo "==================== Summary ===================="
printf "Interface           : %s\n" "$IFACE"
[[ -n "$DOMAIN" ]] && printf "Requested domain    : %s\n" "$DOMAIN"
printf "Duration            : %ss\n" "$DURATION"
printf "UDP 319 (event)     : %s packets\n" "$COUNT319"
printf "UDP 320 (general)   : %s packets\n" "$COUNT320"
printf "ptpd last state     : %s\n" "${LAST_STATE:-N/A}"
printf "ptpd master note    : %s\n" "${BEST_LINE:-N/A}"
[[ -n "$UNKNOWN_CFG" ]] && printf "ptpd warnings       : %s\n" "$UNKNOWN_CFG"
printf "Logs                : %s\n" "$LOG"
printf "CSV stats           : %s\n" "$CSV"
printf "PCAP                : %s\n" "$PCAP"
echo "================================================="

# ---- PASS/FAIL ----
PASS=0
if [[ $SAW_SLAVE -eq 1 ]]; then PASS=1
elif [[ "$COUNT319" -ge 1 || "$COUNT320" -ge 1 ]]; then PASS=0
fi

# ---- Plot accuracy (mean) & precision (σ) from CSV (assumes offset in ns) ----
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import matplotlib" >/dev/null 2>&1; then
    info "Plotting accuracy (mean) and precision (σ) → $OUTDIR"
    python3 - "$CSV" "$PLOT_UNIT" <<'PYCODE'
import sys, csv, math, os
from statistics import mean, pstdev
import matplotlib.pyplot as plt

csv_path = sys.argv[1]
outunit  = sys.argv[2]  # ns|us|ms|s
SCALE = {"ns":1.0, "us":1e3, "ms":1e6, "s":1e9}

def sniff_offset_idx(header):
    cand = ["offsetFromMaster","offset_from_master","offset","offsetfrommaster","masterOffset","master_offset"]
    lower = [h.strip().lower() for h in header]
    for c in cand:
        if c.lower() in lower: return lower.index(c.lower())
    for i,h in enumerate(lower):
        if "offset" in h: return i
    return None

with open(csv_path, newline="") as f:
    r = csv.reader(f)
    header = next(r)
    idx = sniff_offset_idx(header)
    if idx is None:
        print("PLOT: could not find offset column in CSV header", header)
        sys.exit(0)
    # CSV offsets assumed in ns (ptpd default). Convert to outunit.
    vals = []
    for row in r:
        try: v = float(row[idx])
        except Exception: continue
        vals.append(v / SCALE[outunit])

if not vals:
    print("PLOT: no numeric offsets found")
    sys.exit(0)

mu = mean(vals)
sg = pstdev(vals)
mx = max(abs(v) for v in vals)

out_dir = os.path.dirname(csv_path)
hist_png = os.path.join(out_dir, "offset_hist.png")
ts_png   = os.path.join(out_dir, "offset_timeseries.png")

# Histogram
fig = plt.figure(figsize=(8,5))
ax = fig.add_subplot(111)
ax.hist(vals, bins=60)
ax.axvline(0.0, linestyle="--", linewidth=1.5, label="Reference (0)")
ax.axvline(mu,  linestyle="-",  linewidth=2.0, label=f"Mean (accuracy B = {mu:.3f} {outunit})")
ax.axvline(mu-sg, linestyle=":", linewidth=1.5, label="-1σ")
ax.axvline(mu+sg, linestyle=":", linewidth=1.5, label="+1σ")
ax.set_xlabel(f"Offset from master [{outunit}]"); ax.set_ylabel("Samples")
ax.set_title("Histogram of offset — Accuracy (B) = |mean|, Precision (C) ≈ σ")
ax.legend(loc="best"); fig.tight_layout(); fig.savefig(hist_png, dpi=150); plt.close(fig)

# Timeseries
fig = plt.figure(figsize=(9,4.5))
ax = fig.add_subplot(111)
ax.plot(vals)
ax.set_xlabel("Sample"); ax.set_ylabel(f"Offset from master [{outunit}]")
ax.set_title("Offset vs time"); fig.tight_layout(); fig.savefig(ts_png, dpi=150); plt.close(fig)

print(f"\nPLOT SUMMARY ({outunit}): samples={len(vals)} mean={mu:.6f} sigma={sg:.6f} max|offset|={mx:.6f}")
print(f"Saved: {hist_png}")
print(f"Saved: {ts_png}")
PYCODE
  else
    warn "Python3 found but matplotlib missing — skipping plots."
    echo "Install once:  pip3 install matplotlib"
  fi
else
  warn "python3 not found — skipping plots."
fi

# ---- Final verdict ----
if [[ $PASS -eq 1 ]]; then
  ok "PTP master connectivity CONFIRMED: reached PTP_SLAVE."
  exit 0
else
  if [[ "$COUNT319" -ge 1 || "$COUNT320" -ge 1 ]]; then
    warn "PTP traffic seen but no SLAVE in ${DURATION}s. Try -t 60 or check domain/profile."
  else
    err "No PTP traffic seen on $IFACE."
  fi
  exit 1
fi
