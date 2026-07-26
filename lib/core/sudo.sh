#!/bin/bash
# MacWash - Sudo session management.

set -euo pipefail
[[ -n "${MACWASH_SUDO_LOADED:-}" ]] && return 0
readonly MACWASH_SUDO_LOADED=1

_MACWASH_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MACWASH_BASE_LOADED:-}" ]] && source "$_MACWASH_CORE_DIR/base.sh"

has_sudo_session() {
    [[ "${MACWASH_TEST_NO_AUTH:-0}" == "1" ]] && return 1
    sudo -n true 2>/dev/null
}

ensure_sudo_session() {
    local reason="${1:-Admin access required}"
    [[ "${MACWASH_TEST_NO_AUTH:-0}" == "1" ]] && return 1

    has_sudo_session && return 0

    echo -e "${BLUE}${ICON_ADMIN}${NC} $reason"
    if sudo -v 2>/dev/null; then
        return 0
    fi
    echo -e "${YELLOW}${ICON_WARNING}${NC} Authentication failed"
    return 1
}

stop_sudo_session() {
    sudo -k 2>/dev/null || true
}
