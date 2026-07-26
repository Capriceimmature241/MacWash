#!/bin/bash
# MacWash - Base definitions, constants, and utilities.
# Loaded first by every module.

set -euo pipefail

[[ -n "${MACWASH_BASE_LOADED:-}" ]] && return 0
readonly MACWASH_BASE_LOADED=1

: "${DRY_RUN:=false}"

# ── Colors (honor NO_COLOR) ──────────────────────────────────────────────────
if [[ -n "${NO_COLOR:-}" ]]; then
    readonly ESC="" GREEN="" BLUE="" CYAN="" YELLOW="" PURPLE=""
    readonly CYAN_BOLD="" PURPLE_BOLD="" RED="" GRAY="" NC=""
else
    readonly ESC=$'\033'
    readonly GREEN="${ESC}[0;32m"
    readonly BLUE="${ESC}[1;34m"
    readonly CYAN="${ESC}[0;36m"
    readonly YELLOW="${ESC}[0;33m"
    readonly PURPLE="${ESC}[0;35m"
    readonly CYAN_BOLD="${ESC}[1;36m"
    readonly PURPLE_BOLD="${ESC}[1;35m"
    readonly RED="${ESC}[0;31m"
    readonly GRAY="${ESC}[0;90m"
    readonly NC="${ESC}[0m"
fi

# ── Icons ────────────────────────────────────────────────────────────────────
readonly ICON_SUCCESS="✓"
readonly ICON_ERROR="✗"
readonly ICON_WARNING="⚠"
readonly ICON_ARROW="▶"
readonly ICON_DRY_RUN="→"
readonly ICON_EMPTY="○"
readonly ICON_SOLID="●"
readonly ICON_LIST="•"
readonly ICON_SUBLIST="↳"
readonly ICON_ADMIN="⚙"
readonly ICON_INFO="ℹ"

# ── Global constants ─────────────────────────────────────────────────────────
readonly MACWASH_TEMP_FILE_AGE_DAYS=7
readonly MACWASH_LOG_AGE_DAYS=7
readonly MACWASH_CRASH_REPORT_AGE_DAYS=7
readonly MACWASH_SAVED_STATE_AGE_DAYS=30
readonly MACWASH_ORPHAN_AGE_DAYS=30
readonly MACWASH_MAX_PARALLEL_JOBS=12
readonly MACWASH_ONE_GIB_KB=$((1024 * 1024))

# ── BSD stat path ────────────────────────────────────────────────────────────
readonly STAT_BSD="/usr/bin/stat"

# ── Formatting helpers ────────────────────────────────────────────────────────
bytes_to_human() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || { echo "0B"; return; }
    if   ((bytes >= 1000000000)); then
        local s=$(( (bytes * 100 + 500000000) / 1000000000 ))
        printf "%d.%02dGB\n" $((s/100)) $((s%100))
    elif ((bytes >= 1000000)); then
        local s=$(( (bytes * 10 + 500000) / 1000000 ))
        printf "%d.%01dMB\n" $((s/10)) $((s%10))
    elif ((bytes >= 1000)); then
        printf "%dKB\n" $(( (bytes+500)/1000 ))
    else
        printf "%dB\n" "$bytes"
    fi
}

bytes_to_human_kb() { bytes_to_human "$(( ${1:-0} * 1024 ))"; }

colorize_size() {
    local s="$1"
    case "$s" in
        *GB) printf '%s%s%s' "$RED"    "$s" "$NC" ;;
        *MB) printf '%s%s%s' "$YELLOW" "$s" "$NC" ;;
        *KB) printf '%s%s%s' "$GREEN"  "$s" "$NC" ;;
        *)   printf '%s%s%s' "$GRAY"   "$s" "$NC" ;;
    esac
}

# ── Time helpers ─────────────────────────────────────────────────────────────
get_epoch_seconds() {
    local r; r=$(/bin/date +%s 2>/dev/null || echo "0")
    [[ "$r" =~ ^[0-9]+$ ]] && echo "$r" || echo "0"
}

