#!/bin/bash
# MacWash - Status command: live system health dashboard.

set -euo pipefail
export LC_ALL=C LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

JSON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --json)    JSON_MODE=true ;;
        --help|-h) show_help; exit 0 ;;
    esac
done
[[ -t 1 ]] || JSON_MODE=true

trap 'show_cursor; cleanup_temp_files; stty sane 2>/dev/null || true; echo ""' EXIT
trap 'show_cursor; cleanup_temp_files; stty sane 2>/dev/null || true; echo ""; exit 130' INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# Metric collectors
# ─────────────────────────────────────────────────────────────────────────────

_cpu_usage() {
    # Use vm.loadavg for instant reading instead of slow top -l 2
    local load1
    load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); print $1}')
    local ncpu; ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    [[ "$ncpu" =~ ^[0-9]+$ && $ncpu -gt 0 ]] || ncpu=1
    # Convert load to percentage (capped at 100)
    local pct; pct=$(awk "BEGIN{v=$load1/$ncpu*100; if(v>100)v=100; printf \"%.1f\",v}" 2>/dev/null || echo "0.0")
    echo "$pct"
}

_cpu_load() {
    sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); printf "%s / %s / %s", $1, $2, $3}'
}

_cpu_cores() {
    local logical; logical=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
    local physical; physical=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "?")
    echo "$logical logical, $physical physical"
}

_mem_stats() {
    local mem_total; mem_total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    local page_size; page_size=$(vm_stat 2>/dev/null | awk '/page size/{gsub(/[^0-9]/,"",$NF); print $NF}')
    [[ "$page_size" =~ ^[0-9]+$ && $page_size -gt 0 ]] || page_size=16384

    local pages_active pages_wired pages_compressed
    pages_active=$(vm_stat 2>/dev/null | awk '/Pages active/{gsub(/\./,"",$NF); print $NF+0}')
    pages_wired=$(vm_stat 2>/dev/null | awk '/Pages wired down/{gsub(/\./,"",$NF); print $NF+0}')
    pages_compressed=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/{gsub(/\./,"",$NF); print $NF+0}')
    [[ "$pages_active" =~ ^[0-9]+$ ]] || pages_active=0
    [[ "$pages_wired" =~ ^[0-9]+$ ]] || pages_wired=0
    [[ "$pages_compressed" =~ ^[0-9]+$ ]] || pages_compressed=0

    local used=$(( (pages_active + pages_wired + pages_compressed) * page_size ))
    local pct=0
    [[ $mem_total -gt 0 ]] && pct=$(( used * 100 / mem_total ))
    [[ $pct -gt 100 ]] && pct=100
    local total_gb=$(( mem_total / 1024 / 1024 / 1024 ))
    local used_dec; used_dec=$(awk "BEGIN{printf \"%.1f\", $used/1073741824}")
    echo "$used_dec $total_gb $pct"
}

_swap_stats() {
    local raw; raw=$(sysctl vm.swapusage 2>/dev/null || echo "")
    local used total
    used=$(echo "$raw" | grep -oE 'used = [0-9.]+M' | grep -oE '[0-9.]+' | head -1 || echo "0")
    total=$(echo "$raw" | grep -oE 'total = [0-9.]+M' | grep -oE '[0-9.]+' | head -1 || echo "0")
    used=$(printf "%.0f" "${used:-0}")
    total=$(printf "%.0f" "${total:-0}")
    echo "$used $total"
}

_mem_pressure() {
    memory_pressure -Q 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%' || echo "?"
}

_disk_stats() {
    local target="/"
    [[ -d "/System/Volumes/Data" ]] && target="/System/Volumes/Data"
    local line; line=$(df -Pk "$target" 2>/dev/null | awk 'NR==2{print $2,$4}')
    local total_kb free_kb
    total_kb=$(echo "$line" | awk '{print $1}')
    free_kb=$(echo "$line" | awk '{print $2}')
    [[ "$total_kb" =~ ^[0-9]+$ && $total_kb -gt 0 ]] || total_kb=1
    [[ "$free_kb" =~ ^[0-9]+$ ]] || free_kb=0
    local used_kb=$(( total_kb - free_kb ))
    local pct=$(( used_kb * 100 / total_kb ))
    local free_gb=$(( free_kb / 1024 / 1024 ))
    local total_gb=$(( total_kb / 1024 / 1024 ))
    local free_dec; free_dec=$(awk "BEGIN{printf \"%.0f\", $free_kb/1048576}")
    echo "$free_dec $total_gb $pct"
}

