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
trap 'stop_inline_spinner 2>/dev/null; cleanup_temp_files; show_cursor; stty sane 2>/dev/null || true' EXIT
trap 'stop_inline_spinner 2>/dev/null; cleanup_temp_files; show_cursor; stty sane 2>/dev/null || true; exit 130' INT TERM

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

# ── Selection menu ────────────────────────────────────────────────────────────
declare -a SELECTED=()
for i in "${!APP_LIST[@]}"; do SELECTED+=("false"); done

current=0
page_size=15

# Save terminal state before raw mode
original_stty=$(stty -g 2>/dev/null || echo "")

restore_terminal() {
    show_cursor
    if [[ -n "$original_stty" ]]; then
        stty "$original_stty" 2>/dev/null || stty sane 2>/dev/null || true
    else
        stty sane 2>/dev/null || true
    fi
}

draw_menu() {
    local start=$(( current / page_size * page_size ))
    local end=$(( start + page_size ))
    [[ $end -gt $total_apps ]] && end=$total_apps

    # Count selected
    local sel_count=0
    for s in "${SELECTED[@]}"; do [[ "$s" == "true" ]] && sel_count=$((sel_count+1)); done

    printf '\033[H\033[2J'
    echo -e "${CYAN_BOLD}  ◈ MacWash  Uninstall${NC}  ${GRAY}${sel_count} selected${NC}"
    echo ""

    local i
    for ((i=start; i<end; i++)); do
        local check="☐"
        [[ "${SELECTED[$i]}" == "true" ]] && check="☑"
        local sz="${APP_SIZES[$i]:-?}"

        if [[ "$i" -eq "$current" ]]; then
            echo -e "  ${CYAN}▶ ${check} ${APP_LIST[$i]}${NC}  ${GRAY}${sz}${NC}"
        else
            echo "    ${check} ${APP_LIST[$i]}  ${sz}"
        fi
    done

    echo ""
    echo -e "  ${GRAY}↑↓ Navigate  |  Space Select  |  Enter Confirm  |  Q Quit${NC}"
}

stty -echo -icanon intr ^C 2>/dev/null || true
hide_cursor

while true; do
    draw_menu

    key=$(read_key 2>/dev/null || echo "QUIT")
    case "$key" in
        UP)
            ((current > 0)) && ((current--))
            ;;
        DOWN)
            ((current < total_apps - 1)) && ((current++))
            ;;
        SPACE)
            if [[ "${SELECTED[$current]}" == "true" ]]; then
                SELECTED[$current]="false"
            else
                SELECTED[$current]="true"
            fi
            ;;
        ENTER)
            break
            ;;
        QUIT)
            restore_terminal
            echo ""
            exit 0
            ;;
    esac
done

restore_terminal
clear

# ── Count selected ────────────────────────────────────────────────────────────
selected_count=0
for s in "${SELECTED[@]}"; do [[ "$s" == "true" ]] && selected_count=$((selected_count+1)); done

if [[ "$selected_count" -eq 0 ]]; then
    echo -e "\n  ${GRAY}Nothing selected.${NC}\n"
    exit 0
fi

# ── Show what will be removed ─────────────────────────────────────────────────
echo ""
echo -e "${CYAN_BOLD}  ◈ MacWash  Uninstall${NC}"
echo ""
echo -e "  ${YELLOW}${ICON_WARNING}${NC} Selected ${RED}$selected_count${NC} app(s) for removal:"
echo ""
for i in "${!APP_LIST[@]}"; do
    [[ "${SELECTED[$i]}" == "true" ]] || continue
    echo -e "  ${GRAY}•${NC} ${APP_LIST[$i]}  ${GRAY}(${APP_SIZES[$i]})${NC}"
done
echo ""
echo -ne "  Continue? [y/N]: "
read -r confirm
echo ""

[[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "  ${GRAY}Aborted.${NC}"; exit 0; }

# ── Uninstall ─────────────────────────────────────────────────────────────────
for i in "${!APP_LIST[@]}"; do
    [[ "${SELECTED[$i]}" == "true" ]] || continue
    uninstall_app "${APP_PATHS[$i]}" "${APP_LIST[$i]}" "${APP_BUNDLE_IDS[$i]:-}"
done

echo ""
echo -e "  ${GRAY}$(printf '─%.0s' {1..60})${NC}"
echo -e "  ${GREEN}${ICON_SUCCESS} Uninstall complete${NC}"
echo ""
log_operation_session_end "uninstall"
