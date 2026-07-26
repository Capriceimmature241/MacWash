#!/bin/bash
# MacWash - Clean command.
# Scans and removes caches, logs, dev artifacts, and junk.

set -euo pipefail
export LC_ALL=C LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/clean/caches.sh"
source "$SCRIPT_DIR/lib/clean/dev.sh"
source "$SCRIPT_DIR/lib/clean/system.sh"
source "$SCRIPT_DIR/lib/clean/user.sh"

DRY_RUN=false
SYSTEM_CLEAN=false
files_cleaned=0
total_size_cleaned=0

trap 'stop_inline_spinner 2>/dev/null; stop_sudo_session; cleanup_temp_files; show_cursor' EXIT
trap 'stop_inline_spinner 2>/dev/null; stop_sudo_session; cleanup_temp_files; show_cursor; exit 130' INT TERM

# ── Arg parsing ───────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true; export MACWASH_DRY_RUN=1 ;;
        --debug)      export MACWASH_DEBUG=1 ;;
        --help|-h)    show_help; exit 0 ;;
        *)
            echo "Unknown option: $arg"
            echo "Use 'macwash clean --help' for supported options."
            exit 1 ;;
    esac
done

export MACWASH_CURRENT_COMMAND="clean"

# ── Header ────────────────────────────────────────────────────────────────────
[[ -t 1 ]] && clear_screen
echo ""
echo -e "${CYAN_BOLD}  ◈ MacWash  Clean${NC}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}${ICON_DRY_RUN} DRY RUN MODE — no files will be deleted${NC}"
    echo ""
fi

# ── Show free space before ────────────────────────────────────────────────────
free_before=0
if free_before=$(get_free_space_kb 2>/dev/null); then
    echo -e "  ${GRAY}Free before: $(bytes_to_human_kb "$free_before")${NC}"
fi

# ── Sudo prompt for system caches ────────────────────────────────────────────
if [[ "$DRY_RUN" != "true" ]]; then
    echo ""
    echo -ne "  ${ICON_ADMIN} System caches need admin. ${GREEN}Enter${NC} to allow, ${GRAY}Space${NC} to skip: "
    key=$(read_key 2>/dev/null || echo "SPACE")
    echo ""
    if [[ "$key" == "ENTER" ]] && ensure_sudo_session "System cleanup requires admin access"; then
        SYSTEM_CLEAN=true
    fi
fi

# ── Run cleanup sections ──────────────────────────────────────────────────────
log_operation_session_start "clean"

start_section "User caches"
    clean_user_caches
end_section

start_section "Browser caches"
    clean_browser_caches
end_section

start_section "Developer tools"
    clean_dev_npm
    clean_dev_python
    clean_dev_go
    clean_dev_rust
    clean_dev_ruby
    clean_dev_frontend
end_section

start_section "App caches"
    clean_app_caches
end_section

start_section "Logs and crash reports"
    clean_user_logs
    clean_crash_reports
end_section

start_section "Temporary files"
    clean_temp_files
end_section

if [[ "$SYSTEM_CLEAN" == "true" ]]; then
    start_section "System caches"
        clean_system_caches
    end_section

    start_section "System logs"
        clean_system_logs
    end_section
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GRAY}$(printf '─%.0s' {1..60})${NC}"
free_after=0
if free_after=$(get_free_space_kb 2>/dev/null) && [[ "$free_before" -gt 0 ]]; then
    local_freed=$((free_after - free_before))
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN} Dry run complete — no changes made${NC}"
    elif [[ $local_freed -gt 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS} Freed: $(colorize_size "$(bytes_to_human_kb "$local_freed")")${NC}  ·  Free now: $(bytes_to_human_kb "$free_after")"
    else
        echo -e "  ${GREEN}${ICON_SUCCESS} Clean complete  ·  Free now: $(bytes_to_human_kb "$free_after")${NC}"
    fi
else
    echo -e "  ${GREEN}${ICON_SUCCESS} Clean complete${NC}"
fi
echo ""

log_operation_session_end "clean" "$files_cleaned" "$(bytes_to_human_kb "$total_size_cleaned")"
