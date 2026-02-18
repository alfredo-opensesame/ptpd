#!/bin/bash

# Minimal compatibility shims for ptpd binary on macOS
 : "${PTPD_BIN:=/usr/sbin/ptpd}"
 : "${DAEMON_BIN:=${PTPD_BIN}}"
 : "${PTPD:=${PTPD_BIN}}"
 : "${DAEMON:=${PTPD_BIN}}"
# PTPd Test Runner
# Script to run PTPd daemon (ptpd2) with comprehensive logging, validation, and analysis

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default to original ptpd2 binary
BINARY_NAME="ptpd2"
BINARY="$PROJECT_DIR/build-cmake/debug/src/$BINARY_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Global variables
INTERFACE=""
CONFIG_FILE=""
DURATION=60          # Default duration
BINARY_PID=""
TCPDUMP_PID=""
LOG_FILE=""
STATS_FILE=""
PCAP_FILE=""
OUTPUT_DIR=""
BINARY_ARGS=()

# Function to show usage
show_usage() {
    echo "Usage: $0 <interface> [config_file] [options]"
    echo ""
    echo "Description:"
    echo "  PTPd test runner that runs the daemon (ptpd2 or ptpd-app) with comprehensive"
    echo "  logging, validation, and analysis."
    echo ""
    echo "Parameters:"
    echo "  interface         Network interface to use (e.g., en0, en5, eth0)"
    echo "  config_file       Configuration file to use (REQUIRED)"
    echo ""
    echo "Options:"
    echo "  -b, --binary NAME Binary to run: ptpd2 (default) or ptpd-app (library-based)"
    echo "  -d, --duration N  Run duration in seconds (default: 60)"
    echo "  -v, --verbose     Enable verbose output"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 en5 resources/ptpd-daemon.conf                  # Run original daemon"
    echo "  $0 en5 resources/ptpd-daemon.conf -b ptpd-app      # Run library-based app"
    echo "  $0 en0 my-config.conf --duration 30                # Run for 30 seconds"
    echo ""
    echo "Binary Options:"
    echo "  ptpd2     - Original PTPd executable (default)"
    echo "  ptpd-app  - Library-based example application (requires -DBUILD_PTPD_LIBRARY=ON)"
    echo ""
    echo "Configuration Requirements:"
    echo "  - All PTPd settings must be in the configuration file"
    echo "  - Interface will be overridden to match the specified interface"
    echo "  - Log and statistics paths will be set automatically"
    echo ""
    echo "Features:"
    echo "  - Configuration validation using actual PTPd binaries"
    echo "  - Comprehensive PTP traffic analysis"
    echo "  - Statistical analysis and plotting"
    echo "  - Packet capture and protocol analysis"
    echo "  - Automatic cleanup and resource management"
    echo "  - Live master detection and synchronization monitoring"
    echo ""
    echo "Requirements:"
    echo "  - Root privileges (sudo) for network operations"
    echo "  - PTP requires raw sockets, timestamping, and shared memory access"
    echo "  - Script will automatically use sudo for PTPd processes"
}

