# Changelog

All notable changes to MacWash are documented here.

---

## [v1.0.4] — 2026-07-27

### Fixed
- **Status dashboard now shows live updating data** (refreshes every ~3 seconds)
- **Q to quit** now works properly in Status view
- Fixed terminal handling when launching Status from main menu

### Added
- **Arrow keys navigation** in process list (↑↓ to select)
- **K key to kill** selected process
- **J/P keys** for vim-style navigation (down/up)
- Process selection highlight with ▶ indicator
- Protection against killing system-critical processes

### Technical
- Disabled strict mode after sourcing to allow read with timeout
- Reset terminal state before entering TUI
- Read input from /dev/tty for reliable keyboard handling
- Background network sampler for non-blocking updates

---

## [v1.0.3] — 2026-07-27

### Fixed
- Minor status display improvements

---

## [v1.0.2] — 2026-07-27

### Added
- `macwash analyze` — folder drill-down with Enter/→ key
- `macwash analyze` — go back up with ← or Backspace key
- `macwash analyze` — expand folder inline with E key (shows contents indented)
- `macwash analyze` — collapse expanded folder with E key again
- `macwash analyze` — delete individual files inside expanded folders
- Visual indicators: ▶ collapsed folder, ▼ expanded folder, ↳ child item
- Breadcrumb path display in analyze header

### Fixed
- Analyze navigation now shows correct folder type icons

---

## [v1.0.1] — 2026-07-27

### Added
- 6 new optimize tasks (now 13 total):
  - Broken preference file repair (plutil lint scan)
  - Dock icon cache refresh
  - Memory pressure relief (sudo purge when needed)
  - Network stack refresh (flush routing table + ARP cache)
  - Login items audit (finds stale startup items)
  - Launch agents cleanup (removes dead LaunchAgents 30d+)
- Homebrew tap: `brew tap toolka/macwash && brew install macwash`
- `toolka/homebrew-macwash` tap repository

### Fixed
- Uptime calculation in `macwash status` and `macwash optimize` (was showing negative value)
- Uninstall menu Space key selection now works correctly
- Terminal properly restored before confirmation prompt in uninstall
- Dock refresh no longer kills terminal session
- All internal variable names fully rebranded to MACWASH_*

---

## [v1.0.0] — 2026-07-26

### Initial Release

**Commands:**
- `macwash` — interactive arrow-key menu
- `macwash clean` — deep cache and junk cleanup
- `macwash uninstall` — app uninstaller with leftover removal
- `macwash optimize` — 7 system optimization tasks
- `macwash analyze` — interactive disk usage browser
- `macwash status` — live CPU/memory/disk/battery dashboard
- `macwash history` — operation log viewer with JSON export

**Clean covers:**
- User app caches
- Browser caches (Chrome, Safari, Firefox, Brave, Edge)
- Developer tool caches (npm, pnpm, pip, go, rust, ruby)
- System logs and crash reports
- App-specific caches

**Optimize tasks (7):**
- DNS cache flush
- QuickLook thumbnails refresh
- LaunchServices database rebuild
- Spotlight index verification
- Saved app states cleanup
- SQLite database vacuum
- Quarantine history cleanup

**Safety:**
- Path validation on every deletion
- System-critical path protection
- Dry-run mode on all commands
- User whitelist support
- Trash routing in Analyze
- Full operation log

**Install:**
- curl installer
- MIT licence
