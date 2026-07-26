#!/bin/bash
# MacWash - Uninstall execution: removes app bundle and known leftovers.

set -euo pipefail

_macwash_leftover_paths() {
    local bundle_id="$1" app_name="$2"
    local -a paths=()
    local lc_name; lc_name=$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]')
    local nospace; nospace="${lc_name// /}"

    # Preference and Application Support directories
    local -a search_roots=(
        "$HOME/Library/Application Support"
        "$HOME/Library/Preferences"
        "$HOME/Library/Caches"
        "$HOME/Library/Logs"
        "$HOME/Library/Cookies"
        "$HOME/Library/HTTPStorages"
        "$HOME/Library/WebKit"
        "$HOME/Library/Saved Application State"
        "/Library/Application Support"
        "/Library/Preferences"
    )

    # 1. Bundle-ID exact match (most reliable)
    if [[ "$bundle_id" != "unknown" ]]; then
        local root
        for root in "${search_roots[@]}"; do
            [[ -d "$root" ]] || continue
            while IFS= read -r -d '' candidate; do
                paths+=("$candidate")
            done < <(find "$root" -mindepth 1 -maxdepth 2 \
                \( -name "$bundle_id" -o -name "$bundle_id.*" -o -name "*.$bundle_id" \) \
                -print0 2>/dev/null || true)
        done
        # Container
        [[ -d "$HOME/Library/Containers/$bundle_id" ]] && \
            paths+=("$HOME/Library/Containers/$bundle_id")
        [[ -d "$HOME/Library/Group Containers/$bundle_id" ]] && \
            paths+=("$HOME/Library/Group Containers/$bundle_id")
    fi

    # 2. App-name match (loose fallback)
    [[ ${#app_name} -ge 5 ]] && {
        local root
        for root in "${search_roots[@]}"; do
            [[ -d "$root" ]] || continue
            while IFS= read -r -d '' candidate; do
                local base; base=$(basename "$candidate" | tr '[:upper:]' '[:lower:]')
                [[ "$base" == "$lc_name" || "$base" == "$nospace" || \
                   "$base" == *"$lc_name"* ]] && paths+=("$candidate")
            done < <(find "$root" -mindepth 1 -maxdepth 1 -print0 2>/dev/null || true)
        done
    }

    # Deduplicate
    local -a unique=()
    local seen p
    declare -A seen=()
    for p in "${paths[@]}"; do
        [[ -z "${seen[$p]+x}" ]] && { unique+=("$p"); seen[$p]=1; }
    done
    [[ ${#unique[@]} -gt 0 ]] && printf '%s\n' "${unique[@]}"
}

uninstall_app() {
    local app_path="$1" app_name="$2" bundle_id="${3:-unknown}"

    echo -e "\n  ${CYAN}${ICON_ARROW}${NC} Removing: ${CYAN_BOLD}$app_name${NC}"

    # Remove the .app bundle
    local app_size_kb; app_size_kb=$(get_path_size_kb "$app_path" 2>/dev/null || echo 0)
    if [[ "${MACWASH_DRY_RUN:-0}" == "1" ]]; then
        echo -e "    ${YELLOW}${ICON_DRY_RUN}${NC} Would remove: $app_path  ($(bytes_to_human_kb "$app_size_kb"))"
    else
        if safe_remove "$app_path" false; then
            echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Removed application bundle ($(bytes_to_human_kb "$app_size_kb"))"
            log_operation "uninstall" "REMOVED" "$app_path" "$(bytes_to_human_kb "$app_size_kb")"
        else
            echo -e "    ${RED}${ICON_ERROR}${NC} Failed to remove: $app_path"
            return 1
        fi
    fi

    # Find and remove leftovers
    local leftover_count=0 leftover_kb=0
    while IFS= read -r leftover; do
        [[ -e "$leftover" ]] || continue
        should_protect_path "$leftover" && continue
        local sz; sz=$(get_path_size_kb "$leftover" 2>/dev/null || echo 0)
        [[ "$sz" =~ ^[0-9]+$ ]] || sz=0
        if [[ "${MACWASH_DRY_RUN:-0}" == "1" ]]; then
            echo -e "    ${YELLOW}${ICON_DRY_RUN}${NC} Would remove leftover: $leftover"
        else
            if safe_remove "$leftover" true; then
                leftover_count=$((leftover_count + 1))
                leftover_kb=$((leftover_kb + sz))
                log_operation "uninstall" "REMOVED" "$leftover" "leftover"
            fi
        fi
    done < <(_macwash_leftover_paths "$bundle_id" "$app_name")

    if [[ "$leftover_count" -gt 0 ]]; then
        echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Cleaned $leftover_count leftover(s) ($(bytes_to_human_kb "$leftover_kb"))"
    fi

    # Launch agents
    local -a agent_dirs=("$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons")
    for adir in "${agent_dirs[@]}"; do
        [[ -d "$adir" ]] || continue
        while IFS= read -r -d '' plist; do
            [[ "$bundle_id" == "unknown" ]] && continue
            local prog; prog=$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null || echo "")
            [[ "$prog" == *"$bundle_id"* || "$prog" == *"$app_path"* ]] || continue
            if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
                launchctl unload "$plist" 2>/dev/null || true
                safe_remove "$plist" true
                echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Removed launch agent: $(basename "$plist")"
            else
                echo -e "    ${YELLOW}${ICON_DRY_RUN}${NC} Would remove launch agent: $(basename "$plist")"
            fi
        done < <(find "$adir" -maxdepth 1 -name "*.plist" -print0 2>/dev/null || true)
    done
}
