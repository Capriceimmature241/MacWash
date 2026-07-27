#!/bin/bash
# MacWash - Status: live system health dashboard with process management.
# Q to quit, K to kill selected process, ↑↓ to navigate processes.

export LC_ALL=C LANG=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

# IMPORTANT: Disable strict mode AFTER sourcing - the sourced files enable it
# This is required because the read command with timeout returns non-zero
set +e
set +u
set +o pipefail

JSON_MODE=false
for arg in "$@"; do
    case "$arg" in --json) JSON_MODE=true ;; --help|-h) show_help; exit 0 ;; esac
done

# Only force JSON mode if explicitly piped (not just when running in terminal)
if [[ "$JSON_MODE" != "true" ]] && [[ ! -t 1 ]] && [[ ! -t 0 ]]; then
    JSON_MODE=true
fi

# Process selection state
PROC_SELECT=0
declare -a PROC_PIDS=()
declare -a PROC_NAMES=()

# ── Helpers ───────────────────────────────────────────────────────────────────
_bar() {
    local p=${1:-0} w=${2:-24} c=${3:-}
    [[ "$p" =~ ^[0-9]+$ ]] || p=0; [[ $p -gt 100 ]] && p=100
    local f=$(( p * w / 100 )) e b="" i
    [[ $f -gt $w ]] && f=$w; e=$(( w - f ))
    for ((i=0;i<f;i++)); do b+="█"; done
    for ((i=0;i<e;i++)); do b+="░"; done
    [[ -n "$c" ]] && printf '%s%s%s' "$c" "$b" "$NC" || printf '%s' "$b"
}
_col() {
    local p=${1:-0} inv=${2:-}
    [[ "$p" =~ ^[0-9]+$ ]] || p=0
    if [[ "$inv" == "1" ]]; then
        [[ $p -lt 20 ]] && echo "$RED" || { [[ $p -lt 50 ]] && echo "$YELLOW" || echo "$GREEN"; }
    else
        [[ $p -gt 85 ]] && echo "$RED" || { [[ $p -gt 60 ]] && echo "$YELLOW" || echo "$GREEN"; }
    fi
}
_div() { printf '  \033[90m'; printf '─%.0s' {1..62}; printf '\033[0m\n'; }

