.PHONY: all check format test install clean

# MacWash v1.0.2 — Clean, optimize and speed up your Mac
INSTALL_DIR ?= /usr/local/bin

all: check

check:
	@echo "Checking shell scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		find bin lib -name '*.sh' | xargs shellcheck --shell=bash --severity=warning; \
		echo "shellcheck OK"; \
	else \
		echo "shellcheck not installed (brew install shellcheck)"; \
	fi
	@if command -v shfmt >/dev/null 2>&1; then \
		find bin lib -name '*.sh' | xargs shfmt -d -i 4 -ln bash; \
		echo "shfmt OK"; \
	else \
		echo "shfmt not installed (brew install shfmt)"; \
	fi

format:
	@command -v shfmt >/dev/null 2>&1 || { echo "brew install shfmt"; exit 1; }
	find bin lib -name '*.sh' | xargs shfmt -w -i 4 -ln bash

test:
	@echo "Running basic syntax checks..."
	find bin lib -name '*.sh' -exec bash -n {} \; && echo "Syntax OK"

install:
	@echo "Installing to $(INSTALL_DIR)..."
	cp macwash "$(INSTALL_DIR)/macwash"
	chmod +x "$(INSTALL_DIR)/macwash"
	@echo "Installed."

clean:
	@echo "Nothing to clean (pure shell project)."
