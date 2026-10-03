#!/bin/bash

# Function to check a single directory's Git status
# Outputs status string like "[UNCOMMITTED] /path" or "[UNPUSHED] /path"
# Returns 0 if it's a Git repo root, 1 otherwise.
check_git_status() {
  local dir="$1"
  local status=""
  echo >&2 "DEBUG: Checking status for $dir" # Print to stderr

  # Check if it's inside a git working tree
  if ! git -C "$dir" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
     return 1 # Not a git repo or inside one
  fi

  # Check if it's the *root* of the working tree
  local git_root
  git_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
  # Use realpath for robust comparison
  local real_dir real_git_root
  real_dir=$(realpath "$dir")
  real_git_root=$(realpath "$git_root" 2>/dev/null || echo "") # Handle potential error if git_root is empty/invalid
  echo >&2 "DEBUG: Git root check: real_dir='$real_dir', real_git_root='$real_git_root'"
  if [[ -z "$git_root" ]] || [[ "$real_dir" != "$real_git_root" ]]; then
      # It's inside a repo, but not the root dir we want to report on.
      return 1
  fi

  # Check for uncommitted changes (includes untracked files)
  local porcelain_status
  porcelain_status=$(git -C "$dir" status --porcelain)
  echo >&2 "DEBUG: Porcelain status output for $dir:"$'\n'"$porcelain_status"
  if [[ -n "$porcelain_status" ]]; then
    status="UNCOMMITTED"
  else
    # Check for unpushed changes (only if clean)
    if git -C "$dir" rev-parse --abbrev-ref '@{u}' > /dev/null 2>&1; then
      if [[ -n $(git -C "$dir" log '@{u}..' --oneline) ]]; then
        status="UNPUSHED"
      fi
    fi
  fi

  # Report status only if UNCOMMITTED or UNPUSHED
  echo >&2 "DEBUG: Determined status for $dir: $status"
  if [[ "$status" == "UNCOMMITTED" || "$status" == "UNPUSHED" ]]; then
    echo "[$status] $dir"
  fi

  return 0 # It was a git repo root
}

# --- Main Script Logic ---