# ── Collectors ────────────────────────────────────────────────────────────────
get_cpu() {
    local l n
    l=$(sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); print $1+0}')
    n=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    [[ "$n" =~ ^[0-9]+$ && $n -gt 0 ]] || n=1
    awk "BEGIN{v=$l/$n*100; if(v>100)v=100; printf \"%.1f\",v}" 2>/dev/null || echo "0.0"
}
get_load() { sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); printf "%s/%s/%s",$1,$2,$3}'; }
get_cores() {
    local l p
    l=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
    p=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "?")
    echo "${l}L / ${p}P"
}
get_mem() {
    local mt ps pa pw pc u pct tg ud
    mt=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    ps=$(vm_stat 2>/dev/null | awk '/page size/{gsub(/[^0-9]/,"",$NF); print $NF+0}')
    [[ "$ps" =~ ^[0-9]+$ && $ps -gt 0 ]] || ps=16384
    pa=$(vm_stat 2>/dev/null | awk '/Pages active/{gsub(/\./,"",$NF); print $NF+0}')
    pw=$(vm_stat 2>/dev/null | awk '/Pages wired down/{gsub(/\./,"",$NF); print $NF+0}')
    pc=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/{gsub(/\./,"",$NF); print $NF+0}')
    [[ "$pa" =~ ^[0-9]+$ ]] || pa=0
    [[ "$pw" =~ ^[0-9]+$ ]] || pw=0
    [[ "$pc" =~ ^[0-9]+$ ]] || pc=0
    u=$(( (pa + pw + pc) * ps ))
    pct=0; [[ $mt -gt 0 ]] && pct=$(( u * 100 / mt )); [[ $pct -gt 100 ]] && pct=100
    tg=$(( mt / 1073741824 ))
    ud=$(awk "BEGIN{printf \"%.1f\",$u/1073741824}")
    echo "$ud $tg $pct"
}
get_swap() {
    local r u t
    r=$(sysctl vm.swapusage 2>/dev/null || echo "")
    u=$(echo "$r" | grep -oE 'used = [0-9.]+M' | grep -oE '[0-9.]+' | head -1 || echo "0")
    t=$(echo "$r" | grep -oE 'total = [0-9.]+M' | grep -oE '[0-9.]+' | head -1 || echo "0")
    printf "%.0f %.0f" "${u:-0}" "${t:-0}"
}
get_pres() { memory_pressure -Q 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%' || echo "?"; }
get_disk() {
    local tgt fk tk pct fg tg
    tgt="/"; [[ -d "/System/Volumes/Data" ]] && tgt="/System/Volumes/Data"
    fk=$(df -Pk "$tgt" 2>/dev/null | awk 'NR==2{print $4+0}')
    tk=$(df -Pk "$tgt" 2>/dev/null | awk 'NR==2{print $2+0}')
    [[ "$tk" =~ ^[0-9]+$ && $tk -gt 0 ]] || tk=1
    [[ "$fk" =~ ^[0-9]+$ ]] || fk=0
    pct=$(( (tk - fk) * 100 / tk ))
    fg=$(( fk / 1048576 )); tg=$(( tk / 1048576 ))
    echo "$fg $tg $pct"
}
get_batt() {
    local r pct st tl io des mx hp cy tr tc
    r=$(pmset -g batt 2>/dev/null || echo "")
    pct=$(echo "$r" | grep -oE '[0-9]+%' | head -1 | tr -d '%'); [[ "$pct" =~ ^[0-9]+$ ]] || pct="?"
    if echo "$r" | grep -q "AC Power"; then
        echo "$r" | grep -qi "charging" && st="Charging" || st="Charged"
    elif echo "$r" | grep -qi "discharging"; then
        st="On Battery"
        tl=$(echo "$r" | grep -oE '[0-9]+:[0-9]+ remaining' | sed 's/ remaining//' | head -1)
    else
        st="Unknown"
    fi
    io=$(ioreg -l -n AppleSmartBattery 2>/dev/null | grep -E '"CycleCount" = |"Temperature" = |"DesignCapacity" = |"AppleRawMaxCapacity" = ' || true)
    des=$(echo "$io" | grep '"DesignCapacity"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    mx=$(echo "$io" | grep '"AppleRawMaxCapacity"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$des" =~ ^[0-9]+$ && "$mx" =~ ^[0-9]+$ && $des -gt 0 ]] && hp=$(awk "BEGIN{printf \"%.0f\",$mx/$des*100}") || hp="?"
    cy=$(echo "$io" | grep '"CycleCount"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1); [[ "$cy" =~ ^[0-9]+$ ]] || cy="?"
    tr=$(echo "$io" | grep '"Temperature"' | awk -F'= ' '{gsub(/ /,"",$NF); print $NF+0}' | head -1)
    [[ "$tr" =~ ^[0-9]+$ ]] && tc=$(awk "BEGIN{printf \"%.0f\",$tr/100}") || tc="?"
    printf '%s|%s|%s|%s|%s|%s' "$pct" "$st" "${tl:-}" "$hp" "$cy" "$tc"
}
get_net() {
    local if1 l1 l2 r1 t1 r2 t2 rs ts rh th
    if1=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1); [[ -z "$if1" ]] && if1="en0"
    l1=$(netstat -ib 2>/dev/null | awk -v i="$if1" '$1==i && $3!~/Link/{print $7,$10; exit}')
    r1=$(echo "$l1" | awk '{print $1+0}'); t1=$(echo "$l1" | awk '{print $2+0}')
    sleep 1
    l2=$(netstat -ib 2>/dev/null | awk -v i="$if1" '$1==i && $3!~/Link/{print $7,$10; exit}')
    r2=$(echo "$l2" | awk '{print $1+0}'); t2=$(echo "$l2" | awk '{print $2+0}')
    rs=$(( r2-r1 )); [[ $rs -lt 0 ]] && rs=0
    ts=$(( t2-t1 )); [[ $ts -lt 0 ]] && ts=0
    rh=$(awk "BEGIN{v=$rs; if(v>=1048576)printf\"%.1fMB/s\",v/1048576; else if(v>=1024)printf\"%.0fKB/s\",v/1024; else printf\"%dB/s\",v}")
    th=$(awk "BEGIN{v=$ts; if(v>=1048576)printf\"%.1fMB/s\",v/1048576; else if(v>=1024)printf\"%.0fKB/s\",v/1024; else printf\"%dB/s\",v}")
    printf '%s|%s|%s' "$if1" "$rh" "$th"
}
get_uptime() {
    local b n e d h
    b=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\),.*/\1/p' | tr -d '[:space:]')
    [[ "$b" =~ ^[0-9]+$ ]] || b=0
    n=$(date +%s 2>/dev/null || echo 0)
    e=$(( n - b )); [[ $e -lt 0 ]] && e=0
    d=$(( e/86400 )); h=$(( (e%86400)/3600 ))
    [[ $d -gt 0 ]] && printf '%dd %dh' "$d" "$h" || printf '%dh %dm' "$h" "$(( (e%3600)/60 ))"
}
get_score() {
    local ci=$1 mp=$2 dp=$3 su=${4:-0} st=${5:-1} s=100
    [[ $ci -gt 90 ]] && s=$((s-25)); [[ $ci -gt 70 ]] && s=$((s-10))
    [[ $mp -gt 90 ]] && s=$((s-20)); [[ $mp -gt 75 ]] && s=$((s-10))
    [[ $dp -gt 95 ]] && s=$((s-20)); [[ $dp -gt 85 ]] && s=$((s-10))
    [[ $st -gt 0 ]] && { local sp=$(( su*100/st )); [[ $sp -gt 80 ]] && s=$((s-10)); }
    [[ $s -lt 0 ]] && s=0; echo $s
}
top_procs() {
    # Store PIDs for selection/kill feature
    PROC_PIDS=()
    PROC_NAMES=()
    local idx=0
    ps -Acro pid,pcpu,pmem,rss,comm 2>/dev/null | awk 'NR>1 && NF>=5 {
        pid=$1; cpu=$2; mem=$3; rss=$4
        name=""; for(i=5;i<=NF;i++) name=(i==5)?$i:name" "$i
        gsub(/^com\.apple\./,"",name)
        if(length(name)>24) name=substr(name,1,21)"..."
        mb=rss/1024
        n=int(cpu/10); if(n>8)n=8; if(n<0)n=0
        bar=""; for(j=0;j<n;j++) bar=bar"▮"; for(j=n;j<8;j++) bar=bar"▯"
        printf "%s|%s|%s|%s|%.1f|%s\n",pid,name,cpu,mem,mb,bar
    }' | head -10 | while IFS='|' read -r pid name cpu mem mb bar; do
        PROC_PIDS+=("$pid")
        PROC_NAMES+=("$name")
        echo "$pid|$name|$cpu|$mem|$mb|$bar"
    done
}

