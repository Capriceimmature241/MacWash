#!/bin/bash
# MacWash - Optimization task implementations.

set -euo pipefail

opt_msg() {
    local msg="$1"
    if [[ "${MACWASH_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $msg"
    else
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $msg"
    fi
}

opt_announce() {
    echo -e "\n  ${BLUE}${ICON_ARROW}${NC} $1"
}

opt_flush_dns() {
    if [[ "${MACWASH_OPT_SUDO:-false}" != "true" ]]; then
        echo -e "  ${GRAY}skipped (admin access not granted)${NC}"; return 0
    fi
    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        sudo dscacheutil -flushcache 2>/dev/null || true
        sudo killall -HUP mDNSResponder 2>/dev/null || true
    fi
    opt_msg "DNS cache flushed"
    opt_msg "mDNSResponder restarted"
}

opt_quicklook_refresh() {
    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        qlmanage -r cache >/dev/null 2>&1 || true
        qlmanage -r >/dev/null 2>&1 || true
        safe_remove "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache" true
        safe_remove "$HOME/Library/Caches/com.apple.iconservices.store" true
        safe_remove "$HOME/Library/Caches/com.apple.iconservices" true
    fi
    opt_msg "QuickLook thumbnails refreshed"
    opt_msg "Icon services cache rebuilt"
}

opt_launch_services() {
    local lsreg
    lsreg=$(find /System/Library/Frameworks/CoreServices.framework \
        -name "lsregister" -type f 2>/dev/null | head -1 || true)
    [[ -z "$lsreg" ]] && { echo -e "  ${GRAY}lsregister not found${NC}"; return 0; }

    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        start_inline_spinner "Rebuilding LaunchServices..."
        "$lsreg" -gc >/dev/null 2>&1 || true
        "$lsreg" -r -f -domain local -domain user -domain system >/dev/null 2>&1 || true
        stop_inline_spinner
    fi
    opt_msg "LaunchServices database rebuilt"
    opt_msg "File associations refreshed"
}

opt_spotlight_check() {
    local status; status=$(mdutil -s / 2>/dev/null || echo "")
    if echo "$status" | grep -qi "Indexing disabled"; then
        echo -e "  ${GRAY}${ICON_EMPTY}${NC} Spotlight disabled"
        return 0
    fi
    opt_msg "Spotlight index verified"
}

opt_saved_states() {
    local state_dir="$HOME/Library/Saved Application State"
    [[ -d "$state_dir" ]] || return 0
    local count=0
    while IFS= read -r -d '' d; do
        should_protect_path "$d" && continue
        safe_remove "$d" true && count=$((count+1))
    done < <(find "$state_dir" -maxdepth 1 -type d -name "*.savedState" \
        -mtime "+${MACWASH_SAVED_STATE_AGE_DAYS}" -print0 2>/dev/null || true)
    [[ "$count" -gt 0 ]] && opt_msg "Removed $count old app saved states" \
        || opt_msg "Saved states already clean"
}

opt_sqlite_vacuum() {
    command -v sqlite3 >/dev/null 2>&1 || {
        echo -e "  ${GRAY}sqlite3 unavailable${NC}"; return 0
    }
    # Check apps aren't open
    local busy=()
    for app in Mail Safari Messages; do
        pgrep -x "$app" >/dev/null 2>&1 && busy+=("$app")
    done
    [[ ${#busy[@]} -gt 0 ]] && {
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Close before vacuuming: ${busy[*]}"
        return 0
    }

    local vacuumed=0
    local -a dbs=(
        "$HOME/Library/Messages/chat.db"
        "$HOME/Library/Safari/History.db"
        "$HOME/Library/Safari/TopSites.db"
        "$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
    )
    for db in "${dbs[@]}"; do
        [[ -f "$db" ]] || continue
        should_protect_path "$db" && continue
        if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
            sqlite3 "$db" "VACUUM;" 2>/dev/null && vacuumed=$((vacuumed+1)) || true
        else
            vacuumed=$((vacuumed+1))
        fi
    done
    opt_msg "Vacuumed $vacuumed SQLite databases"
}

opt_quarantine_db() {
    command -v sqlite3 >/dev/null 2>&1 || return 0
    local qdb="$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
    [[ -f "$qdb" ]] || { opt_msg "Quarantine DB clean"; return 0; }
    should_protect_path "$qdb" && return 0
    local count; count=$(sqlite3 "$qdb" "SELECT COUNT(*) FROM LSQuarantineEvent;" 2>/dev/null || echo 0)
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if [[ "$count" -gt 0 && "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        sqlite3 "$qdb" "DELETE FROM LSQuarantineEvent; VACUUM;" 2>/dev/null || true
    fi
    opt_msg "Quarantine history cleared ($count entries)"
}