# Function to validate PTPd configuration file
validate_ptpd_config() {
    local config_file="$1"
    local config_name="$2"

    if [ -z "$config_file" ]; then
        return 0  # No config file to validate
    fi

    print_status "🔍 Validating PTPd configuration: $config_name"

    # Check if file exists and is readable
    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi

    if [ ! -r "$config_file" ]; then
        print_error "Configuration file not readable: $config_file"
        return 1
    fi

    if [ ! -s "$config_file" ]; then
        print_error "Configuration file is empty: $config_file"
        return 1
    fi

    # Basic syntax validation
    local validation_errors=0
    local line_number=0
    local has_interface=false
    local has_preset=false
    local critical_settings=0

    print_status "📋 Performing syntax validation..."

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))

        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*[\;#] ]]; then
            continue
        fi

        # Check for basic key=value format for namespaced settings
        if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*= ]]; then
            critical_settings=$((critical_settings + 1))

            if [[ "$line" =~ ptpengine:interface ]]; then
                has_interface=true
            elif [[ "$line" =~ ptpengine:preset ]]; then
                has_preset=true
            fi

        # Non-namespaced key=value (warn unless it's global:)
        elif [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*= ]] || [[ "$line" =~ = ]]; then
            if [[ ! "$line" =~ ^[[:space:]]*global:[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*= ]]; then
                print_warning "  Line $line_number: Potentially invalid setting format: ${line:0:50}..."
                validation_errors=$((validation_errors + 1))
            else
                critical_settings=$((critical_settings + 1))
            fi
        fi
    done < "$config_file"

    # Validation summary
    print_status "📊 Validation results:"
    print_status "  - Total lines processed: $line_number"
    print_status "  - Critical settings found: $critical_settings"
    print_status "  - Format warnings: $validation_errors"
    print_status "  - Interface setting: $([ "$has_interface" = true ] && echo '✅ Found' || echo '⚠️  Missing (will be overridden)')"
    print_status "  - Preset setting: $([ "$has_preset" = true ] && echo '✅ Found' || echo '⚠️  Missing')"

    # Binary validation using: sudo ptpd -c <conf> -k
    local binary_path
    binary_path="$BINARY"

    if [ -n "$binary_path" ] && [ -x "$binary_path" ]; then
        print_status "🧪 Validating configuration with: sudo $binary_path -c \"$config_file\" -k"
        local test_output
        local temp_output="/tmp/ptpd_config_test_$$.log"

        sudo "$binary_path" -c "$config_file" -k >"$temp_output" 2>&1

        local test_result=$?
        test_output=$(cat "$temp_output")
        rm -f "$temp_output"

        if [ $test_result -eq 0 ]; then
            print_success "✅ Configuration validated by PTPd daemon"
            if [ -n "$test_output" ]; then
                echo "$test_output" | head -3 | while IFS= read -r info_line; do
                    print_status "    $info_line"
                done
            fi
        else
            print_error "❌ PTPd daemon configuration validation failed:"
            echo "$test_output" | head -10 | while IFS= read -r error_line; do
                if [[ "$error_line" =~ ERROR|FATAL|Invalid|Unknown ]]; then
                    print_error "    $error_line"
                else
                    print_status "    $error_line"
                fi
            done
            return 1
        fi
    else
        print_warning "PTPd daemon binary not available for thorough configuration testing"
        print_warning "Falling back to basic syntax validation only"
    fi

    # Critical validation failures
    if [ $critical_settings -eq 0 ]; then
        print_error "❌ No valid PTPd settings found in configuration file"
        return 1
    fi

    if [ $validation_errors -gt 5 ]; then
        print_error "❌ Too many configuration format warnings ($validation_errors)"
        print_error "This may indicate a corrupted or incompatible configuration file"
        return 1
    fi

    print_success "✅ Configuration validation passed"
    return 0
}


# Function to find daemon binary
find_daemon_binary() {
    local daemon_bin=ptpd
    echo "$daemon_bin"
}

# Function to find app binary
find_app_binary() {
    local app_bin=ptpd
    echo "$app_bin"
}

# Function to parse command line arguments
parse_arguments() {
    local verbose=false

    if [ $# -lt 2 ]; then
        show_usage
        exit 1
    fi

    # Parse interface (first argument)
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            INTERFACE="$1"
            ;;
    esac
    shift

    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--binary)
                BINARY_NAME="$2"
                if [[ "$BINARY_NAME" != "ptpd2" ]] && [[ "$BINARY_NAME" != "ptpd-app" ]]; then
                    print_error "Binary must be 'ptpd2' or 'ptpd-app', got: $BINARY_NAME"
                    exit 1
                fi
                # Update BINARY path based on binary name
                for BUILD_DIR in "build-cmake/debug" "build-cmake/release"; do
                    if [[ "$BINARY_NAME" == "ptpd-app" ]]; then
                        CANDIDATE="$PROJECT_DIR/$BUILD_DIR/src-app/$BINARY_NAME"
                    else
                        CANDIDATE="$PROJECT_DIR/$BUILD_DIR/src/$BINARY_NAME"
                    fi
                    if [ -x "$CANDIDATE" ]; then
                        BINARY="$CANDIDATE"
                        break
                    fi
                done
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
                    print_error "Invalid duration: $DURATION (must be positive integer)"
                    exit 1
                fi
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$CONFIG_FILE" ]; then
                    CONFIG_FILE="$1"
                else
                    print_error "Too many arguments. Expected interface and config file."
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$INTERFACE" ]; then
        print_error "Interface name is required"
        show_usage
        exit 1
    fi

    if [ -z "$CONFIG_FILE" ]; then
        print_error "Configuration file is required"
        show_usage
        exit 1
    fi

    # Verify binary exists
    if [ ! -x "$BINARY" ]; then
        print_error "Binary not found or not executable: $BINARY"
        if [[ "$BINARY_NAME" == "ptpd-app" ]]; then
            print_error "Make sure you built with: cmake -B build-cmake/debug -DBUILD_PTPD_LIBRARY=ON"
        fi
        exit 1
    fi

    # Display which binary we're using
    print_status "Using binary: $BINARY_NAME ($BINARY)"
}

