# Contributing to MacWash 🧼

Thank you for your interest in contributing to MacWash! We welcome contributions from everyone — whether it's fixing a typo, improving documentation, or building entirely new features.

---

## 🚀 Quick Start

### 1. Fork the repository

Click the **Fork** button on [GitHub](https://github.com/toolka/MacWash).

### 2. Clone your fork

```bash
git clone https://github.com/YOUR_USERNAME/MacWash.git
cd MacWash
```

### 3. Create a new branch

```bash
git checkout -b feature/my-new-feature
```

Use prefixes like:
- `feature/` for new features
- `fix/` for bug fixes
- `docs/` for documentation
- `refactor/` for code improvements

### 4. Make your changes

Edit the code, then test before submitting:

```bash
# Run syntax check
make test

# Test locally
bash macwash --help
bash macwash clean --dry-run
bash macwash status
```

### 5. Commit your changes

```bash
git add .
git commit -m "Add feature: better cache cleanup"
```

Write clear, descriptive commit messages. See [Commit Guidelines](#commit-guidelines).

### 6. Push to your fork

```bash
git push origin feature/my-new-feature
```

### 7. Open a Pull Request

Go to your fork on GitHub and click **New Pull Request**.

---

## 📋 Contribution Guidelines

### Code Style

- **Bash 3.2 compatible** — MacWash must work on the bash version that ships with macOS
- **shellcheck clean** — run `shellcheck macwash bin/*.sh lib/**/*.sh` and fix warnings
- Use 4-space indentation
- Use `[[ ]]` for conditionals (not `[ ]`)
- Quote variables: `"$var"` not `$var`
- Use `local` for function variables
- Add comments for non-obvious logic

### Safety First

MacWash is a system tool that deletes files. Safety is paramount:

- **Never delete without validation** — use `validate_safe_path()` before any removal
- **Test with `--dry-run`** — all commands must support dry-run mode
- **Add to protection lists** — system-critical paths go in `lib/core/protection.sh`
- **Log operations** — use `log_operation()` for audit trails

### Commit Guidelines

Write clear commit messages:

```
Add feature: Xcode DerivedData cleanup

- Scan ~/Library/Developer/Xcode/DerivedData
- Report project count and total size
- Add to clean command under developer tools section
- Respect --dry-run flag
```

Format:
- First line: imperative mood, under 72 characters
- Blank line
- Body: explain what and why (not how)

### Pull Request Guidelines

- **Keep changes focused** — one feature or fix per PR
- **Test thoroughly** — test on both Intel and Apple Silicon if possible
- **Update documentation** — update README, help text, or CHANGELOG as needed
- **Add to CHANGELOG** — document your changes under `## [Unreleased]`

### Large Changes

For significant changes (new commands, architecture changes, new dependencies):

1. **Open an Issue first** to discuss your proposal
2. Wait for feedback before starting major work
3. Reference the issue in your PR

---

## 🏷️ Good First Issues

New to MacWash? Look for issues labeled:

- [`good first issue`](https://github.com/toolka/MacWash/labels/good%20first%20issue) — great for newcomers
- [`help wanted`](https://github.com/toolka/MacWash/labels/help%20wanted) — we'd love help with these
- [`documentation`](https://github.com/toolka/MacWash/labels/documentation) — improve docs

Easy first contributions:
- Fix typos in README or help text
- Add a new app to the cache cleanup list
- Improve error messages
- Add shellcheck fixes
- Test on a macOS version we haven't tested

---

## 🗺️ What to Work On

Check the [ROADMAP.md](ROADMAP.md) for planned features. Items marked with `[ ]` are open for contribution.

Popular areas:
- **New cleaning modules** — add support for more apps and caches
- **Uninstall improvements** — better leftover detection
- **Status enhancements** — more system metrics
- **Documentation** — tutorials, examples, translations

---

## 🧪 Testing

### Run syntax check

```bash
make test
```

### Test commands manually

```bash
# Always test with --dry-run first
bash macwash clean --dry-run
bash macwash uninstall --dry-run
bash macwash optimize --dry-run

# Test interactive features
bash macwash
bash macwash analyze ~/Downloads
bash macwash status
```

### Test on different macOS versions

If you have access to multiple macOS versions, please test on:
- macOS 14 Sonoma
- macOS 13 Ventura
- macOS 12 Monterey

---

## 📁 Project Structure

```
MacWash/
├── macwash              # Main entry point
├── bin/                 # Command scripts
│   ├── clean.sh
│   ├── uninstall.sh
│   ├── optimize.sh
│   ├── analyze.sh
│   ├── status.sh
│   └── history.sh
├── lib/
│   ├── core/            # Core modules
│   │   ├── base.sh      # Colors, constants, utilities
│   │   ├── ui.sh        # Terminal UI (cursor, keyboard, spinner)
│   │   ├── protection.sh # Path validation and protection lists
│   │   ├── file_ops.sh  # Safe file operations
│   │   ├── log.sh       # Operation logging
│   │   └── ...
│   ├── clean/           # Clean command modules
│   ├── optimize/        # Optimize command modules
│   └── uninstall/       # Uninstall command modules
├── Formula/             # Homebrew formula
├── install.sh           # curl installer
├── Makefile             # Build and test
└── docs/                # Documentation (coming)
```

---

## 💬 Getting Help

- **Questions?** Open a [Discussion](https://github.com/toolka/MacWash/discussions)
- **Found a bug?** Open an [Issue](https://github.com/toolka/MacWash/issues)
- **Have an idea?** Open a [Feature Request](https://github.com/toolka/MacWash/issues/new?template=feature_request.md)

---

## 🙏 Thank You

Every contribution matters — whether it's a one-line fix or a major feature. Thank you for helping make MacWash better for everyone!

If MacWash helps you, consider:
- ⭐ Starring the repo
- 📢 Sharing with friends and colleagues
- 📝 Writing about it

---

*Happy cleaning!* 🧼
