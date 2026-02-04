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

test_fresh_install
test_backup_existing
test_conflict_keep_local
test_dry_run
test_idempotency

echo -e "
${GREEN}ALL TESTS PASSED${NC}"