# Function to setup output directories and files
setup_output() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    OUTPUT_DIR="$(dirname "$SCRIPT_DIR")/ptpd_logs/${timestamp}"
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/locks"

    LOG_FILE="$OUTPUT_DIR/ptpd_daemon_${INTERFACE}.log"
    STATS_FILE="$OUTPUT_DIR/ptpd_daemon_${INTERFACE}.csv"
    PCAP_FILE="$OUTPUT_DIR/ptp_${INTERFACE}.pcap"

    print_status "📁 Output directory: $OUTPUT_DIR"
    print_status "📝 Log file: $LOG_FILE"
    print_status "📊 Statistics file: $STATS_FILE"
    print_status "📦 Packet capture: $PCAP_FILE"
}

# Function to handle configuration file (absolute, $PWD, script dir only) — POSIX/macOS safe
setup_configuration() {
    # No config? nothing to do.
    if [ -z "$CONFIG_FILE" ]; then
        return 0
    fi

    # Resolve script directory in a POSIX way.
    # If this file is sourced, $0 may be the parent shell; we fall back to $PWD.
    # You can override by exporting SCRIPT_DIR before calling.
    if [ -z "$SCRIPT_DIR" ]; then
        case "$0" in
            /*)  SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || pwd) ;;
            */*) SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || pwd) ;;
            *)   SCRIPT_DIR="$PWD" ;;
        esac
    fi

    # Expand leading ~ manually (POSIX-safe)
    case "$CONFIG_FILE" in
        "~/"* ) REQ_CONF="$HOME/${CONFIG_FILE#~/}" ;;
        "~"   ) REQ_CONF="$HOME" ;;
        *     ) REQ_CONF="$CONFIG_FILE" ;;
    esac

    # Strip trailing slash (if any)
    # shellcheck disable=SC2001
    REQ_CONF=$(printf '%s' "$REQ_CONF" | sed 's:/*$::')

    resolved_conf=""

    # 1) Absolute path?
    case "$REQ_CONF" in
        /*) [ -f "$REQ_CONF" ] && resolved_conf="$REQ_CONF" ;;
        *)
            # 2) current working directory
            if [ -z "$resolved_conf" ] && [ -f "$PWD/$REQ_CONF" ]; then
                resolved_conf="$PWD/$REQ_CONF"
            fi
            # 3) project directory (parent of scripts/)
            if [ -z "$resolved_conf" ] && [ -f "$PROJECT_DIR/$REQ_CONF" ]; then
                resolved_conf="$PROJECT_DIR/$REQ_CONF"
            fi
            # 4) script directory
            if [ -z "$resolved_conf" ] && [ -f "$SCRIPT_DIR/$REQ_CONF" ]; then
                resolved_conf="$SCRIPT_DIR/$REQ_CONF"
            fi
            ;;
    esac

    if [ -z "$resolved_conf" ]; then
        print_error "Configuration file not found (searched):"
        print_error "  - $REQ_CONF"
        print_error "  - $PWD/$REQ_CONF"
        print_error "  - $PROJECT_DIR/$REQ_CONF"
        print_error "  - $SCRIPT_DIR/$REQ_CONF"
        exit 1
    fi

    # Validate configuration if validator exists
    if command -v validate_ptpd_config >/dev/null 2>&1; then
        if ! validate_ptpd_config "$resolved_conf" "$(basename "$resolved_conf")"; then
            print_error "Configuration validation failed: $resolved_conf"
            exit 1
        fi
    else
        print_status "⚠️  validate_ptpd_config not found; skipping validation"
    fi

    # Ensure output and locks dir exist
    if [ -z "$OUTPUT_DIR" ]; then
        print_error "OUTPUT_DIR is not set"
        exit 1
    fi
    mkdir -p "$OUTPUT_DIR/locks" || {
        print_error "Failed to create: $OUTPUT_DIR/locks"
        exit 1
    }

    # Prepare output (use BSD cp; no GNU flags)
    final_conf="$OUTPUT_DIR/ptpd-daemon.conf"
    cp "$resolved_conf" "$final_conf" || {
        print_error "Failed to copy config to: $final_conf"
        exit 1
    }

    {
        echo ""
        echo "; Runtime overrides for test run (daemon mode)"
        printf "ptpengine:interface = %s\n" "$INTERFACE"
        printf "global:log_file = %s\n" "$LOG_FILE"
        printf "global:statistics_file = %s\n" "$STATS_FILE"
        echo "global:statistics_update_interval = 1"
        printf "global:lock_directory = %s\n" "$OUTPUT_DIR/locks"
    } >> "$final_conf"

    CONFIG_FILE="$final_conf"
    print_status "📋 Using configuration file: $resolved_conf"
    print_status "📋 Configuration prepared: $CONFIG_FILE"
}




# Function to setup binary arguments
setup_binary_args() {
    if [ -z "$CONFIG_FILE" ]; then
        print_error "Configuration file is required. All parameters except interface must be specified in the config file."
        print_status "Available config files in resources/:"
        ls -1 "$PROJECT_DIR/resources/"*.conf 2>/dev/null | sed 's|.*/||' || echo "  No config files found"
        exit 1
    fi

    BINARY_ARGS=(
        -C
        -c "$CONFIG_FILE"
        -i "$INTERFACE"
        -D -D -D
    )

}

