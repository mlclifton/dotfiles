# Code Review: `scripts/dot-sync.sh`

Review-only — no changes to be made.

---

## 1. `eval` in `import_config` (line 221) — Security & Robustness

**Problem:** The `find` command is built as a string and executed via `eval`:

```bash
local find_cmd="find \"$search_root\" -type f \
    -not -path '*/.git/*' \
    ..."
mapfile -t selected_files < <(eval "$find_cmd" | fzf ...)
```

`eval` is fragile and dangerous if `$search_root` contains shell metacharacters (spaces, quotes, semicolons). A path like `/home/user/my dir; rm -rf /` would be interpreted by the shell.

**Recommendation:** Replace with a direct `find` call or an array-based approach:

```bash
mapfile -t selected_files < <(
    find "$search_root" -type f \
        -not -path '*/.git/*' \
        -not -path '*/.cache/*' \
        -not -path '*/.local/share/*' \
        -not -path '*/.ssh/*' \
        -not -path "$DOTFILES_DIR/*" \
    | fzf --multi --prompt="Select config file(s) to import (Tab to multi-select): "
)
```

No `eval` needed — the original `find_cmd` string was only necessary because of the way quoting was handled, but direct invocation works fine here.

---

## 2. `import_config` discards directory structure (line 274)

**Problem:** When importing a file, only `basename` is preserved:

```bash
local repo_file="$target_dir/$(basename "$selected_file")"
```

This means `~/.config/nvim/init.vim` becomes `configs/<category>/init.vim` instead of `configs/<category>/.config/nvim/init.vim`. This contradicts the mapping convention used by `install_dotfiles`, which strips the category directory and maps the rest to `$HOME`. With only the basename preserved, `install_dotfiles` would symlink it to `$HOME/init.vim` — the wrong location.

**Recommendation:** Preserve the path relative to `$HOME`:

```bash
local rel_path="${selected_file#$HOME/}"
local repo_file="$target_dir/$rel_path"
```

Then `mkdir -p "$(dirname "$repo_file")"` before the copy. This keeps the import and install paths consistent.

---

## 3. No `trap` for cleanup or interrupts in the main script

**Problem:** The test suite has `trap cleanup EXIT` (line 40), but the main script has no signal handling. If a user hits Ctrl+C mid-operation, partially-created symlinks or half-copied files can be left behind. The pre-flight snapshot helps with recovery, but the user gets no guidance.

**Recommendation:** Add a trap that logs a message pointing the user to the snapshot:

```bash
trap 'log_warn "Interrupted. Restore from snapshot in ~/.dotfiles_backup_*.tar.gz if needed."' INT TERM
```

This is low-effort and high-value — users know where to look if something goes wrong.

---

## 4. `local var=$(cmd)` masks return codes (lines 150, 161, 340)

**Problem:** Several places use `local var=$(command)`:

```bash
local target_dir="$(dirname "$target_file")"     # line 150
local current_link=$(readlink "$target_file")     # line 161 (inside conditional, less risky)
local full_target_path="$HOME/$rel_path"          # line 340 (just string concat, not a command)
```

In Bash, `local` always returns 0, masking any failure from the command substitution. If `dirname` somehow fails, the error goes unnoticed.

**Recommendation:** Split declaration from assignment for command substitutions:

```bash
local target_dir
target_dir="$(dirname "$target_file")"
```

Line 161 is inside an `if [[ -L ... ]]` block so `readlink` is unlikely to fail, and line 340 is pure string concatenation (no risk). So line 150 is the main one worth fixing. This is a minor issue but a well-known Bash pitfall worth addressing.

---

## 5. `cd` without restoration (lines 294, 378)

**Problem:** Both `import_config` and `sync_git` use `cd "$DOTFILES_DIR"` to change the working directory for git operations, but never restore it. After `import_config` or `sync_git` returns, the script's working directory has silently changed. In the current code flow this doesn't cause bugs because `main()` runs these functions sequentially and nothing after depends on `cwd`, but it's a latent issue if the script grows.

**Recommendation:** Use a subshell `( cd "$DOTFILES_DIR" && ... )` or `pushd`/`popd` to scope the directory change. Alternatively, pass `-C "$DOTFILES_DIR"` to git commands instead of changing directories:

