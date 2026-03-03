#!/bin/bash
# run_sanitizers.sh
# Build and run ptpd2 under AddressSanitizer (ASAN), ThreadSanitizer (TSAN),
# UndefinedBehaviorSanitizer (UBSAN), static analysis with clang-tidy,
# and formatting checks with clang-format.
#
# Usage:
#   ./run_sanitizers.sh [options]
#
# Options:
#   -c, --config FILE   Config file for a live run (uses -k check mode if omitted)
#   -i, --iface IFACE   Network interface (required for live run)
#   -d, --duration N    Run duration in seconds for live run (default: 10)
#   -s, --sanitizer S   Run only one check: asan | tsan | ubsan | clang-tidy | clang-format
#                       (default: all)
#   -B, --no-build      Skip build/configure step (use existing binaries / compile_commands.json)
#   -h, --help          Show this message
#
# Notes:
#   - ASAN, TSAN, and UBSAN must be built/run in separate binaries; they cannot be combined.
#   - clang-tidy is a static analysis pass; it uses compile_commands.json from the debug build
#     (or generates one if absent) and does not require root or a running binary.
#   - clang-format runs in check-only mode (--dry-run --Werror): it reports files that would be
#     reformatted but does not modify them.  Style is read from .clang-format if present,
#     otherwise falls back to LLVM style.
#   - A live run requires root; config-check mode (-k) does not.
#   - TSAN on macOS may require 'sudo' even for -k due to raw socket probing.
#   - Reports are written to logs/sanitizers/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
success() { echo -e "${GREEN}[PASS]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[FAIL]${NC}    $*"; }
header()  { echo -e "\n${CYAN}=== $* ===${NC}"; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CONFIG_FILE=""
INTERFACE=""
DURATION=10
RUN_ASAN=true
RUN_TSAN=true
RUN_UBSAN=true
RUN_TIDY=true
RUN_FORMAT=true
SKIP_BUILD=false
LOG_DIR="$PROJECT_DIR/logs/sanitizers"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
show_usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)    CONFIG_FILE="$2"; shift 2 ;;
        -i|--iface)     INTERFACE="$2";   shift 2 ;;
        -d|--duration)  DURATION="$2";    shift 2 ;;
        -s|--sanitizer)
            case "$2" in
                asan)         RUN_ASAN=true;  RUN_TSAN=false; RUN_UBSAN=false; RUN_TIDY=false; RUN_FORMAT=false ;;
                tsan)         RUN_ASAN=false; RUN_TSAN=true;  RUN_UBSAN=false; RUN_TIDY=false; RUN_FORMAT=false ;;
                ubsan)        RUN_ASAN=false; RUN_TSAN=false; RUN_UBSAN=true;  RUN_TIDY=false; RUN_FORMAT=false ;;
                clang-tidy)   RUN_ASAN=false; RUN_TSAN=false; RUN_UBSAN=false; RUN_TIDY=true;  RUN_FORMAT=false ;;
                clang-format) RUN_ASAN=false; RUN_TSAN=false; RUN_UBSAN=false; RUN_TIDY=false; RUN_FORMAT=true  ;;
                *) error "Unknown check '$2'. Use: asan | tsan | ubsan | clang-tidy | clang-format"; exit 1 ;;
            esac
            shift 2 ;;
        -B|--no-build)  SKIP_BUILD=true; shift ;;
        -h|--help)      show_usage; exit 0 ;;
        *) error "Unknown argument: $1"; show_usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"