render_procs() {
    local sel=${1:-0}
    local idx=0
    PROC_PIDS=()
    PROC_NAMES=()
    
    ps -Acro pid,pcpu,pmem,rss,comm 2>/dev/null | awk 'NR>1 && NF>=5 {
        pid=$1; cpu=$2; mem=$3; rss=$4
        name=""; for(i=5;i<=NF;i++) name=(i==5)?$i:name" "$i
        gsub(/^com\.apple\./,"",name)
        if(length(name)>24) name=substr(name,1,21)"..."
        mb=rss/1024
        n=int(cpu/10); if(n>8)n=8; if(n<0)n=0
        bar=""; for(j=0;j<n;j++) bar=bar"▮"; for(j=n;j<8;j++) bar=bar"▯"
        printf "%s|%s|%s|%s|%.1f|%s\n",pid,name,cpu,mem,mb,bar
    }' | head -10 > /tmp/mw_procs_$$
    
    while IFS='|' read -r pid name cpu mem mb bar; do
        PROC_PIDS+=("$pid")
        PROC_NAMES+=("$name")
        if [[ $idx -eq $sel ]]; then
            # Matrix green highlight for selected process
            printf '\033[2K  \033[1;92m▶ %-6s  %-24s  %6s%%  %5s%%  %7sMB  %s\033[0m\n' \
                "$pid" "$name" "$cpu" "$mem" "$mb" "$bar"
        else
            printf '\033[2K  %-6s  %-24s  %6s%%  %5s%%  %7sMB  %s\n' \
                "$pid" "$name" "$cpu" "$mem" "$mb" "$bar"
        fi
        idx=$((idx + 1))
    done < /tmp/mw_procs_$$
    rm -f /tmp/mw_procs_$$ 2>/dev/null || true
    
    # Fill remaining lines if less than 10 processes
    while [[ $idx -lt 10 ]]; do
        printf '\033[2K\n'
        idx=$((idx + 1))
    done
}

