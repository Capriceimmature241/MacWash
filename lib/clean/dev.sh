#!/bin/bash
# MacWash - Developer tool cache cleanup.

set -euo pipefail

# ── npm / pnpm / yarn / bun ──────────────────────────────────────────────────
clean_dev_npm() {
    # npm
    if command -v npm >/dev/null 2>&1; then
        local npm_cache; npm_cache=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
        [[ "$npm_cache" == /* ]] || npm_cache="$HOME/.npm"
        if [[ -d "$npm_cache" ]] && ! is_path_whitelisted "$npm_cache"; then
            if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
                npm cache clean --force >/dev/null 2>&1 || true
            fi
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} npm cache cleaned"
            note_activity
        fi
    fi

    # yarn
    safe_clean "$HOME/.yarn/cache"/*         "Yarn cache"
    safe_clean "$HOME/Library/Caches/Yarn"/* "Yarn v1 cache"

    # bun
    safe_clean "$HOME/.bun/install/cache"/*  "Bun cache"

    # pnpm
    safe_clean "$HOME/Library/pnpm/store"/*  "pnpm store cache"
}

# ── Python ────────────────────────────────────────────────────────────────────
clean_dev_python() {
    if command -v pip3 >/dev/null 2>&1 && pip3 --version >/dev/null 2>&1; then
        if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
            pip3 cache purge >/dev/null 2>&1 || true
        fi
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} pip cache cleaned"
        note_activity
    fi
    safe_clean "$HOME/.pyenv/cache"/*          "pyenv download cache"
    safe_clean "$HOME/.cache/pip"/*            "pip cache"
    safe_clean "$HOME/.cache/poetry"/*         "Poetry cache"
    safe_clean "$HOME/.pytest_cache"/*         "Pytest cache"
    safe_clean "$HOME/.cache/ruff"/*           "Ruff cache"
    safe_clean "$HOME/.cache/mypy"/*           "MyPy cache"
}

# ── Go ────────────────────────────────────────────────────────────────────────
clean_dev_go() {
    command -v go >/dev/null 2>&1 || return 0
    local gcache; gcache=$(go env GOCACHE 2>/dev/null || echo "$HOME/Library/Caches/go-build")
    if [[ -d "$gcache" ]] && ! is_path_whitelisted "$gcache"; then
        if [[ "${MACWASH_DRY_RUN:-0}" != "1" ]]; then
            go clean -cache >/dev/null 2>&1 || true
        fi
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Go build cache cleaned"
        note_activity
    fi
}

# ── Rust ──────────────────────────────────────────────────────────────────────
clean_dev_rust() {
    safe_clean "$HOME/.cargo/registry/cache"/* "Rust cargo cache"
    safe_clean "$HOME/.cargo/git"/*            "Cargo git cache"
    safe_clean "$HOME/.rustup/downloads"/*     "Rustup downloads"
}

# ── Ruby ──────────────────────────────────────────────────────────────────────
clean_dev_ruby() {
    safe_clean "$HOME/.rbenv/cache"/*           "rbenv cache"
    safe_clean "$HOME/.gem/specs"/*             "gem spec cache"
    safe_clean "$HOME/.bundle/cache"/*          "Bundler cache"
}

# ── Frontend build tools ──────────────────────────────────────────────────────
clean_dev_frontend() {
    safe_clean "$HOME/.cache/typescript"/*  "TypeScript cache"
    safe_clean "$HOME/.cache/electron"/*    "Electron cache"
    safe_clean "$HOME/.cache/node-gyp"/*    "node-gyp cache"
    safe_clean "$HOME/.turbo/cache"/*       "Turbo cache"
    safe_clean "$HOME/.vite/cache"/*        "Vite cache"
    safe_clean "$HOME/.cache/vite"/*        "Vite global cache"
    safe_clean "$HOME/.cache/webpack"/*     "Webpack cache"
    safe_clean "$HOME/.parcel-cache"/*      "Parcel cache"
    safe_clean "$HOME/.cache/eslint"/*      "ESLint cache"
}