# Build ptpd2 with a given set of extra C/linker flags.
# Usage: build_sanitizer <name> <flags>
#   name  : asan | tsan  (used as the build subdirectory name)
#   flags : sanitizer flags passed to both C compiler and linker
build_sanitizer() {
    local name="$1"
    local flags="$2"
    local build_dir="$PROJECT_DIR/build-cmake/$name"
    local log="$LOG_DIR/build_${name}_${TIMESTAMP}.log"

    header "Building ptpd2 with $(echo "$name" | tr '[:lower:]' '[:upper:]')"
    info "Build dir : $build_dir"
    info "Flags     : $flags"
    info "Build log : $log"

    mkdir -p "$build_dir"

    # Configure
    cmake -S "$PROJECT_DIR" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Debug \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=OFF \
        -DENABLE_RUNTIME_DEBUG=ON \
        -DDEBUG_LEVEL=all \
        -DENABLE_PCAP=OFF \
        -DENABLE_SNMP=OFF \
        -DENABLE_STATISTICS=ON \
        -DENABLE_DAEMON=OFF \
        -DBUILD_WITH_SWCLOCK=ON \
        -DCMAKE_C_FLAGS="$flags" \
        -DCMAKE_EXE_LINKER_FLAGS="$flags" \
        > "$log" 2>&1

    # Build
    cmake --build "$build_dir" -- -j"$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)" \
        >> "$log" 2>&1

    local binary="$build_dir/src/ptpd2"
    if [[ -x "$binary" ]]; then
        success "Built: $binary"
    else
        error "Binary not found after build: $binary"
        error "See build log: $log"
        return 1
    fi
}