# Function to start packet capture
start_packet_capture() {
    print_status "📡 Starting packet capture on $INTERFACE..."
    sudo tcpdump -i "$INTERFACE" -n -U '(udp port 319 or udp port 320)' -w "$PCAP_FILE" > /dev/null 2>&1 &
    TCPDUMP_PID=$!
    print_success "Packet capture started (PID: $TCPDUMP_PID)"
}

# Stop and clean any PTPd instances on macOS (launchd/Homebrew/custom builds)
stop_ptpd_processes() {
    print_status "🛑 Stopping all PTPd processes on macOS..."

    # Helper: check if a command exists
    have() { command -v "$1" >/dev/null 2>&1; }

    # 0) Try Homebrew services first (common for local installs)
    if have brew; then
        # Stop any brew services whose name contains "ptpd"
        # (handles ptpd, ptpd2, custom formula names)
        local brew_services
        brew_services="$(brew services list 2>/dev/null | awk 'NR>1 && tolower($1) ~ /ptpd/ {print $1}')"
        if [ -n "$brew_services" ]; then
            while IFS= read -r svc; do
                print_status "🔧 brew services stop $svc"
                brew services stop "$svc" >/dev/null 2>&1 || true
                # In case it was started for the current user only:
                brew services stop --user "$svc" >/dev/null 2>&1 || true
            done <<< "$brew_services"
        fi
    fi

    # 1) launchctl: stop/unload by label (system + user domains)
    #    Find any loaded launchd jobs with 'ptpd' in the label
    local labels
    labels="$(launchctl list 2>/dev/null | awk 'NR>1 {print $3}' | grep -Ei 'ptpd(_app)?(2)?' || true)"

    if [ -n "$labels" ]; then
        while IFS= read -r lbl; do
            [ -z "$lbl" ] && continue
            print_status "🧰 launchctl bootout (system) $lbl"
            launchctl bootout system "$lbl" >/dev/null 2>&1 || true

            print_status "🧰 launchctl bootout (gui/$UID) $lbl"
            launchctl bootout "gui/$UID" "$lbl" >/dev/null 2>&1 || true

            # Older macOS sometimes needs kickstart -k to force stop
            launchctl kickstart -k "system/$lbl" >/dev/null 2>&1 || true
            launchctl kickstart -k "gui/$UID/$lbl" >/dev/null 2>&1 || true
        done <<< "$labels"
    fi

    # 2) launchctl: unload any on-disk plists that mention ptpd (if they exist)
    #    We try bootout with the *path* which works even without a loaded label match
    local plist
    for plist in /Library/LaunchDaemons/*ptpd*.plist \
                 /Library/LaunchAgents/*ptpd*.plist \
                 "$HOME"/Library/LaunchAgents/*ptpd*.plist; do
        [ -e "$plist" ] || continue
        print_status "📄 launchctl bootout by plist: $plist"
        launchctl bootout system "$plist" >/dev/null 2>&1 || true
        launchctl bootout "gui/$UID" "$plist" >/dev/null 2>&1 || true
    done

    # 3) Kill any leftover processes by pattern (TERM then KILL)
    #    BSD pkill supports -f; keep a precise pattern to avoid false positives.
    #    Matches: ptpd, ptpd2, ptpd_App as a full token or path component.
    local PTP_PAT='(^|/)(ptpd2?|ptpd_App)([[:space:]]|$)'
    if pgrep -f "$PTP_PAT" >/dev/null 2>&1; then
        print_status "🔪 pkill -TERM leftover ptpd processes"
        sudo pkill -TERM -f "$PTP_PAT" 2>/dev/null || true

        # brief wait loop for graceful exit
        for _ in 1 2 3 4 5; do
            pgrep -f "$PTP_PAT" >/dev/null 2>&1 || break
            sleep 0.4
        done

        # force kill anything stubborn
        if pgrep -f "$PTP_PAT" >/dev/null 2>&1; then
            print_status "💀 pkill -KILL stubborn ptpd processes"
            sudo pkill -KILL -f "$PTP_PAT" 2>/dev/null || true
        fi
    fi

    # 4) Clean lock/pid files (common macOS locations + tmp)
    #    Note: /var is a symlink to /private/var on macOS.
    sudo rm -f /var/run/ptpd*.pid /var/run/ptpd*.lock 2>/dev/null || true
    sudo rm -f /private/var/run/ptpd*.pid /private/var/run/ptpd*.lock 2>/dev/null || true
    sudo rm -f /tmp/ptpd*.pid /tmp/ptpd*.lock 2>/dev/null || true
    sudo rm -f /usr/local/var/run/ptpd*.pid /usr/local/var/run/ptpd*.lock 2>/dev/null || true
    sudo rm -f /opt/homebrew/var/run/ptpd*.pid /opt/homebrew/var/run/ptpd*.lock 2>/dev/null || true

    sudo pkill -f '(^|/)(ptpd2?|ptpd_App)([[:space:]]|$)' 2>/dev/null || true

    # 5) Sanity check: show anything still around
    if pgrep -a -f "$PTP_PAT" >/dev/null 2>&1; then
        print_error "Some PTPd processes are still running:"
        pgrep -a -f "$PTP_PAT" || true
        return 1
    fi

    print_success "PTPd processes cleaned up on macOS"
}

# Function to check for PTP master using packet capture file
check_ptp_master() {
    local pcap_file="$1"

    if [ ! -f "$pcap_file" ]; then
        return 1
    fi

    # Check for PTP announce messages (UDP 319) in the existing capture
    local ptp_traffic=$(tcpdump -nn -r "$pcap_file" 'udp port 319' 2>/dev/null | wc -l | awk '{print $1}')

    if [ "$ptp_traffic" -gt 0 ]; then
        return 0
    fi

    return 1
}

# Function to monitor software clock in real-time
monitor_sw_clock() {
    local duration=$1
    local log_file=$2
    local stats_file=$3

    print_status "📡 Starting live synchronization monitoring..."
    print_status "Press Ctrl+C to stop early"
    echo ""  # Clear space for live updates

    local start_time=$(date +%s)
    local last_master_check=0
    local master_found=false
    local sync_achieved=false
    local last_progress_msg=""

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Safety check: if elapsed time goes negative or too large, reset
        if [ $elapsed -lt 0 ] || [ $elapsed -gt $((duration * 2)) ]; then
            print_warning "⚠️  Time calculation anomaly detected (elapsed: ${elapsed}s), resetting..."
            start_time=$(date +%s)
            elapsed=0
        fi

        # Check if we've exceeded duration
        if [ $elapsed -ge $duration ]; then
            break
        fi

        # Check for master every 10 seconds if not found
        if [ $master_found = false ] && [ $((elapsed - last_master_check)) -ge 10 ]; then
            if check_ptp_master "$PCAP_FILE"; then
                master_found=true
                echo ""  # Clear line for clean output
                print_success "🎯 PTP Master discovered!"
            fi
            last_master_check=$elapsed
        fi

        # Monitor log file for key events (less frequently to avoid spam)
        if [ -f "$log_file" ] && [ $((elapsed % 3)) -eq 0 ]; then
            # Look for recent master/sync events (last 3 lines)
            local recent_logs=$(tail -3 "$log_file" 2>/dev/null)

            # Check for master detection (improved patterns for app mode)
            if echo "$recent_logs" | grep -q -i "best.*master\|grandmaster\|announce.*received\|master.*clock\|ptp.*master"; then
                if [ $master_found = false ]; then
                    echo ""  # Clear line
                    print_success "🎯 PTP Master discovered in logs!"
                    master_found=true
                fi
            fi

            # Check for synchronization events - look for both initial sync and ongoing servo activity
            if echo "$recent_logs" | grep -q -i "received.*sync\|synchronized\|discipline\|adjFreq_wrapper\|updateClock.*servo\|PI servo"; then
                if [ $sync_achieved = false ]; then
                    echo ""  # Clear line
                    print_success "🔄 Clock synchronization active!"
                    sync_achieved=true
                fi
            fi
        fi

        # Monitor statistics file for latest measurements
        local current_progress=""
        if [ -f "$stats_file" ]; then
            local latest_stats=$(grep -v "^#" "$stats_file" | grep -E ",[[:space:]]*slv[[:space:]]*," | tail -1 2>/dev/null)
            if [ -n "$latest_stats" ]; then
                # Parse CSV fields
                local offset=$(echo "$latest_stats" | cut -d',' -f5 | sed 's/^[ \t]*//;s/[ \t]*$//')
                local delay=$(echo "$latest_stats" | cut -d',' -f4 | sed 's/^[ \t]*//;s/[ \t]*$//')
                local state=$(echo "$latest_stats" | cut -d',' -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')

                # If we have valid measurements in slave state, we have both master and sync
                if [ "$state" = "slv" ] && [ -n "$offset" ] && [[ "$offset" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                    if [ $master_found = false ]; then
                        master_found=true
                        echo ""  # Clear line
                        print_success "🎯 PTP Master detected via slave measurements!"
                    fi
                    if [ $sync_achieved = false ]; then
                        sync_achieved=true
                        echo ""  # Clear line
                        print_success "🔄 Clock synchronization active!"
                    fi
                fi

                if [ -n "$offset" ] && [[ "$offset" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                    # Convert to microseconds for display
                    local offset_us=$(echo "$offset * 1000000" | bc -l 2>/dev/null | sed 's/\..*$//')
                    local delay_us=$(echo "$delay * 1000000" | bc -l 2>/dev/null | sed 's/\..*$//')

                    # Ensure elapsed is positive for display
                    local display_elapsed=$elapsed
                    if [ $elapsed -lt 0 ]; then
                        display_elapsed=0
                    fi

                    current_progress="${GREEN}[${display_elapsed}s]${NC} State: ${state} | Offset: ${offset_us} μs | Delay: ${delay_us} μs | Master: $([ $master_found = true ] && echo "✅" || echo "❌") | Sync: $([ $sync_achieved = true ] && echo "✅" || echo "❌")"
                fi
            fi
        fi

        # Show progress with clean overwrite
        if [ -n "$current_progress" ] && [ "$current_progress" != "$last_progress_msg" ]; then
            # Clear the line and show new progress
            printf "\r\033[K%b" "$current_progress"
            last_progress_msg="$current_progress"
        elif [ $((elapsed % 5)) -eq 0 ] && [ $elapsed -gt 0 ] && [ -z "$current_progress" ]; then
            # Fallback progress indicator
            local display_elapsed=$elapsed
            if [ $elapsed -lt 0 ]; then
                display_elapsed=0
            fi
            printf "\r\033[K${BLUE}[${display_elapsed}s]${NC} Monitoring... | Master: $([ $master_found = true ] && echo "✅" || echo "❌") | Sync: $([ $sync_achieved = true ] && echo "✅" || echo "❌")"
        fi

        sleep 1
    done

    echo ""  # Final newline after monitoring
    echo ""  # Extra space before results
}

# Function to run the binary
run_binary() {
    print_status "Starting PTPd daemon on interface $INTERFACE (requires sudo)"



    echo ""
    echo "Command called:"
    echo "sudo $BINARY ${BINARY_ARGS[*]} >> \"$LOG_FILE\" 2>&1 &"
    echo ""

    sudo /bin/bash -c "\"$BINARY\" ${BINARY_ARGS[*]} >> \"$LOG_FILE\" 2>&1 &"

    BINARY_PID=$!
    print_success "PTPd started with root privileges (PID: $BINARY_PID)"

    # Give it a moment to start
    sleep 2

    # Check for immediate startup issues
    if ! sudo kill -0 "$BINARY_PID" 2>/dev/null; then
        print_error "❌ PTPd failed to start properly"
        if [ -f "$LOG_FILE" ]; then
            print_status "Last few log lines:"
            tail -5 "$LOG_FILE"
        fi
        exit 1
    fi
}

# Function to analyze results
analyze_results() {
    print_header "📊 ANALYSIS AND RESULTS"

    # Stop packet capture
    if [ -n "$TCPDUMP_PID" ]; then
        sudo kill -TERM "$TCPDUMP_PID" 2>/dev/null || true
    fi

    # Wait for processes to finish
    sleep 2

    # Analyze traffic
    if [ -f "$PCAP_FILE" ]; then
        local count319=$(tcpdump -nn -r "$PCAP_FILE" 'udp port 319' 2>/dev/null | wc -l | awk '{print $1}')
        local count320=$(tcpdump -nn -r "$PCAP_FILE" 'udp port 320' 2>/dev/null | wc -l | awk '{print $1}')

        print_status "📦 PTP Traffic Analysis:"
        print_status "  - UDP 319 (Event): $count319 packets"
        print_status "  - UDP 320 (General): $count320 packets"

        if [ "$count319" -gt 0 ] || [ "$count320" -gt 0 ]; then
            print_success "✅ PTP traffic detected - daemon is communicating"
        else
            print_warning "⚠️  No PTP traffic detected"
        fi
    fi

    # Analyze logs for synchronization status
    if [ -f "$LOG_FILE" ]; then
        local sync_indicators=$(grep -i "sync\|slave\|master\|offset" "$LOG_FILE" | wc -l | awk '{print $1}')
        local master_events=$(grep -i "master\|grandmaster" "$LOG_FILE" | wc -l | awk '{print $1}')
        local sync_events=$(grep -i "synchronized\|discipline\|servo" "$LOG_FILE" | wc -l | awk '{print $1}')

        print_status "📋 Log Analysis Summary:"
        print_status "  - Total synchronization entries: $sync_indicators"
        print_status "  - Master-related events: $master_events"
        print_status "  - Synchronization events: $sync_events"

        # Show key log excerpts
        print_status "📋 Key Events:"
        if [ $master_events -gt 0 ]; then
            grep -i "master\|grandmaster" "$LOG_FILE" | head -2 | while IFS= read -r line; do
                print_status "  🎯 $line"
            done
        fi

        if [ $sync_events -gt 0 ]; then
            grep -i "synchronized\|discipline" "$LOG_FILE" | head -2 | while IFS= read -r line; do
                print_status "  🔄 $line"
            done
        fi
    fi

    # Final synchronization assessment
    print_header "🎯 SYNCHRONIZATION SUMMARY"

    local final_assessment="Unknown"
    local final_offset=""

    if [ -f "$STATS_FILE" ]; then
        local stats_count=$(tail -n +2 "$STATS_FILE" 2>/dev/null | wc -l | awk '{print $1}')
        if [ "$stats_count" -gt 0 ]; then
            # Get the last valid slave measurement (skip init, dsbl, empty lines)
            local last_measurement=$(grep -v "^#" "$STATS_FILE" | grep -E ",[[:space:]]*slv[[:space:]]*," | tail -1 2>/dev/null)

            # Fallback to any valid measurement if no slave state found
            if [ -z "$last_measurement" ]; then
                last_measurement=$(grep -v "^#" "$STATS_FILE" | grep -v ",[[:space:]]*init[[:space:]]*," | grep -v ",[[:space:]]*dsbl[[:space:]]*," | tail -1 2>/dev/null)
            fi

            # Extract offset (field 5) and state (field 2), handle spaces
            final_offset=$(echo "$last_measurement" | cut -d',' -f5 | sed 's/^[ \t]*//;s/[ \t]*$//')
            local final_state=$(echo "$last_measurement" | cut -d',' -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')

            # Check if we have a valid numeric offset (not empty, not just zeros)
            if [ -n "$final_offset" ] && [[ "$final_offset" =~ ^-?[0-9]+\.?[0-9]*$ ]] && [ "$(echo "$final_offset" | sed 's/[0.-]//g')" != "" ]; then
                # Convert from seconds to microseconds (* 1,000,000)
                local offset_us=$(echo "$final_offset * 1000000" | bc -l 2>/dev/null | sed 's/\..*$//')
                local abs_offset_us=$(echo "$offset_us" | tr -d '-')

                # Assess quality based on microsecond values
                if (( abs_offset_us < 1000 )); then
                    final_assessment="Excellent (< 1ms)"
                elif (( abs_offset_us < 10000 )); then
                    final_assessment="Good (< 10ms)"
                elif (( abs_offset_us < 100000 )); then
                    final_assessment="Acceptable (< 100ms)"
                else
                    final_assessment="Poor (> 100ms)"
                fi

                print_status "🎯 Final State: $final_state"
                print_status "🎯 Final Offset: ${offset_us} μs (${final_offset} s)"
                print_status "🎯 Sync Quality: $final_assessment"
                print_status "🎯 Total Measurements: $stats_count"

                # Show trend from last few measurements
                local recent_offsets=$(grep -v "^#" "$STATS_FILE" | tail -5 | cut -d',' -f5 | sed 's/^[ \t]*//;s/[ \t]*$//' | grep -v "^$" | tail -3)
                if [ -n "$recent_offsets" ]; then
                    print_status "🎯 Recent Trend:"
                    echo "$recent_offsets" | while IFS= read -r offset; do
                        if [[ "$offset" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                            local trend_us=$(echo "$offset * 1000000" | bc -l 2>/dev/null | sed 's/\..*$//')
                            print_status "   ${trend_us} μs"
                        fi
                    done
                fi
            else
                print_warning "⚠️  No valid offset measurements recorded"
                print_status "   Raw final offset value: '$final_offset'"
                print_status "   Final state: '$final_state'"
                print_status "   Last measurement line: '$last_measurement'"
            fi
        else
            print_warning "⚠️  No statistics data collected"
        fi
    fi

    # Run analysis scripts
    local analysis_dir="$(dirname "$SCRIPT_DIR")/analysis"
    
    # Analyze CSV statistics
    if [ -f "$STATS_FILE" ] && command -v python3 >/dev/null 2>&1; then
        if [ -f "$analysis_dir/analyze_ptp.py" ]; then
            print_header "📈 PTP STATISTICS ANALYSIS"
            python3 "$analysis_dir/analyze_ptp.py" "$STATS_FILE" || print_warning "Statistical analysis failed"
            echo ""
        fi
    fi
    
    # Analyze packet capture
    if [ -f "$PCAP_FILE" ] && command -v tcpdump >/dev/null 2>&1; then
        if [ -f "$analysis_dir/analyze_pcap.sh" ]; then
            print_header "📦 PACKET CAPTURE ANALYSIS"
            "$analysis_dir/analyze_pcap.sh" "$PCAP_FILE" || print_warning "Packet analysis failed"
            echo ""
        fi
    fi

    print_header "📁 OUTPUT FILES"
    print_status "📂 Directory: $OUTPUT_DIR"
    print_status "📝 Log: $LOG_FILE"
    print_status "📊 Statistics: $STATS_FILE"
    print_status "📦 Packet capture: $PCAP_FILE"
}

# Function to cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    print_warning "\n🛑 Cleaning up..."

    if [ -n "$BINARY_PID" ]; then
        sudo kill -TERM "$BINARY_PID" 2>/dev/null || true
        sleep 2
        sudo kill -KILL "$BINARY_PID" 2>/dev/null || true
    fi

    if [ -n "$TCPDUMP_PID" ]; then
        sudo kill -TERM "$TCPDUMP_PID" 2>/dev/null || true
    fi

    stop_ptpd_processes > /dev/null 2>&1

    if [ $exit_code -eq 0 ]; then
        analyze_results
    fi

    exit $exit_code
}

# Main execution
main() {
    clear
    echo ""
    echo ""
    echo ""
    print_header "═══════════════════════════════════════════════════════════════"
    print_header "🚀 PTPd Test Runner"
    print_header "═══════════════════════════════════════════════════════════════"

    "$BINARY" -v 2>/dev/null | head -1 | while IFS= read -r ver_line; do
        print_status "Using PTPd binary: $ver_line"
    done

    # Parse arguments
    parse_arguments "$@"

    # Change to project root
    cd "$SCRIPT_DIR"

    # Validate interface
    if ! ifconfig "$INTERFACE" >/dev/null 2>&1; then
        print_error "Network interface '$INTERFACE' not found!"
        echo ""
        print_status "Available interfaces:"
        ifconfig -l
        exit 1
    fi

    print_success "Interface $INTERFACE is available"
    print_status "Running daemon mode for ${DURATION}s"

    # Setup
    print_status "==> Stopping stale ptpd instances..."
    stop_ptpd_processes
    print_status "==> Setting up output folders..."
    setup_output
    print_status "==> Preparing Configuration..."
    setup_configuration
    print_status "==> Preparing ptpd arguments..."
    setup_binary_args

    # Start execution
    print_status "📝 Starting packet capture..."
    start_packet_capture
    print_status "📝 Running binary..."
    run_binary

    # Start live monitoring
    monitor_sw_clock "$DURATION" "$LOG_FILE" "$STATS_FILE"

    # Stop daemon
    print_status "🛑 Stopping daemon..."
    if [ -n "$BINARY_PID" ]; then
        sudo kill -TERM "$BINARY_PID" 2>/dev/null || true
    fi

    print_success "Test completed successfully!"
}

# Set up signal handling
trap 'cleanup_on_exit' INT TERM EXIT

# Run main function
main "$@"
