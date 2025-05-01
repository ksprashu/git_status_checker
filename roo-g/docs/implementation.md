# Implementation Plan & Algorithm for Git Status Scanner Script

## 1. Chosen Language: Bash

Bash is chosen for its direct integration with shell commands like `find` and `git`.

## 2. Algorithm (Conceptual Bash Implementation)

```bash
#!/bin/bash

# Function to check a single directory's Git status
# Outputs status string like "[UNCOMMITTED] /path" or "[UNPUSHED] /path"
# Returns 0 if it's a Git repo (regardless of status), 1 otherwise.
check_git_status() {
  local dir="$1"
  local status=""

  # Check if it's a git repository root (contains .git)
  if [[ ! -d "$dir/.git" ]]; then
     # If using a find strategy that only calls this on potential roots,
     # this check might be redundant, but good for standalone use.
     # Alternatively, use: git -C "$dir" rev-parse --is-inside-work-tree > /dev/null 2>&1
     # For this design, we assume find identifies the .git dir parent.
     return 1 # Not a git repo root
  fi

  # Check for uncommitted changes
  if [[ -n $(git -C "$dir" status --porcelain) ]]; then
    status="UNCOMMITTED"
  else
    # Check for unpushed changes (only if clean)
    # Check if remote upstream exists first
    if git -C "$dir" rev-parse --abbrev-ref '@{u}' > /dev/null 2>&1; then
      # Upstream exists, check log difference
      if [[ -n $(git -C "$dir" log '@{u}..' --oneline) ]]; then
        status="UNPUSHED"
      else
        status="SYNCED" # Or omit for less noise
      fi
    else
      # No upstream configured
      status="NO REMOTE" # Or omit
    fi
  fi

  # Report status if relevant (Uncommitted or Unpushed are primary)
  # Add SYNCED or NO REMOTE if desired for verbosity
  if [[ "$status" == "UNCOMMITTED" || "$status" == "UNPUSHED" ]]; then
    echo "[$status] $dir"
  # Optional: Uncomment to report other statuses
  # elif [[ "$status" == "SYNCED" || "$status" == "NO REMOTE" ]]; then
  #   echo "[$status] $dir"
  fi

  return 0 # It was a git repo
}

# --- Main Script Logic ---

ROOT_DIR="${1:-.}" # Use provided arg or default to current dir
ROOT_DIR=$(realpath "$ROOT_DIR") # Resolve to absolute path

echo "Scanning directory: $ROOT_DIR"

# Use newline-separated lists for Bash 3 compatibility
processed_dirs_list=""
non_git_roots_list=""
git_roots_list=""

# Helper function to check if a path is in a newline-separated list
path_in_list() {
    echo "$2" | grep -q -F -x "$1"
}

# Construct the find command's prune arguments for ignored directories
ignored_dirs=(node_modules venv .venv env .env target build dist)
prune_paths=()
for ignore_name in "${ignored_dirs[@]}"; do
    # Add '-name DIR_NAME -prune -o' for each ignored name
    # Ensure proper quoting if names could have spaces (though these don't)
    prune_paths+=(-name "$ignore_name" -prune -o)
done

# 1. Find all Git repository roots (.git directories), pruning ignored dirs
# Also prune .git itself to avoid descending into it
while IFS= read -r -d $'\0' git_dir; do
  repo_root=$(dirname "$git_dir")
  repo_root=$(realpath "$repo_root") # Ensure absolute path

  # Check if already processed (e.g., nested repo root)
  if path_in_list "$repo_root" "$git_roots_list"; then
      continue
  fi
  git_roots_list="${git_roots_list}${repo_root}"$'\n'

  # Check and report status of this repo root
  check_git_status "$repo_root"

  # Mark this directory and all its parents up to ROOT_DIR as processed
  if ! path_in_list "$repo_root" "$processed_dirs_list"; then
      processed_dirs_list="${processed_dirs_list}${repo_root}"$'\n'
  fi
  parent=$(dirname "$repo_root")
  while [[ "$parent" != "/" && "$parent" != "." && "$parent" == "$ROOT_DIR"* ]]; do
      if ! path_in_list "$parent" "$processed_dirs_list"; then
          processed_dirs_list="${processed_dirs_list}${parent}"$'\n'
      fi
      if [[ "$parent" == "$ROOT_DIR" ]]; then break; fi
      parent=$(dirname "$parent")
  done

done < <(find "$ROOT_DIR" -type d \( "${prune_paths[@]}" -name .git \) -print0)


# 2. Find all directories, pruning ignored and known git repo areas, to identify potential non-Git roots
while IFS= read -r -d $'\0' dir; do
  if [[ ! -d "$dir" ]]; then continue; fi # Skip if not a directory (e.g., broken link)
  dir=$(realpath "$dir") # Ensure absolute path

  # Skip if directory is already known to be within a Git repo
  if path_in_list "$dir" "$processed_dirs_list"; then
    continue
  fi

  # Check if any parent (within ROOT_DIR) is already marked as processed or a non-git root
  is_child=false
  parent=$(dirname "$dir")
  while [[ "$parent" != "/" && "$parent" != "." && "$parent" == "$ROOT_DIR"* ]]; do
      if path_in_list "$parent" "$processed_dirs_list" || path_in_list "$parent" "$non_git_roots_list"; then
          is_child=true
          break
      fi
      if [[ "$parent" == "$ROOT_DIR" ]]; then break; fi
      parent=$(dirname "$parent")
  done

  # If it's not processed and not a child of an already identified non-git root, mark it.
  if ! $is_child; then
      # Double check it's not actually a git repo itself
       if ! git -C "$dir" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
           if ! path_in_list "$dir" "$non_git_roots_list"; then
               non_git_roots_list="${non_git_roots_list}${dir}"$'\n'
           fi
       else
           # It IS a git repo but wasn't caught in pass 1 (should be rare now)
           # Mark it processed so its children are skipped.
           if ! path_in_list "$dir" "$processed_dirs_list"; then
               processed_dirs_list="${processed_dirs_list}${dir}"$'\n'
           fi
       fi
  fi

# Use find again, pruning ignored dirs AND known git roots this time
# Construct prune paths for known git roots found in pass 1
git_root_prune_paths=()
while IFS= read -r groot; do
    if [[ -n "$groot" ]]; then
        git_root_prune_paths+=(-path "$groot" -prune -o)
    fi
done < <(echo "$git_roots_list")

done < <(find "$ROOT_DIR" -type d \( "${prune_paths[@]}" "${git_root_prune_paths[@]}" -print \) -print0 ) # Note: -print is needed before -print0


# 3. Report the identified non-git roots
non_git_count=0
while IFS= read -r root; do
    if [[ -n "$root" ]]; then # Ensure we don't process empty lines
        # Final check: Ensure this root itself wasn't actually a git repo missed
        if ! git -C "$root" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
            echo "[NON-GIT] $root"
            ((non_git_count++))
        fi
    fi
done < <(echo "$non_git_roots_list")

echo "---" # Separator before final summary
    # Final check: Ensure this root itself wasn't actually a git repo missed (edge case, unlikely with .git check)
    # This check is mostly redundant given the first pass, but safe.
    if ! git -C "$root" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "[NON-GIT] $root"
    fi
done

if [[ $non_git_count -gt 0 ]]; then
    echo "---"
fi
echo "Scan complete. Found $non_git_count top-level non-Git directories."
echo "Git repositories with statuses (UNCOMMITTED/UNPUSHED) listed above."

# Make the script executable: chmod +x scan_git_repos.sh
# Example usage: ./scan_git_repos.sh /path/to/your/code
```

