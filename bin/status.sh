#!/bin/bash
# MacWash - Status command: live system health dashboard.
# Refreshes every 3s. Press Q or Ctrl+C to quit.

export LC_ALL=C LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
JSON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --json)    JSON_MODE=true ;;
        --help|-h) show_help; exit 0 ;;
    esac
done
[[ -t 1 ]] || JSON_MODE=true

# ── Collectors ────────────────────────────────────────────────────────────────

cpu_usage() {
    local load1 ncpu pct
    load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); print $1+0}')
    ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    [[ "$ncpu" =~ ^[0-9]+$ && $ncpu -gt 0 ]] || ncpu=1
    pct=$(awk "BEGIN{v=$load1/$ncpu*100; if(v>100)v=100; printf \"%.1f\",v}" 2>/dev/null || echo "0.0")
    echo "${pct:-0.0}"
}

cpu_load() {
    sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); printf "%s / %s / %s",$1,$2,$3}'
}

cpu_cores() {
    local l p
    l=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
    p=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "?")
    echo "$l logical, $p physical"
}

mem_stats() {
    local mem_total page_size pages_active pages_wired pages_compressed used pct total_gb used_dec
    mem_total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    page_size=$(vm_stat 2>/dev/null | awk '/page size/{gsub(/[^0-9]/,"",$NF); print $NF+0}')
    [[ "$page_size" =~ ^[0-9]+$ && $page_size -gt 0 ]] || page_size=16384
    pages_active=$(vm_stat 2>/dev/null | awk '/Pages active/{gsub(/\./,"",$NF); print $NF+0}')
    pages_wired=$(vm_stat 2>/dev/null | awk '/Pages wired down/{gsub(/\./,"",$NF); print $NF+0}')
    pages_compressed=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/{gsub(/\./,"",$NF); print $NF+0}')
    [[ "$pages_active" =~ ^[0-9]+$ ]] || pages_active=0
    [[ "$pages_wired" =~ ^[0-9]+$ ]] || pages_wired=0
    [[ "$pages_compressed" =~ ^[0-9]+$ ]] || pages_compressed=0
    used=$(( (pages_active + pages_wired + pages_compressed) * page_size ))
    pct=0
    [[ $mem_total -gt 0 ]] && pct=$(( used * 100 / mem_total ))
    [[ $pct -gt 100 ]] && pct=100
    total_gb=$(( mem_total / 1024 / 1024 / 1024 ))
    used_dec=$(awk "BEGIN{printf \"%.1f\",$used/1073741824}")
    echo "$used_dec $total_gb $pct"
}

swap_stats() {
    local raw used total
    raw=$(sysctl vm.swapusage 2>/dev/null || echo "")
    used=$(echo "$raw" | grep -oE 'used = [0-9.]+M' | grep -oE '[0-9.]+' | head -1 || echo "0")
    total=$(echo "$raw" | grep -oE 'total = [0-9.]+M' | grep -oE '[0-9.]+' | head -1 || echo "0")
    printf "%.0f %.0f" "${used:-0}" "${total:-0}"
}

mem_pressure() {
    memory_pressure -Q 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%' || echo "?"
}

disk_stats() {
    local target free_kb total_kb pct free_gb total_gb
    target="/"
    [[ -d "/System/Volumes/Data" ]] && target="/System/Volumes/Data"
    free_kb=$(df -Pk "$target" 2>/dev/null | awk 'NR==2{print $4+0}')
    total_kb=$(df -Pk "$target" 2>/dev/null | awk 'NR==2{print $2+0}')
    [[ "$total_kb" =~ ^[0-9]+$ && $total_kb -gt 0 ]] || total_kb=1
    [[ "$free_kb" =~ ^[0-9]+$ ]] || free_kb=0
    pct=$(( (total_kb - free_kb) * 100 / total_kb ))
    free_gb=$(( free_kb / 1024 / 1024 ))
    total_gb=$(( total_kb / 1024 / 1024 ))
    echo "$free_gb $total_gb $pct"
}

