#!/bin/bash
# MacWash - Uninstall command.
# Finds installed apps, removes them and their leftover files.

set -euo pipefail
export LC_ALL=C LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/uninstall/scanner.sh"
source "$SCRIPT_DIR/lib/uninstall/batch.sh"

DRY_RUN=false
trap 'stop_inline_spinner 2>/dev/null; cleanup_temp_files; show_cursor' EXIT
trap 'stop_inline_spinner 2>/dev/null; cleanup_temp_files; show_cursor; exit 130' INT TERM

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
echo -e "${CYAN_BOLD}  ◈ MacWash  Uninstall${NC}"
echo ""
[[ "$DRY_RUN" == "true" ]] && echo -e "  ${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}\n"

log_operation_session_start "uninstall"

# ── Scan apps ─────────────────────────────────────────────────────────────────
start_inline_spinner "Scanning installed applications..."
declare -a APP_LIST=()
declare -a APP_SIZES=()
declare -a APP_PATHS=()
declare -a APP_BUNDLE_IDS=()
scan_applications
stop_inline_spinner

total_apps=${#APP_LIST[@]}
if [[ "$total_apps" -eq 0 ]]; then
    echo -e "  ${GRAY}No user-removable applications found.${NC}\n"
    exit 0
fi

echo -e "  ${GRAY}Found $total_apps apps  ·  Select to uninstall:${NC}\n"

# ── Selection menu ────────────────────────────────────────────────────────────
declare -a SELECTED=()
for i in "${!APP_LIST[@]}"; do SELECTED+=("false"); done

current=0
page_size=15

render_list() {
    local start=$((current / page_size * page_size))
    local end=$((start + page_size))
    [[ $end -gt $total_apps ]] && end=$total_apps
    local i
    for ((i=start; i<end; i++)); do
        local check="☐"; [[ "${SELECTED[$i]}" == "true" ]] && check="☑"
        local marker="  "
        [[ "$i" -eq "$current" ]] && marker="${CYAN}▶${NC}"
        local sz="${APP_SIZES[$i]:-?}"
        printf '\r\033[2K  %s %s %-36s  %s\n' "$marker" "$check" "${APP_LIST[$i]}" "$sz"
    done
    echo ""
    echo -e "  ${GRAY}↑↓ Navigate  |  Space Select  |  Enter Confirm  |  Q Quit${NC}"
}

hide_cursor
while true; do
    printf '\033[H'
    echo -e "${CYAN_BOLD}  ◈ MacWash  Uninstall${NC}\n"
    render_list
    printf '\033[J'

    key=$(read_key 2>/dev/null || echo "QUIT")
    case "$key" in
        UP)    ((current > 0))              && ((current--)) ;;
        DOWN)  ((current < total_apps - 1)) && ((current++)) ;;
        SPACE)
            if [[ "${SELECTED[$current]}" == "true" ]]; then
                SELECTED[$current]="false"
            else
                SELECTED[$current]="true"
            fi ;;
        ENTER) break ;;
        QUIT)  show_cursor; echo ""; exit 0 ;;
    esac
done
show_cursor

# ── Confirm and uninstall ─────────────────────────────────────────────────────
selected_count=0
for s in "${SELECTED[@]}"; do [[ "$s" == "true" ]] && selected_count=$((selected_count+1)); done

if [[ "$selected_count" -eq 0 ]]; then
    echo -e "\n  ${GRAY}Nothing selected.${NC}\n"
    exit 0
fi

echo ""
echo -e "  ${YELLOW}${ICON_WARNING}${NC} About to remove ${RED}$selected_count${NC} app(s) and their leftovers."
echo -ne "  ${GRAY}Continue? [y/N]:${NC} "
read -r confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 0; }

echo ""
for i in "${!APP_LIST[@]}"; do
    [[ "${SELECTED[$i]}" == "true" ]] || continue
    uninstall_app "${APP_PATHS[$i]}" "${APP_LIST[$i]}" "${APP_BUNDLE_IDS[$i]:-}"
done

echo ""
echo -e "  ${GRAY}$(printf '─%.0s' {1..60})${NC}"
echo -e "  ${GREEN}${ICON_SUCCESS} Uninstall complete${NC}"
echo ""
log_operation_session_end "uninstall"
