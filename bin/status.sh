#!/bin/bash
# MacWash - Status command: live system health dashboard.

set -euo pipefail
export LC_ALL=C LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

JSON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --help|-h) show_help; exit 0 ;;
    esac
done

# Auto JSON when piped
[[ -t 1 ]] || JSON_MODE=true

trap 'show_cursor; cleanup_temp_files' EXIT
trap 'show_cursor; cleanup_temp_files; exit 130' INT TERM

# ── Metric collectors ─────────────────────────────────────────────────────────
_cpu_usage() {
    top -l 2 -n 0 2>/dev/null | awk '/CPU usage/{last=$0} END{
        match(last, /([0-9.]+)% user.*([0-9.]+)% sys/, a)
        printf "%.1f", a[1]+a[2]
    }' 2>/dev/null || echo "0.0"
}

_mem_stats() {
    local pages_free pages_active pages_inactive pages_speculative pages_wired page_size
    pages_free=$(sysctl -n vm.page_free_count 2>/dev/null || echo 0)
    pages_active=$(sysctl -n vm.page_active_count 2>/dev/null || echo 0)
    pages_inactive=$(sysctl -n vm.page_inactive_count 2>/dev/null || echo 0)
    pages_wired=$(sysctl -n vm.page_wire_count 2>/dev/null || echo 0)
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    local mem_total; mem_total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)

    local used=$(( (pages_active + pages_wired + pages_inactive) * page_size ))
    local total="$mem_total"
    local pct=0
    [[ "$total" -gt 0 ]] && pct=$(( used * 100 / total ))

    local total_gb=$(( total / 1024 / 1024 / 1024 ))
    local used_gb=$(( used / 1024 / 1024 / 1024 ))
    echo "$used_gb $total_gb $pct"
}

_disk_stats() {
    local free_kb; free_kb=$(get_free_space_kb 2>/dev/null || echo 0)
    local total_kb; total_kb=$(df -Pk / 2>/dev/null | awk 'NR==2{print $2}' || echo 0)
    [[ "$total_kb" =~ ^[0-9]+$ ]] || total_kb=0
    local used_kb=$(( total_kb - free_kb ))
    local pct=0
    [[ "$total_kb" -gt 0 ]] && pct=$(( used_kb * 100 / total_kb ))
    local free_gb=$(( free_kb / 1024 / 1024 ))
    local total_gb=$(( total_kb / 1024 / 1024 ))
    echo "$free_gb $total_gb $pct"
}

_uptime_str() {
    local boot; boot=$(sysctl -n kern.boottime 2>/dev/null | grep -oE 'sec = [0-9]+' | grep -oE '[0-9]+' || echo 0)
    local now; now=$(get_epoch_seconds)
    local elapsed=$(( now - boot ))
    local days=$(( elapsed / 86400 ))
    local hours=$(( (elapsed % 86400) / 3600 ))
    printf '%dd %dh' "$days" "$hours"
}

_battery_pct() {
    pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%' || echo "?"
}

_health_score() {
    local cpu="$1" mem_pct="$2" disk_pct="$3"
    local score=100
    # Penalize high usage
    [[ "$cpu" =~ ^[0-9]+(\.[0-9]+)?$ ]] && {
        local cpu_int=${cpu%.*}
        [[ "$cpu_int" -gt 80 ]] && score=$((score - 20))
        [[ "$cpu_int" -gt 60 ]] && score=$((score - 10))
    }
    [[ "$mem_pct" -gt 85 ]] && score=$((score - 20))
    [[ "$mem_pct" -gt 70 ]] && score=$((score - 10))
    [[ "$disk_pct" -gt 90 ]] && score=$((score - 20))
    [[ "$disk_pct" -gt 75 ]] && score=$((score - 10))
    echo "$score"
}

_bar() {
    local pct="${1:-0}" width="${2:-20}"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    local filled=$(( pct * width / 100 ))
    [[ "$filled" -gt "$width" ]] && filled=$width
    local empty=$(( width - filled ))
    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf '%s' "$bar"
}

