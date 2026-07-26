#!/bin/bash
# MacWash - Operation logging.

set -euo pipefail
[[ -n "${MACWASH_LOG_LOADED:-}" ]] && return 0
readonly MACWASH_LOG_LOADED=1

_PURGE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MACWASH_BASE_LOADED:-}" ]] && source "$_PURGE_CORE_DIR/base.sh"

readonly MACWASH_OPS_LOG="${HOME}/Library/Logs/macwash/operations.log"

oplog_enabled() {
    [[ "${PURGE_NO_OPLOG:-0}" != "1" ]]
}

log_operation() {
    oplog_enabled || return 0
    local cmd="$1" action="$2" path="$3" detail="${4:-}"
    ensure_user_file "$MACWASH_OPS_LOG"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    printf '[%s] [%s] %s %s  %s\n' "$ts" "$cmd" "$action" "$path" "$detail" \
        >> "$MACWASH_OPS_LOG" 2>/dev/null || true
}

log_operation_session_start() {
    oplog_enabled || return 0
    local cmd="$1"
    ensure_user_file "$MACWASH_OPS_LOG"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    printf '# ========== %s session started at %s ==========\n' "$cmd" "$ts" \
        >> "$MACWASH_OPS_LOG" 2>/dev/null || true
}

log_operation_session_end() {
    oplog_enabled || return 0
    local cmd="$1" count="${2:-0}" size="${3:-0B}"
    ensure_user_file "$MACWASH_OPS_LOG"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    printf '# ========== %s session ended at %s, %s items, %s ==========\n' \
        "$cmd" "$ts" "$count" "$size" >> "$MACWASH_OPS_LOG" 2>/dev/null || true
}

debug_log() {
    [[ "${MACWASH_DEBUG:-0}" == "1" ]] || return 0
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "?")
    echo "[$ts] DEBUG: $*" >&2
}