get_file_mtime() {
    local f="$1"; [[ -z "$f" ]] && { echo "0"; return; }
    local r; r=$($STAT_BSD -f%m "$f" 2>/dev/null || echo "")
    [[ "$r" =~ ^[0-9]+$ ]] && echo "$r" || echo "0"
}

get_file_size() {
    local f="$1"
    local r; r=$($STAT_BSD -f%z "$f" 2>/dev/null || echo "0")
    echo "${r:-0}"
}

# ── System helpers ───────────────────────────────────────────────────────────
is_root_user()  { [[ "$(id -u)" == "0" ]]; }
detect_arch()   { [[ "$(uname -m)" == "arm64" ]] && echo "Apple Silicon" || echo "Intel"; }

get_free_space_kb() {
    local target="/"
    [[ -d "/System/Volumes/Data" ]] && target="/System/Volumes/Data"
    local kb; kb=$(df -Pk "$target" 2>/dev/null | awk 'NR==2{print $4}' || true)
    [[ "$kb" =~ ^[0-9]+$ ]] && echo "$kb" || return 1
}

get_optimal_parallel_jobs() {
    local type="${1:-default}"
    local cores; cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    case "$type" in
        io|scan) echo $((cores * 2)) ;;
        *)       echo $((cores + 2)) ;;
    esac
}

get_path_size_kb() {
    local path="$1"
    [[ -e "$path" ]] || { echo "0"; return; }
    local out; out=$(du -sk "$path" 2>/dev/null | awk '{print $1; exit}') || out="0"
    [[ "$out" =~ ^[0-9]+$ ]] && echo "$out" || echo "0"
}

# ── User context ──────────────────────────────────────────────────────────────
get_invoking_home() {
    [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]] && \
        dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' | head -1 && return
    echo "${HOME:-}"
}

ensure_user_dir() {
    local p="$1"; [[ -z "$p" ]] && return
    mkdir -p "$p" 2>/dev/null || true
}

ensure_user_file() {
    local p="$1"; [[ -z "$p" ]] && return
    ensure_user_dir "$(dirname "$p")"
    touch "$p" 2>/dev/null || true
}

# ── Temp file management ──────────────────────────────────────────────────────
declare -a MACWASH_TEMP_FILES=()
declare -a MACWASH_TEMP_DIRS=()

create_temp_file() {
    local t; t=$(mktemp "${TMPDIR:-/tmp}/macwash.XXXXXX") || return 1
    MACWASH_TEMP_FILES+=("$t"); echo "$t"
}

create_temp_dir() {
    local t; t=$(mktemp -d "${TMPDIR:-/tmp}/macwash.XXXXXX") || return 1
    MACWASH_TEMP_DIRS+=("$t"); echo "$t"
}

cleanup_temp_files() {
    local f
    [[ ${#MACWASH_TEMP_FILES[@]} -gt 0 ]] && for f in "${MACWASH_TEMP_FILES[@]}"; do
        [[ -f "$f" ]] && rm -f "$f" 2>/dev/null || true
    done
    [[ ${#MACWASH_TEMP_DIRS[@]} -gt 0 ]] && for f in "${MACWASH_TEMP_DIRS[@]}"; do
        [[ -d "$f" ]] && rm -rf "$f" 2>/dev/null || true # SAFE: mktemp dir registered for cleanup
    done
    MACWASH_TEMP_FILES=(); MACWASH_TEMP_DIRS=()
}

# ── Section tracking ─────────────────────────────────────────────────────────
TRACK_SECTION=0
SECTION_ACTIVITY=0

start_section() {
    TRACK_SECTION=1; SECTION_ACTIVITY=0
    echo ""; echo -e "${CYAN_BOLD}${ICON_ARROW} $1${NC}"
}

end_section() {
    if [[ "${TRACK_SECTION:-0}" == "1" && "${SECTION_ACTIVITY:-0}" == "0" ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Nothing to clean"
    fi
    TRACK_SECTION=0
}

note_activity() {
    [[ "${TRACK_SECTION:-0}" == "1" ]] && SECTION_ACTIVITY=1
}