# ── JSON ──────────────────────────────────────────────────────────────────────
if [[ "$JSON_MODE" == "true" ]]; then
    CP=$(get_cpu); read -r MU MT MP <<< "$(get_mem)"; read -r SU ST <<< "$(get_swap)"
    read -r DF DT DP <<< "$(get_disk)"; BR=$(get_batt); BP=$(echo "$BR"|cut -d'|' -f1); BS=$(echo "$BR"|cut -d'|' -f2)
    UP=$(get_uptime); CI="${CP%.*}"; [[ "$CI" =~ ^[0-9]+$ ]] || CI=0
    HS=$(get_score "$CI" "${MP:-0}" "${DP:-0}" "${SU:-0}" "${ST:-1}")
    HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
    printf '{"host":"%s","macos":"%s","uptime":"%s","health":%s,"cpu":{"pct":%s},"memory":{"used_gb":%s,"total_gb":%s,"pct":%s},"disk":{"free_gb":%s,"pct":%s},"battery":{"pct":"%s","status":"%s"}}\n' \
        "$HOST" "$(sw_vers -productVersion 2>/dev/null || echo ?)" "$UP" "$HS" "$CP" "$MU" "$MT" "$MP" "$DF" "$DP" "$BP" "$BS"
    exit 0
fi

# ── Live TUI ──────────────────────────────────────────────────────────────────
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
ARCH=$(detect_arch); MACOS=$(sw_vers -productVersion 2>/dev/null || echo "?")
NET_IF="en0"; NET_RX="--"; NET_TX="--"

# Process selection
PROC_SELECT=0
MAX_PROCS=10

# Clean exit handler
_quit() {
    printf '\033[?25h'
    tput rmcup 2>/dev/null || printf '\033[2J\033[H'
    stty sane </dev/tty 2>/dev/null || stty sane 2>/dev/null || true
    [[ -n "${NETBG:-}" ]] && kill "$NETBG" 2>/dev/null || true
    [[ -n "${NETTMP:-}" ]] && rm -f "$NETTMP" 2>/dev/null || true
    rm -f /tmp/mw_procs_$$ 2>/dev/null || true
    cleanup_temp_files 2>/dev/null || true
    exit 0
}
trap '_quit' INT TERM EXIT

# Kill selected process
_kill_proc() {
    local pid="${PROC_PIDS[$PROC_SELECT]:-}"
    local name="${PROC_NAMES[$PROC_SELECT]:-}"
    [[ -z "$pid" || "$pid" == "0" ]] && return 1
    
    # Don't allow killing system-critical processes
    case "$name" in
        kernel_task|launchd|WindowServer|loginwindow|Finder|Dock|SystemUIServer)
            return 1 ;;
    esac
    
    if kill -15 "$pid" 2>/dev/null; then
        return 0
    elif kill -9 "$pid" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Enter alternate screen so original terminal is preserved
stty sane 2>/dev/null || true  # Reset terminal first
tput smcup 2>/dev/null || true
printf '\033[?25l'

# Configure terminal for raw input - ALWAYS configure on /dev/tty
stty -echo -icanon min 0 time 1 </dev/tty 2>/dev/null || true

