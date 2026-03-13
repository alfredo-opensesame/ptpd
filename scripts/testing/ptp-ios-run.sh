#!/bin/bash
# PTPd iOS Simulator Test Runner
#
# Installs PTPMonitor into a simulator, launches it with auto-start launch
# arguments, collects logs + a tcpdump packet capture on the host interface,
# monitors the PTP state machine live, and produces a summary.
#
# Usage:
#   ./ptp-ios-run.sh <interface> <master_ip> [options]
#
# Parameters:
#   interface   Host network interface the master is reachable on (e.g. en5)
#   master_ip   PTP grandmaster IP address (e.g. 192.168.68.114)
#
# Options:
#   -u / --udid   UDID     Simulator device UDID
#                          (default: C3F3DBCE-2497-4117-94C7-5A2BCB89F1A9)
#   -d / --duration N      Run duration in seconds (default: 60)
#   -b / --build           Rebuild PTPMonitor.app before launching
#   -v / --verbose         Verbose output
#   -h / --help            Show this help
#
# Examples:
#   ./ptp-ios-run.sh en0 192.168.68.114
#   ./ptp-ios-run.sh en0 192.168.68.114 -d 120 --build
#   ./ptp-ios-run.sh en0 192.168.68.114 -u AABBCCDD-... -d 60

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUNDLE_ID="com.example.ptpmonitor"
APP_PATH="$PROJECT_DIR/build-cmake/iossim-ptpd-app-debug/src-app/ios/Debug-iphonesimulator/PTPMonitor.app"
XCODE_PROJECT="$PROJECT_DIR/build-cmake/iossim-ptpd-app-debug/ptpd.xcodeproj"

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_UDID="C3F3DBCE-2497-4117-94C7-5A2BCB89F1A9"
UDID=""
INTERFACE=""
MASTER_IP=""
DURATION=60
DO_BUILD=false

# ── colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'    GREEN='\033[0;32m'  YELLOW='\033[1;33m'
BLUE='\033[0;34m'   CYAN='\033[0;36m'  NC='\033[0m'

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_header()  { echo -e "${CYAN}$1${NC}"; }

# ── PIDs of background processes we own ───────────────────────────────────────
TCPDUMP_PID=""
LOGSTREAM_PID=""
OUTPUT_DIR=""
LOG_FILE=""
PCAP_FILE=""
CSV_FILE=""

# ─────────────────────────────────────────────────────────────────────────────
show_usage() {
    cat <<EOF
Usage: $0 <interface> <master_ip> [options]

Parameters:
  interface    Host network interface to capture on (e.g. en5)
  master_ip    PTP grandmaster IP (e.g. 192.168.68.114)

Options:
  -u / --udid   UDID   Simulator device UDID
                       (default: $DEFAULT_UDID)
  -d / --duration N    Run duration in seconds (default: 60)
  -b / --build         Rebuild PTPMonitor.app before launching
  -v / --verbose       Verbose output
  -h / --help          Show this help

Examples:
  $0 en0 192.168.68.114
  $0 en0 192.168.68.114 -d 120 --build
  $0 en0 192.168.68.114 -u AABBCCDD-1234-... -d 60
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
parse_arguments() {
    case "${1:-}" in -h|--help) show_usage; exit 0 ;; esac

    if [ $# -lt 2 ]; then show_usage; exit 1; fi
    INTERFACE="$1"; shift
    MASTER_IP="$1";  shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--udid)
                UDID="$2"; shift 2 ;;
            -d|--duration)
                DURATION="$2"
                if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
                    print_error "Invalid duration: $DURATION"; exit 1
                fi
                shift 2 ;;
            -b|--build)
                DO_BUILD=true; shift ;;
            -v|--verbose)
                set -x; shift ;;
            -h|--help)
                show_usage; exit 0 ;;
            *)
                print_error "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done

    [ -z "$UDID" ] && UDID="$DEFAULT_UDID"

    if [ -z "$INTERFACE" ] || [ -z "$MASTER_IP" ]; then
        print_error "interface and master_ip are required"
        show_usage; exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
setup_output() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    OUTPUT_DIR="$SCRIPT_DIR/../ptpd_logs/ios_${ts}"
    mkdir -p "$OUTPUT_DIR"
    LOG_FILE="$OUTPUT_DIR/ptpmonitor_${INTERFACE}.log"
    PCAP_FILE="$OUTPUT_DIR/ptp_${INTERFACE}.pcap"
    CSV_FILE="$OUTPUT_DIR/ptpmonitor_${INTERFACE}.csv"
    print_status "📁 Output directory: $OUTPUT_DIR"
    print_status "📝 Log file:         $LOG_FILE"
    print_status "📦 Packet capture:   $PCAP_FILE"
    print_status "📊 CSV output:       $CSV_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