# Run ptpd2 under a sanitizer and capture its output.
# Usage: run_sanitizer <name> [extra env vars...]
run_sanitizer() {
    local name="$1"
    local binary="$PROJECT_DIR/build-cmake/$name/src/ptpd2"
    local report_log="$LOG_DIR/run_${name}_${TIMESTAMP}.log"

    header "Running ptpd2 under $(echo "$name" | tr '[:lower:]' '[:upper:]')"

    if [[ ! -x "$binary" ]]; then
        error "Binary not found: $binary  (did the build succeed?)"
        return 1
    fi

    # Build up the environment variables for the sanitizer runtime.
    local -a env_vars=()

    case "$name" in
        asan)
            # detect_leaks (LeakSanitizer) is Linux-only; macOS ASAN aborts if it is set to 1.
            local lsan_opt="detect_leaks=0"
            [[ "$(uname -s)" == "Linux" ]] && lsan_opt="detect_leaks=1"
            env_vars+=(
                "ASAN_OPTIONS=${lsan_opt}:halt_on_error=0:log_path=${LOG_DIR}/asan_${TIMESTAMP}"
            )
            ;;
        tsan)
            env_vars+=(
                "TSAN_OPTIONS=halt_on_error=0:log_path=${LOG_DIR}/tsan_${TIMESTAMP}"
            )
            ;;
        ubsan)
            env_vars+=(
                "UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0:log_path=${LOG_DIR}/ubsan_${TIMESTAMP}"
            )
            ;;
    esac

    info "Binary    : $binary"
    info "Report    : $report_log"
    info "Env       : ${env_vars[*]:-<none>}"

    local exit_code=0

    if [[ -n "$CONFIG_FILE" && -n "$INTERFACE" ]]; then
        # ----------------------------------------------------------------
        # Live run: requires root and a real network interface.
        # We patch the interface into a temp copy of the config, then run
        # for $DURATION seconds.
        # ----------------------------------------------------------------
        if [[ ! -f "$CONFIG_FILE" ]]; then
            error "Config file not found: $CONFIG_FILE"
            return 1
        fi

        local tmp_conf
        tmp_conf="$(mktemp /tmp/ptpd_${name}_XXXXXX.conf)"
        cp "$CONFIG_FILE" "$tmp_conf"

        # Override interface in the temp config
        if grep -q "ptpengine:interface" "$tmp_conf"; then
            sed -i.bak "s|ptpengine:interface.*|ptpengine:interface = $INTERFACE|" "$tmp_conf"
        else
            echo "ptpengine:interface = $INTERFACE" >> "$tmp_conf"
        fi
        rm -f "${tmp_conf}.bak"

        info "Mode      : live run on $INTERFACE for ${DURATION}s"
        info "Temp conf : $tmp_conf"

        # Run under timeout; ptpd2 is a daemon so we need to wait for it.
        set +e
        env "${env_vars[@]}" timeout "$DURATION" \
            sudo -E "$binary" -c "$tmp_conf" \
            > "$report_log" 2>&1
        exit_code=$?
        set -e

        rm -f "$tmp_conf"

        # timeout returns 124 when it kills the process — that is expected.
        if [[ $exit_code -eq 124 ]]; then
            info "Process terminated after ${DURATION}s (expected)."
            exit_code=0
        fi

    elif [[ -n "$CONFIG_FILE" ]]; then
        # ----------------------------------------------------------------
        # Config-check mode: ptpd2 -c <conf> -k  (no root needed)
        # ----------------------------------------------------------------
        if [[ ! -f "$CONFIG_FILE" ]]; then
            error "Config file not found: $CONFIG_FILE"
            return 1
        fi

        info "Mode      : config-check (-k)"
        set +e
        env "${env_vars[@]}" "$binary" -c "$CONFIG_FILE" -k \
            > "$report_log" 2>&1
        exit_code=$?
        set -e

    else
        # ----------------------------------------------------------------
        # Minimal mode: just run --help to exercise the startup path.
        # ----------------------------------------------------------------
        info "Mode      : --help (no config supplied)"
        set +e
        env "${env_vars[@]}" "$binary" --help \
            > "$report_log" 2>&1
        exit_code=$?
        set -e
        # --help exits non-zero on some builds; treat any exit as OK here.
        exit_code=0
    fi

    # Check the report log (and the per-process log files written by the
    # sanitizer runtime) for error markers.
    local san_errors=0

    # Scan the main output
    if grep -qE "ERROR: (AddressSanitizer|ThreadSanitizer|UndefinedBehaviorSanitizer)|runtime error:" \
            "$report_log" 2>/dev/null; then
        san_errors=$((san_errors + 1))
    fi

    # Scan any per-PID log files the sanitizer runtime may have written
    local pid_logs=()
    case "$name" in
        asan)  pid_logs=( "$LOG_DIR"/asan_${TIMESTAMP}.*  ) ;;
        tsan)  pid_logs=( "$LOG_DIR"/tsan_${TIMESTAMP}.*  ) ;;
        ubsan) pid_logs=( "$LOG_DIR"/ubsan_${TIMESTAMP}.* ) ;;
    esac
    for f in "${pid_logs[@]}"; do
        [[ -f "$f" ]] || continue
        if grep -qE "ERROR: (AddressSanitizer|ThreadSanitizer|UndefinedBehaviorSanitizer)|runtime error:" \
                "$f" 2>/dev/null; then
            san_errors=$((san_errors + 1))
            warn "Sanitizer error(s) found in: $f"
            grep -E "ERROR:|SUMMARY:" "$f" | head -10 || true
        fi
    done

    # Report overall result
    if [[ $exit_code -ne 0 ]]; then
        error "$(echo "$name" | tr '[:lower:]' '[:upper:]'): process exited with code $exit_code"
        [[ -s "$report_log" ]] && tail -20 "$report_log"
        return 1
    fi

    if [[ $san_errors -gt 0 ]]; then
        error "$(echo "$name" | tr '[:lower:]' '[:upper:]'): sanitizer reported errors — see $LOG_DIR"
        return 1
    fi

    success "$(echo "$name" | tr '[:lower:]' '[:upper:]'): no sanitizer errors detected"
    info "Full output in: $report_log"
    return 0
}

# ---------------------------------------------------------------------------
# clang-format: formatting check over all project .c / .h files
# Runs with --dry-run --Werror so no files are modified; exits non-zero if
# any file would be reformatted.  Style: .clang-format if present, else LLVM.
# ---------------------------------------------------------------------------
find_clang_format() {
    local cf
    cf="$(command -v clang-format 2>/dev/null)" && { echo "$cf"; return 0; }
    cf="$(xcrun -f clang-format 2>/dev/null)"   && { echo "$cf"; return 0; }
    for brew_path in /opt/homebrew/bin /opt/homebrew/opt/llvm/bin /usr/local/bin /usr/local/opt/llvm/bin; do
        [[ -x "$brew_path/clang-format" ]] && { echo "$brew_path/clang-format"; return 0; }
    done
    return 1
}