battery_stats() {
    local raw pct status time_left ioreg_out design max health_pct cycles temp_raw temp_c
    raw=$(pmset -g batt 2>/dev/null || echo "")
    pct=$(echo "$raw" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
    [[ "$pct" =~ ^[0-9]+$ ]] || pct="?"

    if echo "$raw" | grep -q "AC Power"; then
        echo "$raw" | grep -qi "charging" && status="Charging" || status="Charged"
    elif echo "$raw" | grep -qi "discharging"; then
        status="On Battery"
        time_left=$(echo "$raw" | grep -oE '[0-9]+:[0-9]+ remaining' | sed 's/ remaining//' | head -1)
    else
        status="Unknown"
    fi

    ioreg_out=$(ioreg -l -n AppleSmartBattery 2>/dev/null | grep -E '"CycleCount" = |"Temperature" = |"DesignCapacity" = |"AppleRawMaxCapacity" = ' || true)
    design=$(echo "$ioreg_out" | grep '"DesignCapacity"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    max=$(echo "$ioreg_out" | grep '"AppleRawMaxCapacity"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$design" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ && $design -gt 0 ]] && \
        health_pct=$(awk "BEGIN{printf \"%.0f\",$max/$design*100}") || health_pct="?"
    cycles=$(echo "$ioreg_out" | grep '"CycleCount"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$cycles" =~ ^[0-9]+$ ]] || cycles="?"
    temp_raw=$(echo "$ioreg_out" | grep '"Temperature"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$temp_raw" =~ ^[0-9]+$ ]] && temp_c=$(awk "BEGIN{printf \"%.0f\",$temp_raw/100}") || temp_c="?"

    echo "${pct}|${status}|${time_left:-}|${health_pct}|${cycles}|${temp_c}"
}

net_stats() {
    local iface line1 line2 rx1 tx1 rx2 tx2 rx_s tx_s rx_h tx_h
    iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1)
    [[ -z "$iface" ]] && iface="en0"
    line1=$(netstat -ib 2>/dev/null | awk -v i="$iface" '$1==i && $3!~/Link/{print $7,$10; exit}')
    rx1=$(echo "$line1" | awk '{print $1+0}'); tx1=$(echo "$line1" | awk '{print $2+0}')
    sleep 1
    line2=$(netstat -ib 2>/dev/null | awk -v i="$iface" '$1==i && $3!~/Link/{print $7,$10; exit}')
    rx2=$(echo "$line2" | awk '{print $1+0}'); tx2=$(echo "$line2" | awk '{print $2+0}')
    rx_s=$(( rx2 - rx1 )); [[ $rx_s -lt 0 ]] && rx_s=0
    tx_s=$(( tx2 - tx1 )); [[ $tx_s -lt 0 ]] && tx_s=0
    rx_h=$(awk "BEGIN{v=$rx_s; if(v>=1048576)printf\"%.1f MB/s\",v/1048576; else if(v>=1024)printf\"%.0f KB/s\",v/1024; else printf\"%d B/s\",v}")
    tx_h=$(awk "BEGIN{v=$tx_s; if(v>=1048576)printf\"%.1f MB/s\",v/1048576; else if(v>=1024)printf\"%.0f KB/s\",v/1024; else printf\"%d B/s\",v}")
    echo "$iface|$rx_h|$tx_h"
}

uptime_str() {
    local boot now elapsed days hours
    boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\),.*/\1/p' | tr -d '[:space:]')
    [[ "$boot" =~ ^[0-9]+$ ]] || boot=0
    now=$(get_epoch_seconds)
    elapsed=$(( now - boot )); [[ $elapsed -lt 0 ]] && elapsed=0
    days=$(( elapsed / 86400 )); hours=$(( (elapsed % 86400) / 3600 ))
    [[ $days -gt 0 ]] && printf '%dd %dh' "$days" "$hours" || printf '%dh %dm' "$hours" "$(( (elapsed % 3600) / 60 ))"
}

health_score() {
    local cpu_i=$1 mem_p=$2 disk_p=$3 swap_u=${4:-0} swap_t=${5:-1}
    local score=100
    [[ $cpu_i -gt 90 ]] && score=$((score-25))
    [[ $cpu_i -gt 70 ]] && score=$((score-10))
    [[ $mem_p -gt 90 ]] && score=$((score-20))
    [[ $mem_p -gt 75 ]] && score=$((score-10))
    [[ $disk_p -gt 95 ]] && score=$((score-20))
    [[ $disk_p -gt 85 ]] && score=$((score-10))
    [[ $swap_t -gt 0 ]] && { local sp=$(( swap_u * 100 / swap_t )); [[ $sp -gt 80 ]] && score=$((score-10)); }
    [[ $score -lt 0 ]] && score=0
    echo $score
}

bar() {
    local pct=${1:-0} width=${2:-24} color=${3:-}
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0; [[ $pct -gt 100 ]] && pct=100
    local filled=$(( pct * width / 100 )) empty b=""
    [[ $filled -gt $width ]] && filled=$width
    empty=$(( width - filled ))
    local i; for ((i=0;i<filled;i++)); do b+="█"; done
    for ((i=0;i<empty;i++)); do b+="░"; done
    [[ -n "$color" ]] && printf '%s%s%s' "$color" "$b" "$NC" || printf '%s' "$b"
}

pct_color() {
    local p=${1:-0} inv=${2:-false}
    [[ "$p" =~ ^[0-9]+$ ]] || p=0
    if [[ "$inv" == "true" ]]; then
        [[ $p -lt 20 ]] && echo "$RED" || { [[ $p -lt 50 ]] && echo "$YELLOW" || echo "$GREEN"; }
    else
        [[ $p -gt 85 ]] && echo "$RED" || { [[ $p -gt 60 ]] && echo "$YELLOW" || echo "$GREEN"; }
    fi
}

top_procs() {
    ps -Acro pid,pcpu,pmem,rss,comm 2>/dev/null | awk 'NR>1 && NF>=5 {
        pid=$1; cpu=$2; mem=$3; rss=$4
        name=""; for(i=5;i<=NF;i++) name=(i==5)?$i:name" "$i
        gsub(/^com\.apple\./,"",name)
        if(length(name)>28) name=substr(name,1,25)"..."
        mb=rss/1024
        n=int(cpu/10); if(n>8)n=8; if(n<0)n=0
        bar=""; for(j=0;j<n;j++) bar=bar"▮"; for(j=n;j<8;j++) bar=bar"▯"
        printf "  %-6s  %-28s  %5s%%  %5s%%  %6.1fMB  %s\n",pid,name,cpu,mem,mb,bar
    }' | head -10
}

div() { echo -e "  ${GRAY}$(printf '─%.0s' {1..62})${NC}"; }

# ── JSON mode ─────────────────────────────────────────────────────────────────
if [[ "$JSON_MODE" == "true" ]]; then
    CPU_PCT=$(cpu_usage)
    read -r MEM_USED MEM_TOTAL MEM_PCT <<< "$(mem_stats)"
    read -r SWAP_USED SWAP_TOTAL <<< "$(swap_stats)"
    read -r DISK_FREE DISK_TOTAL DISK_PCT <<< "$(disk_stats)"
    BATT_RAW=$(battery_stats)
    BATT_PCT=$(echo "$BATT_RAW" | cut -d'|' -f1)
    BATT_STATUS=$(echo "$BATT_RAW" | cut -d'|' -f2)
    HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
    ARCH=$(detect_arch); MACOS=$(sw_vers -productVersion 2>/dev/null || echo "?")
    UPTIME=$(uptime_str)
    CPU_I="${CPU_PCT%.*}"; [[ "$CPU_I" =~ ^[0-9]+$ ]] || CPU_I=0
    HEALTH=$(health_score "$CPU_I" "${MEM_PCT:-0}" "${DISK_PCT:-0}" "${SWAP_USED:-0}" "${SWAP_TOTAL:-1}")
    cat <<EOF
{"host":"$HOST","arch":"$ARCH","macos":"$MACOS","uptime":"$UPTIME","health":$HEALTH,
 "cpu":{"pct":$CPU_PCT,"load":"$(cpu_load)"},
 "memory":{"used_gb":$MEM_USED,"total_gb":$MEM_TOTAL,"pct":$MEM_PCT},
 "swap":{"used_mb":${SWAP_USED:-0},"total_mb":${SWAP_TOTAL:-0}},
 "disk":{"free_gb":$DISK_FREE,"total_gb":$DISK_TOTAL,"pct":$DISK_PCT},
 "battery":{"pct":"$BATT_PCT","status":"$BATT_STATUS"}}
EOF
    exit 0
fi

# ── Live TUI ──────────────────────────────────────────────────────────────────
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
ARCH=$(detect_arch)
MACOS=$(sw_vers -productVersion 2>/dev/null || echo "?")

render() {
    local CPU_PCT=$1 CPU_I=$2 MEM_USED=$3 MEM_TOTAL=$4 MEM_PCT=$5
    local SWAP_USED=$6 SWAP_TOTAL=$7 MEM_PRES=$8
    local DISK_FREE=$9 DISK_TOTAL=${10} DISK_PCT=${11}
    local BATT_PCT=${12} BATT_STATUS=${13} BATT_TIME=${14}
    local BATT_HEALTH=${15} BATT_CYCLES=${16} BATT_TEMP=${17}
    local NET_IFACE=${18} NET_RX=${19} NET_TX=${20}
    local UPTIME=${21} HEALTH=${22} TS=${23}

    printf '\033[H\033[2J'

    local hc="$GREEN"; [[ $HEALTH -lt 70 ]] && hc="$YELLOW"; [[ $HEALTH -lt 50 ]] && hc="$RED"
    local hl="Excellent"; [[ $HEALTH -lt 90 ]] && hl="Good"; [[ $HEALTH -lt 70 ]] && hl="Fair"; [[ $HEALTH -lt 50 ]] && hl="Poor"

    echo -e "${CYAN_BOLD}  ◈ MacWash  Status${NC}  ${hc}● Health $HEALTH  $hl${NC}"
    echo -e "  ${GRAY}$HOST  ·  $ARCH  ·  macOS $MACOS  ·  up $UPTIME${NC}"
    div; echo ""

    # CPU
    local cc; cc=$(pct_color "$CPU_I")
    printf '  %-8s' "${CYAN_BOLD}⚙ CPU${NC}"
    printf '  %s  %s%s%%%s   %sLoad: %s%s\n' "$(bar "$CPU_I" 24 "$cc")" "$cc" "$CPU_PCT" "$NC" "$GRAY" "$(cpu_load)" "$NC"
    printf '  %sCores: %s%s\n\n' "$GRAY" "$(cpu_cores)" "$NC"

    # Memory
    local mc; mc=$(pct_color "$MEM_PCT")
    local sp=0; [[ ${SWAP_TOTAL:-0} -gt 0 ]] && sp=$(( SWAP_USED * 100 / SWAP_TOTAL ))
    local sc; sc=$(pct_color "$sp")
    printf '  %-8s' "${CYAN_BOLD}▦ Memory${NC}"
    printf '  %s  %s%s%%%s   %s%s / %s GB  ·  pressure %s%%%s\n' \
        "$(bar "$MEM_PCT" 24 "$mc")" "$mc" "$MEM_PCT" "$NC" "$GRAY" "$MEM_USED" "$MEM_TOTAL" "$MEM_PRES" "$NC"
    printf '  %sSwap%s    %s  %s%s MB / %s MB%s\n\n' \
        "$GRAY" "$NC" "$(bar "$sp" 24 "$sc")" "$sc" "$SWAP_USED" "$SWAP_TOTAL" "$NC"

    # Disk
    local dc; dc=$(pct_color "$DISK_PCT")
    printf '  %-8s' "${CYAN_BOLD}▤ Disk${NC}"
    printf '  %s  %s%s%%%s   %s%s GB free of %s GB%s\n\n' \
        "$(bar "$DISK_PCT" 24 "$dc")" "$dc" "$DISK_PCT" "$NC" "$GRAY" "$DISK_FREE" "$DISK_TOTAL" "$NC"

    # Battery
    local bi=0; [[ "$BATT_PCT" =~ ^[0-9]+$ ]] && bi=$BATT_PCT
    local bc; bc=$(pct_color "$bi" true)
    local bx=""; [[ -n "${BATT_TIME:-}" ]] && bx="  ${GRAY}${BATT_TIME} left${NC}"
    printf '  %-8s' "${CYAN_BOLD}⚡ Battery${NC}"
    printf '  %s  %s%s%%%s   %s%s%s%s\n' \
        "$(bar "$bi" 24 "$bc")" "$bc" "$BATT_PCT" "$NC" "$GRAY" "$BATT_STATUS" "$NC" "$bx"
    local bd=""
    [[ "${BATT_HEALTH:-?}" != "?" ]] && bd+="health ${BATT_HEALTH}%"
    [[ "${BATT_CYCLES:-?}" != "?" ]] && bd+="  ·  ${BATT_CYCLES} cycles"
    [[ "${BATT_TEMP:-?}" != "?" ]] && bd+="  ·  ${BATT_TEMP}°C"
    [[ -n "$bd" ]] && echo -e "           ${GRAY}${bd}${NC}"
    echo ""

    # Network
    printf '  %-8s' "${CYAN_BOLD}⇅ Network${NC}"
    printf '  %s↓ %s  ↑ %s  [%s]%s\n\n' "$GRAY" "$NET_RX" "$NET_TX" "$NET_IFACE" "$NC"

    # Processes
    div
    printf '  %s%-6s  %-28s  %6s  %6s  %7s  %s%s\n' \
        "${CYAN_BOLD}" "PID" "Process" "CPU" "MEM" "Memory" "Activity" "${NC}"
    echo -e "  ${GRAY}$(printf '─%.0s' {1..70})${NC}"
    top_procs
    echo ""
    div
    printf '  %sLive · Q to quit · Updated: %s%s\n' "$GRAY" "$TS" "$NC"
    printf '\033[J'
}

# ── Main ──────────────────────────────────────────────────────────────────────
printf '\033[2J\033[H'
printf '\033[?25l'  # hide cursor

# Trap for clean exit
_status_exit() {
    printf '\033[?25h'  # show cursor
    printf '\033[2J\033[H'
    stty sane 2>/dev/null || true
    cleanup_temp_files 2>/dev/null || true
    echo ""
    exit 0
}
trap _status_exit INT TERM EXIT

# Get initial network (takes 1s)
NET_RAW=$(net_stats)
NET_IFACE=$(echo "$NET_RAW" | cut -d'|' -f1)
NET_RX=$(echo "$NET_RAW" | cut -d'|' -f2)
NET_TX=$(echo "$NET_RAW" | cut -d'|' -f3)

# Background network updater
NET_TMP=$(mktemp /tmp/macwash_net.XXXXXX)
(
    while true; do
        r=$(net_stats 2>/dev/null) && printf '%s\n' "$r" > "$NET_TMP"
        sleep 2
    done
) &
NET_BG=$!
disown $NET_BG 2>/dev/null || true

# Main loop — pure timed loop, no stty tricks
while true; do
    # Collect all metrics
    CPU_PCT=$(cpu_usage)
    CPU_I="${CPU_PCT%.*}"; [[ "$CPU_I" =~ ^[0-9]+$ ]] || CPU_I=0
    read -r MEM_USED MEM_TOTAL MEM_PCT <<< "$(mem_stats)"
    read -r SWAP_USED SWAP_TOTAL <<< "$(swap_stats)"
    MEM_PRES=$(mem_pressure)
    read -r DISK_FREE DISK_TOTAL DISK_PCT <<< "$(disk_stats)"
    BATT_RAW=$(battery_stats)
    BATT_PCT=$(echo "$BATT_RAW" | cut -d'|' -f1)
    BATT_STATUS=$(echo "$BATT_RAW" | cut -d'|' -f2)
    BATT_TIME=$(echo "$BATT_RAW" | cut -d'|' -f3)
    BATT_HEALTH=$(echo "$BATT_RAW" | cut -d'|' -f4)
    BATT_CYCLES=$(echo "$BATT_RAW" | cut -d'|' -f5)
    BATT_TEMP=$(echo "$BATT_RAW" | cut -d'|' -f6)
    UPTIME=$(uptime_str)
    HEALTH=$(health_score "$CPU_I" "${MEM_PCT:-0}" "${DISK_PCT:-0}" "${SWAP_USED:-0}" "${SWAP_TOTAL:-1}")
    TS=$(date '+%H:%M:%S' 2>/dev/null || echo "")

    # Read latest network
    if [[ -s "$NET_TMP" ]]; then
        NET_IFACE=$(cut -d'|' -f1 "$NET_TMP")
        NET_RX=$(cut -d'|' -f2 "$NET_TMP")
        NET_TX=$(cut -d'|' -f3 "$NET_TMP")
    fi

    render "$CPU_PCT" "$CPU_I" \
        "${MEM_USED:-0}" "${MEM_TOTAL:-16}" "${MEM_PCT:-0}" \
        "${SWAP_USED:-0}" "${SWAP_TOTAL:-0}" "${MEM_PRES:-?}" \
        "${DISK_FREE:-0}" "${DISK_TOTAL:-0}" "${DISK_PCT:-0}" \
        "${BATT_PCT:-?}" "${BATT_STATUS:-?}" "${BATT_TIME:-}" \
        "${BATT_HEALTH:-?}" "${BATT_CYCLES:-?}" "${BATT_TEMP:-?}" \
        "${NET_IFACE:-en0}" "${NET_RX:---}" "${NET_TX:---}" \
        "$UPTIME" "$HEALTH" "$TS"

    # Wait 3s — check for Q keypress using /dev/tty
    i=0
    while [[ $i -lt 30 ]]; do
        if read -r -s -n1 -t 0.1 ch < /dev/tty 2>/dev/null; then
            case "$ch" in
                q|Q) kill $NET_BG 2>/dev/null; rm -f "$NET_TMP"; _status_exit ;;
            esac
        fi
        i=$(( i + 1 ))
    done
done
