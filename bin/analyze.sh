#!/bin/bash
# MacWash - Analyze command: interactive disk explorer with drill-down.

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

# ── State ─────────────────────────────────────────────────────────────────────
declare -a ENTRY_NAMES=()
declare -a ENTRY_PATHS=()
declare -a ENTRY_SIZES=()
declare -a ENTRY_IS_DIR=()
declare -a ENTRY_EXPANDED=()   # true/false per entry — is this entry expanded?
declare -a CHILD_NAMES=()      # flat list of expanded children
declare -a CHILD_PATHS=()
declare -a CHILD_SIZES=()
declare -a CHILD_PARENT=()     # index of parent entry

# Navigation stack for drill-down
declare -a NAV_STACK=()        # stack of previous SCAN_PATH values

current=0
offset=0
page_h=18
free_kb=0

# ── Scan a directory into the entry arrays ────────────────────────────────────
scan_dir() {
    local dir="$1"
    ENTRY_NAMES=(); ENTRY_PATHS=(); ENTRY_SIZES=(); ENTRY_IS_DIR=(); ENTRY_EXPANDED=()
    CHILD_NAMES=(); CHILD_PATHS=(); CHILD_SIZES=(); CHILD_PARENT=()
    current=0; offset=0

    [[ -t 1 ]] && clear_screen
    start_inline_spinner "Scanning ${dir}..."

    local tmp_sort; tmp_sort=$(create_temp_file)
    while IFS= read -r -d '' entry; do
        local local_name="${entry##*/}"
        [[ -z "$local_name" || "$local_name" == "." ]] && continue
        local sz; sz=$(get_path_size_kb "$entry" 2>/dev/null || echo 0)
        [[ "$sz" =~ ^[0-9]+$ ]] || sz=0
        [[ "$sz" -lt 1 ]] && continue
        local is_dir="false"
        [[ -d "$entry" ]] && is_dir="true"
        printf '%010d\t%s\t%s\t%s\n' "$sz" "$local_name" "$entry" "$is_dir"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null) | sort -rn > "$tmp_sort"

    stop_inline_spinner

    while IFS=$'\t' read -r sz name path is_dir; do
        sz="${sz#"${sz%%[^0]*}"}"
        [[ -z "$sz" ]] && sz=0
        ENTRY_NAMES+=("$name")
        ENTRY_PATHS+=("$path")
        ENTRY_SIZES+=("$sz")
        ENTRY_IS_DIR+=("$is_dir")
        ENTRY_EXPANDED+=("false")
    done < "$tmp_sort"

    free_kb=$(get_free_space_kb 2>/dev/null || echo 0)
}

# ── Expand a directory entry inline ──────────────────────────────────────────
expand_entry() {
    local idx="$1"
    local entry_path="${ENTRY_PATHS[$idx]}"

    [[ "${ENTRY_IS_DIR[$idx]}" != "true" ]] && return 0
    [[ "${ENTRY_EXPANDED[$idx]}" == "true" ]] && {
        # Collapse — remove children for this parent
        local -a new_cn=() new_cp=() new_cs=() new_cpar=()
        for i in "${!CHILD_PARENT[@]}"; do
            [[ "${CHILD_PARENT[$i]}" == "$idx" ]] && continue
            new_cn+=("${CHILD_NAMES[$i]}")
            new_cp+=("${CHILD_PATHS[$i]}")
            new_cs+=("${CHILD_SIZES[$i]}")
            new_cpar+=("${CHILD_PARENT[$i]}")
        done
        CHILD_NAMES=("${new_cn[@]+"${new_cn[@]}"}") 
        CHILD_PATHS=("${new_cp[@]+"${new_cp[@]}"}")
        CHILD_SIZES=("${new_cs[@]+"${new_cs[@]}"}")
        CHILD_PARENT=("${new_cpar[@]+"${new_cpar[@]}"}")
        ENTRY_EXPANDED[$idx]="false"
        return 0
    }

    # Expand — scan children
    start_inline_spinner "Expanding ${ENTRY_NAMES[$idx]}..."
    local tmp; tmp=$(create_temp_file)
    while IFS= read -r -d '' child; do
        local cname="${child##*/}"
        [[ -z "$cname" ]] && continue
        local csz; csz=$(get_path_size_kb "$child" 2>/dev/null || echo 0)
        [[ "$csz" =~ ^[0-9]+$ ]] || csz=0
        [[ "$csz" -lt 1 ]] && continue
        printf '%010d\t%s\t%s\n' "$csz" "$cname" "$child"
    done < <(find "$entry_path" -mindepth 1 -maxdepth 1 -print0 2>/dev/null) | sort -rn > "$tmp"
    stop_inline_spinner

    while IFS=$'\t' read -r csz cname cpath; do
        csz="${csz#"${csz%%[^0]*}"}"
        [[ -z "$csz" ]] && csz=0
        CHILD_NAMES+=("$cname")
        CHILD_PATHS+=("$cpath")
        CHILD_SIZES+=("$csz")
        CHILD_PARENT+=("$idx")
    done < "$tmp"

    ENTRY_EXPANDED[$idx]="true"
}

