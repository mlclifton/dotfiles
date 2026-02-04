#!/usr/bin/env bash

# Dotfiles Manager - Main Synchronization Script
# Purpose: Safe, idempotent, and reversible dotfiles management.

set -euo pipefail

# --- Configuration & Constants ---
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGS_DIR="$DOTFILES_DIR/configs"
PACKAGES_DIR="$DOTFILES_DIR/packages"
LOG_FILE="$DOTFILES_DIR/dot-sync.log"

# --- State Variables ---
DRY_RUN=false
NON_INTERACTIVE=false
COMMAND_INSTALL=false
COMMAND_PACKAGES=false
COMMAND_SYNC=false

# --- UI & Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Utilities ---

# Safe execution wrapper
run_cmd() {
    local cmd=("$@")
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} ${cmd[*]}"
        return 0
    fi
    "${cmd[@]}"
}

# Interactive prompt utility
confirm() {
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        return 0
    fi

    local prompt="$1"
    local response
    read -r -p "$(echo -e "${YELLOW}[CONFIRM]${NC} $prompt [y/N] ")" response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

A robust, symlink-based dotfiles management system.

Options:
  --install     Installs dotfiles (creates symlinks from configs/ to \$HOME).
  --packages    Reinstalls system packages from the package list.
  --sync        Pulls latest changes from GitHub and/or pushes local repo changes.
  --dry-run     Shows what would happen without making any changes.
  -y, --yes     Non-interactive mode (assumes 'yes' to all prompts).
  --help        Displays this help message.

Default behavior is interactive mode.
EOF
}

# --- Core Logic ---

