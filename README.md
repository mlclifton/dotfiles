# Dotfiles Manager

A robust, symlink-based dotfiles management system designed for Omarchy (Arch-based) Linux. This tool allows you to version control your configuration files and restore them (along with your system packages) easily on any machine.

## Purpose
The primary goal is to provide a safe, idempotent, and reversible way to manage system customizations. By using symbolic links, we ensure that the repository remains the "source of truth" while allowing the system to use the configurations in their standard locations (e.g., `~/.zshrc`).

## Core Principles
- **Safety First**: Existing files are backed up (`.bak`) before being replaced by symlinks.
- **Dry Run Support**: Users can preview all changes before they are applied.
- **Interactive Mode**: Fine-grained control over which configurations or packages are installed.
- **Secret Management**: Built-in pattern to include sensitive data (API keys, etc.) while keeping them out of Git.
- **Idempotency**: Running the scripts multiple times is safe and won't create redundant links or backups.

## Repository Structure
```text
dotfiles/
├── configs/            # Categorized configurations
│   ├── zsh/            # Zsh specific files (.zshrc, .zprofile)
│   ├── git/            # Git configuration (.gitconfig)
│   ├── omarchy/        # Omarchy-specific customizations
│   └── ...
├── packages/           # System package lists
│   └── pacman.list     # List of packages for restoration
├── scripts/
│   └── dot-sync.sh     # The main management script
├── tests/              # Test suite
│   └── run_tests.sh    # Script to run sandboxed integration tests
├── .gitignore          # Prevents tracking of secrets and temp files
└── README.md           # This file
```

## Features & Usage

### The `dot-sync.sh` Script
This is the primary tool for synchronizing your environment. By default, the script runs in **interactive mode**, prompting for confirmation before each major action.

**Commands:**
- `--install [PATH]`: Installs dotfiles (creates symlinks). If `[PATH]` is provided, only files targeting that path are processed.
- `--add [PATH]`: Interactively selection and import of new files into the repository. If `[PATH]` is provided, the search is restricted to that directory.
- `--packages`: Reinstalls system packages from the package list.
- `--sync`: Pulls latest changes from GitHub and/or pushes local repo changes.
- `--yes` (or `-y`): Non-interactive mode (assumes 'yes' to all prompts).
- `--dry-run`: Shows what *would* happen without making any changes to the filesystem.
- `--help`: Displays usage information.

### Safety & Migration Strategy
To ensure **zero data loss** during migration or updates, this tool employs a multi-layered safety approach:

1.  **Pre-flight Snapshot:** Before modifying any file, the script creates a timestamped archive (e.g., `~/.dotfiles_backup_20240204_1200.tar.gz`) containing all the files that are about to be touched.
2.  **Smart Conflict Resolution:** If a file exists at the target location and differs from the repository version, the script will:
    -   **Show the Diff:** Display a color-coded comparison of the local file vs. the repository file.
    -   **Ask for Action:**
        -   `[K]eep Local`: Overwrite the repository file with your local version, then symlink.
        -   `[O]verwrite`: Backup the local file (`.bak`) and replace it with the repository version.
        -   `[S]kip`: Do nothing for this file.
3.  **Atomic Backups:** When replacing a local file, the original is always renamed (e.g., `~/.zshrc.bak`) rather than deleted.
4.  **Dry-Run Verification:** You can (and should) always run with `--dry-run` first to see exactly what will happen.

### Testing Strategy
To guarantee reliability without risking your actual machine, the repository includes a comprehensive test suite in the `tests/` directory.

-   **Sandboxed Integration Tests:** The testing script (`tests/run_tests.sh`) creates a temporary, isolated environment (a fake `$HOME` and fake repo).
-   **Verification Scenarios:**
    -   Verifies that symlinks are created correctly.
    -   Verifies that existing files are backed up correctly.
    -   Verifies that `--dry-run` makes absolutely no changes.
    -   Verifies that the Pre-flight Snapshot is created.
-   **Requirement:** Tests must pass before any changes are committed to the repository.

### Secret Management
To handle sensitive information, the system looks for `.secrets` files within config directories. These are sourced by your main configs (e.g., `.zshrc` sources `~/.zsh_secrets`) but are explicitly ignored by `.gitignore` to prevent accidental commits.

### How to Add a New Config
1.  Run `scripts/dot-sync.sh --add`.
2.  Use the interactive picker (`fzf`) to select one or more files (use **Tab** for multi-select).
3.  Confirm the selection and provide a category (e.g., `zsh`) when prompted.
4.  Run `scripts/dot-sync.sh --install` to create the symlink for the newly added files.
5.  (Optional) Push changes to the remote if not already done during `--add`: `scripts/dot-sync.sh --sync`.

## Troubleshooting
- **Log File:** Check `dot-sync.log` for detailed execution logs.
- **Backups:** If something goes wrong, check for `.bak` files in your home directory or the timestamped tarball in `~/`.

### Coding Standards
- **Language:** Bash (Targeting Bash 4+).
- **Safety:** Script must start with `set -euo pipefail` to ensure fail-fast behavior.
- **Style:** Use snake_case for variables/functions. Variables should be quoted to handle spaces in paths.
- **Output:** Use ANSI escape codes for colors (Green=Success, Yellow=Warning, Red=Error, Blue=Info).

### Architecture Details
1.  **Mapping Logic:**
    -   Files located in `configs/<category>/<filename>` must map to `$HOME/<filename>`.
    -   Example: `configs/zsh/.zshrc` -> `~/.zshrc`.
    -   The script should recurse through all directories in `configs/`.

2.  **Safe Execution Wrapper:**
    -   Create a function `run_cmd()` that accepts a command string or arguments.
    -   If `DRY_RUN` is true, print the command with a specific prefix (e.g., `[DRY-RUN] rm ...`) and return 0.
    -   If `DRY_RUN` is false, execute the command and check its exit status.

3.  **Conflict Resolution Flow:**
    -   Use `diff -u --color=always <local> <repo>` to show changes.
    -   Loop input until valid response: `[k]eep`, `[o]verwrite`, `[s]kip`.
    -   **Keep:** `cp <local> <repo>` (then link).
    -   **Overwrite:** `mv <local> <local>.bak` (then link).

4.  **Snapshotting:**
    -   Command: `tar -czf "$HOME/.dotfiles_backup_$(date +%s).tar.gz" -T <list_of_files_to_change>`.
    -   This must run *before* any file manipulation loop starts.

5.  **Git Sync:**
    -   `git pull` (fast-forward only recommended).
    -   `git add -A`.
    -   `git commit -m "Auto-sync: $(date)"`.
    -   `git push`.

6.  **Testing Requirements:**
    -   Tests must use a temporary directory as a fake `$HOME`.
    -   Use `expect` or heredocs to simulate user input for interactive prompts in tests.