# ── Move item to Trash ────────────────────────────────────────────────────────
trash_item() {
    local item_path="$1"
    local item_name="$2"

    show_cursor
    stty sane 2>/dev/null || true
    echo ""
    echo -ne "  ${YELLOW}${ICON_WARNING}${NC} Move '${item_name}' to Trash? [y/N]: "
    read -r confirm
    stty -echo -icanon 2>/dev/null || true
    hide_cursor

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if validate_path_for_deletion "$item_path" 2>/dev/null; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} Would trash: $item_name"
            else
                # Escape path for AppleScript
                local escaped_path="${item_path//\\/\\\\}"
                escaped_path="${escaped_path//\"/\\\"}"
                osascript -e "tell application \"Finder\" to move POSIX file \"$escaped_path\" to trash" 2>/dev/null \
                    && {
                        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Moved to Trash: $item_name"
                        free_kb=$(get_free_space_kb 2>/dev/null || echo "$free_kb")
                        return 0
                    } || echo -e "  ${RED}${ICON_ERROR}${NC} Could not move to Trash"
            fi
        else
            echo -e "  ${RED}${ICON_ERROR}${NC} Protected path — cannot delete"
        fi
    fi
    return 1
}

# ── Build flat render list (entries + their expanded children) ────────────────
# Sets RENDER_* arrays used by render_analyze
declare -a RENDER_NAMES=()
declare -a RENDER_PATHS=()
declare -a RENDER_SIZES=()
declare -a RENDER_INDENT=()   # 0=top-level, 1=child
declare -a RENDER_IS_DIR=()
declare -a RENDER_EXPANDED=()
declare -a RENDER_ENTRY_IDX=() # maps render row → entry or child index
declare -a RENDER_IS_CHILD=()  # true if this row is a child item

