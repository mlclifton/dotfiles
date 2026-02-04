# Dotfiles Project Task List

## Phase 1: Repository Setup
- [ ] Initialize git repository in `~/src/dotfiles`.
- [ ] Create directory structure (`configs/`, `packages/`, `scripts/`).
- [ ] Create `.gitignore` to strictly exclude sensitive files (`*.secrets`, `*.local`).
- [ ] Write initial `README.md` (Completed).

## Phase 2: Script Development (`scripts/dot-sync.sh`)
- [ ] Implement robust argument parsing (flags: `--install`, `--packages`, `--sync`, `--dry-run`, `--yes`, `--help`).
- [ ] Set "Interactive Mode" as the default execution state.
- [ ] Create a "Safe Execution" wrapper that respects the `--dry-run` flag.
- [ ] Implement Logging UI (Colors for Info, Warning, Error, Success).
- [ ] Implement Interactive Prompt utility for user confirmations.
- [ ] **Core Logic**:
    - [ ] Implement **Mapping Mechanism**: Define how files in `configs/` map to `$HOME`.
    - [ ] Implement **Pre-flight Snapshot** (tarball creation).
    - [ ] Implement **Diff Logic**: Compare local file vs repo file.
    - [ ] Implement **Conflict Resolution Prompt**:
        -   Show Diff.
        -   Options: Keep Local (Update Repo), Use Remote (Backup Local), Skip.
    - [ ] Implement backup logic (real file -> `.bak`).
    - [ ] Implement symlink logic (repo -> `$HOME`).
    - [ ] **Git Integration**: Implement `--sync` logic (git pull/add/commit/push).
- [ ] **Package Logic**:
    - [ ] Implement package list export (generating `packages/pacman.list`).
    - [ ] Implement package installation logic with explicit user confirmation.

## Phase 3: Testing & Migration (Safety Focus)
- [ ] **Test Suite (`tests/run_tests.sh`)**:
    - [ ] Create sandbox environment generator (fake home/repo).
    - [ ] Write integration test: "Fresh Install" (no existing files).
    - [ ] Write integration test: "Backup Existing" (existing files preserved).
    - [ ] Write integration test: "Conflict: Keep Local" (repo updated).
    - [ ] Write integration test: "Conflict: Overwrite" (local updated).
    - [ ] Write integration test: "Idempotency" (run twice, no changes).
    - [ ] Write integration test: "Dry Run" (no changes made).
- [ ] **Migration**:
    - [ ] Migrate `~/.zshrc` and related files to `configs/zsh/`.
    - [ ] Migrate Omarchy-specific user configs to `configs/omarchy/`.
    - [ ] Create `.zsh_secrets` template (ignored by git).
    - [ ] Add the "Secrets" inclusion snippet to the template `.zshrc`.
    - [ ] Run `tests/run_tests.sh` and ensure ALL pass.
    - [ ] Run `dot-sync.sh --install --dry-run` to verify against real home.
    - [ ] Run `dot-sync.sh --install` (interactive by default) to finalize.

## Phase 4: Finalization
- [ ] Verify `--help` output is comprehensive.
- [ ] Test `--dry-run` produces no filesystem changes.
- [ ] Add basic instructions for "how to add a new config" to README.

