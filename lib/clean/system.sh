#!/bin/bash
# MacWash - System-level cleanup (requires sudo).

set -euo pipefail

clean_system_caches() {
    [[ "${SYSTEM_CLEAN:-false}" == "true" ]] || return 0
    start_inline_spinner "Cleaning system caches..."

    # /Library/Caches — safe stale files
    if sudo -n test -d "/Library/Caches" 2>/dev/null; then
        while IFS= read -r -d '' f; do
            should_protect_path "$f" && continue
            safe_sudo_remove "$f"
        done < <(sudo -n find "/Library/Caches" -maxdepth 4 -type f \
            \( -name "*.cache" -o -name "*.tmp" \) \
            -mtime "+${MACWASH_TEMP_FILE_AGE_DAYS}" -print0 2>/dev/null || true)
    fi

    stop_inline_spinner
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} System caches cleaned"
    note_activity
}

clean_system_logs() {
    [[ "${SYSTEM_CLEAN:-false}" == "true" ]] || return 0
    start_inline_spinner "Cleaning system logs..."

    local -a log_dirs=("/private/var/log" "/Library/Logs")
    for dir in "${log_dirs[@]}"; do
        sudo -n test -d "$dir" 2>/dev/null || continue
        while IFS= read -r -d '' f; do
            should_protect_path "$f" && continue
            safe_sudo_remove "$f"
        done < <(sudo -n find "$dir" -maxdepth 3 -type f \
            \( -name "*.log" -o -name "*.gz" -o -name "*.asl" \) \
            -mtime "+${MACWASH_LOG_AGE_DAYS}" -print0 2>/dev/null || true)
    done

    stop_inline_spinner
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} System logs cleaned"
    note_activity
}
