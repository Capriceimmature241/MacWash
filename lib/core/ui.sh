#!/bin/bash
# MacWash - Terminal UI: cursor, keyboard input, spinner, menus.

set -euo pipefail
[[ -n "${MACWASH_UI_LOADED:-}" ]] && return 0
readonly MACWASH_UI_LOADED=1

_MACWASH_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MACWASH_BASE_LOADED:-}" ]] && source "$_MACWASH_CORE_DIR/base.sh"

# ── Cursor control ───────────────────────────────────────────────────────────
clear_screen() { printf '\033[2J\033[H'; }
hide_cursor()  { [[ -t 1 ]] && printf '\033[?25l' >&2 || true; }
show_cursor()  { [[ -t 1 ]] && printf '\033[?25h' >&2 || true; }

safe_clear_lines() {
    local n="${1:-1}"
    local i
    for ((i=0; i<n; i++)); do
        printf '\033[1A\r\033[2K' >&2 || true
    done
}

# ── is ANSI supported ────────────────────────────────────────────────────────
is_ansi_supported() {
    [[ -t 1 ]] || return 1
    local t; t=$(tput colors 2>/dev/null || echo "0")
    [[ "$t" =~ ^[0-9]+$ && "$t" -ge 8 ]]
}

# ── Menu option rendering ────────────────────────────────────────────────────
show_menu_option() {
    local number="$1" text="$2" selected="$3"
    if [[ "$selected" == "true" ]]; then
        echo -e "  ${CYAN_BOLD}${ICON_ARROW} $number. $text${NC}"
    else
        echo "    $number. $text"
    fi
}

# ── Keyboard input ───────────────────────────────────────────────────────────
read_key() {
    local key rest
    IFS= read -r -s -n1 key
    [[ $? -ne 0 ]] && { echo "QUIT"; return 0; }
    [[ -z "$key" ]] && { echo "ENTER"; return 0; }
    case "$key" in
        $'\n'|$'\r') echo "ENTER" ;;
        ' ')         echo "SPACE" ;;
        'q'|'Q')     echo "QUIT"  ;;
        'j'|'J')     echo "DOWN"  ;;
        'k'|'K')     echo "UP"    ;;
        'h'|'H')     echo "LEFT"  ;;
        'l'|'L')     echo "RIGHT" ;;
        'v'|'V')     echo "VERSION" ;;
        'u'|'U')     echo "UPDATE"  ;;
        'G')         echo "BOTTOM" ;;
        'g')
            if IFS= read -r -s -n1 -t 0.3 rest 2>/dev/null; then
                [[ "$rest" == "g" ]] && echo "TOP" || echo "OTHER"
            else
                echo "OTHER"
            fi ;;
        $'\x03')     echo "QUIT" ;;
        $'\x7f'|$'\x08') echo "DELETE" ;;
        $'\x1b')
            if IFS= read -r -s -n1 -t 1 rest 2>/dev/null && [[ "$rest" == "[" ]]; then
                if IFS= read -r -s -n1 -t 1 rest 2>/dev/null; then
                    case "$rest" in
                        A) echo "UP"    ;; B) echo "DOWN"  ;;
                        C) echo "RIGHT" ;; D) echo "LEFT"  ;;
                        *) echo "OTHER" ;;
                    esac
                else echo "QUIT"; fi
            else echo "QUIT"; fi ;;
        [[:print:]]) echo "CHAR:$key" ;;
        *)           echo "OTHER" ;;
    esac
}

drain_pending_input() {
    local t="${1:-0.01}"
    local n=0
    while IFS= read -r -s -n1 -t "$t" _ 2>/dev/null; do
        ((n++)); [[ $n -gt 100 ]] && break; t="0.01"
    done
    return 0
}

# ── Inline spinner ────────────────────────────────────────────────────────────
MACWASH_SPINNER_PID=""
MACWASH_SPINNER_STOP_FILE=""
MACWASH_SPINNER_MSG_FILE=""
MACWASH_SPINNER_DIR=""

_macwash_spinner_chars() { printf '%s' '|/-\'; }

start_inline_spinner() {
    stop_inline_spinner 2>/dev/null || true
    local message="$1"

    [[ -t 1 ]] || { echo -n "  ${BLUE}|${NC} $message" >&2; return 0; }

    local ctrl_dir
    ctrl_dir=$(mktemp -d "${TMPDIR:-/tmp}/.macwash-spinner.XXXXXX") || return 0
    MACWASH_SPINNER_DIR="$ctrl_dir"
    MACWASH_TEMP_DIRS+=("$ctrl_dir")
    MACWASH_SPINNER_STOP_FILE="$ctrl_dir/stop"
    MACWASH_SPINNER_MSG_FILE="$ctrl_dir/message"
    printf '%s\n' "$message" > "$MACWASH_SPINNER_MSG_FILE"

    (
        local stop="$MACWASH_SPINNER_STOP_FILE"
        local msgf="$MACWASH_SPINNER_MSG_FILE"
        local chars; chars=$(_macwash_spinner_chars)
        local i=0 cur="$message" nxt=""
        printf '\r\033[2K' >&2
        while [[ ! -f "$stop" ]]; do
            local c="${chars:$((i % ${#chars})):1}"
            if [[ -f "$msgf" && -r "$msgf" ]]; then
                IFS= read -r nxt < "$msgf" 2>/dev/null || nxt=""
                [[ -n "$nxt" ]] && cur="$nxt"
            fi
            printf '\r  %s%s%s %s' "$BLUE" "$c" "$NC" "$cur" >&2
            i=$((i+1)); /bin/sleep 0.05
        done
        rm -f "$stop" 2>/dev/null; exit 0
    ) &
    MACWASH_SPINNER_PID=$!
    disown "$MACWASH_SPINNER_PID" 2>/dev/null || true
}

stop_inline_spinner() {
    [[ -n "$MACWASH_SPINNER_PID" ]] || return 0
    [[ -n "$MACWASH_SPINNER_STOP_FILE" ]] && touch "$MACWASH_SPINNER_STOP_FILE" 2>/dev/null || true
    local w=0
    while kill -0 "$MACWASH_SPINNER_PID" 2>/dev/null && [[ $w -lt 5 ]]; do
        /bin/sleep 0.05; w=$((w+1))
    done
    kill -KILL "$MACWASH_SPINNER_PID" 2>/dev/null || true
    wait "$MACWASH_SPINNER_PID" 2>/dev/null || true
    [[ -t 1 ]] && printf '\r\033[2K' >&2 || true
    MACWASH_SPINNER_PID=""; MACWASH_SPINNER_STOP_FILE=""; MACWASH_SPINNER_MSG_FILE=""; MACWASH_SPINNER_DIR=""
}