ensure_simulator_booted() {
    local state
    state=$(xcrun simctl list devices -j 2>/dev/null \
        | python3 -c "
import json,sys
d=json.load(sys.stdin)
for rt in d.get('devices',{}).values():
    for dev in rt:
        if dev.get('udid')=='$UDID':
            print(dev.get('state',''))
            sys.exit(0)
" 2>/dev/null || echo "")

    if [ "$state" = "Booted" ]; then
        print_success "Simulator $UDID already booted"
        return
    fi
    print_status "Booting simulator $UDID ..."
    xcrun simctl boot "$UDID" 2>/dev/null || true
    # Wait up to 30 s for Booted state
    local n=0
    while [ $n -lt 30 ]; do
        state=$(xcrun simctl list devices -j 2>/dev/null \
            | python3 -c "
import json,sys
d=json.load(sys.stdin)
for rt in d.get('devices',{}).values():
    for dev in rt:
        if dev.get('udid')=='$UDID':
            print(dev.get('state',''))
            sys.exit(0)
" 2>/dev/null || echo "")
        [ "$state" = "Booted" ] && break
        sleep 1; n=$((n+1))
    done
    if [ "$state" != "Booted" ]; then
        print_error "Simulator did not boot within 30 s (state: $state)"
        exit 1
    fi
    print_success "Simulator booted"
    # Open the Simulator app so the window appears
    open -a Simulator 2>/dev/null || true
    sleep 2
}

# ─────────────────────────────────────────────────────────────────────────────
build_app() {
    print_header "🔨 Building PTPMonitor..."
    xcodebuild \
        -project "$XCODE_PROJECT" \
        -scheme PTPMonitor \
        -destination "platform=iOS Simulator,id=$UDID" \
        -configuration Debug \
        build \
        2>&1 | grep -E "error:|warning:|BUILD |Compiling PTPBridge|Compiling.*Swift" \
             | grep -v "warning: " \
             || true
    print_success "Build complete"
}

# ─────────────────────────────────────────────────────────────────────────────
install_app() {
    print_status "📲 Installing $APP_PATH ..."
    if [ ! -d "$APP_PATH" ]; then
        print_error "App bundle not found: $APP_PATH"
        print_error "Run with --build or build with cmake first."
        exit 1
    fi
    xcrun simctl install "$UDID" "$APP_PATH"
    print_success "App installed"
}

# ─────────────────────────────────────────────────────────────────────────────
terminate_app() {
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
start_packet_capture() {
    print_status "📡 Starting tcpdump on $INTERFACE ..."
    sudo tcpdump -i "$INTERFACE" -n -U \
        '(udp port 319 or udp port 320 or udp port 10319 or udp port 10320)' \
        -w "$PCAP_FILE" >/dev/null 2>&1 &
    TCPDUMP_PID=$!
    print_success "tcpdump started (PID $TCPDUMP_PID)"
}

# ─────────────────────────────────────────────────────────────────────────────
start_log_stream() {
    print_status "📋 Starting log stream ..."
    # Capture all lines from PTPMonitor process; the -V log handler in ptpd
    # writes via NSLog / os_log so both NSLog and subsystem entries appear.
    # --level info suppresses debug-level UIKit/FrontBoard spam while
    # keeping NSLog (default level) ptpd messages visible.
    xcrun simctl spawn "$UDID" log stream \
        --predicate 'process == "PTPMonitor"' \
        --level info \
        --style compact \
        >"$LOG_FILE" 2>&1 &
    LOGSTREAM_PID=$!
    print_success "Log stream started (PID $LOGSTREAM_PID)"
    sleep 1   # let it initialise before the app launches
}

# ─────────────────────────────────────────────────────────────────────────────
launch_app() {
    print_status "🚀 Launching $BUNDLE_ID ..."
    print_status "   Interface : $INTERFACE"
    print_status "   Master IP : $MASTER_IP"
    xcrun simctl launch "$UDID" "$BUNDLE_ID" \
        --args -PTPAutoStart -PTPMasterIP "$MASTER_IP" -PTPInterface "$INTERFACE"
    print_success "App launched"
}

# ─────────────────────────────────────────────────────────────────────────────
# Live monitor — parses the log stream for state changes and offset values.
# Writes a simple CSV with columns: elapsed_s, state, offset_ns
# ─────────────────────────────────────────────────────────────────────────────
monitor_live() {
    local duration=$1
    print_header "📡 Monitoring for ${duration}s — press Ctrl+C to stop early"
    echo ""

    local start_time
    start_time=$(date +%s)
    local last_state=""
    local master_found=false
    local slave_achieved=false

    # Write CSV header
    echo "elapsed_s,state,offset_ns" >"$CSV_FILE"

    while true; do
        local now
        now=$(date +%s)
        local elapsed=$(( now - start_time ))
        [ "$elapsed" -ge "$duration" ] && break

        # Parse the last few lines of the log for state and offset
        if [ -f "$LOG_FILE" ]; then
            # State change lines — ptpd emits "State change from X to Y"
            local state_line
            state_line=$(grep -o "State change from [A-Z_]* to [A-Z_]*" "$LOG_FILE" 2>/dev/null | tail -1 || true)
            if [ -n "$state_line" ]; then
                local new_state
                new_state=$(echo "$state_line" | sed 's/.*to //')
                if [ "$new_state" != "$last_state" ]; then
                    echo ""
                    case "$new_state" in
                        PTP_SLAVE)
                            print_success "[$elapsed s] $state_line"
                            slave_achieved=true
                            ;;
                        PTP_LISTENING)
                            print_status "[$elapsed s] $state_line"
                            ;;
                        PTP_FAULTY|PTP_INITIALIZING)
                            print_warning "[$elapsed s] $state_line"
                            ;;
                        *)
                            print_status "[$elapsed s] $state_line"
                            ;;
                    esac
                    last_state="$new_state"
                fi
            fi

            # Offset lines — ptpd logs:
            #   "[ptpd]   offset from master:          0s       16335ns"
            # (The '[ptpd]' prefix is added by ios_log_handler via NSLog.)
            # We combine seconds + nanoseconds into a single nanosecond value.
            local offset_ns=""
            local offset_line
            offset_line=$(grep -o 'offset from master:.*ns' "$LOG_FILE" 2>/dev/null \
                | grep -v 'Raw' | tail -1 || true)
            if [ -n "$offset_line" ]; then
                local sec_val ns_val
                sec_val=$(echo "$offset_line" | grep -oE '[0-9]+s' | head -1 | tr -d 's')
                ns_val=$(echo "$offset_line" | grep -oE '[-]?[0-9]+ns' | tail -1 | tr -d 'ns')
                if [ -n "$sec_val" ] && [ -n "$ns_val" ]; then
                    offset_ns=$(( sec_val * 1000000000 + ns_val ))
                fi
            fi

            if [ -n "$offset_ns" ] && [ "$offset_ns" != "0" ]; then
                # Detect master from unicast grant messages
                if grep -q "received.*grant\|ANNOUNCE.*grant\|unicast.*granted" "$LOG_FILE" 2>/dev/null; then
                    master_found=true
                fi

                # Append to CSV
                echo "$elapsed,$last_state,$offset_ns" >>"$CSV_FILE"

                local offset_us
                offset_us=$(( offset_ns / 1000 ))
                printf "\r\033[K${BLUE}[%ds]${NC} State: %-20s Offset: %d ns (%d µs)  Master: %s  Slave: %s" \
                    "$elapsed" "$last_state" "$offset_ns" "$offset_us" \
                    "$([ "$master_found" = true ] && echo "✅" || echo "❌")" \
                    "$([ "$slave_achieved" = true ] && echo "✅" || echo "❌")"
            else
                if [ $(( elapsed % 5 )) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
                    printf "\r\033[K${BLUE}[%ds]${NC} State: %-20s  Waiting for offset data..." \
                        "$elapsed" "${last_state:-STARTING}"
                fi
            fi
        fi

        sleep 1
    done

    echo ""
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
stop_capture() {
    if [ -n "$TCPDUMP_PID" ]; then
        sudo kill -TERM "$TCPDUMP_PID" 2>/dev/null || true
        TCPDUMP_PID=""
    fi
    if [ -n "$LOGSTREAM_PID" ]; then
        kill -TERM "$LOGSTREAM_PID" 2>/dev/null || true
        LOGSTREAM_PID=""
    fi
    sleep 1
}

# ─────────────────────────────────────────────────────────────────────────────
analyze_results() {
    print_header "📊 ANALYSIS"

    # ── Packet capture ──────────────────────────────────────────────────────
    if [ -f "$PCAP_FILE" ]; then
        local c319 c320 c10319 c10320
        c319=$(tcpdump  -nn -r "$PCAP_FILE" 'udp port 319'   2>/dev/null | wc -l | tr -d ' ')
        c320=$(tcpdump  -nn -r "$PCAP_FILE" 'udp port 320'   2>/dev/null | wc -l | tr -d ' ')
        c10319=$(tcpdump -nn -r "$PCAP_FILE" 'udp port 10319' 2>/dev/null | wc -l | tr -d ' ')
        c10320=$(tcpdump -nn -r "$PCAP_FILE" 'udp port 10320' 2>/dev/null | wc -l | tr -d ' ')
        print_status "📦 PTP Traffic:"
        print_status "   UDP  319 (Event):       $c319 packets"
        print_status "   UDP  320 (General):     $c320 packets"
        print_status "   UDP 10319 (UC Event):   $c10319 packets"
        print_status "   UDP 10320 (UC General): $c10320 packets"
        local total=$(( c319 + c320 + c10319 + c10320 ))
        if [ "$total" -gt 0 ]; then
            print_success "✅ PTP traffic detected"
        else
            print_warning "⚠️  No PTP traffic captured — check interface and master"
        fi
    fi

    # ── Log summary ─────────────────────────────────────────────────────────
    if [ -f "$LOG_FILE" ]; then
        local n_state_changes n_faulty n_slave
        n_state_changes=$(grep -c "State change" "$LOG_FILE" 2>/dev/null || echo 0)
        n_faulty=$(grep -cE "PTP_FAULTY|FAULTY" "$LOG_FILE" 2>/dev/null || echo 0)
        n_slave=$(grep -cE  "PTP_SLAVE|Now in state: PTP_SLAVE" "$LOG_FILE" 2>/dev/null || echo 0)
        print_status "📋 State changes : $n_state_changes"
        print_status "   SLAVE entries : $n_slave"
        print_status "   FAULTY entries: $n_faulty"
        if [ "$n_faulty" -gt 0 ]; then
            print_warning "⚠️  FAULTY transitions detected — check log for root cause"
            grep "FAULTY\|sanity\|step\|threshold" "$LOG_FILE" 2>/dev/null | tail -5 | while IFS= read -r line; do
                print_warning "   $line"
            done
        fi
    fi

    # ── CSV offset analysis ─────────────────────────────────────────────────
    if [ -f "$CSV_FILE" ] && [ "$(wc -l < "$CSV_FILE")" -gt 1 ]; then
        local rows
        rows=$(tail -n +2 "$CSV_FILE" | grep -c "PTP_SLAVE" 2>/dev/null || echo 0)
        print_status "📈 Slave-state measurements: $rows"

        if [ "$rows" -gt 0 ]; then
            # Last slave-state offset
            local last_offset
            last_offset=$(tail -n +2 "$CSV_FILE" | grep "PTP_SLAVE" | tail -1 | cut -d',' -f3)
            local abs_offset_ns="${last_offset#-}"   # strip leading minus
            local offset_us=$(( abs_offset_ns / 1000 ))

            if   [ "$offset_us" -lt 1000  ]; then quality="Excellent (< 1 ms)"
            elif [ "$offset_us" -lt 10000 ]; then quality="Good      (< 10 ms)"
            elif [ "$offset_us" -lt 100000 ]; then quality="Acceptable(< 100 ms)"
            else                                   quality="Poor      (≥ 100 ms)"
            fi

            print_header "🎯 SYNCHRONISATION SUMMARY"
            print_status "   Final offset : ${last_offset} ns  (${offset_us} µs)"
            print_status "   Sync quality : $quality"
        else
            print_warning "⚠️  No PTP_SLAVE measurements recorded"
        fi
    else
        print_warning "⚠️  No CSV data collected"
    fi

    # ── File list ────────────────────────────────────────────────────────────
    print_header "📁 OUTPUT FILES"
    print_status "📂 Directory : $OUTPUT_DIR"
    print_status "📝 Log       : $LOG_FILE"
    print_status "📊 CSV       : $CSV_FILE"
    print_status "📦 PCAP      : $PCAP_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
cleanup_on_exit() {
    local code=$?
    # Nothing to clean up if we exited during argument parsing (no session started)
    [ -z "$OUTPUT_DIR" ] && exit $code
    echo ""
    print_warning "🛑 Cleaning up..."
    terminate_app
    stop_capture
    [ $code -eq 0 ] && analyze_results
    exit $code
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
    clear
    echo ""
    print_header "═══════════════════════════════════════════════════════════"
    print_header "🚀 PTPd iOS Simulator Test Runner"
    print_header "═══════════════════════════════════════════════════════════"
    echo ""

    parse_arguments "$@"

    # Validate host interface
    if ! ifconfig "$INTERFACE" >/dev/null 2>&1; then
        print_error "Interface '$INTERFACE' not found on this host"
        ifconfig -l; exit 1
    fi

    print_status "Interface  : $INTERFACE"
    print_status "Master IP  : $MASTER_IP"
    print_status "Simulator  : $UDID"
    print_status "Duration   : ${DURATION}s"
    print_status "Build      : $DO_BUILD"
    echo ""

    setup_output

    ensure_simulator_booted

    $DO_BUILD && build_app

    install_app

    # Terminate any previous session so the launch args take effect cleanly
    terminate_app
    sleep 1

    start_packet_capture
    start_log_stream

    launch_app

    monitor_live "$DURATION"

    terminate_app
    stop_capture

    print_success "Test completed"
}

trap 'cleanup_on_exit' INT TERM EXIT

main "$@"