run_clang_format() {
    header "clang-format formatting check"

    local fmt_bin
    if ! fmt_bin="$(find_clang_format)"; then
        warn "clang-format not found — skipping."
        warn "Install via: brew install clang-format"
        return 0
    fi
    info "clang-format : $fmt_bin"
    info "Version      : $( "$fmt_bin" --version )"

    # Determine style: use .clang-format if present, otherwise LLVM
    local style_flag="--style=file"
    if [[ ! -f "$PROJECT_DIR/.clang-format" ]]; then
        style_flag="--style=LLVM"
        warn "No .clang-format found — using LLVM style as fallback"
    else
        info "Style file   : $PROJECT_DIR/.clang-format"
    fi

    # Collect .c and .h source files (exclude generated / third-party)
    local -a src_files=()
    while IFS= read -r -d '' f; do
        src_files+=("$f")
    done < <(find "$PROJECT_DIR/src" \
                  \( -name '*.c' -o -name '*.h' \) \
                  -not -path '*/CMakeFiles/*' \
                  -not -path '*/dep/iniparser/*' \
                  -print0 2>/dev/null)

    if [[ ${#src_files[@]} -eq 0 ]]; then
        warn "No .c/.h source files found under src/ or src-app/"
        return 0
    fi
    info "Source files : ${#src_files[@]} .c/.h files"

    local report_log="$LOG_DIR/run_clang-format_${TIMESTAMP}.log"
    info "Report       : $report_log"

    # --dry-run: do not write; --Werror: exit non-zero if reformatting needed
    local fmt_exit=0
    local -a bad_files=()
    set +e
    for f in "${src_files[@]}"; do
        "$fmt_bin" --dry-run --Werror $style_flag "$f" >> "$report_log" 2>&1
        if [[ $? -ne 0 ]]; then
            bad_files+=("$f")
        fi
    done
    set -e

    if [[ ${#bad_files[@]} -gt 0 ]]; then
        error "clang-format: ${#bad_files[@]} file(s) need reformatting — see $report_log"
        for f in "${bad_files[@]}"; do
            warn "  needs formatting: ${f#${PROJECT_DIR}/}"
        done
        return 1
    fi

    success "clang-format: all files are properly formatted"
    info "Full output in: $report_log"
    return 0
}

# ---------------------------------------------------------------------------
# clang-tidy: static analysis over all project .c files
# ---------------------------------------------------------------------------
# Checks: broad bugprone/cert/clang-analyzer/misc/performance/portability set.
# Noisy cert random/err checks are suppressed to reduce false-positive churn on
# legacy C code.  Header filter restricts diagnostics to project sources only.
# ---------------------------------------------------------------------------
TIDY_CHECKS="bugprone-*,cert-*,clang-analyzer-*,misc-*,performance-*,portability-*"
TIDY_CHECKS="${TIDY_CHECKS},-cert-err34-c,-cert-msc50-c,-cert-msc51-c,-cert-msc30-c"
TIDY_HEADER_FILTER="^${PROJECT_DIR}/src"

# Resolve clang-tidy binary: prefer PATH, then xcrun, then known Homebrew LLVM paths.
find_clang_tidy() {
    local ct
    ct="$(command -v clang-tidy 2>/dev/null)" && { echo "$ct"; return 0; }
    ct="$(xcrun -f clang-tidy 2>/dev/null)"   && { echo "$ct"; return 0; }
    for brew_path in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
        [[ -x "$brew_path/clang-tidy" ]] && { echo "$brew_path/clang-tidy"; return 0; }
    done
    return 1
}

run_clang_tidy() {
    header "clang-tidy static analysis"

    # ---- locate binary ----
    local tidy_bin
    if ! tidy_bin="$(find_clang_tidy)"; then
        warn "clang-tidy not found — skipping."
        warn "Install via: brew install llvm   (then add /opt/homebrew/opt/llvm/bin to PATH)"
        return 0   # not a hard failure; tool simply isn't installed
    fi
    info "clang-tidy : $tidy_bin"
    info "Version    : $( "$tidy_bin" --version | head -1 )"

    # ---- ensure compile_commands.json ----
    local comp_db_dir="$PROJECT_DIR/build-cmake/debug"
    local comp_db="$comp_db_dir/compile_commands.json"

    if [[ ! -f "$comp_db" ]]; then
        if $SKIP_BUILD; then
            error "compile_commands.json not found at $comp_db and --no-build was set."
            error "Run without -B first, or run the 'Configure Debug' task."
            return 1
        fi
        info "compile_commands.json not found — generating via cmake configure..."
        local tidy_cfg_log="$LOG_DIR/build_clang-tidy_${TIMESTAMP}.log"
        mkdir -p "$comp_db_dir"
        cmake -S "$PROJECT_DIR" -B "$comp_db_dir" \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
            -DENABLE_RUNTIME_DEBUG=ON \
            -DDEBUG_LEVEL=all \
            -DENABLE_PCAP=OFF \
            -DENABLE_SNMP=OFF \
            -DENABLE_STATISTICS=ON \
            -DENABLE_DAEMON=OFF \
            -DBUILD_WITH_SWCLOCK=ON \
            > "$tidy_cfg_log" 2>&1
        info "cmake configure log: $tidy_cfg_log"
    fi

    info "compile_commands.json: $comp_db"

    # ---- collect source files ----
    local -a src_files=()
    while IFS= read -r -d '' f; do
        src_files+=("$f")
    done < <(find "$PROJECT_DIR/src" \
                  -name '*.c' -not -path '*/CMakeFiles/*' -print0 2>/dev/null)

    if [[ ${#src_files[@]} -eq 0 ]]; then
        warn "No .c source files found under src/"
        return 0
    fi
    info "Source files: ${#src_files[@]} .c files"

    # ---- run clang-tidy ----
    local report_log="$LOG_DIR/run_clang-tidy_${TIMESTAMP}.log"
    info "Report     : $report_log"
    info "Checks     : $TIDY_CHECKS"

    # On macOS, clang-tidy from Homebrew LLVM does not know the Xcode SDK path
    # automatically, so system headers can't be found.  Detect and pass it.
    # Also add _DARWIN_C_SOURCE to enable POSIX/BSD extensions that Apple's
    # clang activates by default (needed for timer_create, itimerspec, etc.).
    local -a extra_args=()
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local sdk_path
        sdk_path="$(xcrun --show-sdk-path 2>/dev/null)" && [[ -n "$sdk_path" ]] && \
            extra_args+=(--extra-arg="--sysroot=${sdk_path}")
        extra_args+=(--extra-arg="-D_DARWIN_C_SOURCE")
        [[ ${#extra_args[@]} -gt 0 ]] && info "Sysroot    : $sdk_path"
    fi

    local tidy_exit=0
    set +e
    "$tidy_bin" \
        -p "$comp_db_dir" \
        "--checks=${TIDY_CHECKS}" \
        "--header-filter=${TIDY_HEADER_FILTER}" \
        --format-style=none \
        "${extra_args[@]}" \
        "${src_files[@]}" \
        > "$report_log" 2>&1
    tidy_exit=$?
    set -e

    # ---- parse results ----
    # Clang-tidy diagnostic lines look like:
    #   /path/to/file.c:line:col: (error|warning): message [check-name]
    # Context lines (source excerpts, ^ pointers) do NOT match this form.
    # Distinguish between:
    #   clang-diagnostic-* : compilation-context errors (header/macro issues) -> warn only
    #   everything else     : actual tidy check violations                     -> fail
    local diag_errors tidy_errors warning_count
    diag_errors=$(grep -cE '^[^:]+\.[ch]:[0-9]+:[0-9]+: error:.*\[clang-diagnostic-' \
        "$report_log" 2>/dev/null || true)
    tidy_errors=$(grep -E '^[^:]+\.[ch]:[0-9]+:[0-9]+: error:' "$report_log" 2>/dev/null \
        | grep -cvE '\[clang-diagnostic-' || true)
    warning_count=$(grep -cE '^[^:]+\.[ch]:[0-9]+:[0-9]+: warning:' \
        "$report_log" 2>/dev/null || true)

    info "Diagnostics: ${tidy_errors} tidy error(s), ${diag_errors} parse error(s), ${warning_count} warning(s)"

    if [[ $diag_errors -gt 0 ]]; then
        warn "clang-tidy: ${diag_errors} compile-context error(s) (clang-diagnostic-*) — check sysroot/macros"
        grep -E '^[^:]+\.[ch]:[0-9]+:[0-9]+: error:.*\[clang-diagnostic-' \
            "$report_log" | head -5 || true
    fi

    if [[ $tidy_errors -gt 0 ]]; then
        error "clang-tidy: ${tidy_errors} tidy check error(s) found — see $report_log"
        grep -E '^[^:]+\.[ch]:[0-9]+:[0-9]+: error:' "$report_log" \
            | grep -vE '\[clang-diagnostic-' | head -20 || true
        return 1
    fi

    if [[ $warning_count -gt 0 ]]; then
        warn "clang-tidy: ${warning_count} warning(s) — see $report_log"
        grep -E '^[^:]+\.[ch]:[0-9]+:[0-9]+: warning:' "$report_log" \
            | grep -vE '\[clang-diagnostic-' | head -20 || true
        # Warnings are reported but do not fail the check.
    fi

    if [[ $tidy_exit -ne 0 && $tidy_errors -eq 0 ]]; then
        warn "clang-tidy exited with code $tidy_exit (may indicate an internal tool warning)"
    fi

    success "clang-tidy: no tidy check errors detected"
    info "Full output in: $report_log"
    return 0
}

# ---------------------------------------------------------------------------
# Sanitizer-specific compile flags
# On macOS, clang is always the compiler; -fsanitize=address / thread already
# imply the necessary runtime linkage.  On Linux, also add -fno-omit-frame-pointer
# for better stack traces.
# ---------------------------------------------------------------------------
ASAN_FLAGS="-fsanitize=address   -fno-omit-frame-pointer -g"
TSAN_FLAGS="-fsanitize=thread    -fno-omit-frame-pointer -g"
UBSAN_FLAGS="-fsanitize=undefined -fno-omit-frame-pointer -g -fno-sanitize-recover=undefined"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
header "ptpd Sanitizer Runner"
info "Project : $PROJECT_DIR"
info "Logs    : $LOG_DIR"
[[ -n "$CONFIG_FILE" ]] && info "Config  : $CONFIG_FILE"
[[ -n "$INTERFACE"   ]] && info "Iface   : $INTERFACE"

OVERALL_PASS=true

# ---- ASAN ------------------------------------------------------------------
if $RUN_ASAN; then
    if ! $SKIP_BUILD; then
        build_sanitizer "asan" "$ASAN_FLAGS" || { OVERALL_PASS=false; }
    fi
    run_sanitizer "asan" || { OVERALL_PASS=false; }
fi

# ---- TSAN ------------------------------------------------------------------
if $RUN_TSAN; then
    if ! $SKIP_BUILD; then
        build_sanitizer "tsan" "$TSAN_FLAGS" || { OVERALL_PASS=false; }
    fi
    run_sanitizer "tsan" || { OVERALL_PASS=false; }
fi

# ---- UBSAN -----------------------------------------------------------------
if $RUN_UBSAN; then
    if ! $SKIP_BUILD; then
        build_sanitizer "ubsan" "$UBSAN_FLAGS" || { OVERALL_PASS=false; }
    fi
    run_sanitizer "ubsan" || { OVERALL_PASS=false; }
fi

# ---- clang-tidy ------------------------------------------------------------
if $RUN_TIDY; then
    run_clang_tidy || { OVERALL_PASS=false; }
fi

# ---- clang-format ----------------------------------------------------------
if $RUN_FORMAT; then
    run_clang_format || { OVERALL_PASS=false; }
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary"
if $OVERALL_PASS; then
    success "All sanitizer checks passed."
    exit 0
else
    error "One or more sanitizer checks failed.  See $LOG_DIR for details."
    exit 1
fi
