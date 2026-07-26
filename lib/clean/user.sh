#!/bin/bash
# MacWash - User-level log and temp cleanup.

set -euo pipefail

clean_user_logs() {
    local log_dirs=(
        "$HOME/Library/Logs"
        "$HOME/Library/Application Support/CrashReporter"
    )
    for dir in "${log_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' f; do
            should_protect_path "$f" && continue
            is_path_whitelisted "$f"  && continue
            local sz; sz=$(get_path_size_kb "$f" 2>/dev/null || echo 0)
            safe_remove "$f" true && {
                total_size_cleaned=$((total_size_cleaned + sz))
                note_activity
            }
        done < <(find "$dir" -maxdepth 4 -type f \
            \( -name "*.log" -o -name "*.crash" -o -name "*.ips" \) \
            -mtime "+${MACWASH_LOG_AGE_DAYS}" -print0 2>/dev/null || true)
    done

    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} User logs cleaned"
    note_activity
}

clean_crash_reports() {
    local crash_dir="$HOME/Library/Logs/DiagnosticReports"
    [[ -d "$crash_dir" ]] || return 0

    local count=0
    while IFS= read -r -d '' f; do
        safe_remove "$f" true && count=$((count+1))
    done < <(find "$crash_dir" -maxdepth 1 -type f \
        -mtime "+${MACWASH_CRASH_REPORT_AGE_DAYS}" -print0 2>/dev/null || true)

    [[ "$count" -gt 0 ]] && {
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Crash reports: $count removed"
        note_activity
    }
}

clean_temp_files() {
    local tmp_dirs=("$HOME/.Trash" "/private/tmp" "/private/var/tmp")
    for dir in "${tmp_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' f; do
            [[ -f "$f" ]] || continue
            safe_remove "$f" true
        done < <(find "$dir" -maxdepth 1 -type f \
            -mtime "+${MACWASH_TEMP_FILE_AGE_DAYS}" -print0 2>/dev/null || true)
    done
    note_activity
}
