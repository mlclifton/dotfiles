#!/usr/bin/env bash

# Dotfiles Manager - Main Synchronization Script
# Purpose: Safe, idempotent, and reversible dotfiles management.

set -euo pipefail

# --- Configuration & Constants ---
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGS_DIR="$DOTFILES_DIR/configs"
LOG_FILE="$DOTFILES_DIR/dot-sync.log"

# --- State Variables ---
DRY_RUN=false
NON_INTERACTIVE=false
COMMAND_INSTALL=false
COMMAND_ADD=false
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
Usage: $(basename "$0") [OPTIONS] [PATH]

A robust, symlink-based dotfiles management system.

Options:
  --install     Installs dotfiles (creates symlinks from configs/ to \$HOME).
  --add         Interactively import a new file into the dotfiles repo.
  --sync        Pulls latest changes from GitHub and/or pushes local repo changes.
  --dry-run     Shows what would happen without making any changes.
  -y, --yes     Non-interactive mode (assumes 'yes' to all prompts).
  --help        Displays this help message.

Arguments:
  [PATH]        Optional. Restrict operations to a specific directory (e.g., ~/.config).

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

link_file() {
    local repo_file="$1"
    local rel_path="$2"
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
            return 0
        else
            log_warn "$rel_path is a symlink pointing elsewhere: $current_link"
            if confirm "Replace existing symlink?"; then
                run_cmd rm "$target_file"
            else
                return 0
            fi
        fi
    elif [[ -e "$target_file" ]]; then
        # File exists but is not a symlink
        
        # In DRY_RUN, the repo_file might not exist yet if it was just "added"
        if [[ "$DRY_RUN" == "true" ]] && [[ ! -e "$repo_file" ]]; then
            log_info "$rel_path is a new file (dry-run). Converting to symlink..."
            run_cmd rm "$target_file"
        elif cmp -s "$target_file" "$repo_file"; then
            log_info "$rel_path matches repo version. Converting to symlink..."
            run_cmd rm "$target_file"
        else
            if ! resolve_conflict "$target_file" "$repo_file" "$rel_path"; then
                return 0
            fi
        fi
    fi

    # Create the symlink
    run_cmd ln -s "$repo_file" "$target_file"
    log_success "Linked $rel_path"
}

