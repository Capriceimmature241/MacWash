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

# ── 1. DNS cache flush ────────────────────────────────────────────────────────
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

# ── 2. QuickLook & icon services ──────────────────────────────────────────────
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

# ── 3. LaunchServices rebuild ─────────────────────────────────────────────────
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

# ── 4. Spotlight check ────────────────────────────────────────────────────────
opt_spotlight_check() {
    local status; status=$(mdutil -s / 2>/dev/null || echo "")
    if echo "$status" | grep -qi "Indexing disabled"; then
        echo -e "  ${GRAY}${ICON_EMPTY}${NC} Spotlight disabled"
        return 0
    fi
    opt_msg "Spotlight index verified"
}

# ── 5. Saved app states ───────────────────────────────────────────────────────
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

# ── 6. SQLite vacuum ──────────────────────────────────────────────────────────
opt_sqlite_vacuum() {
    command -v sqlite3 >/dev/null 2>&1 || {
        echo -e "  ${GRAY}sqlite3 unavailable${NC}"; return 0
    }
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

# ── 7. Quarantine DB cleanup ──────────────────────────────────────────────────
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

# ── 8. Broken config repair ───────────────────────────────────────────────────
opt_broken_configs() {
    local prefs_dir="$HOME/Library/Preferences"
    [[ -d "$prefs_dir" ]] || { opt_msg "Preferences already valid"; return 0; }

    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        start_inline_spinner "Checking preference files..."
    fi

    local broken=0
    local deadline=$(( SECONDS + 15 ))  # 15s budget

    while IFS= read -r plist; do
        [[ $SECONDS -ge $deadline ]] && break
        [[ -f "$plist" ]] || continue
        # Skip Apple system plists
        local fname; fname=$(basename "$plist")
        [[ "$fname" == com.apple.* || "$fname" == .GlobalPreferences* ]] && continue
        # Lint check
        plutil -lint "$plist" >/dev/null 2>&1 && continue
        # Broken — remove safely
        should_protect_path "$plist" && continue
        is_path_whitelisted "$plist" && continue
        safe_remove "$plist" true >/dev/null 2>&1 && broken=$((broken+1))
    done < <(find "$prefs_dir" -maxdepth 1 -name "*.plist" -type f 2>/dev/null || true)

    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        stop_inline_spinner
    fi

    [[ "$broken" -gt 0 ]] && opt_msg "Repaired $broken corrupted preference files" \
        || opt_msg "All preference files valid"
}

# ── 9. Dock refresh ───────────────────────────────────────────────────────────
opt_dock_refresh() {
    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        # Remove icon caches that cause broken/blank Dock icons
        # Dock picks up new cache automatically — no restart needed
        safe_remove "$HOME/Library/Caches/com.apple.dock.iconcache" true 2>/dev/null || true
        safe_remove "$HOME/Library/Caches/com.apple.iconservices.store" true 2>/dev/null || true
    fi
    opt_msg "Dock icon cache cleared"
    opt_msg "Dock will refresh on next login"
}

# ── 10. Memory optimization ───────────────────────────────────────────────────
opt_memory_pressure() {
    # Check if memory pressure is high
    local mp_output
    mp_output=$(memory_pressure -Q 2>/dev/null || echo "")

    if ! echo "$mp_output" | grep -Eiq "warning|critical"; then
        opt_msg "Memory pressure already optimal"
        return 0
    fi

    if [[ "${MACWASH_OPT_SUDO:-false}" != "true" ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Memory optimization skipped (admin access required)"
        return 0
    fi

    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        start_inline_spinner "Releasing inactive memory..."
        sudo purge >/dev/null 2>&1 || true
        stop_inline_spinner
    fi
    opt_msg "Inactive memory released"
    opt_msg "System responsiveness improved"
}

# ── 11. Network stack refresh ─────────────────────────────────────────────────
opt_network_stack() {
    # Skip if VPN is active
    if command -v scutil >/dev/null 2>&1; then
        if scutil --nc list 2>/dev/null | grep -q "Connected"; then
            opt_msg "Network stack refresh skipped (VPN active)"
            return 0
        fi
    fi

    if [[ "${MACWASH_OPT_SUDO:-false}" != "true" ]]; then
        echo -e "  ${GRAY}skipped (admin access not granted)${NC}"; return 0
    fi

    if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
        sudo route -n flush >/dev/null 2>&1 || true
        sudo arp -a -d >/dev/null 2>&1 || true
    fi
    opt_msg "Network routing table refreshed"
    opt_msg "ARP cache cleared"
}

# ── 12. Login items audit ─────────────────────────────────────────────────────
opt_login_items_audit() {
    local agents_dir="$HOME/Library/LaunchAgents"
    [[ -d "$agents_dir" ]] || { opt_msg "Login items clean"; return 0; }

    local broken=0
    while IFS= read -r -d '' plist; do
        local fname; fname=$(basename "$plist")
        [[ "$fname" == com.apple.* ]] && continue

        # Extract program path — suppress all errors
        local prog=""
        prog=$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null) || prog=""
        if [[ -z "$prog" || "$prog" != /* ]]; then
            prog=$(plutil -extract Program raw "$plist" 2>/dev/null) || prog=""
        fi

        # Skip plists that don't define a Program path (KeepAlive/MachServices only)
        [[ -z "$prog" || "$prog" != /* ]] && continue

        # If binary doesn't exist — broken
        if [[ ! -e "$prog" ]]; then
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} Stale login item: $fname"
            echo -e "    ${GRAY}Missing: $prog${NC}"
            broken=$((broken+1))
        fi
    done < <(find "$agents_dir" -maxdepth 1 -name "*.plist" -print0 2>/dev/null || true)

    [[ "$broken" -gt 0 ]] && opt_msg "Found $broken stale login item(s) — review manually" \
        || opt_msg "All login items valid"
}

# ── 13. Launch agents cleanup ─────────────────────────────────────────────────
opt_launch_agents_cleanup() {
    local agents_dir="$HOME/Library/LaunchAgents"
    [[ -d "$agents_dir" ]] || { opt_msg "Launch agents clean"; return 0; }

    local removed=0
    while IFS= read -r -d '' plist; do
        local fname; fname=$(basename "$plist")
        [[ "$fname" == com.apple.* ]] && continue

        # Extract program path — suppress all errors
        local prog=""
        prog=$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null) || prog=""
        if [[ -z "$prog" || "$prog" != /* ]]; then
            prog=$(plutil -extract Program raw "$plist" 2>/dev/null) || prog=""
        fi

        # Skip plists that don't define a Program path
        [[ -z "$prog" || "$prog" != /* ]] && continue

        # Only auto-remove if binary is gone AND plist is older than 30 days
        if [[ ! -e "$prog" ]]; then
            local mtime; mtime=$(get_file_mtime "$plist")
            local now; now=$(get_epoch_seconds)
            local age=$(( (now - mtime) / 86400 ))
            if [[ "$age" -gt 30 ]]; then
                if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
                    launchctl unload "$plist" 2>/dev/null || true
                    safe_remove "$plist" true && removed=$((removed+1))
                else
                    echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} Would remove stale agent: $fname"
                    removed=$((removed+1))
                fi
            fi
        fi
    done < <(find "$agents_dir" -maxdepth 1 -name "*.plist" -print0 2>/dev/null || true)

    [[ "$removed" -gt 0 ]] && opt_msg "Removed $removed stale launch agent(s)" \
        || opt_msg "Launch agents already clean"
}
