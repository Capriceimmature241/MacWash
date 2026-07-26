#!/bin/bash
# MacWash - Optimize command.
# Rebuilds caches, flushes DNS, vacuums databases, refreshes services.

set -euo pipefail
export LC_ALL=C LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/optimize/tasks.sh"

DRY_RUN=false
trap 'stop_inline_spinner 2>/dev/null; stop_sudo_session; cleanup_temp_files; show_cursor' EXIT
trap 'stop_inline_spinner 2>/dev/null; stop_sudo_session; cleanup_temp_files; show_cursor; exit 130' INT TERM

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true; export MACWASH_DRY_RUN=1 ;;
        --debug)      export MACWASH_DEBUG=1 ;;
        --help|-h)    show_help; exit 0 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

[[ -t 1 ]] && clear_screen
echo ""
echo -e "${CYAN_BOLD}  ◈ MacWash  Optimize${NC}"
echo ""

[[ "$DRY_RUN" == "true" ]] && echo -e "  ${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}\n"

# ── System info ───────────────────────────────────────────────────────────────
mem_total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
mem_total_gb=$((mem_total / 1024 / 1024 / 1024))
disk_free_kb=$(get_free_space_kb 2>/dev/null || echo 0)
boot_sec=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\),.*/\1/p' | tr -d '[:space:]')
[[ "$boot_sec" =~ ^[0-9]+$ ]] || boot_sec=0
now_sec=$(get_epoch_seconds)
elapsed_sec=$(( now_sec - boot_sec ))
[[ $elapsed_sec -lt 0 ]] && elapsed_sec=0
uptime_days=$(( elapsed_sec / 86400 ))
echo -e "  ${ICON_ADMIN} System  ${mem_total_gb}GB RAM  |  $(bytes_to_human_kb "$disk_free_kb") free  |  Uptime ${uptime_days}d"
echo ""

# ── Sudo ──────────────────────────────────────────────────────────────────────
MACWASH_OPT_SUDO=false
if [[ "$DRY_RUN" != "true" ]] && ensure_sudo_session "System optimization requires admin access"; then
    PURGE_OPT_SUDO=true
fi

log_operation_session_start "optimize"

# ── Tasks ─────────────────────────────────────────────────────────────────────
opt_announce "DNS cache"
    opt_flush_dns

opt_announce "QuickLook thumbnails"
    opt_quicklook_refresh

opt_announce "LaunchServices database"
    opt_launch_services

opt_announce "Spotlight index"
    opt_spotlight_check

opt_announce "Saved app states"
    opt_saved_states

opt_announce "SQLite databases"
    opt_sqlite_vacuum

opt_announce "Quarantine history"
    opt_quarantine_db

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GRAY}$(printf '─%.0s' {1..60})${NC}"
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}${ICON_DRY_RUN} Dry run complete${NC}"
else
    echo -e "  ${GREEN}${ICON_SUCCESS} Optimization complete${NC}"
fi
echo ""

log_operation_session_end "optimize"
