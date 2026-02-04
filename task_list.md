# Dotfiles Project Task List

## Phase 7: Advanced Import & Path Restriction
- [x] **Argument Parsing Enhancements**
    - [x] Add support for an optional `[PATH]` argument to the CLI.
    - [x] Update `show_help` to document the path restriction feature.
- [x] **Improve File Discovery (`--add`)**
    - [x] Update `find` command to include dotfiles in the initial search.
    - [x] Exclude common noisy directories (e.g., `.git`, `.cache`, `.local`, `.ssh`) to keep the list manageable.
    - [x] Restrict the search root to the provided `[PATH]` if it is specified.
- [x] **Update File Selection**
    - [x] Add `--multi` flag to `fzf` in `import_config`.
    - [x] Use `mapfile` or `readarray` to handle multiple selected paths.
- [x] **Path-Restricted Sync/Install (`--install`)**
    - [x] Filter the mappings in `install_dotfiles` to only include files that target the provided `[PATH]` if specified.
- [x] **Refactor Import Loop**
    - [x] Implement a loop to process each selected file.
    - [x] Add logic to "Apply Category to All" to reduce repetitive prompts.
- [x] **Optimize Git Sync**
    - [x] Commit files individually within the loop with descriptive messages.
    - [x] Batch the `git push` operation to run once after the loop completes.
- [x] **Verification**
    - [x] Add an integration test in `tests/run_tests.sh` for multi-file and dotfile import.
    - [x] Add a test case for path restriction in both `--add` and `--install` operations.
    - [x] Ensure all existing tests pass.