build_render_list() {
    RENDER_NAMES=(); RENDER_PATHS=(); RENDER_SIZES=()
    RENDER_INDENT=(); RENDER_IS_DIR=(); RENDER_EXPANDED=()
    RENDER_ENTRY_IDX=(); RENDER_IS_CHILD=()

    local count=${#ENTRY_NAMES[@]}
    for ((i=0; i<count; i++)); do
        RENDER_NAMES+=("${ENTRY_NAMES[$i]}")
        RENDER_PATHS+=("${ENTRY_PATHS[$i]}")
        RENDER_SIZES+=("${ENTRY_SIZES[$i]}")
        RENDER_INDENT+=(0)
        RENDER_IS_DIR+=("${ENTRY_IS_DIR[$i]}")
        RENDER_EXPANDED+=("${ENTRY_EXPANDED[$i]}")
        RENDER_ENTRY_IDX+=("$i")
        RENDER_IS_CHILD+=("false")

        # If expanded, add children after this entry
        if [[ "${ENTRY_EXPANDED[$i]}" == "true" ]]; then
            for j in "${!CHILD_PARENT[@]}"; do
                [[ "${CHILD_PARENT[$j]}" != "$i" ]] && continue
                RENDER_NAMES+=("${CHILD_NAMES[$j]}")
                RENDER_PATHS+=("${CHILD_PATHS[$j]}")
                RENDER_SIZES+=("${CHILD_SIZES[$j]}")
                RENDER_INDENT+=(1)
                RENDER_IS_DIR+=("false")
                RENDER_EXPANDED+=("false")
                RENDER_ENTRY_IDX+=("$j")
                RENDER_IS_CHILD+=("true")
            done
        fi
    done
}

# ── Render ────────────────────────────────────────────────────────────────────
render_analyze() {
    build_render_list
    local render_count=${#RENDER_NAMES[@]}

    # Clamp cursor
    [[ $current -ge $render_count ]] && current=$((render_count - 1))
    [[ $current -lt 0 ]] && current=0
    [[ $current -lt $offset ]] && offset=$current
    [[ $current -ge $((offset + page_h)) ]] && offset=$((current - page_h + 1))
    [[ $offset -lt 0 ]] && offset=0

    printf '\033[H'
    local free_human; free_human=$(bytes_to_human_kb "$free_kb")

    # Breadcrumb path
    local display_path="${SCAN_PATH/#$HOME/~}"
    echo -e "${CYAN_BOLD}  ◈ MacWash  Analyze${NC}  ${GRAY}${display_path}  ·  ${free_human} free${NC}"
    echo ""

    local max_size=${ENTRY_SIZES[0]:-1}
    [[ $max_size -lt 1 ]] && max_size=1

    local end=$((offset + page_h))
    [[ $end -gt $render_count ]] && end=$render_count

    local i
    for ((i=offset; i<end; i++)); do
        local sz_human; sz_human=$(bytes_to_human_kb "${RENDER_SIZES[$i]}")
        local bar_len=$(( RENDER_SIZES[$i] * 18 / max_size ))
        [[ $bar_len -gt 18 ]] && bar_len=18
        [[ $bar_len -lt 0 ]] && bar_len=0
        local bar=""
        local b; for ((b=0; b<bar_len; b++)); do bar+="█"; done

        local indent=""
        [[ "${RENDER_INDENT[$i]}" == "1" ]] && indent="    "

        local type_icon=" "
        if [[ "${RENDER_IS_CHILD[$i]}" == "true" ]]; then
            type_icon="${GRAY}↳${NC}"
        elif [[ "${RENDER_IS_DIR[$i]}" == "true" ]]; then
            if [[ "${RENDER_EXPANDED[$i]}" == "true" ]]; then
                type_icon="${CYAN}▼${NC}"
            else
                type_icon="${CYAN}▶${NC}"
            fi
        else
            type_icon=" "
        fi

        local name_max=22
        local display_name="${RENDER_NAMES[$i]:0:$name_max}"

        if [[ "$i" -eq "$current" ]]; then
            printf '\r\033[2K  %s%s %-22s  %8s  %s\n' \
                "$indent" "${CYAN_BOLD}▶ ${type_icon} ${display_name}${NC}" "" "${CYAN_BOLD}${sz_human}${NC}" "${CYAN}${bar}${NC}"
        else
            printf '\r\033[2K  %s%s %-22s  %8s  %s\n' \
                "$indent" "  ${type_icon} ${display_name}" "" "${GRAY}${sz_human}${NC}" "${GRAY}${bar}${NC}"
        fi
    done

    # Fill empty lines
    local shown=$((end - offset))
    local fill
    for ((fill=shown; fill<page_h; fill++)); do
        printf '\r\033[2K\n'
    done

    # Footer
    local back_hint=""
    [[ ${#NAV_STACK[@]} -gt 0 ]] && back_hint="  |  ${GRAY}← Back${NC}"
    echo ""
    echo -e "  ${GRAY}↑↓ Navigate  |  Enter/→ Open folder  |  E Expand  |  D Delete→Trash  |  O Open  |  Q Quit${back_hint}${NC}"
    printf '\033[J'
}

# ── Main loop ─────────────────────────────────────────────────────────────────
scan_dir "$SCAN_PATH"
stty -echo -icanon intr ^C 2>/dev/null || true
hide_cursor

while true; do
    render_analyze
    local_count=${#RENDER_NAMES[@]}

    key=$(read_key 2>/dev/null || echo "QUIT")

    case "$key" in
        UP)
            ((current > 0)) && ((current--))
            ;;
        DOWN)
            ((current < local_count - 1)) && ((current++))
            ;;

        # Enter or → — drill into directory
        ENTER|RIGHT)
            if [[ "${RENDER_IS_CHILD[$current]:-false}" == "false" && \
                  "${RENDER_IS_DIR[$current]:-false}" == "true" ]]; then
                local drill_path="${RENDER_PATHS[$current]}"
                NAV_STACK+=("$SCAN_PATH")
                SCAN_PATH="$drill_path"
                scan_dir "$drill_path"
                stty -echo -icanon 2>/dev/null || true
            fi
            ;;

        # ← or Backspace — go back up
        LEFT|DELETE)
            if [[ ${#NAV_STACK[@]} -gt 0 ]]; then
                local last_idx=$(( ${#NAV_STACK[@]} - 1 ))
                SCAN_PATH="${NAV_STACK[$last_idx]}"
                unset 'NAV_STACK[$last_idx]'
                NAV_STACK=("${NAV_STACK[@]+"${NAV_STACK[@]}"}")
                scan_dir "$SCAN_PATH"
                stty -echo -icanon 2>/dev/null || true
            fi
            ;;

        # E — expand/collapse folder inline
        "CHAR:e"|"CHAR:E")
            local entry_idx="${RENDER_ENTRY_IDX[$current]}"
            if [[ "${RENDER_IS_CHILD[$current]:-false}" == "false" && \
                  "${RENDER_IS_DIR[$current]:-false}" == "true" ]]; then
                expand_entry "$entry_idx"
                stty -echo -icanon 2>/dev/null || true
            fi
            ;;

        # D — delete current item to Trash
        "CHAR:d"|"CHAR:D")
            local item_path="${RENDER_PATHS[$current]}"
            local item_name="${RENDER_NAMES[$current]}"
            local is_child="${RENDER_IS_CHILD[$current]:-false}"
            local entry_idx="${RENDER_ENTRY_IDX[$current]}"

            if trash_item "$item_path" "$item_name"; then
                if [[ "$is_child" == "true" ]]; then
                    # Remove from child arrays
                    local -a new_cn=() new_cp=() new_cs=() new_cpar=()
                    for j in "${!CHILD_NAMES[@]}"; do
                        [[ "$j" == "$entry_idx" ]] && continue
                        new_cn+=("${CHILD_NAMES[$j]}")
                        new_cp+=("${CHILD_PATHS[$j]}")
                        new_cs+=("${CHILD_SIZES[$j]}")
                        new_cpar+=("${CHILD_PARENT[$j]}")
                    done
                    CHILD_NAMES=("${new_cn[@]+"${new_cn[@]}"}") 
                    CHILD_PATHS=("${new_cp[@]+"${new_cp[@]}"}")
                    CHILD_SIZES=("${new_cs[@]+"${new_cs[@]}"}")
                    CHILD_PARENT=("${new_cpar[@]+"${new_cpar[@]}"}")
                else
                    # Remove from entry arrays
                    local -a new_en=() new_ep=() new_es=() new_ed=() new_ex=()
                    for j in "${!ENTRY_NAMES[@]}"; do
                        [[ "$j" == "$entry_idx" ]] && continue
                        new_en+=("${ENTRY_NAMES[$j]}")
                        new_ep+=("${ENTRY_PATHS[$j]}")
                        new_es+=("${ENTRY_SIZES[$j]}")
                        new_ed+=("${ENTRY_IS_DIR[$j]}")
                        new_ex+=("${ENTRY_EXPANDED[$j]}")
                    done
                    ENTRY_NAMES=("${new_en[@]+"${new_en[@]}"}") 
                    ENTRY_PATHS=("${new_ep[@]+"${new_ep[@]}"}")
                    ENTRY_SIZES=("${new_es[@]+"${new_es[@]}"}")
                    ENTRY_IS_DIR=("${new_ed[@]+"${new_ed[@]}"}")
                    ENTRY_EXPANDED=("${new_ex[@]+"${new_ex[@]}"}")
                fi
                build_render_list
                local new_count=${#RENDER_NAMES[@]}
                [[ $current -ge $new_count && $current -gt 0 ]] && ((current--))
                free_kb=$(get_free_space_kb 2>/dev/null || echo "$free_kb")
            fi
            stty -echo -icanon 2>/dev/null || true
            ;;

        # O — open in Finder
        "CHAR:o"|"CHAR:O")
            show_cursor
            open "${RENDER_PATHS[$current]}" 2>/dev/null || true
            hide_cursor
            ;;

        QUIT)
            break
            ;;
    esac
done

show_cursor
stty sane 2>/dev/null || true
echo ""
