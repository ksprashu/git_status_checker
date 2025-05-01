#!/usr/bin/env bash

# backup_git_status.sh - Script to scan through subfolders recursively in the given directory,
# detect Git repositories, and report their status (uncommitted changes, commits not pushed).
# Additionally, list top-level directories without any Git repository within them.

# Usage: ./backup_git_status.sh /path/to/code

dir_to_scan="$1"

if [[ -z "$dir_to_scan" ]]; then
  echo "Usage: $0 /path/to/code"
  exit 1
fi

if [[ ! -d "$dir_to_scan" ]]; then
  echo "Error: Directory '$dir_to_scan' does not exist." >&2
  exit 1
fi

# Arrays to store results
declare -a git_repos
declare -a non_git_topdirs

# Function to check status of a git repo
check_git_repo() {
  local repo_path="$1"
  pushd "$repo_path" >/dev/null || return

  # Check for uncommitted changes
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "[MODIFIED]  $repo_path"
  fi

  # Check for unpushed commits
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    local ahead=$(git rev-list --left-right --count HEAD..."$upstream" 2>/dev/null | awk '{print $1}')
    if [[ "$ahead" -gt 0 ]]; then
      echo "[UNPUSHED]  $repo_path ($ahead commit(s) ahead of $upstream)"
    fi
  else
    echo "[NO UPSTREAM] $repo_path (no remote tracking branch)"
  fi

  popd >/dev/null || return
}

# Recursive scan function
scan_folder() {
  local current_dir="$1"
  local top_level_root="$2"
  local found_git=false

  # Detect if current_dir is a git repo
  if [[ -d "$current_dir/.git" ]]; then
    # It's a git repo, record and check status
    git_repos+=("$current_dir")
    found_git=true
    check_git_repo "$current_dir"
    return
  fi

  # Not a git repo, scan children
  shopt -s nullglob dotglob
  local children=("$current_dir"/*)
  shopt -u nullglob dotglob

  for child in "${children[@]}"; do
    if [[ -d "$child" ]]; then
      scan_folder "$child" "$top_level_root"
    fi
  done

  # If scanning a top-level directory and found no git in its subtree, record it
  if [[ "$current_dir" == "$top_level_root" ]]; then
    # check if any known git repo starts with this prefix
    for repo in "${git_repos[@]}"; do
      if [[ "$repo" == "$current_dir"* ]]; then
        found_git=true
        break
      fi
    done

    if [[ "$found_git" == false ]]; then
      non_git_topdirs+=("$current_dir")
    fi
  fi
}

# Main logic

echo "Scanning '$dir_to_scan' for Git repositories and statuses..."

shopt -s nullglob dotglob
for entry in "$dir_to_scan"/*; do
  if [[ -d "$entry" ]]; then
    scan_folder "$entry" "$entry"
  fi
done
shopt -u nullglob dotglob

# Display non-git top directories
if (( ${#non_git_topdirs[@]} > 0 )); then
  echo -e "\nTop-level directories without any Git repository (nor any in their subfolders):"
  for d in "${non_git_topdirs[@]}"; do
    echo "  - $d"
  done
else
  echo -e "\nAll top-level directories contain at least one Git repository."
fi

# Summary

echo -e "\nSummary:"
echo "  Total Git repos found: ${#git_repos[@]}"
echo "  Top-level non-git directories: ${#non_git_topdirs[@]}"