# Ensure realpath is available (often in coreutils)
if ! command -v realpath &> /dev/null; then
    # Basic fallback for realpath if not found
    realpath() {
        [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
    }
    # More robust polyfill could be added if needed
fi

# Ensure git is available
if ! command -v git &> /dev/null; then
    echo "Error: git command not found. Please install Git." >&2
    exit 1
fi

ROOT_DIR="${1:-.}" # Use provided arg or default to current dir
# Check if the provided directory exists
if [[ ! -d "$ROOT_DIR" ]]; then
    echo "Error: Directory '$ROOT_DIR' not found." >&2
    exit 1
fi
# Resolve to absolute path using the potentially defined function or command
ROOT_DIR=$(realpath "$ROOT_DIR")

echo "Scanning directory: $ROOT_DIR"
echo "---"

# Use newline-separated strings instead of associative arrays
processed_dirs_list=""
non_git_roots_list=""
git_roots_list=""

# Helper function to check if a path is in a newline-separated list
path_in_list() {
    local path="$1"
    local list="$2"
    # Use grep with -F (fixed string) and -x (exact line match)
    echo "$list" | grep -q -F -x "$path"
}

# --- Define ignored directories and construct find prune arguments ---
ignored_dirs=(node_modules venv .venv env .env target build dist)
prune_paths_ignore=()
for ignore_name in "${ignored_dirs[@]}"; do
    # Add '-name DIR_NAME -prune -o' for each ignored name
    prune_paths_ignore+=(-name "$ignore_name" -prune -o)
done
# Also prune the .git directory itself
prune_paths_ignore+=(-name ".git" -prune -o)
# --- End ignore definition ---


# 1. Find all Git repository roots (.git directories), pruning ignored dirs
echo "Pass 1: Finding Git repositories..."
while IFS= read -r -d $'\0' git_dir; do
  # $git_dir is the path to the .git directory itself
  repo_root=$(dirname "$git_dir")
  # Resolve path AFTER checking existence (should exist if found by find)
  if [[ ! -d "$repo_root" ]]; then continue; fi
  repo_root=$(realpath "$repo_root")

  # Check if already processed (e.g., nested repo root found via parent)
  if path_in_list "$repo_root" "$git_roots_list"; then
      continue
  fi
  git_roots_list="${git_roots_list}${repo_root}"$'\n'

  # Check and report status of this repo root
  check_git_status "$repo_root"

  # Mark this repo root and all its parents *up to ROOT_DIR* as processed
  if ! path_in_list "$repo_root" "$processed_dirs_list"; then
      processed_dirs_list="${processed_dirs_list}${repo_root}"$'\n'
  fi
  parent=$(dirname "$repo_root")
  # Loop while parent is not root, not '.', and starts with ROOT_DIR
  while [[ "$parent" != "/" && "$parent" != "." && "$parent" == "$ROOT_DIR"* ]]; do
      if ! path_in_list "$parent" "$processed_dirs_list"; then
          processed_dirs_list="${processed_dirs_list}${parent}"$'\n'
      fi
      # Break if parent is the ROOT_DIR itself
      if [[ "$parent" == "$ROOT_DIR" ]]; then break; fi
      parent=$(dirname "$parent")
  done
# Use find: Start at ROOT_DIR. Apply pruning for ignored names AND .git itself.
# If not pruned, check if it's a directory named .git and print its path null-terminated.
done < <(find "$ROOT_DIR" \( "${prune_paths_ignore[@]}" -false \) -o \( -type d -name .git -print0 \))


# 2. Find all directories again, pruning ignored dirs AND known git roots, to identify potential non-Git roots
echo "Pass 2: Finding non-Git directories..."
# Construct prune paths for known git roots found in pass 1
git_root_prune_paths=()
while IFS= read -r groot; do
    if [[ -n "$groot" ]]; then
        # Use -path for full path matching, ensure it's anchored if needed, though realpath helps
        git_root_prune_paths+=(-path "$groot" -prune -o)
    fi
done < <(echo "$git_roots_list")

while IFS= read -r -d $'\0' dir; do
  # Found directory 'dir' was not pruned by ignore list or git root list
  if [[ ! -d "$dir" ]]; then continue; fi # Skip if not a directory (e.g., broken link)
  dir=$(realpath "$dir")

  # Skip if directory is somehow already marked processed (shouldn't happen if pruning works)
  if path_in_list "$dir" "$processed_dirs_list"; then
    continue
  fi

  # Check if any parent (within ROOT_DIR) is already marked as a non-git root.
  is_child_of_non_git=false
  parent=$(dirname "$dir")
  while [[ "$parent" != "/" && "$parent" != "." && "$parent" == "$ROOT_DIR"* ]]; do
      if path_in_list "$parent" "$non_git_roots_list"; then
          is_child_of_non_git=true
          break
      fi
      if [[ "$parent" == "$ROOT_DIR" ]]; then break; fi
      parent=$(dirname "$parent")
  done

  # If it's not processed and not a child of an already identified non-git root, mark it.
  if ! $is_child_of_non_git; then
      # Double check it's not actually a git repo itself (should be rare)
       if ! git -C "$dir" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
           if ! path_in_list "$dir" "$non_git_roots_list"; then
               non_git_roots_list="${non_git_roots_list}${dir}"$'\n'
           fi
       else
           # It IS a git repo but wasn't caught (e.g. bare repo, submodule?). Mark processed.
           if ! path_in_list "$dir" "$processed_dirs_list"; then
               processed_dirs_list="${processed_dirs_list}${dir}"$'\n'
           fi
       fi
  fi
# Use find: Start at ROOT_DIR. Apply pruning for ignored names AND known git roots.
# If not pruned, check if it's a directory (-type d) and print its path null-terminated.
# The final -print0 applies to items not pruned.
done < <(find "$ROOT_DIR" \( "${prune_paths_ignore[@]}" "${git_root_prune_paths[@]}" -false \) -o \( -type d -print0 \))


# 3. Report the identified non-git roots
echo "---"
echo "Non-Git Root Directories Found:"
non_git_count=0
# Use process substitution and read loop for portability over IFS manipulation
while IFS= read -r root; do
    if [[ -n "$root" ]]; then # Ensure we don't process empty lines
        # Final check: Ensure this root itself wasn't actually a git repo missed
        # This check is less critical now with the improved Pass 1, but safe.
        if ! git -C "$root" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
            echo "[NON-GIT] $root"
            ((non_git_count++))
        fi
    fi
done < <(echo "$non_git_roots_list")


if [[ $non_git_count -eq 0 ]]; then
    echo "(None)"
fi

echo "---"
echo "Scan complete. Found $non_git_count top-level non-Git directories."
echo "Git repositories with statuses (UNCOMMITTED/UNPUSHED) listed above."