## 3. Implementation Steps

1.  **Create Script File:** Create `scan_git_repos.sh`.
2.  **Add Shebang & Permissions:** Add `#!/bin/bash` at the top and make executable (`chmod +x scan_git_repos.sh`).
3.  **Implement Argument Parsing:** Add the `ROOT_DIR="${1:-.}"` and `realpath` logic (include fallback if `realpath` command is missing). Add checks for `git` command existence and if `ROOT_DIR` exists.
4.  **Implement `check_git_status` Function:** Adapt the function to robustly check if a directory is a Git repo root using `rev-parse --show-toplevel` and `realpath` comparison. Check status using `git -C`, `status --porcelain`, `rev-parse @{u}`, and `log @{u}..`. Ensure correct output formatting.
5.  **Implement Git Repo Discovery (Pass 1):**
    *   Define the hardcoded list of ignored directory names: `node_modules`, `venv`, `.venv`, `env`, `.env`, `target`, `build`, `dist`.
    *   Construct the `find` command arguments for pruning these ignored directories (`-name ... -prune -o`). Also prune `.git` itself.
    *   Use `find "$ROOT_DIR" -type d \( <prune_options> -name .git \) -print0` to locate `.git` directories efficiently.
    *   In the loop, use `git rev-parse --show-toplevel` and `realpath` to find the actual repo root.
    *   Populate the `git_roots_list` and `processed_dirs_list` (newline-separated strings) using the `path_in_list` helper function to avoid duplicates and mark parents. Call `check_git_status` for each unique repo root found.
6.  **Implement Non-Git Root Discovery (Pass 2):**
    *   Construct `find` command arguments to prune the ignored directories AND the Git roots found in Pass 1 (`-path ... -prune -o`).
    *   Use `find "$ROOT_DIR" -type d \( <ignore_prunes> <git_root_prunes> -print \) -print0` to iterate through remaining directories.
    *   In the loop, skip directories already in `processed_dirs_list`.
    *   Check if any parent is in `processed_dirs_list` or `non_git_roots_list`. If not, check if the current directory is *not* a Git repo itself (`git rev-parse --is-inside-work-tree`), and if so, add it to `non_git_roots_list`.
7.  **Implement Reporting:** Use a `while read` loop over `echo "$non_git_roots_list"` to iterate and print the paths with the `[NON-GIT]` status. Add start/completion messages.
8.  **Refinement & Error Handling:** (Already partially addressed in steps 3 & 4) Ensure `realpath` fallback works. Handle potential errors from `find` or `git` commands gracefully (e.g., permission denied - `find` might print errors but continue).
9.  **Testing:** Test extensively with the scenarios listed previously, paying special attention to directories matching the ignore list and nested repositories. Ensure performance improvement is noticeable on large trees.

*(Note: The two-pass `find` approach with explicit pruning is maintained for clarity and compatibility.)*
