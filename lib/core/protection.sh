#!/bin/bash
# MacWash - App protection lists and path protection logic.

set -euo pipefail
[[ -n "${MACWASH_PROTECTION_LOADED:-}" ]] && return 0
readonly MACWASH_PROTECTION_LOADED=1

_MACWASH_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MACWASH_BASE_LOADED:-}" ]] && source "$_MACWASH_CORE_DIR/base.sh"

# ── System-critical bundle IDs (never uninstall) ─────────────────────────────
readonly -a SYSTEM_CRITICAL_BUNDLES=(
    "com.apple.finder"
    "com.apple.dock"
    "com.apple.Safari"
    "com.apple.SystemPreferences"
    "com.apple.systempreferences"
    "com.apple.loginwindow"
    "com.apple.Spotlight"
    "com.apple.security*"
    "com.apple.keychain*"
    "com.apple.controlcenter"
    "com.apple.notificationcenterui"
    "com.apple.accessibility*"
    "com.apple.touchid*"
    "com.apple.WindowServer"
    "com.apple.coreservices*"
)

# ── Data-protected bundles (don't clean data, safe to uninstall) ─────────────
readonly -a DATA_PROTECTED_BUNDLES=(
    "com.1password*"
    "com.agilebits*"
    "com.lastpass*"
    "com.bitwarden*"
    "com.dashlane*"
    "com.nssurge*"
    "com.jetbrains*"
    "com.microsoft*"
    "com.docker*"
    "com.apple.Notes"
    "com.apple.mail"
    "com.apple.Mail"
    "com.apple.iCloud*"
    "com.apple.mobileme*"
    "com.apple.MobileMe*"
    "com.tencent*"
)

# ── Bundle pattern matcher ────────────────────────────────────────────────────
_bundle_matches() {
    local id="$1" pattern="$2"
    [[ -z "$pattern" ]] && return 1
    # shellcheck disable=SC2053
    [[ "$id" == $pattern ]]
}

should_protect_from_uninstall() {
    local bundle_id="$1"
    local p
    for p in "${SYSTEM_CRITICAL_BUNDLES[@]}"; do
        _bundle_matches "$bundle_id" "$p" && return 0
    done
    return 1
}

should_protect_data() {
    local bundle_id="$1"
    case "$bundle_id" in
        com.apple.*) return 0 ;;
    esac
    local p
    for p in "${DATA_PROTECTED_BUNDLES[@]}"; do
        _bundle_matches "$bundle_id" "$p" && return 0
    done
    return 1
}

# ── Main path protection gate ─────────────────────────────────────────────────
should_protect_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1

    # System settings / control center / Finder / Dock
    case "$p" in
        *SystemSettings* | *SystemPreferences* | *ControlCenter* \
        | *com.apple.dock* | *com.apple.finder* \
        | *com.apple.security* | *com.apple.keychain* \
        | */Library/Keychains* | */Library/Keychains/* \
        | */Library/Accounts* | */Library/Accounts/* \
        | */Library/Mail*     | */Library/Mail/* \
        | */Library/Calendars*| */Library/Calendars/* \
        | */Library/Contacts* | */Library/Contacts/* \
        | */Library/Logs/macwash | */Library/Logs/macwash/* \
        | */Mobile\ Documents* \
        | *com.apple.iCloud* | *com.apple.MobileMe*)
            return 0 ;;
    esac

    # Container paths — extract bundle ID and check
    if [[ "$p" =~ /Library/Containers/([^/]+) ]] || \
       [[ "$p" =~ /Library/Group\ Containers/([^/]+) ]]; then
        local bid="${BASH_REMATCH[1]}"
        # Caches/tmp inside containers are always regenerable
        [[ "$p" == */Data/Library/Caches/* || "$p" == */Data/tmp/* ]] && return 1
        should_protect_data "$bid" && return 0
    fi

    return 1
}

# ── User whitelist ────────────────────────────────────────────────────────────
declare -a WHITELIST_PATTERNS=()

is_path_whitelisted() {
    local target="$1"
    [[ -z "$target" ]] && return 1
    [[ ${#WHITELIST_PATTERNS[@]} -eq 0 ]] && return 1
    local norm="${target%/}"
    local pat
    for pat in "${WHITELIST_PATTERNS[@]}"; do
        local cp="${pat%/}"
        # shellcheck disable=SC2053
        [[ "$norm" == "$cp" ]] && return 0
        [[ "$norm" == $cp ]]   && return 0
        [[ "$cp" == "$norm"/* ]] && return 0
        [[ "$norm" == "$cp"/* ]] && return 0
    done
    return 1
}

load_whitelist() {
    local wl_file="${HOME}/.config/macwash/whitelist"
    WHITELIST_PATTERNS=()
    [[ -f "$wl_file" ]] || return 0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        [[ "$line" == ~* ]] && line="${line/#~/$HOME}"
        line="${line//\$HOME/$HOME}"
        WHITELIST_PATTERNS+=("$line")
    done < "$wl_file"
}
