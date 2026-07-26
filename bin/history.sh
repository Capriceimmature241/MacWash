#!/bin/bash
# MacWash - History command: show operation log.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

JSON_MODE=false
LIMIT=20

for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --limit=*) LIMIT="${arg#--limit=}" ;;
        --help|-h) show_help; exit 0 ;;
    esac
done

LOG="$HOME/Library/Logs/macwash/operations.log"

if [[ ! -f "$LOG" ]]; then
    echo -e "\n  ${GRAY}No history yet. Run 'macwash clean' to start.${NC}\n"
    exit 0
fi

if [[ "$JSON_MODE" == "true" ]]; then
    echo '{"log": "'"$LOG"'", "entries": ['
    tail -n "$LIMIT" "$LOG" | awk '{printf "  {\"line\": \"%s\"},\n", $0}' | sed '$ s/,$//'
    echo ']}'
else
    echo ""
    echo -e "${CYAN_BOLD}  ◈ MacWash  History${NC}"
    echo ""
    echo -e "  ${GRAY}Log: $LOG${NC}"
    echo ""
    tail -n "$LIMIT" "$LOG" | while IFS= read -r line; do
        echo "  $line"
    done
    echo ""
fi
