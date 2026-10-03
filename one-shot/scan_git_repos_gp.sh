#!/bin/zsh

# --- Argument Handling ---
# Check if a command-line argument (target directory) is provided
if [[ $# -eq 0 ]]; then
  # No argument provided, default to the current directory
  TARGET_DIR="."
  echo "No target directory specified. Scanning the current directory ($(pwd))..."
elif [[ $# -eq 1 ]]; then
  # One argument provided, use it as the target directory
  TARGET_DIR="$1"
else
  # More than one argument provided
  echo "Usage: $0 [target_directory]"
  echo "Error: Please provide zero or one directory path as an argument."
  exit 1
fi

# --- Function Definitions ---

# Function to check a single directory recursively for Git repositories
# Returns 0 if a Git repo was found at this level or below.
# Returns 1 if no Git repo was found at this level or below.
check_dir() {
  local dir_path="$1"
  local found_git_in_subtree=false # Flag to track if git repo found anywhere in this subtree

  # Check if the current directory is a git repo
  # Use -e to also find .git files (for worktrees, submodules) although -d is common
  if [[ -e "$dir_path/.git" ]]; then
    echo "\n--- Git Repo Found: $dir_path ---"
    # Change into the repo directory to run git commands
    # Using a subshell (...) avoids the need for cd -
    (
      # Use pushd/popd for potentially safer directory changes
      pushd "$dir_path" > /dev/null || return 1 # Exit subshell if pushd fails

      local repo_status=""
      local current_branch_info=""
      local has_uncommitted=false
      local has_unpushed=false
      local is_detached=false
      local is_empty=false
      local has_upstream=false

      # 1. Check for uncommitted changes (staged or unstaged)
      if [[ -n "$(git status --porcelain)" ]]; then
        repo_status+="  - Status: Uncommitted changes found.\n"
        has_uncommitted=true
      fi

      # 2. Check branch status and push status relative to upstream (if any)
      # Fetch the status including branch info in one go
      # Note: This still compares against the *locally known* state of the remote-tracking branch.
      # Run 'git fetch' manually beforehand for the most up-to-date comparison.
      current_branch_info=$(git status --short --branch | head -n 1)

      # Check for detached HEAD state
      if [[ "$current_branch_info" == *"no branch"* ]] || [[ "$current_branch_info" == *"HEAD detached"* ]]; then
        is_detached=true
        repo_status+="  - Status: Currently in detached HEAD state.\n"
        # If uncommitted changes weren't found above, re-check specifically for detached state
        if ! $has_uncommitted && [[ -n "$(git status --porcelain)" ]]; then
            repo_status+="  - Status: Uncommitted changes found (in detached HEAD state).\n"
            has_uncommitted=true
        fi
      # Check for empty repository
      elif [[ $(git rev-list --count --all) -eq 0 ]]; then
        is_empty=true
        repo_status+="  - Status: Repository is empty (no commits).\n"
      # Regular branch check
      else
        # Extract branch name (simplistic, handles common cases)
        local branch_name=$(echo "$current_branch_info" | sed -n 's/^## \([^ \.]*\).*/\1/p')

        # Check if upstream is configured
        if [[ "$current_branch_info" == *"..."* ]]; then
          has_upstream=true
          # Check if ahead of upstream (unpushed commits)
          if [[ "$current_branch_info" == *"[ahead "* ]]; then
            has_unpushed=true
            local upstream_info=$(echo "$current_branch_info" | sed -n 's/.*\[\(.*\)\].*/\1/p')
            repo_status+="  - Push Status: Branch '$branch_name' has unpushed commits ($upstream_info).\n"
          fi
        else
          # No upstream configured, but check if there are local commits
          if [[ $(git rev-list --count HEAD) -gt 0 ]]; then
            has_unpushed=true # Treat as unpushed since it's not on *any* remote tracking branch
            repo_status+="  - Push Status: Branch '$branch_name' exists locally but has no upstream configured. Local commits exist.\n"
          else
            # No upstream and no local commits (likely a new branch)
             repo_status+="  - Push Status: Branch '$branch_name' exists locally, has no upstream configured, and no local commits.\n"
          fi
        fi
      fi

      # Final summary for the repo
      if ! $has_uncommitted && ! $has_unpushed && ! $is_detached && ! $is_empty; then
         # Looks clean relative to its state and upstream (if any)
         echo "  - Status: Clean. No uncommitted changes found."
         if $has_upstream; then
            echo "  - Push Status: Branch '$branch_name' seems up-to-date with its configured upstream."
         else
             # Clean, but no upstream and no commits yet means nothing to push anyway
             if [[ $(git rev-list --count HEAD) -eq 0 ]]; then
                echo "  - Push Status: Branch '$branch_name' has no upstream and no local commits."
             else
                # This case should have been caught by the 'has_unpushed' logic above if commits exist
                # Add a fallback message just in case
                echo "  - Push Status: Branch '$branch_name' has no upstream configured (status unclear without commits check)."
             fi
         fi
      elif [[ -z "$repo_status" ]]; then
          # If repo_status is empty but we had issues (like detached HEAD or empty repo)
          echo "  - Status: Check specific messages above. Repository might be empty or in detached HEAD."
      else
          # Print the compiled status messages
          echo -e "$repo_status" | sed 's/\\n/\n/g' # Ensure newlines are interpreted correctly
      fi

      popd > /dev/null # Return to original directory
    ) # End of subshell

    return 0 # Indicate Git repo found at this level
  fi # End of git repo check

  # If not a git repo, recursively check subdirectories
  local item
  # Use find for better handling of filenames with special characters and depth control
  # However, sticking to simple loop for now to match original logic
  for item in "$dir_path"/*; do
    # Check if item exists and is a directory before recursing
    # Avoids errors with broken symlinks etc. Also skip .git directories explicitly if iterating this way
    if [[ -d "$item" && "$(basename "$item")" != ".git" ]]; then
      # Pass the recursive call's return status up the chain
      check_dir "$item"
      if [[ $? -eq 0 ]]; then
        # If a git repo was found anywhere below, mark it
        found_git_in_subtree=true
      fi
    fi
  done

  # Return 0 if git was found in children, 1 otherwise
  if [[ "$found_git_in_subtree" = true ]]; then
    return 0
  else
    return 1
  fi
}

# --- Main Script Execution ---

# Resolve TARGET_DIR to an absolute path for clearer output, handle potential errors
ABS_TARGET_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd)
if [[ $? -ne 0 || -z "$ABS_TARGET_DIR" ]]; then
    echo "Error: Target directory '$TARGET_DIR' is not valid or cannot be accessed."
    exit 1
fi
TARGET_DIR="$ABS_TARGET_DIR" # Use the absolute path

# Check if the resolved target directory exists and is a directory
if [[ ! -d "$TARGET_DIR" ]]; then
  # This check might be redundant after the cd/pwd check, but kept for clarity
  echo "Error: Target path '$TARGET_DIR' not found or is not a valid directory."
  exit 1
fi

echo "Scanning directory '$TARGET_DIR' for Git repositories..."
echo "======================================================"

# Iterate through top-level items in the target directory
local top_item
# Use find to handle potentially complex filenames and avoid issues with globbing limits
# -maxdepth 1 ensures we only process immediate children of TARGET_DIR
# -mindepth 1 avoids processing TARGET_DIR itself
find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -print0 | while IFS= read -r -d $'\0' top_item; do
  # Process only directories at the top level
  if [[ -d "$top_item" ]]; then
    # Call the recursive function for this top-level directory
    check_dir "$top_item"
    local exit_status=$? # Capture the return status

    # If the function returns 1 (non-zero), it means NO git repo was found
    # in this top_item or any of its subdirectories.
    if [[ $exit_status -ne 0 ]]; then
      # We already know it's not a git repo itself (checked in the function),
      # and the non-zero status means no children had one either.
      echo "\n--- Non-Git Directory Tree: $top_item ---"
      echo "  - No Git repositories found within this directory or its subdirectories."
    fi
  elif [[ -f "$top_item" ]]; then
    # Optional: Report skipped files at the top level
    # echo "\n--- Skipping File: $top_item ---"
    : # Do nothing for files by default
  fi
done

echo "\n======================================================"
echo "Scan complete."

exit 0
