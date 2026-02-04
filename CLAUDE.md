# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Symlink-based dotfiles manager for Omarchy (Arch Linux). A single Bash script (`scripts/dot-sync.sh`) manages configuration files by creating symlinks from a categorized repo structure to `$HOME`. Pure Bash 4+ with dependencies on `fzf`, `git`, and `tar`.

## Commands

```bash
# Install configs (create symlinks from configs/ to $HOME)
./scripts/dot-sync.sh --install

# Install only configs under a specific path
./scripts/dot-sync.sh --install .config/nvim

# Import new config files into the repo interactively (uses fzf)
./scripts/dot-sync.sh --add

# Pull/push git changes
./scripts/dot-sync.sh --sync

# Preview any command without making changes
./scripts/dot-sync.sh --dry-run --install

# Non-interactive mode (assume yes)
./scripts/dot-sync.sh -y --install

# Run the full test suite
./tests/run_tests.sh

# Run tests interactively (pause between each test)
./tests/run_tests.sh -i
```

## Architecture

**File mapping:** `configs/<category>/<relative_path>` symlinks to `$HOME/<relative_path>`. The category directory is organizational only and does not appear in the target path. Example: `configs/nvim/.config/nvim/init.vim` → `~/.config/nvim/init.vim`.

**dot-sync.sh** key functions:
- `install_dotfiles()` — scans `configs/` recursively, creates symlinks via `link_file()`
- `import_config()` — uses fzf for multi-file selection, copies to `configs/<category>/`, commits each file individually
- `resolve_conflict()` — shows diff, prompts for keep-local/overwrite/skip
- `sync_git()` — pull --ff-only, stage, commit, push
- `create_snapshot()` — timestamped tarball backup before modifications
- `run_cmd()` — execution wrapper that respects `DRY_RUN` flag

**Test suite** (`tests/run_tests.sh`) runs sandboxed integration tests using temporary directories for both `$HOME` and the repo. Tests cover: fresh install, backup existing, conflict resolution, dry run, idempotency, path-restricted install, and multi-file import.

## Coding Conventions

- Bash 4+ with `set -euo pipefail`
- `snake_case` for functions and variables, `UPPER_CASE` for constants/globals
- Color-coded log output: `[INFO]` blue, `[SUCCESS]` green, `[WARN]` yellow, `[ERROR]` red, `[DRY-RUN]` yellow
- Safety patterns: pre-flight snapshot before modifying files, `.bak` backups of replaced files, dry-run support on all destructive operations

## Secret Management

Secrets (API keys, tokens) are kept in `~/.zsh_secrets` or similar files sourced at shell startup. These are excluded from git via `.gitignore` patterns (`*.secrets`, `*.local`, `.env`). Example templates (`.zsh_secrets.example`) are checked in to show the expected format.
