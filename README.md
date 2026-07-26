<div align="center">

# MacWash 🧼

**Clean, optimize and speed up your Mac — free and open source.**

*Deep clean caches · Uninstall apps · Analyze disk · Optimize services · Monitor system*

<p>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey?style=flat-square" />
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/shell-bash%203.2%2B-green?style=flat-square" />
  <img src="https://img.shields.io/badge/version-1.0.0-orange?style=flat-square" />
  <img src="https://img.shields.io/github/stars/toolka/MacWash?style=flat-square" />
</p>

<!-- Add a screenshot or GIF here once available -->
<!-- <img src="docs/demo.gif" width="800" /> -->

</div>

---

> 💡 A native Mac app with GUI, menu bar HUD, and visual disk maps is coming.
> [Sign up for early access →](https://macwash.app)

---

## Why MacWash?

- **Free forever** — no subscription, no upsell, no telemetry
- **All-in-one** — clean, uninstall, analyze, optimize, and monitor in a single command
- **Safety-first** — dry-run mode, path validation, protection lists, and whitelist support
- **CleanMyMac alternative** — does the same deep cleaning, completely free from the terminal
- **Developer friendly** — cleans npm, pip, go, rust, ruby, docker caches automatically

---

## Features

- 🧹 **Deep clean** — user caches, browser data, dev tool caches, logs, crash reports
- 🗑️ **Smart uninstall** — removes apps and all leftover preferences, caches, and agents
- 📊 **Disk analyzer** — interactive browser sorted by size, move to Trash safely
- ⚡ **Optimize** — DNS flush, LaunchServices rebuild, Spotlight check, SQLite vacuum
- 📡 **Live status** — CPU, memory, disk, battery dashboard with health score

---

## Quick Start

**Install via script**

```bash
curl -fsSL https://raw.githubusercontent.com/toolka/MacWash/main/install.sh | bash
```

**Install via Homebrew tap**

```bash
brew tap toolka/macwash
brew install macwash
```

> `brew install macwash` via official Homebrew core is coming once we reach enough ⭐ stars.

---

## Usage

```bash
macwash                       # Interactive menu
macwash clean                 # Deep cache and junk cleanup
macwash clean --dry-run       # Preview only — no files deleted
macwash uninstall             # Remove apps + all leftovers
macwash optimize              # Flush DNS, rebuild caches, vacuum DBs
macwash analyze ~/Downloads   # Explore folder by size
macwash status                # Live CPU/memory/disk/battery dashboard
macwash history               # Show operation log
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
| `macwash update` | Update MacWash to latest version |
| `macwash remove` | Uninstall MacWash from your system |

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

## Requirements

- macOS 12 or later
- bash 3.2+ (pre-installed on all Macs)
- No dependencies required

---

## Contributing

Contributions are welcome. Open an issue or pull request.

```bash
# Clone
git clone https://github.com/toolka/MacWash.git
cd MacWash

# Test syntax
make test

# Run locally
bash macwash --help
```

---

## License

MIT — free forever. If MacWash helps you, give it a ⭐ and share it with others.
