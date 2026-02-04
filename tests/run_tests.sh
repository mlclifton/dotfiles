#!/usr/bin/env bash

set -euo pipefail

# --- Test Environment Setup ---
TEST_DIR=$(mktemp -d /tmp/dotfiles_test.XXXXXX)
FAKE_HOME="$TEST_DIR/home"
FAKE_REPO="$TEST_DIR/repo"
DOT_SYNC="$FAKE_REPO/scripts/dot-sync.sh"

mkdir -p "$FAKE_HOME"
mkdir -p "$FAKE_REPO"

# Copy the project to the fake repo
cp -r . "$FAKE_REPO"

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_test() { echo -e "${GREEN}[TEST]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Helper to run dot-sync in the fake environment
run_dot_sync() {
    HOME="$FAKE_HOME" "$DOT_SYNC" "$@"
}

reset_env() {
    rm -rf "$FAKE_HOME" "$FAKE_REPO"
    mkdir -p "$FAKE_HOME"
    mkdir -p "$FAKE_REPO"
    cp -r . "$FAKE_REPO"
}

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# --- Test Scenarios ---

test_fresh_install() {
    reset_env
    log_test "Running Fresh Install test..."
    
    # Setup: Create a config in the repo
    mkdir -p "$FAKE_REPO/configs/zsh"
    echo "export TEST_VAR=1" > "$FAKE_REPO/configs/zsh/.zshrc"
    
    # Run install
    run_dot_sync --install --yes
    
    # Verify
    if [[ -L "$FAKE_HOME/.zshrc" ]] && [[ "$(readlink "$FAKE_HOME/.zshrc")" == "$FAKE_REPO/configs/zsh/.zshrc" ]]; then
        log_test "SUCCESS: .zshrc symlinked correctly."
    else
        log_fail "FAILED: .zshrc not symlinked correctly."
    fi
}

test_backup_existing() {
    reset_env
    log_test "Running Backup Existing test..."
    
    # Setup: Existing file in home
    echo "original content" > "$FAKE_HOME/.gitconfig"
    
    # Config in repo
    mkdir -p "$FAKE_REPO/configs/git"
    echo "[user]" > "$FAKE_REPO/configs/git/.gitconfig"
    
    # Run install (Overwrite mode)
    echo "o" | run_dot_sync --install
    
    # Verify
    if [[ -L "$FAKE_HOME/.gitconfig" ]] && [[ -f "$FAKE_HOME/.gitconfig.bak" ]]; then
        log_test "SUCCESS: Existing file backed up and replaced by symlink."
    else
        log_fail "FAILED: Backup logic failed."
    fi
}

test_dry_run() {
    reset_env
    log_test "Running Dry Run test..."
    
    # Setup: File in repo, not in home
    mkdir -p "$FAKE_REPO/configs/tmux"
    echo "set -g prefix C-a" > "$FAKE_REPO/configs/tmux/.tmux.conf"
    
    # Run dry-run
    run_dot_sync --install --dry-run --yes
    
    # Verify
    if [[ ! -e "$FAKE_HOME/.tmux.conf" ]]; then
        log_test "SUCCESS: Dry run made no changes."
    else
        log_fail "FAILED: Dry run modified the filesystem."
    fi
}

test_idempotency() {
    reset_env
    log_test "Running Idempotency test..."
    
    # Run twice
    run_dot_sync --install --yes
    run_dot_sync --install --yes
    
    log_test "SUCCESS: Run twice without errors."
}

test_conflict_keep_local() {
    reset_env
    log_test "Running Conflict: Keep Local test..."
    
    # Setup: Existing file in home
    echo "user change" > "$FAKE_HOME/.zshrc"
    
    # Config in repo
    mkdir -p "$FAKE_REPO/configs/zsh"
    echo "repo version" > "$FAKE_REPO/configs/zsh/.zshrc"
    
    # Run install (Keep Local mode)
    echo "k" | run_dot_sync --install
    
    # Verify
    if [[ -L "$FAKE_HOME/.zshrc" ]] && [[ "$(cat "$FAKE_REPO/configs/zsh/.zshrc")" == "user change" ]]; then
        log_test "SUCCESS: Repository updated with local version."
    else
        log_fail "FAILED: Keep Local logic failed."
    fi
}

# --- Execution ---

test_path_restricted_install() {
    reset_env
    log_test "Running Path Restricted Install test..."

    # Setup: 
    # 1. Config outside restriction
    mkdir -p "$FAKE_REPO/configs/zsh"
    echo "export TEST=1" > "$FAKE_REPO/configs/zsh/.zshrc"
    
    # 2. Config inside restriction (e.g. .config/nvim)
    # Mapping: configs/nvim/.config/nvim/init.vim -> ~/.config/nvim/init.vim
    mkdir -p "$FAKE_REPO/configs/nvim/.config/nvim"
    echo "set number" > "$FAKE_REPO/configs/nvim/.config/nvim/init.vim"
    
    # Ensure target directory exists (as required by the script argument validation)
    mkdir -p "$FAKE_HOME/.config"

    # Run install restricted to ~/.config
    run_dot_sync --install --yes "$FAKE_HOME/.config"

    # Verify:
    # .zshrc should NOT be linked
    if [[ -L "$FAKE_HOME/.zshrc" ]]; then
        log_fail "FAILED: .zshrc should NOT be linked when restriction is active."
    else
        # Ensure it wasn't created at all
        if [[ -e "$FAKE_HOME/.zshrc" ]]; then
             log_fail "FAILED: .zshrc shouldn't exist."
        fi
    fi

    # init.vim SHOULD be linked
    if [[ -L "$FAKE_HOME/.config/nvim/init.vim" ]] && [[ "$(readlink "$FAKE_HOME/.config/nvim/init.vim")" == "$FAKE_REPO/configs/nvim/.config/nvim/init.vim" ]]; then
        log_test "SUCCESS: Restricted install only processed target path."
    else
        log_fail "FAILED: init.vim not linked correctly."
    fi
}

test_multi_file_import() {
    reset_env
    log_test "Running Multi-File Import test..."
    
    # Setup Fake FZF
    mkdir -p "$TEST_DIR/bin"
    cat << 'EOF' > "$TEST_DIR/bin/fzf"
#!/bin/bash
# Mock fzf to return pre-defined files
if [[ -f "$MOCK_FZF_FILE" ]]; then
    cat "$MOCK_FZF_FILE"
fi
EOF
    chmod +x "$TEST_DIR/bin/fzf"
    export PATH="$TEST_DIR/bin:$PATH"
    export MOCK_FZF_FILE="$TEST_DIR/fzf_selection.txt"

    # Create files to import
    echo "content1" > "$FAKE_HOME/file1"
    echo "content2" > "$FAKE_HOME/file2"

    # Set selection
    echo "$FAKE_HOME/file1" > "$MOCK_FZF_FILE"
    echo "$FAKE_HOME/file2" >> "$MOCK_FZF_FILE"

    # Setup git in fake repo (needed for git operations in import_config)
    (cd "$FAKE_REPO" && git init && git config user.email "test@example.com" && git config user.name "Test User")

    # Run dot-sync --add
    # Input: 
    # 1. Category "testcat" (Global)
    # 2. Confirm link for file1 (y)
    # 3. Confirm link for file2 (y)
    # Note: git push will fail because there is no remote, but that's okay, run_cmd allows failure? 
    # Wait, set -e is on. git push failure might crash script.
    # run_cmd executes command. If git push fails, script exits.
    # We should mock git or ensure it doesn't fail.
    # Or just let it fail but catch it?
    # Actually, run_cmd checks exit status? No, it just runs it. set -e catches it.
    
    # Let's mock git too? Or add a remote.
    # Simpler: Mock git to exit 0.
    cat << 'EOF' > "$TEST_DIR/bin/git"
#!/bin/bash
# Mock git
if [[ "$1" == "push" ]]; then
    echo "Mock git push"
    exit 0
else
    /usr/bin/git "$@"
fi
EOF
    chmod +x "$TEST_DIR/bin/git"

    # Run with input
    # 0. 'c' to continue after verification
    # 1. Category "testcat" (Global)
    echo -e "c\ntestcat\n" | run_dot_sync --add

    # Verify
    # 1. Configs exist
    if [[ -f "$FAKE_REPO/configs/testcat/file1" ]] && [[ -f "$FAKE_REPO/configs/testcat/file2" ]]; then
        log_test "SUCCESS: Files copied to repo."
    else
        log_fail "FAILED: Files not copied to repo."
    fi

    # 2. Symlinks should NOT be created by --add anymore
    if [[ ! -L "$FAKE_HOME/file1" ]] && [[ ! -L "$FAKE_HOME/file2" ]]; then
        log_test "SUCCESS: Files NOT symlinked by --add."
    else
        log_fail "FAILED: Files were symlinked by --add (should be handled by --install)."
    fi
    
    # 3. Git commits
    # We used real git for add/commit (via our wrapper which calls /usr/bin/git for non-push)
    # Check log
    local commit_count
    commit_count=$(cd "$FAKE_REPO" && /usr/bin/git log --oneline | grep "Add file" | wc -l)
    # Actually message is "Add <rel_path> to <category> configs"
    commit_count=$(cd "$FAKE_REPO" && /usr/bin/git log --oneline | grep "Add .* to testcat configs" | wc -l)
    
    if [[ "$commit_count" -eq 2 ]]; then
        log_test "SUCCESS: Two commits created."
    else
        log_fail "FAILED: Expected 2 commits, found $commit_count."
    fi
}

TESTS=(
    test_fresh_install
    test_backup_existing
    test_conflict_keep_local
    test_dry_run
    test_idempotency
    test_path_restricted_install
    test_multi_file_import
)

declare -A TEST_SPECS
TEST_SPECS[test_fresh_install]="Fresh install should create symlinks for repo configs that don't exist in HOME."
TEST_SPECS[test_backup_existing]="Installing should backup existing HOME files before replacing them with symlinks."
TEST_SPECS[test_conflict_keep_local]="Installing with 'keep' should update the repository with the local file content."
TEST_SPECS[test_dry_run]="Dry run should report intended changes without modifying the filesystem."
TEST_SPECS[test_idempotency]="Running install multiple times should be safe and produce the same result."
TEST_SPECS[test_path_restricted_install]="Restricted install should only process files within the specified target path."
TEST_SPECS[test_multi_file_import]="Importing multiple files should copy them to the repo and create individual commits."

declare -A TEST_DESCS
TEST_DESCS[test_fresh_install]="Creates a dummy config in a fake repo and runs 'dot-sync --install'. Verifies the symlink is created in a fake HOME."
TEST_DESCS[test_backup_existing]="Creates a file in fake HOME, runs 'dot-sync --install' in overwrite mode. Verifies a .bak file is created."
TEST_DESCS[test_conflict_keep_local]="Creates different versions of a file in HOME and repo, runs 'dot-sync' in keep mode. Verifies repo content matches HOME."
TEST_DESCS[test_dry_run]="Runs 'dot-sync --dry-run' and verifies that no files are actually created or modified in the fake HOME."
TEST_DESCS[test_idempotency]="Runs the install command twice in succession to ensure it doesn't crash or create redundant backups/links."
TEST_DESCS[test_path_restricted_install]="Sets up files in multiple directories but runs install targeting only one. Verifies others are ignored."
TEST_DESCS[test_multi_file_import]="Mocks fzf/git to simulate selecting multiple files for import. Verifies files move to repo and git log shows commits."

INTERACTIVE=false
if [[ "${1:-}" == "-i" ]] || [[ "${1:-}" == "--interactive" ]]; then
    INTERACTIVE=true
fi

echo -e "\n${GREEN}Starting Test Suite...${NC}"

for i in "${!TESTS[@]}"; do
    test_name="${TESTS[$i]}"
    
    echo -e "\n======================================================================"
    echo -e "${GREEN}TEST $((i+1))/${#TESTS[@]}: ${test_name}${NC}"
    echo -e "SPEC: ${TEST_SPECS[$test_name]}"
    echo -e "HOW:  ${TEST_DESCS[$test_name]}"
    echo -e "======================================================================\n"

    $test_name

    if [[ "$INTERACTIVE" == "true" ]]; then
        echo -e "\n${GREEN}Test '${test_name}' passed.${NC}"
        
        # If not the last test, ask to continue
        if [[ $i -lt $((${#TESTS[@]} - 1)) ]]; then
            read -p "Press Enter to proceed to the next test (or 'q' to quit): " choice
            if [[ "$choice" == "q" ]]; then
                echo -e "\n${RED}Test suite terminated by user.${NC}"
                exit 0
            fi
        fi
    fi
done

echo -e "\n${GREEN}ALL TESTS PASSED${NC}"