# ── Collect ───────────────────────────────────────────────────────────────────
CPU_USAGE=$(_cpu_usage)
read -r MEM_USED_GB MEM_TOTAL_GB MEM_PCT <<< "$(_mem_stats)"
read -r DISK_FREE_GB DISK_TOTAL_GB DISK_PCT <<< "$(_disk_stats)"
UPTIME=$(_uptime_str)
BATTERY=$(_battery_pct)
CPU_INT=${CPU_USAGE%.*}
HEALTH=$(_health_score "${CPU_INT:-0}" "${MEM_PCT:-0}" "${DISK_PCT:-0}")

# Hostname + arch
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
ARCH=$(detect_arch)
MACOS=$(sw_vers -productVersion 2>/dev/null || echo "?")

# ── JSON mode ─────────────────────────────────────────────────────────────────
if [[ "$JSON_MODE" == "true" ]]; then
    cat <<EOF
{
  "host": "$HOST",
  "arch": "$ARCH",
  "macos": "$MACOS",
  "uptime": "$UPTIME",
  "health_score": $HEALTH,
  "cpu": {"usage": $CPU_USAGE},
  "memory": {"used_gb": $MEM_USED_GB, "total_gb": $MEM_TOTAL_GB, "used_percent": $MEM_PCT},
  "disk":   {"free_gb": $DISK_FREE_GB, "total_gb": $DISK_TOTAL_GB, "used_percent": $DISK_PCT},
  "battery": {"percent": "$BATTERY"}
}
EOF
    exit 0
fi

# ── Live TUI mode ─────────────────────────────────────────────────────────────
hide_cursor
_render() {
    printf '\033[H'
    # Health color
    local hcolor="$GREEN"
    [[ "$HEALTH" -lt 70 ]] && hcolor="$YELLOW"
    [[ "$HEALTH" -lt 50 ]] && hcolor="$RED"

    echo -e "${CYAN_BOLD}  ◈ MacWash  Status${NC}  ${GRAY}Health ${hcolor}● $HEALTH${NC}  ${GRAY}$HOST · $ARCH · macOS $MACOS · up $UPTIME${NC}"
    echo ""

    # CPU card
    echo -e "  ${CYAN_BOLD}⚙ CPU${NC}"
    echo -e "  Total   $(_bar "$CPU_INT")  ${CPU_USAGE}%"
    echo ""

    # Memory card
    echo -e "  ${CYAN_BOLD}▦ Memory${NC}"
    echo -e "  Used    $(_bar "$MEM_PCT")  ${MEM_PCT}%  (${MEM_USED_GB}/${MEM_TOTAL_GB} GB)"
    echo ""

    # Disk card
    echo -e "  ${CYAN_BOLD}▤ Disk${NC}"
    echo -e "  Used    $(_bar "$DISK_PCT")  ${DISK_PCT}%  ·  ${DISK_FREE_GB} GB free of ${DISK_TOTAL_GB} GB"
    echo ""

    # Battery
    echo -e "  ${CYAN_BOLD}⚡ Battery${NC}"
    local batt_pct=0
    [[ "$BATTERY" =~ ^[0-9]+$ ]] && batt_pct="$BATTERY"
    echo -e "  Level   $(_bar "$batt_pct")  ${BATTERY}%"
    echo ""

    # Top processes
    echo -e "  ${CYAN_BOLD}▶ Top Processes${NC}"
    ps -Acro pid,pcpu,pmem,comm 2>/dev/null | head -8 | tail -7 | \
        awk '{printf "  %-6s  CPU:%-6s  MEM:%-6s  %s\n", $1, $2"%", $3"%", $4}' || true
    echo ""
    echo -e "  ${GRAY}Q Quit  ·  Refreshes every 2s${NC}"
    printf '\033[J'
}

while true; do
    # Re-collect every cycle
    CPU_USAGE=$(_cpu_usage)
    read -r MEM_USED_GB MEM_TOTAL_GB MEM_PCT <<< "$(_mem_stats)"
    read -r DISK_FREE_GB DISK_TOTAL_GB DISK_PCT <<< "$(_disk_stats)"
    CPU_INT=${CPU_USAGE%.*}
    HEALTH=$(_health_score "${CPU_INT:-0}" "${MEM_PCT:-0}" "${DISK_PCT:-0}")
    _render

    # Non-blocking key check with 2s timeout
    key=""
    IFS= read -r -s -n1 -t 2 key 2>/dev/null || true
    [[ "$key" == "q" || "$key" == "Q" || "$key" == $'\x03' ]] && break
done

show_cursor
echo ""
