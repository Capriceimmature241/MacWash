# MacWash Roadmap 🗺️

This document outlines planned features and improvements for MacWash. Features are grouped by priority and release milestone.

---

## ✅ v1.0 — Current (Released)

- Interactive arrow-key menu
- `macwash clean` — deep cache cleanup (user, browser, dev tools, app caches)
- `macwash uninstall` — app uninstaller with leftover removal
- `macwash optimize` — 13 system optimization tasks
- `macwash analyze` — interactive disk usage browser
- `macwash status` — live system dashboard with health score
- `macwash history` — operation log viewer with JSON export
- Dry-run mode on all commands
- Path validation and system protection lists
- User whitelist support
- Homebrew tap (`brew tap toolka/macwash`)
- curl installer

---

## 🔵 v1.1 — Clean Expansion

**Goal:** Match the cleaning depth of the best Mac cleaners.

### Developer Cache Expansion
- [ ] Xcode DerivedData cleanup with project count reporting
- [ ] Xcode device support symbols (iOS, watchOS, tvOS — keep latest 2)
- [ ] Xcode documentation cache (remove old indexes)
- [ ] CoreSimulator caches and device temp files
- [ ] Android SDK and NDK cache cleanup
- [ ] Bun, mise, volta, fnm runtime caches
- [ ] uv Python package manager cache
- [ ] Conda/Anaconda metadata and tarball cache
- [ ] SBT, Ivy, Gradle daemon caches
- [ ] Turbo, Vite, Parcel, Webpack build caches
- [ ] Pre-commit hooks cache
- [ ] Swift Package Manager cache

### Browser Expansion
- [ ] Chrome old version cleanup (keep Current symlink, remove older)
- [ ] Edge old version cleanup
- [ ] Brave old version cleanup
- [ ] Browser Service Worker cache cleanup (with protection for offline web apps)
- [ ] Incomplete download file cleanup (.crdownload, .part, .download)

### App Cache Expansion (100+ apps)
- [ ] Communication — Discord, Legcord, Teams, WeChat, DingTalk, Telegram
- [ ] AI apps — ChatGPT, Claude, LM Studio, Cursor, Windsurf
- [ ] Design — Figma, Sketch, Adobe suite, Canva, Affinity
- [ ] Video — Final Cut Pro generated caches, DaVinci Resolve, JianyingPro
- [ ] Gaming — Steam, Epic Games, Battle.net, GOG Galaxy
- [ ] Media — Spotify (with offline music detection), VLC, IINA, Plex
- [ ] Productivity — Notion, Obsidian, Bear, Typora, Logseq

### System Deep Clean
- [ ] GPU/Metal shader cache cleanup (rebuildable, stale only)
- [ ] Incomplete Time Machine backup cleanup
- [ ] Stale wallpaper download files (idleassetsd temp)
- [ ] Browser code signature clone cleanup
- [ ] System diagnostic log cleanup
- [ ] Power log cleanup

---

## 🟡 v1.2 — Purge Command

**Goal:** Add project artifact cleaner for developers.

### `macwash purge` command
- [ ] Scan for `node_modules`, `target`, `.build`, `build`, `dist`, `venv`
- [ ] Interactive multi-select menu by project
- [ ] Size display per project artifact
- [ ] Recent projects (7d) marked and unselected by default
- [ ] Custom scan paths via `~/.config/macwash/purge_paths`
- [ ] `macwash purge --paths` to configure scan directories
- [ ] Support for Next.js `.next` cache, Python `__pycache__`, Flutter `.dart_tool`
- [ ] CACHEDIR.TAG support (skip directories that declare themselves caches)
- [ ] `fd` integration for faster scanning when available
- [ ] Dry-run mode

---

## 🟠 v1.3 — Installer Cleanup

**Goal:** Find and remove installer files wasting disk space.

### `macwash installer` command
- [ ] Scan for `.dmg`, `.pkg`, `.mpkg`, `.iso`, `.xip`, `.zip` files
- [ ] Scan locations: Downloads, Desktop, Documents, Homebrew cache, iCloud, Mail
- [ ] ZIP inspection — only flag ZIPs containing installer payloads
- [ ] Source label per file (Downloads, Homebrew, iCloud, etc.)
- [ ] Interactive multi-select with size display
- [ ] Select all / Invert selection shortcuts
- [ ] Dry-run mode

---

## 🔴 v1.4 — Shell Completion + Touch ID

**Goal:** Better terminal experience and sudo convenience.

### `macwash completion` command
- [ ] Bash completion setup
- [ ] Zsh completion setup
- [ ] Fish completion setup
- [ ] Auto-detect current shell

### `macwash touchid` command
- [ ] Enable Touch ID for sudo
- [ ] Disable Touch ID for sudo
- [ ] Status check
- [ ] Support for macOS Sonoma+ `sudo_local` file
- [ ] Backup existing sudo config before changes
- [ ] Clamshell mode detection (lid closed = skip Touch ID)
- [ ] Dry-run mode

---

## 🟣 v1.5 — Advanced Optimize

**Goal:** Match full professional-grade optimization.