```bash
run_cmd git -C "$DOTFILES_DIR" add "$repo_file"
run_cmd git -C "$DOTFILES_DIR" commit -m "Add $rel_path to $category configs"
```

---

## 6. Colon-delimited string mappings are fragile (line 325)

**Problem:** File mappings use a colon as a delimiter:

```bash
mappings+=("$repo_file:$rel_path")
```

Then parsed with:

```bash
local repo_file="${mapping%%:*}"
local rel_path="${mapping#*:}"
```

If a file path ever contains a colon (valid on Linux, e.g., `file:with:colons.conf`), this parsing breaks. The `repo_file` gets truncated and `rel_path` gets garbage.

**Recommendation:** Use a delimiter that's illegal in file paths (null byte isn't practical in Bash), or better, use two parallel arrays:

```bash
repo_files+=("$repo_file")
rel_paths+=("$rel_path")
```

Then iterate with index. This eliminates the parsing entirely.

---

## 7. `git add -A` in `sync_git` is broad (line 384)

**Problem:** `git add -A` stages everything in the repo, relying entirely on `.gitignore` to exclude unwanted files. If a user accidentally drops a large binary or sensitive file into the repo directory, it gets committed without any prompt.

**Recommendation:** Consider staging only the `configs/` directory, or at minimum logging what's being staged so the user can verify:

```bash
run_cmd git add configs/
# or
git diff --name-only --cached  # show what will be committed
```

This is a minor concern since `.gitignore` covers the common cases, but the defensive approach is more consistent with the script's overall safety philosophy.

---

## 8. No validation on category names (line 269)

**Problem:** The category name entered by the user is used directly in file paths:

```bash
read -r -p "Enter category name for $rel_path (e.g., zsh, git, vim): " category
local target_dir="$CONFIGS_DIR/$category"
```

A user could enter `../../../etc` or a name with spaces/special characters, creating unexpected directory structures.

**Recommendation:** Validate the category is a simple alphanumeric name:

```bash
if [[ ! "$category" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Category must be alphanumeric (hyphens and underscores allowed)."
    category=""
    continue
fi
```

---

## 9. `import_config` always pushes to remote (line 308)

**Problem:** After committing files, `import_config` unconditionally runs `git push`. This couples the import operation to having a configured remote and network access. If the user is offline or hasn't set up a remote yet, the script fails with `set -e` active.

**Recommendation:** Either guard the push with a remote check, or make pushing a separate step (the `--sync` command already handles push). Something like:

```bash
if git remote get-url origin &>/dev/null; then
    run_cmd git push
else
    log_info "No remote configured. Use --sync to push later."
fi
```

This is also more consistent with the script's design: `--add` imports, `--sync` synchronizes.

---

## 10. `test_idempotency` doesn't assert much (test line 104-113)

**Problem:** The idempotency test just runs install twice and checks that it doesn't crash:

```bash
run_dot_sync --install --yes
run_dot_sync --install --yes
log_test "SUCCESS: Run twice without errors."
```

It doesn't verify the actual state — no check that the symlink still points correctly, no check for duplicate `.bak` files, no check that the snapshot doesn't grow unboundedly.

**Recommendation:** Add assertions after the second run:

- Verify symlinks still point to the correct targets
- Verify no `.bak` files were created (since nothing should conflict on the second run)
- Verify only one snapshot was created per run (or that the second run's snapshot is minimal)

---

## Summary — ranked by impact

| # | Issue | Severity | Effort |
|---|-------|----------|--------|
| 2 | `import_config` discards directory structure | Bug | Low |
| 1 | `eval` usage in `import_config` | Security | Low |
| 9 | Unconditional `git push` in `import_config` | Reliability | Low |
| 6 | Colon-delimited mappings break on colons in paths | Robustness | Low |
| 8 | No category name validation | Input safety | Low |
| 3 | No signal trap in main script | UX | Low |
| 5 | `cd` without restoration | Maintainability | Low |
| 7 | `git add -A` stages everything | Safety | Low |
| 4 | `local` masking return codes | Correctness | Low |
| 10 | Weak idempotency test assertions | Test quality | Low |

Items 1 and 2 are the most important — one is a security issue, the other is a functional bug that causes imported files to be installed to the wrong location.
