<div align="center">

# MacWash 🧼

**Clean, optimize and speed up your Mac — free and open source.**

*Deep clean caches · Uninstall apps · Analyze disk · Optimize services · Monitor system*

<p>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey?style=flat-square" />
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/shell-bash%203.2%2B-brightgreen?style=flat-square" />
  <img src="https://img.shields.io/github/v/release/toolka/MacWash?style=flat-square&color=orange" />
  <img src="https://img.shields.io/github/stars/toolka/MacWash?style=flat-square&color=yellow" />
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square" />
  <img src="https://img.shields.io/badge/contributions-welcome-brightgreen?style=flat-square" />
</p>

</div>

---

> 💡 A native Mac app with GUI, menu bar HUD, and visual disk maps is coming.
> [Sign up for early access →](https://macwash.app)

---

## Why MacWash?

- **Free forever** — no subscription, no upsell, no telemetry
- **All-in-one** — clean, uninstall, analyze, optimize, and monitor in a single command
- **Safety-first** — dry-run mode, path validation, system protection lists, whitelist support
- **Developer friendly** — cleans npm, pip, go, rust, ruby, docker, conda caches automatically
- **Open source** — MIT licence, fully auditable, no hidden behaviour

---

## Features

### 🧹 Deep System Cleanup
Remove gigabytes of junk from your Mac:
- User app caches, browser data (Chrome, Safari, Firefox, Brave, Edge)
- Developer tool caches — npm, pnpm, bun, yarn, pip, uv, go, rust, ruby, conda, docker
- System logs, crash reports, temp files
- App-specific caches — Slack, Spotify, Figma, VS Code, Zoom, Discord, and 100+ more
- Orphaned app data from already-uninstalled applications
- Finder metadata (.DS_Store files)
- Trash emptying

### 🗑️ Smart App Uninstaller
Remove apps and every trace they leave behind:
- Full app bundle removal
- Leftover preferences, caches, logs, cookies, WebKit storage
- Launch agents and daemons cleanup
- Application Support remnants

### 📊 Interactive Disk Analyzer
Explore what's eating your disk space:
- Browse folders sorted by size with visual bars
- Navigate with arrow keys
- Move items to Trash safely via Finder
- Open items directly in Finder
- JSON output for scripting

### ⚡ System Optimizer — 13 tasks
Run all maintenance tasks in one command:
1. **DNS cache flush** — faster browsing, fixes connectivity issues
2. **QuickLook refresh** — fixes broken thumbnails and previews
3. **LaunchServices rebuild** — fixes "Open With" menu issues
4. **Spotlight verification** — ensures search is working
5. **App saved states** — removes old state files (30d+)
6. **SQLite vacuum** — compacts Mail, Safari, Messages databases
7. **Quarantine DB cleanup** — clears Gatekeeper download history
8. **Preference file repair** — detects and removes corrupted .plist files
9. **Dock refresh** — clears broken icon caches
10. **Memory optimization** — releases inactive memory when pressure is high
11. **Network stack refresh** — flushes routing table and ARP cache
12. **Login items audit** — finds stale startup items pointing to missing apps
13. **Launch agents cleanup** — removes dead LaunchAgents (30d+ old, binary missing)

### 📡 Live System Dashboard
Real-time system health with health score:
- CPU usage and load
- Memory usage and pressure
- Disk usage and free space
- Battery level, health, cycles, temperature
- Top processes by CPU
- JSON output for automation

### 📋 Operation History
Full audit trail of everything MacWash does:
- Timestamped operation log
- Session start/end tracking
- JSON export for scripting

---

## Quick Start

**Install via script** (recommended — works on all Macs, no Xcode CLT needed)

```bash
curl -fsSL https://raw.githubusercontent.com/toolka/MacWash/main/install.sh | bash
```

**Install via Homebrew tap**

```bash
brew tap toolka/macwash
brew trust toolka/macwash
brew install macwash
```

---

## Usage

```bash
macwash                       # Interactive arrow-key menu
macwash clean                 # Deep cache and junk cleanup
macwash clean --dry-run       # Preview only — no files deleted
macwash uninstall             # Remove apps + all leftovers
macwash optimize              # Run all 13 optimization tasks
macwash analyze               # Explore disk usage by size
macwash analyze ~/Downloads   # Explore a specific folder
macwash status                # Live CPU/memory/disk/battery dashboard
macwash status --json         # Machine-readable output
macwash history               # Show operation log
macwash history --json        # Export history as JSON
macwash update                # Update MacWash to latest version
macwash remove                # Uninstall MacWash from your system
```

---

## Commands Reference

| Command | Description |
|---|---|
| `macwash` | Interactive arrow-key menu |
| `macwash clean [--dry-run]` | Deep cache and junk cleanup |
| `macwash uninstall [--dry-run]` | App uninstaller with leftover removal |
| `macwash optimize [--dry-run]` | Run all 13 system optimization tasks |
| `macwash analyze [path]` | Interactive disk usage browser |
| `macwash status [--json]` | Live CPU/memory/disk/battery dashboard |
| `macwash history [--json]` | Show operation history |
| `macwash update` | Update MacWash to latest version |
| `macwash remove [--dry-run]` | Uninstall MacWash from your system |

### Global Options

| Option | Description |
|---|---|
| `--dry-run` | Preview all changes without applying them |
| `--debug` | Show detailed debug output |
| `--help` | Show help |
| `--version` | Show version |

---

## Safety

MacWash is safety-first by design. Every destructive operation passes through multiple validation layers:

### Path Validation
- **Absolute paths only** — relative paths are always rejected
- **No path traversal** — `..` as a path component is rejected
- **No control characters** — paths with `\n`, `\t` or other control chars rejected
- **Symlink resolution** — symlinks pointing to protected system paths are rejected
- **Ancestor symlink guard** — parent directory symlinks are resolved and checked too

### Protection Lists
System-critical paths that are **never** touched:
```
/ /System /bin /sbin /usr /etc /Library/Extensions
/Library/Keychains /Applications/Finder.app /Applications/Safari.app
```

Protected app categories (data never deleted):
- Password managers (1Password, Bitwarden, LastPass)
- VPN and proxy tools (WireGuard, Tailscale, Shadowsocks)
- AI tools (Claude, ChatGPT, Cursor, Ollama)
- IDEs (JetBrains, VS Code, Xcode data)
- iCloud / Mobile Documents

### User Controls
- **`--dry-run`** — preview all changes before applying
- **Whitelist** — add paths to `~/.config/macwash/whitelist` to protect them forever
- **Trash routing** — Analyze moves files to Trash (recoverable), not permanent delete
- **Operation log** — every action logged to `~/Library/Logs/macwash/operations.log`
- **Confirmation prompts** — destructive operations require explicit confirmation

---

## Tips

- Always run `--dry-run` first to preview what will be cleaned
- Use `macwash clean` for apps already uninstalled, `macwash uninstall` for installed apps
- Navigate with arrow keys `↑↓` and Vim bindings `h/j/k/l`
- `macwash history` shows exactly what was cleaned and when
- `macwash status --json` works great with `jq` for monitoring scripts

---

## Requirements

- macOS 12 or later (Intel + Apple Silicon)
- bash 3.2+ (pre-installed on all Macs)
- No compilation required — pure shell

---

## Contributing

We welcome contributions from everyone — bug fixes, new features, documentation, and testing on different macOS versions.

Read [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

**You can help by:**
- 🐛 Fixing bugs
- ✨ Adding new cleaning modules or app support
- 🎨 Improving the UI
- 📖 Improving documentation
- 🧪 Testing on different macOS versions
- 🌍 Reporting issues

Look for [`good first issue`](https://github.com/toolka/MacWash/labels/good%20first%20issue) labels for easy entry points.

```bash
# Clone and test locally
git clone https://github.com/toolka/MacWash.git
cd MacWash
make test
bash macwash --help
```

Before starting large changes, open an Issue to discuss your proposal. We appreciate every contribution — large or small.

---

## License

MIT — free forever. If MacWash helps you, give it a ⭐ and share it with others.
