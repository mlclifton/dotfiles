# Implementation Notes: Advanced Import & Path Restriction

These notes summarize the planned changes for the `dot-sync.sh` script to support multi-file selection, dotfile discovery, and path-restricted operations.

## Current State & Issues
- `import_config` only allows selecting one file at a time via `fzf`.
- The `find` command in `import_config` explicitly excludes dotfiles in its first pass.
- There is no mechanism to restrict operations (like `--add` or `--install`) to a specific directory.
- `git push` is called after every single file import, which is inefficient for batch operations.

## Planned Changes

### 1. Argument Parsing
- Support an optional positional argument `[PATH]` (e.g., `./dot-sync.sh --add ~/.config`).
- Store this in a variable (e.g., `TARGET_PATH`) and resolve it to an absolute path if provided.
- Update `show_help` to reflect this new capability.

### 2. Enhanced `import_config`
- **Discovery**: Update `find` to include dotfiles but exclude noise:
  ```bash
  find "${SEARCH_ROOT:-$HOME}" -type f 
      -not -path '*/.git/*' 
      -not -path '*/.cache/*' 
      -not -path '*/.local/share/*'
  ```
- **Selection**: Use `fzf --multi` and capture output using `mapfile -t`.
- **Categorization**: 
  - Add a "Apply to all" toggle for the category prompt when multiple files are selected.
- **Git Workflow**: 
  - Move `git push` outside the file processing loop.
  - Commit each file individually to keep history clean.

### 3. Path-Restricted `--install`
- In `install_dotfiles`, filter the `mappings` array.
- Only process files where the destination path (relative to `$HOME`) starts with the user-provided `TARGET_PATH`.

### 4. Technical Details to Remember
- Use `set -euo pipefail` (already present, maintain it).
- Ensure `confirm` prompts remain for symlink conversion as per safety requirements.
- Use `realpath` or `readlink -f` to normalize paths for comparison.

## Verification Tasks
- Add a test in `tests/run_tests.sh` that mocks `fzf` output to simulate multi-file selection.
- Add a test case for path-restricted installation to ensure only targeted files are symlinked.
- Verify that dotfiles are correctly discovered and handled.
