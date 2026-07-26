#!/bin/bash
# MacWash - Installer.
# Usage: curl -fsSL https://raw.githubusercontent.com/toolka/MacWash/main/install.sh | bash

set -euo pipefail

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/macwash"
REPO="toolka/MacWash"
BRANCH="main"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
[[ -n "${NO_COLOR:-}" ]] && GREEN='' YELLOW='' RED='' NC=''

log_ok()   { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_err()  { echo -e "${RED}✗${NC} $1"; exit 1; }

[[ "$OSTYPE" == darwin* ]] || log_err "MacWash requires macOS."

echo ""
echo "  Installing MacWash v1.0.2..."
echo ""

# ── Fetch source ──────────────────────────────────────────────────────────────
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" \
        -o "$TMP/macwash.tar.gz" 2>/dev/null \
    && tar -xzf "$TMP/macwash.tar.gz" -C "$TMP" \
    && SRC=$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1) \
    || log_err "Failed to fetch source from GitHub."
elif command -v git >/dev/null 2>&1; then
    git clone --depth=1 "https://github.com/$REPO.git" "$TMP/macwash" >/dev/null 2>&1
    SRC="$TMP/macwash"
else
    log_err "curl or git is required."
fi

[[ -f "$SRC/macwash" ]] || log_err "Source missing 'macwash' entrypoint."

# ── Install ───────────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR/bin" "$CONFIG_DIR/lib"
cp -r "$SRC/bin/"*  "$CONFIG_DIR/bin/"  2>/dev/null && chmod +x "$CONFIG_DIR/bin/"* || true
cp -r "$SRC/lib/"*  "$CONFIG_DIR/lib/"  2>/dev/null || true

if [[ -w "$INSTALL_DIR" ]]; then
    cp "$SRC/macwash" "$INSTALL_DIR/macwash"
    chmod +x "$INSTALL_DIR/macwash"
else
    echo "  Admin access needed to install to $INSTALL_DIR"
    sudo cp "$SRC/macwash" "$INSTALL_DIR/macwash"
    sudo chmod +x "$INSTALL_DIR/macwash"
fi

# Patch SCRIPT_DIR inside macwash to point to CONFIG_DIR
sed -i '' "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$CONFIG_DIR\"|" "$INSTALL_DIR/macwash" 2>/dev/null || true

log_ok "MacWash installed to $INSTALL_DIR/macwash"
log_ok "Libraries installed to $CONFIG_DIR"
echo ""
echo "  Run: macwash"
echo ""
