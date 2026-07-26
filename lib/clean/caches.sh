#!/bin/bash
# MacWash - User cache cleanup module.

set -euo pipefail

clean_user_caches() {
    local cache_root="$HOME/Library/Caches"
    [[ -d "$cache_root" ]] || return 0

    start_inline_spinner "Scanning user caches..."

    local cleaned=0 total_kb=0
    # Scan top-level cache dirs older than retention window
    while IFS= read -r -d '' dir; do
        [[ -d "$dir" ]] || continue
        should_protect_path "$dir" && continue
        is_path_whitelisted "$dir" && continue

        local name; name=$(basename "$dir")
        # Skip Apple critical caches
        case "$name" in
            com.apple.finder | com.apple.spotlight* | com.apple.Spotlight* \
            | CloudKit* | com.apple.FontRegistry* | com.apple.homed \
            | com.apple.containermanagerd | com.apple.HomeKit)
                continue ;;
        esac

        local size_kb; size_kb=$(get_path_size_kb "$dir" 2>/dev/null || echo 0)
        [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0
        [[ "$size_kb" -lt 1024 ]] && continue   # skip < 1MB

        stop_inline_spinner
        if safe_remove "$dir" true "$size_kb"; then
            total_kb=$((total_kb + size_kb))
            cleaned=$((cleaned + 1))
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Cache: $name · $(colorize_size "$(bytes_to_human_kb "$size_kb")")"
            note_activity
        fi
        start_inline_spinner "Scanning user caches..."
    done < <(find "$cache_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    stop_inline_spinner

    # Trash / saved state
    local trash_dir="$HOME/.Trash"
    if [[ -d "$trash_dir" ]]; then
        local trash_kb; trash_kb=$(get_path_size_kb "$trash_dir" 2>/dev/null || echo 0)
        [[ "$trash_kb" =~ ^[0-9]+$ ]] || trash_kb=0
        if [[ "$trash_kb" -gt 0 ]]; then
            if safe_clean "$trash_dir"/* "Trash"; then
                total_kb=$((total_kb + trash_kb))
            fi
        fi
    fi

    files_cleaned=$((files_cleaned + cleaned))
    total_size_cleaned=$((total_size_cleaned + total_kb))
}

clean_browser_caches() {
    local -a browser_caches=(
        "$HOME/Library/Caches/Google/Chrome"
        "$HOME/Library/Caches/com.google.Chrome"
        "$HOME/Library/Caches/org.mozilla.firefox"
        "$HOME/Library/Caches/com.apple.Safari"
        "$HOME/Library/Caches/com.microsoft.edgemac"
        "$HOME/Library/Caches/com.operasoftware.Opera"
        "$HOME/Library/Caches/com.brave.Browser"
    )

    local total_kb=0
    for cache in "${browser_caches[@]}"; do
        [[ -d "$cache" ]] || continue
        should_protect_path "$cache" && continue
        is_path_whitelisted "$cache" && continue

        local size_kb; size_kb=$(get_path_size_kb "$cache" 2>/dev/null || echo 0)
        [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0
        [[ "$size_kb" -lt 512 ]] && continue

        local name; name=$(basename "$cache")
        if safe_remove "$cache" true "$size_kb"; then
            total_kb=$((total_kb + size_kb))
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Browser cache: $name · $(colorize_size "$(bytes_to_human_kb "$size_kb")")"
            note_activity
        fi
    done

    files_cleaned=$((files_cleaned + 1))
    total_size_cleaned=$((total_size_cleaned + total_kb))
}

clean_app_caches() {
    # Spotify, Dropbox, Slack, Teams, Zoom — known safe rebuildable caches
    local -a targets=(
        "$HOME/Library/Caches/com.spotify.client"
        "$HOME/Library/Caches/com.dropbox.Dropbox"
        "$HOME/Library/Caches/com.tinyspeck.slackmacgap"
        "$HOME/Library/Caches/com.microsoft.teams"
        "$HOME/Library/Caches/us.zoom.xos"
        "$HOME/Library/Caches/com.figma.Desktop"
        "$HOME/Library/Caches/com.electron.app"
        "$HOME/Library/Caches/Sublime Text"
        "$HOME/Library/Caches/JetBrains"
    )

    for t in "${targets[@]}"; do
        [[ -d "$t" ]] || continue
        should_protect_path "$t" && continue
        is_path_whitelisted "$t" && continue
        local sz; sz=$(get_path_size_kb "$t" 2>/dev/null || echo 0)
        [[ "$sz" -lt 512 ]] && continue
        safe_clean "$t" "$(basename "$t") cache"
    done
}