_battery_stats() {
    local raw; raw=$(pmset -g batt 2>/dev/null || echo "")
    local pct="?" status="?" time_left=""
    pct=$(echo "$raw" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
    [[ "$pct" =~ ^[0-9]+$ ]] || pct="?"

    if echo "$raw" | grep -q "AC Power"; then
        if echo "$raw" | grep -qi "charging"; then
            status="Charging"
        else
            status="Charged"
        fi
    elif echo "$raw" | grep -qi "discharging"; then
        status="On Battery"
        time_left=$(echo "$raw" | grep -oE '[0-9]+:[0-9]+ remaining' | sed 's/ remaining//' | head -1)
    else
        status="Unknown"
    fi

    # Battery health from ioreg
    local design max health_pct="?"
    local ioreg_out; ioreg_out=$(ioreg -l -n AppleSmartBattery 2>/dev/null | grep -E '"CycleCount" = |"Temperature" = |"DesignCapacity" = |"AppleRawMaxCapacity" = ' || true)
    design=$(echo "$ioreg_out" | grep '"DesignCapacity"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    max=$(echo "$ioreg_out" | grep '"AppleRawMaxCapacity"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$design" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ && $design -gt 0 ]] && \
        health_pct=$(awk "BEGIN{printf \"%.0f\", $max/$design*100}")

    # Cycle count
    local cycles
    cycles=$(echo "$ioreg_out" | grep '"CycleCount"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$cycles" =~ ^[0-9]+$ ]] || cycles="?"

    # Temperature
    local temp_raw temp_c="?"
    temp_raw=$(echo "$ioreg_out" | grep '"Temperature"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$temp_raw" =~ ^[0-9]+$ ]] && temp_c=$(awk "BEGIN{printf \"%.0f\", $temp_raw/100}")

    echo "${pct}|${status}|${time_left}|${health_pct}|${cycles}|${temp_c}"
}

_network_stats() {
    # Get the primary interface
    local iface; iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1)
    [[ -z "$iface" ]] && iface="en0"

    # Get current bytes
    local line; line=$(netstat -ib 2>/dev/null | awk -v iface="$iface" '$1==iface && $3!~/Link/{print $7,$10; exit}')
    local rx1 tx1
    rx1=$(echo "$line" | awk '{print $1}')
    tx1=$(echo "$line" | awk '{print $2}')
    [[ "$rx1" =~ ^[0-9]+$ ]] || rx1=0
    [[ "$tx1" =~ ^[0-9]+$ ]] || tx1=0

    sleep 1

    local line2; line2=$(netstat -ib 2>/dev/null | awk -v iface="$iface" '$1==iface && $3!~/Link/{print $7,$10; exit}')
    local rx2 tx2
    rx2=$(echo "$line2" | awk '{print $1}')
    tx2=$(echo "$line2" | awk '{print $2}')
    [[ "$rx2" =~ ^[0-9]+$ ]] || rx2=0
    [[ "$tx2" =~ ^[0-9]+$ ]] || tx2=0

    local rx_speed=$(( (rx2 - rx1) ))
    local tx_speed=$(( (tx2 - tx1) ))
    [[ $rx_speed -lt 0 ]] && rx_speed=0
    [[ $tx_speed -lt 0 ]] && tx_speed=0

    # Format speed
    local rx_human tx_human
    rx_human=$(awk "BEGIN{
        v=$rx_speed
        if(v>=1048576) printf \"%.1f MB/s\",v/1048576
        else if(v>=1024) printf \"%.0f KB/s\",v/1024
        else printf \"%d B/s\",v
    }")
    tx_human=$(awk "BEGIN{
        v=$tx_speed
        if(v>=1048576) printf \"%.1f MB/s\",v/1048576
        else if(v>=1024) printf \"%.0f KB/s\",v/1024
        else printf \"%d B/s\",v
    }")

    echo "$iface $rx_human $tx_human"
}

_uptime_str() {
    local boot
    boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\),.*/\1/p' | tr -d '[:space:]')
    [[ "$boot" =~ ^[0-9]+$ ]] || boot=0
    local now; now=$(get_epoch_seconds)
    local elapsed=$(( now - boot ))
    [[ $elapsed -lt 0 ]] && elapsed=0
    local days=$(( elapsed / 86400 ))
    local hours=$(( (elapsed % 86400) / 3600 ))
    local mins=$(( (elapsed % 3600) / 60 ))
    [[ $days -gt 0 ]] && printf '%dd %dh' "$days" "$hours" || printf '%dh %dm' "$hours" "$mins"
}

_health_score() {
    local cpu_pct="$1" mem_pct="$2" disk_pct="$3" swap_used="$4" swap_total="$5"
    local score=100
    local ci="${cpu_pct%.*}"
    [[ "$ci" =~ ^[0-9]+$ ]] || ci=0
    [[ $ci -gt 90 ]] && score=$((score-25))
    [[ $ci -gt 70 ]] && score=$((score-10))
    [[ $mem_pct -gt 90 ]] && score=$((score-20))
    [[ $mem_pct -gt 75 ]] && score=$((score-10))
    [[ $disk_pct -gt 95 ]] && score=$((score-20))
    [[ $disk_pct -gt 85 ]] && score=$((score-10))
    if [[ "$swap_total" =~ ^[0-9]+$ && "$swap_used" =~ ^[0-9]+$ && $swap_total -gt 0 ]]; then
        local swap_pct=$(( swap_used * 100 / swap_total ))
        [[ $swap_pct -gt 80 ]] && score=$((score-10))
    fi
    [[ $score -lt 0 ]] && score=0
    echo "$score"
}

_bar() {
    local pct="${1:-0}" width="${2:-24}" color="${3:-}"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    [[ $pct -gt 100 ]] && pct=100
    local filled=$(( pct * width / 100 ))
    [[ $filled -gt $width ]] && filled=$width
    local empty=$(( width - filled ))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    [[ -n "$color" ]] && printf '%s%s%s' "$color" "$bar" "$NC" || printf '%s' "$bar"
}

_color_for_pct() {
    local pct="${1:-0}" invert="${2:-false}"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    if [[ "$invert" == "true" ]]; then
        [[ $pct -lt 20 ]] && echo "$RED" && return
        [[ $pct -lt 50 ]] && echo "$YELLOW" && return
        echo "$GREEN"
    else
        [[ $pct -gt 85 ]] && echo "$RED" && return
        [[ $pct -gt 60 ]] && echo "$YELLOW" && return
        echo "$GREEN"
    fi
}

_top_processes() {
    # Use ps with RSS (memory in KB) for accurate MB display
    ps -Acro pid,pcpu,pmem,rss,comm 2>/dev/null | awk 'NR>1 && NF>=5 {
        pid=$1; cpu=$2; mem=$3; rss=$4
        name=""
        for(i=5;i<=NF;i++) name=(i==5)?$i:name" "$i
        # Strip only leading bundle prefix noise — preserve real name
        gsub(/^com\.apple\./,"",name)
        # Convert RSS KB to MB
        mb = rss/1024
        # Truncate to 28 chars max
        if(length(name)>28) name=substr(name,1,25)"..."
        # CPU mini bar (1 block per 10%)
        bar=""
        n=int(cpu/10); if(n>8)n=8; if(n<0)n=0
        for(j=0;j<n;j++) bar=bar"▮"
        for(j=n;j<8;j++) bar=bar"▯"
        printf "  %-6s  %-28s  %5s%%  %5s%%  %5.1fMB  %s\n", pid, name, cpu, mem, mb, bar
    }' | head -10
}

# ─────────────────────────────────────────────────────────────────────────────
# Collect all metrics
# ─────────────────────────────────────────────────────────────────────────────
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
ARCH=$(detect_arch)
MACOS=$(sw_vers -productVersion 2>/dev/null || echo "?")

_collect() {
    CPU_PCT=$(_cpu_usage)
    CPU_LOAD=$(_cpu_load)
    CPU_CORES=$(_cpu_cores)
    read -r MEM_USED MEM_TOTAL MEM_PCT <<< "$(_mem_stats)"
    read -r SWAP_USED SWAP_TOTAL <<< "$(_swap_stats)"
    MEM_PRESSURE=$(_mem_pressure)
    read -r DISK_FREE DISK_TOTAL DISK_PCT <<< "$(_disk_stats)"
    read -r BATT_PCT BATT_STATUS BATT_TIME BATT_HEALTH BATT_CYCLES BATT_TEMP <<< "$(IFS='|'; _battery_stats | tr '|' ' ')"
    # Re-parse with | delimiter for accuracy
    local batt_raw; batt_raw=$(_battery_stats)
    BATT_PCT=$(echo "$batt_raw" | cut -d'|' -f1)
    BATT_STATUS=$(echo "$batt_raw" | cut -d'|' -f2)
    BATT_TIME=$(echo "$batt_raw" | cut -d'|' -f3)
    BATT_HEALTH=$(echo "$batt_raw" | cut -d'|' -f4)
    BATT_CYCLES=$(echo "$batt_raw" | cut -d'|' -f5)
    BATT_TEMP=$(echo "$batt_raw" | cut -d'|' -f6)
    UPTIME=$(_uptime_str)
    CPU_INT="${CPU_PCT%.*}"; [[ "$CPU_INT" =~ ^[0-9]+$ ]] || CPU_INT=0
    [[ "$MEM_PCT" =~ ^[0-9]+$ ]] || MEM_PCT=0
    [[ "$DISK_PCT" =~ ^[0-9]+$ ]] || DISK_PCT=0
    HEALTH=$(_health_score "$CPU_INT" "$MEM_PCT" "$DISK_PCT" "${SWAP_USED:-0}" "${SWAP_TOTAL:-1}")
}

# JSON mode
if [[ "$JSON_MODE" == "true" ]]; then
    _collect
    cat <<EOF
{
  "host": "$HOST", "arch": "$ARCH", "macos": "$MACOS", "uptime": "$UPTIME",
  "health_score": $HEALTH,
  "cpu": {"usage_pct": $CPU_PCT, "load": "$CPU_LOAD"},
  "memory": {"used_gb": $MEM_USED, "total_gb": $MEM_TOTAL, "used_pct": $MEM_PCT, "pressure_pct": "$MEM_PRESSURE"},
  "swap": {"used_mb": ${SWAP_USED:-0}, "total_mb": ${SWAP_TOTAL:-0}},
  "disk": {"free_gb": $DISK_FREE, "total_gb": $DISK_TOTAL, "used_pct": $DISK_PCT},
  "battery": {"pct": "$BATT_PCT", "status": "$BATT_STATUS", "health_pct": "$BATT_HEALTH", "cycles": "$BATT_CYCLES", "temp_c": "$BATT_TEMP"}
}
EOF
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Render
# ─────────────────────────────────────────────────────────────────────────────
_divider() { echo -e "  ${GRAY}$(printf '─%.0s' {1..60})${NC}"; }

_render() {
    printf '\033[H\033[J'

    # ── Header ────────────────────────────────────────────────────────────────
    local hcolor="$GREEN"
    [[ $HEALTH -lt 70 ]] && hcolor="$YELLOW"
    [[ $HEALTH -lt 50 ]] && hcolor="$RED"
    local hlabel="Excellent"
    [[ $HEALTH -lt 90 ]] && hlabel="Good"
    [[ $HEALTH -lt 70 ]] && hlabel="Fair"
    [[ $HEALTH -lt 50 ]] && hlabel="Poor"

    echo -e "${CYAN_BOLD}  ◈ MacWash  Status${NC}  ${hcolor}● Health $HEALTH  $hlabel${NC}"
    echo -e "  ${GRAY}$HOST  ·  $ARCH  ·  macOS $MACOS  ·  up $UPTIME${NC}"
    _divider
    echo ""

    # ── CPU ───────────────────────────────────────────────────────────────────
    local cpu_color; cpu_color=$(_color_for_pct "$CPU_INT")
    printf '  %-10s' "${CYAN_BOLD}⚙ CPU${NC}"
    printf '  %s  ' "$(_bar "$CPU_INT" 24 "$cpu_color")"
    printf '%s%s%%%s' "$cpu_color" "$CPU_PCT" "$NC"
    printf '   %sLoad: %s%s\n' "$GRAY" "$CPU_LOAD" "$NC"
    printf '  %s%s%s\n' "$GRAY" "           Cores: $CPU_CORES" "$NC"
    echo ""

    # ── Memory ────────────────────────────────────────────────────────────────
    local mem_color; mem_color=$(_color_for_pct "$MEM_PCT")
    local swap_pct=0
    [[ "${SWAP_TOTAL:-0}" =~ ^[0-9]+$ && ${SWAP_TOTAL:-0} -gt 0 ]] && \
        swap_pct=$(( ${SWAP_USED:-0} * 100 / ${SWAP_TOTAL:-1} ))
    printf '  %-10s' "${CYAN_BOLD}▦ Memory${NC}"
    printf '  %s  ' "$(_bar "$MEM_PCT" 24 "$mem_color")"
    printf '%s%s%%%s' "$mem_color" "$MEM_PCT" "$NC"
    printf '   %s%s / %s GB  ·  pressure %s%%%s\n' "$GRAY" "$MEM_USED" "$MEM_TOTAL" "$MEM_PRESSURE" "$NC"
    local swap_color; swap_color=$(_color_for_pct "$swap_pct")
    printf '  %sSwap%s      %s  %s%s MB used of %s MB%s\n' \
        "$GRAY" "$NC" \
        "$(_bar "$swap_pct" 24 "$swap_color")" \
        "$swap_color" "${SWAP_USED:-0}" "${SWAP_TOTAL:-0}" "$NC"
    echo ""

    # ── Disk ──────────────────────────────────────────────────────────────────
    local disk_color; disk_color=$(_color_for_pct "$DISK_PCT")
    printf '  %-10s' "${CYAN_BOLD}▤ Disk${NC}"
    printf '  %s  ' "$(_bar "$DISK_PCT" 24 "$disk_color")"
    printf '%s%s%%%s' "$disk_color" "$DISK_PCT" "$NC"
    printf '   %s%s GB free of %s GB%s\n' "$GRAY" "$DISK_FREE" "$DISK_TOTAL" "$NC"
    echo ""

    # ── Battery ───────────────────────────────────────────────────────────────
    local batt_int=0
    [[ "$BATT_PCT" =~ ^[0-9]+$ ]] && batt_int=$BATT_PCT
    local batt_color; batt_color=$(_color_for_pct "$batt_int" true)
    local batt_extra=""
    [[ -n "${BATT_TIME:-}" ]] && batt_extra="  ${GRAY}${BATT_TIME} left${NC}"
    printf '  %-10s' "${CYAN_BOLD}⚡ Battery${NC}"
    printf '  %s  ' "$(_bar "$batt_int" 24 "$batt_color")"
    printf '%s%s%%%s' "$batt_color" "$BATT_PCT" "$NC"
    printf '   %s%s%s%s\n' "$GRAY" "$BATT_STATUS" "$NC" "$batt_extra"

    local batt_details=""
    [[ "${BATT_HEALTH:-?}" != "?" ]] && batt_details+="health ${BATT_HEALTH}%"
    [[ "${BATT_CYCLES:-?}" != "?" ]] && batt_details+="  ·  ${BATT_CYCLES} cycles"
    [[ "${BATT_TEMP:-?}" != "?" ]] && batt_details+="  ·  ${BATT_TEMP}°C"
    [[ -n "$batt_details" ]] && echo -e "             ${GRAY}${batt_details}${NC}"
    echo ""

    # ── Network ───────────────────────────────────────────────────────────────
    printf '  %-10s' "${CYAN_BOLD}⇅ Network${NC}"
    printf '  %s%s%s\n' "$GRAY" "  ↓ $NET_RX  ↑ $NET_TX  [$NET_IFACE]" "$NC"
    echo ""

    # ── Top Processes ─────────────────────────────────────────────────────────
    _divider
    printf '  %s%-6s  %-28s  %6s  %6s  %7s  %s%s\n' \
        "${CYAN_BOLD}" "PID" "Process" "CPU" "MEM" "Memory" "Activity" "${NC}"
    echo -e "  ${GRAY}$(printf '─%.0s' {1..68})${NC}"
    _top_processes
    echo ""

    # ── Footer ────────────────────────────────────────────────────────────────
    _divider
    local ts; ts=$(date '+%H:%M:%S' 2>/dev/null || echo "")
    echo -e "  ${GRAY}Q Quit  ·  Live refresh  ·  Updated: ${ts}${NC}"
    printf '\033[J'
}

# ─────────────────────────────────────────────────────────────────────────────
# Main loop — truly live, refreshes every 3 seconds
# ─────────────────────────────────────────────────────────────────────────────
clear_screen
stty -echo -icanon intr ^C 2>/dev/null || true
hide_cursor

NET_IFACE="en0"; NET_RX="-- KB/s"; NET_TX="-- KB/s"

# Start background network sampler — writes to temp file every 3s
NET_TMP=$(create_temp_file)
(
    while true; do
        iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1)
        [[ -z "$iface" ]] && iface="en0"
        line1=$(netstat -ib 2>/dev/null | awk -v i="$iface" '$1==i && $3!~/Link/{print $7,$10; exit}')
        rx1=$(echo "$line1" | awk '{print $1}'); tx1=$(echo "$line1" | awk '{print $2}')
        [[ "$rx1" =~ ^[0-9]+$ ]] || rx1=0; [[ "$tx1" =~ ^[0-9]+$ ]] || tx1=0
        sleep 1
        line2=$(netstat -ib 2>/dev/null | awk -v i="$iface" '$1==i && $3!~/Link/{print $7,$10; exit}')
        rx2=$(echo "$line2" | awk '{print $1}'); tx2=$(echo "$line2" | awk '{print $2}')
        [[ "$rx2" =~ ^[0-9]+$ ]] || rx2=0; [[ "$tx2" =~ ^[0-9]+$ ]] || tx2=0
        rx_speed=$(( rx2 - rx1 )); tx_speed=$(( tx2 - tx1 ))
        [[ $rx_speed -lt 0 ]] && rx_speed=0; [[ $tx_speed -lt 0 ]] && tx_speed=0
        rx_h=$(awk "BEGIN{v=$rx_speed; if(v>=1048576) printf \"%.1f MB/s\",v/1048576; else if(v>=1024) printf \"%.0f KB/s\",v/1024; else printf \"%d B/s\",v}")
        tx_h=$(awk "BEGIN{v=$tx_speed; if(v>=1048576) printf \"%.1f MB/s\",v/1048576; else if(v>=1024) printf \"%.0f KB/s\",v/1024; else printf \"%d B/s\",v}")
        printf '%s|%s|%s\n' "$iface" "$rx_h" "$tx_h" > "$NET_TMP"
        sleep 2
    done
) 2>/dev/null &
NET_BG_PID=$!
disown "$NET_BG_PID" 2>/dev/null || true

# Initial collect
_collect

while true; do
    # Read network from background sampler
    if [[ -s "$NET_TMP" ]]; then
        NET_IFACE=$(cut -d'|' -f1 "$NET_TMP")
        NET_RX=$(cut -d'|' -f2 "$NET_TMP")
        NET_TX=$(cut -d'|' -f3 "$NET_TMP")
    fi

    _render

    # Non-blocking key check — 3s timeout for live refresh
    key=""
    IFS= read -r -s -n1 -t 3 key 2>/dev/null || true
    case "$key" in
        q|Q|$'\x03') break ;;
    esac

    # Recollect metrics
    _collect
done

# Cleanup background sampler
kill "$NET_BG_PID" 2>/dev/null || true
wait "$NET_BG_PID" 2>/dev/null || true

show_cursor
stty sane 2>/dev/null || true
echo ""
