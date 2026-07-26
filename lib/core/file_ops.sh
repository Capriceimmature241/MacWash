#!/bin/bash
# MacWash - Safe file operations with path validation.

set -euo pipefail
[[ -n "${MACWASH_FILE_OPS_LOADED:-}" ]] && return 0
readonly MACWASH_FILE_OPS_LOADED=1

_MACWASH_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MACWASH_BASE_LOADED:-}" ]] && source "$_MACWASH_CORE_DIR/base.sh"

# ── Critical path deny-list ──────────────────────────────────────────────────
_macwash_is_critical_path() {
    local p="$1"
    case "$p" in
        / | /bin | /bin/* | /sbin | /sbin/* | /usr | /usr/bin | /usr/bin/* \
            | /usr/sbin | /usr/sbin/* | /System | /System/* \
            | /Library | /Library/Apple | /Library/Apple/* \
            | /Library/Extensions | /Library/Extensions/* \
            | /Library/Keychains | /Library/Keychains/* \
            | /Applications | /Applications/Finder.app | /Applications/Finder.app/* \
            | /Applications/Safari.app | /Applications/Safari.app/* \
            | /Volumes | /opt | /opt/homebrew \
            | /private | /private/etc | /private/etc/* \
            | /private/var | /private/var/db | /private/var/db/* \
            | /Users | /Users/Shared | /Users/Guest | /Users/Guest/*)
            return 0 ;;
        /usr/local/* | /opt/homebrew/*) return 1 ;;
    esac
    # Block bare user home roots /Users/<name>  (single component below /Users)
    if [[ "$p" == /Users/* && "$p" != /Users/*/* ]]; then return 0; fi
    return 1
}

# ── Path validator ────────────────────────────────────────────────────────────
validate_path_for_deletion() {
    local p="$1"
    [[ -z "$p" ]]         && { echo "MacWash: empty path" >&2; return 1; }
    [[ "$p" != /* ]]      && { echo "MacWash: not absolute: $p" >&2; return 1; }
    [[ "$p" =~ (^|/)\.\.(\/|$) ]] && { echo "MacWash: traversal: $p" >&2; return 1; }
    [[ "$p" =~ [[:cntrl:]] ]] && { echo "MacWash: control chars: $p" >&2; return 1; }

    # Symlink leaf resolution
    if [[ -L "$p" ]]; then
        local target; target=$(readlink "$p" 2>/dev/null) || return 1
        [[ "$target" != /* ]] && target="$(dirname "$p")/$target"
        _macwash_is_critical_path "$target" && { echo "MacWash: symlink -> critical: $p" >&2; return 1; }
    fi

    # Allow known safe subtrees under /private before the deny check
    case "$p" in
        /private/tmp/* | /private/var/tmp/* | /private/var/log | /private/var/log/* \
            | /private/var/folders/* | /private/var/db/diagnostics | /private/var/db/diagnostics/*)
            return 0 ;;
    esac

    _macwash_is_critical_path "$p" && { echo "MacWash: critical path: $p" >&2; return 1; }

    # App protection check (if loaded)
    if declare -f should_protect_path >/dev/null 2>&1 && should_protect_path "$p"; then
        [[ "${MACWASH_DEBUG:-0}" == "1" ]] && echo "MacWash: protected: $p" >&2
        return 1
    fi
    return 0
}

# ── Safe remove ───────────────────────────────────────────────────────────────
safe_remove() {
    local path="$1"
    local silent="${2:-false}"
    local precomputed_kb="${3:-}"

    if [[ "$silent" == "true" ]]; then
        validate_path_for_deletion "$path" 2>/dev/null || return 1
    else
        validate_path_for_deletion "$path" || return 1
    fi

    [[ -e "$path" || -L "$path" ]] || return 0

    # Whitelist check
    if declare -f is_path_whitelisted >/dev/null 2>&1 && is_path_whitelisted "$path"; then
        return 1
    fi

    if [[ "${MACWASH_DRY_RUN:-0}" == "1" ]]; then
        [[ "${MACWASH_DEBUG:-0}" == "1" ]] && echo "  [DRY RUN] Would remove: $path" >&2
        return 0
    fi

    local rc=0; rm -rf "$path" 2>/dev/null || rc=$?    # SAFE: validated above
    return $rc
}

# ── Safe sudo remove ──────────────────────────────────────────────────────────
safe_sudo_remove() {
    local path="$1"
    validate_path_for_deletion "$path" || return 1
    [[ -e "$path" ]] || return 0
    [[ -L "$path" ]] && { echo "MacWash: refuse sudo remove symlink: $path" >&2; return 1; }

    if [[ "${MACWASH_DRY_RUN:-0}" == "1" ]]; then
        [[ "${MACWASH_DEBUG:-0}" == "1" ]] && echo "  [DRY RUN] Would sudo remove: $path" >&2
        return 0
    fi

    if [[ "${MACWASH_TEST_NO_AUTH:-0}" == "1" ]]; then return 1; fi

    sudo -n rm -rf "$path" 2>/dev/null || return 1    # SAFE: validated above
    return 0
}

# ── Batch safe_clean helper ──────────────────────────────────────────────────
# Usage: safe_clean <paths…> <description>
safe_clean() {
    [[ $# -lt 2 ]] && return 0
    local description="${*: -1}"
    local -a paths=("${@:1:$#-1}")
    local cleaned=0 total_kb=0

    for p in "${paths[@]}"; do
        [[ -e "$p" || -L "$p" ]] || continue
        local size_kb=0
        size_kb=$(get_path_size_kb "$p" 2>/dev/null || echo 0)
        [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0

        if safe_remove "$p" true; then
            cleaned=$((cleaned + 1))
            total_kb=$((total_kb + size_kb))
        fi
    done

    [[ "$cleaned" -eq 0 ]] && return 0

    local human; human=$(bytes_to_human_kb "$total_kb")
    if [[ "${MACWASH_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $description · $(colorize_size "$human") dry"
    else
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $description · $(colorize_size "$human")"
    fi
    note_activity
}
