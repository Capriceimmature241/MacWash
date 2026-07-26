# MacWash 🧼

> Clean, optimize and speed up your Mac. Free and open source — clean, uninstall, analyze, optimize, and monitor from the terminal.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey?style=flat-square" />
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/shell-bash%203.2%2B-green?style=flat-square" />
  <img src="https://img.shields.io/badge/version-1.0.0-orange?style=flat-square" />
</p>

MacWash is a free, open-source macOS system maintenance CLI. It combines deep cache cleanup,
smart app uninstall, disk analysis, system optimization, and a live status dashboard into a single command.

> 💡 A native Mac app with GUI, menu bar HUD, and visual disk maps is coming.
> [Sign up for early access →](https://macwash.app)

---

## Features

- **🧹 Deep clean** — user caches, browser data, dev tool caches, logs, crash reports
- **🗑️ Smart uninstall** — removes apps and all leftover preferences, caches, and agents
- **📊 Disk analyzer** — interactive browser sorted by size, move to Trash safely
- **⚡ Optimize** — DNS flush, LaunchServices rebuild, Spotlight check, SQLite vacuum
- **📡 Live status** — CPU, memory, disk, battery dashboard with health score

---

## Quick Start

**Install via Homebrew tap**

```bash
brew tap macwash/homebrew
brew install macwash
```

**Or via script**

```bash
curl -fsSL https://raw.githubusercontent.com/toolka/MacWash/main/install.sh | bash
```

> Coming soon: `brew install macwash` (official Homebrew core — once we hit enough stars ⭐)

# Run
macwash                       # Interactive menu
macwash clean                 # Deep cleanup
macwash clean --dry-run       # Preview only — no changes made
macwash uninstall             # Remove apps + leftovers
macwash optimize              # Refresh caches & services
macwash analyze ~/Downloads   # Explore a folder by size
macwash status                # Live system dashboard
macwash history               # Operation log
```

---

## Commands

| Command | Description |
|---|---|
| `macwash` | Interactive arrow-key menu |
| `macwash clean [--dry-run]` | Deep cache and junk cleanup |
| `macwash uninstall [--dry-run]` | App uninstaller with leftover removal |
| `macwash optimize [--dry-run]` | Rebuild caches, flush DNS, vacuum DBs |
| `macwash analyze [path]` | Interactive disk usage browser |
| `macwash status [--json]` | Live CPU/memory/disk/battery dashboard |
| `macwash history [--json]` | Show operation history |
| `macwash update` | Update MacWash |
| `macwash remove` | Uninstall MacWash |

---

## Safety

MacWash is safety-first by design:

- **Path validation** on every deletion — absolute paths, no traversal, no symlink tricks
- **Protection lists** — system-critical bundles and paths are never touched
- **Dry-run mode** — preview all changes before applying (`--dry-run`)
- **Whitelist** — add paths to `~/.config/macwash/whitelist` to protect them forever
- **Trash routing** — Analyze moves files to Trash (recoverable), not permanent delete
- **Operation log** — every action logged to `~/Library/Logs/macwash/operations.log`

---

## Install via Homebrew (coming soon)

```bash
brew install macwash
```

---

## License

MIT — free forever. If it helps you, give it a ⭐ and share it.
