#!/bin/bash
# MacWash - Analyze command: interactive disk explorer.

set -euo pipefail
export LC_ALL=C LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

SCAN_PATH="${1:-}"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true; export MACWASH_DRY_RUN=1 ;;
        --debug)      export MACWASH_DEBUG=1 ;;
        --help|-h)    show_help; exit 0 ;;
        -*) echo "Unknown option: $arg"; exit 1 ;;
        *)  SCAN_PATH="$arg" ;;
    esac
done

[[ -z "$SCAN_PATH" ]] && SCAN_PATH="$HOME"
SCAN_PATH=$(cd "$SCAN_PATH" 2>/dev/null && pwd) || { echo "Cannot access: $SCAN_PATH"; exit 1; }

trap 'stop_inline_spinner 2>/dev/null; cleanup_temp_files; show_cursor' EXIT
trap 'stop_inline_spinner 2>/dev/null; cleanup_temp_files; show_cursor; exit 130' INT TERM

[[ -t 1 ]] && clear_screen

# ── Scan ─────────────────────────────────────────────────────────────────────
start_inline_spinner "Scanning $SCAN_PATH..."

declare -a ENTRY_NAMES=()
declare -a ENTRY_PATHS=()
declare -a ENTRY_SIZES=()  # in KB

while IFS= read -r -d '' entry; do
    [[ -d "$entry" || -f "$entry" ]] || continue
    local_name="${entry##*/}"
    [[ -z "$local_name" || "$local_name" == "." ]] && continue
    sz=$(get_path_size_kb "$entry" 2>/dev/null || echo 0)
    [[ "$sz" =~ ^[0-9]+$ ]] || sz=0
    [[ "$sz" -lt 1 ]] && continue
    ENTRY_NAMES+=("$local_name")
    ENTRY_PATHS+=("$entry")
    ENTRY_SIZES+=("$sz")
done < <(find "$SCAN_PATH" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

stop_inline_spinner

# Sort by size (simple bubble pass for small lists; for large we use temp file)
count=${#ENTRY_NAMES[@]}
if [[ "$count" -gt 1 ]]; then
    tmp_sort=$(create_temp_file)
    for i in "${!ENTRY_NAMES[@]}"; do
        printf '%010d\t%s\t%s\n' "${ENTRY_SIZES[$i]}" "${ENTRY_NAMES[$i]}" "${ENTRY_PATHS[$i]}"
    done | sort -rn > "$tmp_sort"

    ENTRY_NAMES=(); ENTRY_SIZES=(); ENTRY_PATHS=()
    while IFS=$'\t' read -r sz name path; do
        sz="${sz#"${sz%%[^0]*}"}"   # strip leading zeros
        [[ -z "$sz" ]] && sz=0
        ENTRY_NAMES+=("$name")
        ENTRY_SIZES+=("$sz")
        ENTRY_PATHS+=("$path")
    done < "$tmp_sort"
    count=${#ENTRY_NAMES[@]}
fi

# ── Interactive browser ───────────────────────────────────────────────────────
current=0
offset=0
page_h=20

free_kb=$(get_free_space_kb 2>/dev/null || echo 0)

render_analyze() {
    printf '\033[H'
    local free_human; free_human=$(bytes_to_human_kb "$free_kb")
    echo -e "${CYAN_BOLD}  ◈ MacWash  Analyze${NC}  ${GRAY}${SCAN_PATH}  ·  ${free_human} free${NC}"
    echo ""

    local end=$((offset + page_h))
    [[ $end -gt $count ]] && end=$count
    local i
    for ((i=offset; i<end; i++)); do
        local sz_human; sz_human=$(bytes_to_human_kb "${ENTRY_SIZES[$i]}")
        local bar_len=$(( ENTRY_SIZES[$i] * 20 / (ENTRY_SIZES[0] + 1) ))
        [[ "$bar_len" -gt 20 ]] && bar_len=20
        local bar; bar=$(printf '█%.0s' $(seq 1 "$bar_len") 2>/dev/null || printf '%*s' "$bar_len" '' | tr ' ' '█')
        local marker="   "
        [[ "$i" -eq "$current" ]] && marker="${CYAN}▶  ${NC}"

        printf '\r\033[2K  %s %-20s  %6s  %s\n' \
            "$marker" "${ENTRY_NAMES[$i]:0:20}" "$sz_human" "$bar"
    done
    echo ""
    echo -e "  ${GRAY}↑↓ Navigate  |  D Delete→Trash  |  O Open  |  Q Quit${NC}"
    printf '\033[J'
}

hide_cursor
while true; do
    render_analyze

    key=$(read_key 2>/dev/null || echo "QUIT")
    case "$key" in
        UP)
            ((current > 0)) && ((current--))
            [[ "$current" -lt "$offset" ]] && offset=$current ;;
        DOWN)
            ((current < count - 1)) && ((current++))
            [[ "$current" -ge $((offset + page_h)) ]] && offset=$((current - page_h + 1)) ;;
        "CHAR:o"|"CHAR:O")
            show_cursor
            open "${ENTRY_PATHS[$current]}" 2>/dev/null || true
            hide_cursor ;;
        "CHAR:d"|"CHAR:D")
            show_cursor
            echo ""
            echo -ne "  ${YELLOW}${ICON_WARNING}${NC} Move '${ENTRY_NAMES[$current]}' to Trash? [y/N]: "
            read -r confirm
            hide_cursor
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                local_path="${ENTRY_PATHS[$current]}"
                if validate_path_for_deletion "$local_path" 2>/dev/null; then
                    osascript -e "tell application \"Finder\" to move POSIX file \"$local_path\" to trash" 2>/dev/null \
                        && {
                            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Moved to Trash: ${ENTRY_NAMES[$current]}"
                            # Remove from list
                            ENTRY_NAMES=("${ENTRY_NAMES[@]:0:$current}" "${ENTRY_NAMES[@]:$((current+1))}")
                            ENTRY_PATHS=("${ENTRY_PATHS[@]:0:$current}" "${ENTRY_PATHS[@]:$((current+1))}")
                            ENTRY_SIZES=("${ENTRY_SIZES[@]:0:$current}" "${ENTRY_SIZES[@]:$((current+1))}")
                            count=${#ENTRY_NAMES[@]}
                            [[ "$current" -ge "$count" && "$current" -gt 0 ]] && ((current--))
                            free_kb=$(get_free_space_kb 2>/dev/null || echo "$free_kb")
                        } || echo -e "  ${RED}${ICON_ERROR}${NC} Could not move to Trash"
                fi
            fi ;;
        QUIT)
            break ;;
    esac
done

show_cursor
echo ""