# Background net sampler
NETTMP=$(mktemp /tmp/mw_net.XXXXXX 2>/dev/null || echo "/tmp/mw_net_$$")
( while true; do r=$(get_net 2>/dev/null) && echo "$r" > "$NETTMP"; sleep 3; done ) &
NETBG=$!
disown $NETBG 2>/dev/null || true

# Main live loop
while true; do
    # Collect
    CP=$(get_cpu); CI="${CP%.*}"; [[ "$CI" =~ ^[0-9]+$ ]] || CI=0
    CL=$(get_load); CC=$(get_cores)
    read -r MU MT MP <<< "$(get_mem)"
    read -r SU ST <<< "$(get_swap)"
    PR=$(get_pres)
    read -r DF DT DP <<< "$(get_disk)"
    BR=$(get_batt)
    BP=$(echo "$BR"|cut -d'|' -f1); BS=$(echo "$BR"|cut -d'|' -f2)
    BT=$(echo "$BR"|cut -d'|' -f3); BH=$(echo "$BR"|cut -d'|' -f4)
    BC=$(echo "$BR"|cut -d'|' -f5); BTC=$(echo "$BR"|cut -d'|' -f6)
    UP=$(get_uptime)
    [[ "$MP" =~ ^[0-9]+$ ]] || MP=0; [[ "$DP" =~ ^[0-9]+$ ]] || DP=0
    SP=0; [[ "${ST:-0}" =~ ^[0-9]+$ && ${ST:-0} -gt 0 ]] && SP=$(( ${SU:-0}*100/${ST:-1} ))
    HS=$(get_score "$CI" "$MP" "$DP" "${SU:-0}" "${ST:-1}")
    TS=$(date '+%H:%M:%S' 2>/dev/null || echo "")

    # Network from bg sampler
    if [[ -s "$NETTMP" ]]; then
        NET_IF=$(cut -d'|' -f1 "$NETTMP")
        NET_RX=$(cut -d'|' -f2 "$NETTMP")
        NET_TX=$(cut -d'|' -f3 "$NETTMP")
    fi

    # Render
    printf '\033[H'

    # Header
    HC="$GREEN"; [[ $HS -lt 70 ]] && HC="$YELLOW"; [[ $HS -lt 50 ]] && HC="$RED"
    HL="Excellent"; [[ $HS -lt 90 ]] && HL="Good"; [[ $HS -lt 70 ]] && HL="Fair"; [[ $HS -lt 50 ]] && HL="Poor"
    printf '\033[2K'; echo -e "${CYAN_BOLD}  ◈ MacWash  Status${NC}  ${HC}● Health $HS  $HL${NC}"
    printf '\033[2K'; echo -e "  ${GRAY}$HOST  ·  $ARCH  ·  macOS $MACOS  ·  up $UP${NC}"
    printf '\033[2K'; _div; printf '\033[2K\n'

    # CPU
    CC1=$(_col "$CI"); printf '\033[2K'
    printf '  %-8s  %s  %s%s%%%s   %sLoad: %s  Cores: %s%s\n' \
        "${CYAN_BOLD}⚙ CPU${NC}" "$(_bar "$CI" 24 "$CC1")" "$CC1" "$CP" "$NC" "$GRAY" "$CL" "$CC" "$NC"
    printf '\033[2K\n'

    # Memory
    MC=$(_col "$MP"); SC=$(_col "$SP"); printf '\033[2K'
    printf '  %-8s  %s  %s%s%%%s   %s%s/%s GB  pressure %s%%%s\n' \
        "${CYAN_BOLD}▦ Mem${NC}" "$(_bar "$MP" 24 "$MC")" "$MC" "$MP" "$NC" "$GRAY" "$MU" "$MT" "$PR" "$NC"
    printf '\033[2K'
    printf '  %-8s  %s  %s%s/%s MB%s\n' "${GRAY}Swap${NC}" "$(_bar "$SP" 24 "$SC")" "$SC" "${SU:-0}" "${ST:-0}" "$NC"
    printf '\033[2K\n'

    # Disk
    DC=$(_col "$DP"); printf '\033[2K'
    printf '  %-8s  %s  %s%s%%%s   %s%s GB free of %s GB%s\n' \
        "${CYAN_BOLD}▤ Disk${NC}" "$(_bar "$DP" 24 "$DC")" "$DC" "$DP" "$NC" "$GRAY" "$DF" "$DT" "$NC"
    printf '\033[2K\n'

    # Battery
    BI=0; [[ "$BP" =~ ^[0-9]+$ ]] && BI=$BP
    BC2=$(_col "$BI" 1); BX=""; [[ -n "${BT:-}" ]] && BX="  ${GRAY}${BT} left${NC}"
    printf '\033[2K'
    printf '  %-8s  %s  %s%s%%%s   %s%s%s%s\n' \
        "${CYAN_BOLD}⚡ Batt${NC}" "$(_bar "$BI" 24 "$BC2")" "$BC2" "$BP" "$NC" "$GRAY" "$BS" "$NC" "$BX"
    BD=""
    [[ "${BH:-?}" != "?" ]] && BD+="health ${BH}%"
    [[ "${BC:-?}" != "?" ]] && BD+="  ·  ${BC} cycles"
    [[ "${BTC:-?}" != "?" ]] && BD+="  ·  ${BTC}°C"
    printf '\033[2K'; [[ -n "$BD" ]] && echo -e "           ${GRAY}${BD}${NC}" || echo ""
    printf '\033[2K\n'

    # Network
    printf '\033[2K'
    printf '  %-8s  %s↓ %s  ↑ %s  [%s]%s\n' \
        "${CYAN_BOLD}⇅ Net${NC}" "$GRAY" "$NET_RX" "$NET_TX" "$NET_IF" "$NC"
    printf '\033[2K\n'

    # Processes
    printf '\033[2K'; _div
    printf '\033[2K'; printf '  %s%-6s  %-24s  %7s  %6s  %8s  %s%s\n' \
        "${CYAN_BOLD}" "PID" "Process" "CPU" "MEM" "Memory" "Activity" "${NC}"
    printf '\033[2K'; printf '  \033[90m'; printf '─%.0s' {1..68}; printf '\033[0m\n'
    
    # Render processes with selection
    render_procs "$PROC_SELECT"
    
    printf '\033[2K\n'
    printf '\033[2K'; _div
    printf '\033[2K'; printf '  \033[90m↑↓ Navigate  |  K Kill  |  Q Quit  |  Live %s\033[0m\n' "$TS"
    printf '\033[J'

    # Input handling loop - check for keys every 0.1s for 3 seconds total
    i=0
    while [[ $i -lt 30 ]]; do
        ch=""
        # Read from /dev/tty directly for reliable input in all terminal contexts
        if IFS= read -r -s -n1 -t 0.1 ch </dev/tty 2>/dev/null; then
            case "$ch" in
                q|Q) _quit ;;
                $'\x03') _quit ;;  # Ctrl+C
                $'\x1b')  # Escape sequence (arrow keys)
                    seq=""
                    IFS= read -r -s -n2 -t 0.1 seq </dev/tty 2>/dev/null || true
                    case "$seq" in
                        '[A') # Up arrow
                            [[ $PROC_SELECT -gt 0 ]] && PROC_SELECT=$((PROC_SELECT - 1))
                            break  # Refresh immediately
                            ;;
                        '[B') # Down arrow
                            [[ $PROC_SELECT -lt $((MAX_PROCS - 1)) ]] && PROC_SELECT=$((PROC_SELECT + 1))
                            break  # Refresh immediately
                            ;;
                    esac
                    ;;
                k|K)  # Kill selected process
                    if _kill_proc; then
                        break  # Refresh to show updated process list
                    fi
                    ;;
                j|J)  # Vim down
                    [[ $PROC_SELECT -lt $((MAX_PROCS - 1)) ]] && PROC_SELECT=$((PROC_SELECT + 1))
                    break
                    ;;
                p|P)  # Vim up (since K is kill)
                    [[ $PROC_SELECT -gt 0 ]] && PROC_SELECT=$((PROC_SELECT - 1))
                    break
                    ;;
            esac
        fi
        i=$((i + 1))
    done
done
