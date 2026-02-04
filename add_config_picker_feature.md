# Solution Description: Advanced Config Import & Path Restriction

This feature enhances the `dot-sync.sh` script to support multi-file selection, dotfile discovery, and targeted operations via path restrictions.

## Core Objectives
- **Multi-File Efficiency**: Import multiple configurations in a single session.
- **Improved Discovery**: Seamlessly find and include hidden dotfiles while filtering out system noise.
- **Targeted Operations**: Restrict the scope of `--add` or `--install` to specific subdirectories.
- **Source of Truth**: Maintain the repository as the primary record before local modification.

## Technical Specifications

### 1. Dependencies
- **fzf**: Used with `--multi` for batch selection.
- **find**: Used with custom filters to include hidden files and exclude noise.
- **git**: Used for granular commits and batched synchronization.

### 2. Implementation Logic

#### A. File Selection & Path Restriction
- **Search Root**: Defaults to `$HOME`, but can be overridden by an optional CLI path argument (e.g., `scripts/dot-sync.sh --add ~/.config/nvim`).
- **Discovery**: `find "$SEARCH_ROOT" -maxdepth 2 -type f` refined to:
    - Include dotfiles (e.g., `.zshrc`).
    - Exclude noisy or sensitive directories (e.g., `.git/`, `.cache/`, `.local/`, `.ssh/`).
- **Interaction**: `fzf --multi --prompt="Select file(s) to import (Tab to multi-select): "`.
- **Result**: Capture multiple paths into a Bash array.

#### B. Categorization Workflow
- For the first file, prompt for a "Category" (e.g., `zsh`).
- If multiple files are selected, provide an option to "Apply this category to all remaining files".
- If "Apply to all" is declined, prompt for each file individually.

#### C. Batch Import & Sync
1. **Iterate**: Process each selected file:
    - Copy to `configs/<category>/<filename>`.
    - `git add <new_file>`
    - `git commit -m "Add <filename> to <category> configs"`
2. **Push**: Execute `git push` once after all files in the batch are committed.

#### D. Path-Restricted Install
- If a path argument is provided with `--install`, only files whose target mapping falls within that path will be processed.
- Example: `scripts/dot-sync.sh --install ~/.config` will only link files that would be placed inside `~/.config`.

### 3. Architecture & Refactoring
- **Argument Parser**: Support an optional positional `[PATH]` argument.
- **Logic Isolation**: The `import_config` function will handle its own loop and user interaction for categorization.
- **Mapping Filter**: The `install_dotfiles` function will include a conditional check against the restricted path.

## Safety Considerations
- **Manual Confirmation**: Each symlink conversion requires explicit confirmation, even in batch mode.
- **Pre-flight Snapshot**: The snapshotting logic must account for only the files within the restricted path if specified.