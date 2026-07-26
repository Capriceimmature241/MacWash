#!/bin/bash
# MacWash - Self-update flow.

set -euo pipefail
[[ -z "${MACWASH_BASE_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/base.sh"

update_macwash() {
    echo ""
    echo -e "${CYAN_BOLD}  ◈ MacWash  Update${NC}"
    echo ""
    echo -e "  ${GRAY}Visit: https://github.com/toolka/MacWash/releases${NC}"
    echo -e "  ${GRAY}Or run: curl -fsSL https://raw.githubusercontent.com/toolka/MacWash/main/install.sh | bash${NC}"
    echo -e "  ${GRAY}Or brew: brew tap toolka/macwash && brew install macwash${NC}"
    echo ""
}