create_snapshot() {
    local files_to_snapshot=("$@")
    if [[ ${#files_to_snapshot[@]} -eq 0 ]]; then
        return 0
    fi

    local snapshot_name="$HOME/.dotfiles_backup_$(date +%s).tar.gz"
    log_info "Creating pre-flight snapshot: $snapshot_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} tar -czf \"$snapshot_name\" -C \"$HOME\" ${files_to_snapshot[*]}"
    else
        # Filter out files that don't exist yet to avoid tar errors
        local existing_files=()
        for f in "${files_to_snapshot[@]}"; do
            if [[ -e "$HOME/$f" ]]; then
                existing_files+=("$f")
            fi
        done
        
        if [[ ${#existing_files[@]} -gt 0 ]]; then
            tar -czf "$snapshot_name" -C "$HOME" "${existing_files[@]}"
        else
            log_info "No existing files to snapshot."
        fi
    fi
}

resolve_conflict() {
    local local_file="$1"
    local repo_file="$2"
    local rel_path="$3"

    echo -e "${YELLOW}Conflict detected for $rel_path${NC}"
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_warn "Non-interactive mode: Skipping $rel_path"
        return 1
    fi

    diff -u --color=always "$local_file" "$repo_file" || true
    
    while true; do
        read -r -p "Action: [K]eep Local, [O]verwrite, [S]kip? " choice
        case "$choice" in
            [kK]*) 
                log_info "Keeping local version (updating repository)..."
                run_cmd cp "$local_file" "$repo_file"
                run_cmd rm "$local_file"
                return 0
                ;;
            [oO]*)
                log_info "Overwriting local version (backing up existing)..."
                run_cmd mv "$local_file" "${local_file}.bak"
                return 0
                ;;
            [sS]*)
                log_info "Skipping $rel_path"
                return 1
                ;;
            *) echo "Invalid choice." ;;
        esac
    done
}

install_dotfiles() {
    log_info "Scanning $CONFIGS_DIR for dotfiles..."
    
    # Collect all files and determine their mappings
    local mappings=()
    # configs/<category>/<relative_path> -> $HOME/<relative_path>
    
    # Use find to get all files in configs/
    # We want to skip the <category> directory level
    while IFS= read -r -d '' category_dir; do
        category=$(basename "$category_dir")
        while IFS= read -r -d '' repo_file; do
            rel_path="${repo_file#$category_dir/}"
            mappings+=("$repo_file:$rel_path")
        done < <(find "$category_dir" -type f -print0)
    done < <(find "$CONFIGS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

    if [[ ${#mappings[@]} -eq 0 ]]; then
        log_warn "No dotfiles found in $CONFIGS_DIR."
        return 0
    fi

    # Pre-flight Snapshot
    local target_files=()
    for mapping in "${mappings[@]}"; do
        rel_path="${mapping#*:}"
        target_files+=("$rel_path")
    done
    create_snapshot "${target_files[@]}"

    # Process each mapping
    for mapping in "${mappings[@]}"; do
        local repo_file="${mapping%%:*}"
        local rel_path="${mapping#*:}"
        local target_file="$HOME/$rel_path"
        local target_dir="$(dirname "$target_file")"

        log_info "Processing $rel_path..."

        # Ensure target directory exists
        if [[ ! -d "$target_dir" ]]; then
            run_cmd mkdir -p "$target_dir"
        fi

        if [[ -L "$target_file" ]]; then
            # If it's a symlink, check where it points
            local current_link
            current_link=$(readlink "$target_file")
            if [[ "$current_link" == "$repo_file" ]]; then
                log_success "$rel_path is already correctly linked."
                continue
            else
                log_warn "$rel_path is a symlink pointing elsewhere: $current_link"
                if confirm "Replace existing symlink?"; then
                    run_cmd rm "$target_file"
                else
                    continue
                fi
            fi
        elif [[ -e "$target_file" ]]; then
            # File exists but is not a symlink
            if cmp -s "$target_file" "$repo_file"; then
                log_info "$rel_path matches repo version. Converting to symlink..."
                run_cmd rm "$target_file"
            else
                if ! resolve_conflict "$target_file" "$repo_file" "$rel_path"; then
                    continue
                fi
            fi
        fi

        # Create the symlink
        run_cmd ln -s "$repo_file" "$target_file"
        log_success "Linked $rel_path"
    done
}

restore_packages() {
    local pkg_list="$PACKAGES_DIR/pacman.list"
    if [[ ! -f "$pkg_list" ]]; then
        log_error "Package list not found at $pkg_list"
        return 1
    fi

    log_info "Installing packages from $pkg_list..."
    if confirm "Proceed with package installation?"; then
        # Assuming Arch Linux as per README
        run_cmd sudo pacman -S --needed - < "$pkg_list"
    fi
}

export_packages() {
    log_info "Exporting current package list to $PACKAGES_DIR/pacman.list"
    if [[ ! -d "$PACKAGES_DIR" ]]; then
        run_cmd mkdir -p "$PACKAGES_DIR"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} pacman -Qqen > $PACKAGES_DIR/pacman.list"
    else
        pacman -Qqen > "$PACKAGES_DIR/pacman.list"
    fi
    log_success "Packages exported."
}

sync_git() {
    log_info "Synchronizing with remote repository..."
    
    # Push/Pull from current directory (the repo root)
    cd "$DOTFILES_DIR"

    log_info "Pulling latest changes..."
    run_cmd git pull --ff-only

    # Update package list before pushing
    export_packages

    log_info "Committing local changes..."
    run_cmd git add -A
    
    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log_info "No local changes to commit."
    else
        run_cmd git commit -m "Auto-sync: $(date)"
        log_info "Pushing changes..."
        run_cmd git push
    fi
}

# --- Argument Parsing ---

if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)  COMMAND_INSTALL=true; shift ;;
        --packages) COMMAND_PACKAGES=true; shift ;;
        --sync)     COMMAND_SYNC=true; shift ;;
        --dry-run)  DRY_RUN=true; shift ;;
        -y|--yes)   NON_INTERACTIVE=true; shift ;;
        --help)     show_help; exit 0 ;;
        *)          log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# --- Main Logic (Placeholders) ---

main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode. No changes will be made."
    fi

    if [[ "$COMMAND_INSTALL" == "true" ]]; then
        install_dotfiles
    fi

    if [[ "$COMMAND_PACKAGES" == "true" ]]; then
        restore_packages
    fi

    if [[ "$COMMAND_SYNC" == "true" ]]; then
        sync_git
    fi

    log_success "Operation completed successfully."
}

main
