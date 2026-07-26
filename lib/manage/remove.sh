#!/bin/bash
# MacWash - Self-removal flow.

set -euo pipefail
[[ -z "${MACWASH_BASE_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/base.sh"

remove_macwash() {
    local dry_run="${1:-false}"
    echo ""
    echo -e "${CYAN_BOLD}  ◈ MacWash  Remove${NC}"
    echo ""

    local install_dir="/usr/local/bin"
    local config_dir="$HOME/.config/macwash"

    echo -e "  This will remove:"
    echo -e "  ${GRAY}•${NC} $install_dir/macwash"
    echo -e "  ${GRAY}•${NC} $config_dir"
    echo ""
    echo -ne "  Continue? [y/N]: "
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Aborted."; return; }

    if [[ "$dry_run" != "true" ]]; then
        [[ -f "$install_dir/macwash" ]] && sudo rm -f "$install_dir/macwash" # SAFE: known install path
        [[ -d "$config_dir" ]]          && rm -rf "$config_dir"              # SAFE: user config dir
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} MacWash removed."
    else
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} Would remove: $install_dir/macwash and $config_dir"
    fi
    echo ""
}
