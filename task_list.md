# Dotfiles Project Task List

## Phase 5: Interactive Config Import (`--add`)
- [x] **File Selection Interface**
    - [x] Implement a file picker function to select files from `$HOME` to import.
    - [x] Support using `fzf` if available, falling back to a standard Bash `select` menu or path input.
    - [x] Prompt the user to assign a "Category" (folder under `configs/`) for the selected file(s).
- [x] **Import & Sync Logic**
    - [x] Copy the selected file(s) to the target `configs/<category>/` directory.
    - [x] Perform a git sync (commit and push) *immediately* after copying to ensure the repo is the source of truth.
- [x] **Symlink Conversion**
    - [x] Trigger the symlinking process for the newly added file(s).
    - [x] **Constraint**: Enforce manual user confirmation before replacing the original file with the symlink.

## Phase 6: GitHub Remote Integration
- [x] **Remote Setup Helper**
    - [x] Guide the user through creating a GitHub repository (using `gh` CLI or manual instructions).
    - [x] command to link the local repository to the remote (`git remote add origin`).
    - [x] Verify the remote connection and push the `main` branch.
