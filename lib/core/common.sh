#!/bin/bash
# MacWash - Common loader: sources all core modules in order.

set -euo pipefail
[[ -n "${MACWASH_COMMON_LOADED:-}" ]] && return 0
readonly MACWASH_COMMON_LOADED=1

_PURGE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_PURGE_CORE_DIR/base.sh"
source "$_PURGE_CORE_DIR/ui.sh"
source "$_PURGE_CORE_DIR/protection.sh"
source "$_PURGE_CORE_DIR/file_ops.sh"
source "$_PURGE_CORE_DIR/log.sh"
source "$_PURGE_CORE_DIR/help.sh"
source "$_PURGE_CORE_DIR/sudo.sh"

load_whitelist 2>/dev/null || true

# ── show_version ──────────────────────────────────────────────────────────────
show_version() {
    local v
    v=$(grep -m1 '^VERSION=' "$MACWASH_ENTRY_SCRIPT" 2>/dev/null | sed 's/VERSION="//' | sed 's/"//') || v="1.0.0"
    echo -e "${CYAN_BOLD}MacWash${NC} version ${GREEN}${v}${NC}"
    echo "macOS cleanup and optimization tool"
    echo "https://github.com/toolka/MacWash"
}

# ── print_summary_block ───────────────────────────────────────────────────────
print_summary_block() {
    local title="$1"; shift
    local -a lines=("$@")
    echo ""
    echo -e "${CYAN_BOLD}${ICON_ARROW} $title${NC}"
    local l
    for l in "${lines[@]}"; do
        echo -e "  ${GREEN}${ICON_SUBLIST}${NC} $l"
    done
    echo ""
}

# ── path identity ─────────────────────────────────────────────────────────────
purge_path_identity() {
    local p="${1%/}"; [[ -z "$p" ]] && p="$1"
    if [[ -e "$p" || -L "$p" ]]; then
        local id; id=$(stat -L -f '%d:%i' "$p" 2>/dev/null || true)
        [[ "$id" =~ ^[0-9]+:[0-9]+$ ]] && { printf 'inode:%s\n' "$id"; return; }
    fi
    printf 'path:%s\n' "$p"
}
