#!/bin/bash
# MacWash - Help text.

set -euo pipefail
[[ -n "${MACWASH_HELP_LOADED:-}" ]] && return 0
readonly MACWASH_HELP_LOADED=1

show_help() {
    cat <<EOF

${CYAN_BOLD}MacWash${NC} — Clean, optimize and speed up your Mac. Free and open source.

${CYAN_BOLD}Usage:${NC}
  macwash                     Interactive menu
  macwash clean               Deep cache and junk cleanup
  macwash uninstall           Remove apps and their leftovers
  macwash optimize            Refresh caches and services
  macwash analyze [path]      Explore disk usage
  macwash status              Live system dashboard
  macwash history             Show operation history

${CYAN_BOLD}Options:${NC}
  --dry-run                   Preview without making changes
  --debug                     Verbose debug output
  --help                      Show this help
  --version                   Show version

${CYAN_BOLD}Examples:${NC}
  macwash clean --dry-run     Preview cleanup targets
  macwash analyze ~/Downloads Explore a specific folder
  macwash history --json      Machine-readable log

${CYAN_BOLD}Logs:${NC}
  ~/Library/Logs/macwash/operations.log
EOF
}

show_version() {
    local v
    v=$(grep -m1 '^VERSION=' "$MACWASH_ENTRY_SCRIPT" 2>/dev/null | sed 's/VERSION="\(.*\)"/\1/') || v="1.0.0"
    echo -e "${CYAN_BOLD}MacWash${NC} version ${GREEN}${v}${NC}"
    echo "macOS cleanup and optimization tool"
    echo "https://github.com/toolka/MacWash"
}