import_config() {
    log_info "Starting interactive config import..."

    # Check for fzf
    if ! command -v fzf &> /dev/null; then
        log_error "fzf is required for interactive import."
        return 1
    fi

    local search_root="${TARGET_PATH:-$HOME}"
    local selected_files=()
    
    while true; do
        log_info "Searching in: $search_root"

        # Select files using fzf --multi
        if ! mapfile -t selected_files < <(
            find "$search_root" -type f \
                -not -path '*/.git/*' \
                -not -path '*/.cache/*' \
                -not -path '*/.local/share/*' \
                -not -path '*/.ssh/*' \
                -not -path "$DOTFILES_DIR/*" \
            | fzf --multi --prompt="Select config file(s) to import (Tab to multi-select): "
        ); then
            log_warn "No file selected."
            return 0
        fi

        if [[ ${#selected_files[@]} -eq 0 ]]; then
            log_warn "No file selected."
            return 0
        fi

        # Verification step
        echo -e "\n${BLUE}Selected files for import:${NC}"
        for f in "${selected_files[@]}"; do
            echo "  - $f"
        done
        
        local choice
        read -r -p "$(echo -e "\nAction: [C]ontinue, [R]e-select, [Q]uit? ")" choice
        case "$choice" in
            [cC]*) break ;;
            [rR]*) continue ;;
            *) log_info "Import cancelled."; return 0 ;;
        esac
    done

    log_info "Selected ${#selected_files[@]} files."

    local global_category=""
    local use_global_category=false

    # Ask for global category if multiple files are selected
    if [[ ${#selected_files[@]} -gt 1 ]]; then
        while true; do
            read -r -p "Enter category name for ALL files (leave empty to prompt individually): " global_category
            if [[ -z "$global_category" ]]; then
                break
            elif [[ "$global_category" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                use_global_category=true
                break
            else
                log_error "Category must be alphanumeric (hyphens and underscores allowed)."
            fi
        done
    fi

    local files_committed=false
    
    for selected_file in "${selected_files[@]}"; do
        # Calculate relative path from HOME for consistency
        local rel_path="${selected_file#$HOME/}"
        log_info "Processing: $rel_path"

        local category="$global_category"
        if [[ "$use_global_category" == "false" ]]; then
            while [[ -z "$category" ]]; do
                read -r -p "Enter category name for $rel_path (e.g., zsh, git, vim): " category
                if [[ -n "$category" ]] && [[ ! "$category" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    log_error "Category must be alphanumeric (hyphens and underscores allowed)."
                    category=""
                fi
            done
        fi

        local target_dir="$CONFIGS_DIR/$category"
        local repo_file="$target_dir/$rel_path"
        
        # Check if target already exists
        if [[ -e "$repo_file" ]]; then
            log_warn "File already exists in repo: $repo_file"
            if ! confirm "Overwrite repo version?"; then
                # Reset category if looping
                if [[ "$use_global_category" == "false" ]]; then category=""; fi
                continue
            fi
        else
            log_info "Adding new file to repository: $rel_path"
        fi

        # Copy file to repo
        run_cmd mkdir -p "$(dirname "$repo_file")"
        run_cmd cp "$selected_file" "$repo_file"

        # Sync with Git (Commit only)
        log_info "Staging $rel_path..."
        run_cmd git -C "$DOTFILES_DIR" add "$repo_file"
        run_cmd git -C "$DOTFILES_DIR" commit -m "Add $rel_path to $category configs"
        files_committed=true

        # Reset category if we are prompting individually
        if [[ "$use_global_category" == "false" ]]; then
            category=""
        fi
    done

    # Push once if any files were committed
    if [[ "$files_committed" == "true" ]]; then
        if git remote get-url origin &>/dev/null; then
            log_info "Pushing all changes to remote..."
            run_cmd git push
        else
            log_info "No remote configured. Use --sync to push later."
        fi
    fi
}

install_dotfiles() {
    log_info "Scanning $CONFIGS_DIR for dotfiles..."

    # Collect all files using parallel arrays
    local repo_files=()
    local rel_paths=()
    # configs/<category>/<relative_path> -> $HOME/<relative_path>

    # Use find to get all files in configs/
    # We want to skip the <category> directory level
    while IFS= read -r -d '' category_dir; do
        category=$(basename "$category_dir")
        while IFS= read -r -d '' repo_file; do
            rel_path="${repo_file#$category_dir/}"
            repo_files+=("$repo_file")
            rel_paths+=("$rel_path")
        done < <(find "$category_dir" -type f -print0)
    done < <(find "$CONFIGS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

    if [[ ${#repo_files[@]} -eq 0 ]]; then
        log_warn "No dotfiles found in $CONFIGS_DIR."
        return 0
    fi

    # Filter based on TARGET_PATH if specified
    local filtered_repo_files=()
    local filtered_rel_paths=()
    if [[ -n "$TARGET_PATH" ]]; then
        log_info "Restricting installation to: $TARGET_PATH"
        for i in "${!repo_files[@]}"; do
            local full_target_path="$HOME/${rel_paths[$i]}"

            # Check if full_target_path starts with TARGET_PATH
            # We assume paths are normalized enough for simple prefix matching
            if [[ "$full_target_path" == "$TARGET_PATH"* ]]; then
                filtered_repo_files+=("${repo_files[$i]}")
                filtered_rel_paths+=("${rel_paths[$i]}")
            fi
        done
    else
        filtered_repo_files=("${repo_files[@]}")
        filtered_rel_paths=("${rel_paths[@]}")
    fi

    if [[ ${#filtered_repo_files[@]} -eq 0 ]]; then
        log_info "No dotfiles match the criteria/path."
        return 0
    fi

    # Pre-flight Snapshot
    create_snapshot "${filtered_rel_paths[@]}"

    # Process each file
    for i in "${!filtered_repo_files[@]}"; do
        link_file "${filtered_repo_files[$i]}" "${filtered_rel_paths[$i]}"
    done
}

sync_git() {
    log_info "Synchronizing with remote repository..."

    log_info "Pulling latest changes..."
    run_cmd git -C "$DOTFILES_DIR" pull --ff-only

    log_info "Committing local changes..."
    run_cmd git -C "$DOTFILES_DIR" add configs/

    # Check if there are changes to commit
    if git -C "$DOTFILES_DIR" diff --cached --quiet; then
        log_info "No local changes to commit."
    else
        run_cmd git -C "$DOTFILES_DIR" commit -m "Auto-sync: $(date)"
        log_info "Pushing changes..."
        run_cmd git -C "$DOTFILES_DIR" push
    fi
}

# --- Argument Parsing ---

if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

TARGET_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)  COMMAND_INSTALL=true; shift ;;
        --add)      COMMAND_ADD=true; shift ;;
        --sync)     COMMAND_SYNC=true; shift ;;
        --dry-run)  DRY_RUN=true; shift ;;
        -y|--yes)   NON_INTERACTIVE=true; shift ;;
        --help)     show_help; exit 0 ;;
        -*)         log_error "Unknown option: $1"; show_help; exit 1 ;;
        *)          
            if [[ -z "$TARGET_PATH" ]]; then
                TARGET_PATH="$1"
                shift
            else
                log_error "Multiple paths specified: $TARGET_PATH and $1"
                show_help
                exit 1
            fi
            ;;
    esac
done

if [[ -n "$TARGET_PATH" ]]; then
   if [[ ! -d "$TARGET_PATH" ]]; then
       log_error "Target path does not exist or is not a directory: $TARGET_PATH"
       exit 1
   fi
   # Resolve absolute path
   TARGET_PATH=$(cd "$TARGET_PATH" && pwd)
   log_info "Targeting specific path: $TARGET_PATH"
fi

# --- Main Logic (Placeholders) ---

main() {
    # Set up signal handling for clean interruption
    trap 'log_warn "Interrupted. Restore from snapshot in ~/.dotfiles_backup_*.tar.gz if needed."' INT TERM

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode. No changes will be made."
    fi

    if [[ "$COMMAND_ADD" == "true" ]]; then
        import_config
    fi

    if [[ "$COMMAND_INSTALL" == "true" ]]; then
        install_dotfiles
    fi

    if [[ "$COMMAND_SYNC" == "true" ]]; then
        sync_git
    fi

    log_success "Operation completed successfully."
}

main
