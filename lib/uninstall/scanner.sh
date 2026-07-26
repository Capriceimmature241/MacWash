#!/bin/bash
# MacWash - App scanner for uninstall command.

set -euo pipefail

_purge_app_dirs() {
    local -a dirs=("/Applications" "$HOME/Applications")
    local vol
    for vol in /Volumes/*/Applications; do
        [[ -d "$vol" ]] || continue
        [[ "$vol" -ef "/Applications" ]] && continue
        dirs+=("$vol")
    done
    printf '%s\n' "${dirs[@]}"
}

_purge_resolve_bundle_id() {
    local plist="$1/Contents/Info.plist"
    [[ -f "$plist" ]] || { echo "unknown"; return; }
    local bid; bid=$(plutil -extract CFBundleIdentifier raw "$plist" 2>/dev/null || echo "")
    [[ -n "$bid" && "$bid" != "(null)" ]] && echo "$bid" || echo "unknown"
}

_purge_resolve_display_name() {
    local app_path="$1" fallback="$2"
    local plist="$app_path/Contents/Info.plist"
    [[ -f "$plist" ]] || { echo "$fallback"; return; }
    local n
    n=$(mdls -name kMDItemDisplayName -raw "$app_path" 2>/dev/null || echo "")
    [[ -n "$n" && "$n" != "(null)" && "$n" != /* ]] && { echo "${n%.app}"; return; }
    n=$(plutil -extract CFBundleDisplayName raw "$plist" 2>/dev/null || echo "")
    [[ -n "$n" && "$n" != "(null)" ]] && { echo "${n%.app}"; return; }
    n=$(plutil -extract CFBundleName raw "$plist" 2>/dev/null || echo "")
    [[ -n "$n" && "$n" != "(null)" ]] && { echo "${n%.app}"; return; }
    echo "$fallback"
}

scan_applications() {
    local app_dir app_path app_name bundle_id display_name size_kb size_human
    APP_LIST=(); APP_SIZES=(); APP_PATHS=(); APP_BUNDLE_IDS=()

    while IFS= read -r app_dir; do
        [[ -d "$app_dir" ]] || continue
        while IFS= read -r -d '' app_path; do
            [[ -d "$app_path" ]] || continue
            app_name="${app_path##*/}"; app_name="${app_name%.app}"

            # Skip nested apps inside another .app
            local parent="${app_path%/*}"
            [[ "$parent" == *.app || "$parent" == *.app/* ]] && continue

            bundle_id=$(_purge_resolve_bundle_id "$app_path")
            should_protect_from_uninstall "$bundle_id" && continue

            display_name=$(_purge_resolve_display_name "$app_path" "$app_name")
            size_kb=$(get_path_size_kb "$app_path" 2>/dev/null || echo 0)
            [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0
            size_human=$(bytes_to_human_kb "$size_kb")

            APP_LIST+=("$display_name")
            APP_SIZES+=("$size_human")
            APP_PATHS+=("$app_path")
            APP_BUNDLE_IDS+=("$bundle_id")
        done < <(find "$app_dir" -maxdepth 3 -name "*.app" -print0 2>/dev/null)
    done < <(_purge_app_dirs)
}