### Additional optimize tasks
- [ ] **Periodic maintenance** — run macOS daily/weekly/monthly scripts if stale
- [ ] **Shared file list repair** — fix corrupted Finder favorites and recent documents
- [ ] **Disk health check** — verify filesystem integrity with diskutil
- [ ] **Spotlight orphan rules** — remove Spotlight rules for uninstalled apps
- [ ] **Legacy overrides audit** — remove hidden App Nap and disk-image overrides
- [ ] **Notification database cleanup** — clean old delivered notifications
- [ ] **Usage data cleanup** — clean old coreduet usage tracking data
- [ ] **Spotlight smart rebuild** — only rebuild if search is measured as slow
- [ ] **Permission repair** — fix user directory permission issues if detected
- [ ] **Network .DS_Store prevention** — stop Finder writing .DS_Store on network/USB drives

### Optimize whitelist
- [ ] `macwash optimize --whitelist` — interactive whitelist manager for optimization tasks
- [ ] Persistent whitelist config at `~/.config/macwash/whitelist_optimize`

---

## 🔵 v1.6 — Uninstall Improvements

**Goal:** Match professional app uninstallers.

### Uninstall enhancements
- [ ] Show last used date per app (Old/Recent label)
- [ ] Sort by name, size, or last used date
- [ ] Search/filter by app name
- [ ] Batch uninstall with single confirmation
- [ ] Homebrew cask detection (auto-use `brew uninstall --cask --zap`)
- [ ] Sibling install guard (don't delete shared data when two installs share bundle ID)
- [ ] LaunchServices unregister on removal
- [ ] Login item removal via AppleScript
- [ ] `--permanent` flag to bypass Trash and delete directly
- [ ] `--list` flag to show installed apps without interactive UI
- [ ] Direct uninstall: `macwash uninstall slack`
- [ ] Official uninstaller detection (Adobe, Parallels, etc.)

---

## 🟡 v2.0 — Analyze Enhancement

**Goal:** Visual disk analysis like DaisyDisk.

### Analyze improvements
- [ ] Treemap visualization in terminal (ASCII blocks)
- [ ] Large files report (files over 1GB)
- [ ] Old downloads report (files not accessed in 90+ days)
- [ ] External drive support (`macwash analyze /Volumes`)
- [ ] JSON output (`macwash analyze --json ~/Documents`)
- [ ] Preview file before deleting (P key)
- [ ] File info view (F key)
- [ ] Refresh current view (R key)
- [ ] Direct navigation into subdirectory (→ key)
- [ ] Cleanable items detection (caches, logs, etc.)

---

## 🟠 v2.1 — Status Enhancement

**Goal:** iStat Menus-level monitoring from terminal.

### Status improvements
- [ ] GPU usage monitoring
- [ ] Network per-interface speed (Wi-Fi vs Ethernet)
- [ ] Fan speed display (Apple Silicon + Intel)
- [ ] Per-core CPU view (toggle with C key)
- [ ] Process CPU alert banner (sustained high usage warning)
- [ ] Bluetooth device listing
- [ ] `--proc-cpu-threshold` flag for custom alert threshold
- [ ] Auto-JSON when output is piped

---

## 🔴 v2.2 — Update System

**Goal:** Professional self-update with version management.

### `macwash update` improvements
- [ ] Version discovery from GitHub releases
- [ ] Homebrew vs script install detection
- [ ] Background update check with banner in main menu
- [ ] `macwash update --nightly` for latest main branch
- [ ] `macwash update --force` for forced reinstall
- [ ] Checksum verification on download
- [ ] Rollback support

---

## 🟣 v3.0 — Quick Launchers

**Goal:** Integrate with popular launchers.

### Launcher integration
- [ ] Raycast script commands setup
- [ ] Alfred workflow setup
- [ ] Setup script: `macwash setup-launchers`
- [ ] Commands: MacWash Clean, Uninstall, Optimize, Analyze, Status

---

## 🔵 v3.1 — Official Homebrew Core

**Goal:** `brew install macwash` without tap.

### Requirements for Homebrew core submission
- [ ] 75+ GitHub stars
- [ ] Stable v1.x release with at least 3 versions
- [ ] Clean formula passing `brew audit --strict`
- [ ] Submit PR to `Homebrew/homebrew-core`

---

## 💡 Future Ideas (Backlog)

These are ideas being evaluated for future versions:

- **Duplicate file finder** — find and remove duplicate files across your disk
- **Large file scanner** — interactive report of files over configurable size threshold
- **App update checker** — check for outdated apps (not via App Store)
- **Startup items manager** — full view of everything that launches at login
- **Memory pressure monitor** — continuous background monitoring
- **Disk space timeline** — track how disk usage changes over time
- **Multi-user support** — clean caches for multiple user accounts (with sudo)
- **Scheduled cleaning** — run macwash clean on a schedule via launchd
- **Shell integration** — auto-clean on terminal open if last clean was 7+ days ago
- **Windows support** — experimental Windows PowerShell version

---

## 📝 Notes

- All features respect `--dry-run` mode before implementation
- All new commands follow the existing safety model (path validation, protection lists)
- Breaking changes to config file locations will include migration helpers
- Contributions for any roadmap item are welcome — open an issue first to discuss

---

*Last updated: v1.0.1*
*Feedback and feature requests welcome via [GitHub Issues](https://github.com/toolka/MacWash/issues)*
