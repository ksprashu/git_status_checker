#!/bin/zsh

# Script to recursively find Git repositories and check their status sequentially.
# Reports uncommitted changes and unpushed commits.
# Also reports top-level directories under the target directory that contain no Git repositories.
# Version 7: Reverted to sequential execution.

# --- Configuration ---
# Default directory to scan if no argument is provided
DEFAULT_DIR="${HOME}/code"
# Timeout duration in seconds for git fetch
FETCH_TIMEOUT=15

# Colors for output (optional)
COLOR_NC='\033[0m' # No Color
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_MAGENTA='\033[0;35m'

# --- Globals ---
# Associative array to keep track of top-level dirs containing git repos
# Needs to be global because it's modified within the find loop's sub-process
# (due to process substitution) but read later.
typeset -gA top_level_dirs_with_git

# --- Functions ---

# Function to check the status of a single Git repository
check_repo_status() {
  # Make local variables truly local to this function instance
  local repo_path="$1"
  local repo_name=$(basename "$repo_path")
  local original_dir=$(pwd)
  local status_output=""
  local uncommitted=false
  local unpushed=false
  local no_upstream=false
  local no_remote=false
  # Localize variables used within the function
  local fetch_pid sleep_pid fetch_status fetch_timed_out first_finished_pid upstream add_fetch_status_msg wait_status

  # Change into the repository directory
  cd "$repo_path" || {
    printf "${COLOR_RED}Error: Could not cd into '%s'. Skipping.${COLOR_NC}\n" "$repo_path" >&2
    return 1
  }

  # Check 1: Uncommitted changes (staged, unstaged, untracked)
  if [[ -n "$(git status --porcelain)" ]]; then
    uncommitted=true
    status_output+="${COLOR_RED}Uncommitted changes${COLOR_NC}"
  fi

  # Check 2: Unpushed commits
  # First, check if there are any remotes configured
  if [[ -z "$(git remote -v)" ]]; then
    no_remote=true
    if [[ "$uncommitted" = true ]]; then
      status_output+=", "
    fi
    status_output+="${COLOR_YELLOW}No remote configured${COLOR_NC}"
  else
    # Fetch latest remote state quietly with a timeout (macOS compatible)
    fetch_status=0
    fetch_timed_out=false

    # Start fetch in the background
    (command git fetch --quiet) & fetch_pid=$! # Use command to avoid potential alias/function issues

    # Start sleep in the background
    (sleep $FETCH_TIMEOUT) & sleep_pid=$!

    # Wait for the first process (fetch or sleep) to finish
    # Redirect stderr of wait to avoid "Terminated" messages for killed processes
    wait -p first_finished_pid $fetch_pid $sleep_pid >/dev/null 2>&1
    wait_status=$? # Capture wait's exit status

    # Check which process finished first
    if [[ $wait_status -eq 0 && $first_finished_pid -eq $fetch_pid ]]; then
        # Fetch finished first (within timeout)
        kill $sleep_pid >/dev/null 2>&1 # Kill the sleep process
        wait $fetch_pid # Get the exit status of fetch
        fetch_status=$?
        if [[ $fetch_status -ne 0 ]]; then
             printf "${COLOR_YELLOW}Warning: 'git fetch' failed in %s (exit code %s). Check connection or permissions.${COLOR_NC}\n" "$repo_path" "$fetch_status" >&2
        fi
    elif [[ $wait_status -eq 0 && $first_finished_pid -eq $sleep_pid ]]; then
        # Sleep finished first (fetch timed out)
        kill -9 $fetch_pid >/dev/null 2>&1 # Force kill the fetch process
        fetch_timed_out=true
        fetch_status=1 # Indicate failure
        printf "${COLOR_YELLOW}Warning: 'git fetch' timed out after %s seconds in %s.${COLOR_NC}\n" "$FETCH_TIMEOUT" "$repo_path" >&2
    else
        # Handle cases where wait might fail or return unexpected PIDs
        # Check if pids still exist before killing
        kill -0 $fetch_pid >/dev/null 2>&1 && kill -9 $fetch_pid >/dev/null 2>&1 # Kill fetch if still running
        kill -0 $sleep_pid >/dev/null 2>&1 && kill $sleep_pid >/dev/null 2>&1 # Kill sleep if still running
        fetch_timed_out=true # Assume timeout as the likely cause
        fetch_status=1
        printf "${COLOR_YELLOW}Warning: Could not determine fetch status reliably in %s, assuming timeout.${COLOR_NC}\n" "$repo_path" >&2
    fi

    # Clean up any remaining background processes (wait without blocking)
    wait $fetch_pid >/dev/null 2>&1
    wait $sleep_pid >/dev/null 2>&1


    # Check if the current branch has an upstream configured
    # Only check upstream if fetch didn't fail or timeout
    if [[ $fetch_status -eq 0 ]]; then
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
    fi

    if [[ -z "$upstream" ]]; then
      # Don't report 'no upstream' if fetch failed/timed out, as it might be inaccurate
      if [[ $fetch_status -eq 0 ]]; then
          no_upstream=true
      fi
      # Check if there are *any* local commits not on *any* remote branch
      if git rev-parse --verify HEAD &>/dev/null && git log --branches --not --remotes --simplify-by-decoration --oneline &>/dev/null; then
         unpushed=true
         if [[ "$uncommitted" = true || "$no_remote" = true ]]; then
           status_output+=", "
         fi
         # Add specific message based on whether upstream check was possible
         if [[ $fetch_status -eq 0 && "$no_upstream" = true ]]; then
             status_output+="${COLOR_YELLOW}Unpushed commits (no upstream branch set)${COLOR_NC}"
         elif [[ $fetch_timed_out = true ]]; then
             status_output+="${COLOR_YELLOW}Unpushed commits (upstream status unknown due to fetch timeout)${COLOR_NC}"
         else
             status_output+="${COLOR_YELLOW}Unpushed commits (upstream status unknown due to fetch failure)${COLOR_NC}"
         fi
      elif [[ "$uncommitted" = true || "$no_remote" = true ]]; then
         if [[ $fetch_status -eq 0 && "$no_upstream" = true ]]; then
            status_output+=", ${COLOR_YELLOW}No upstream branch set${COLOR_NC}"
         fi
      else
         if [[ "$uncommitted" = false && "$no_remote" = false && $fetch_status -eq 0 && "$no_upstream" = true ]]; then
             status_output+="${COLOR_YELLOW}No upstream branch set${COLOR_NC}"
         fi
      fi

    else
      # Upstream is configured, check specifically against it
      if git rev-parse --verify HEAD &>/dev/null && [[ -n "$(git log '@{u}..' --oneline)" ]]; then
        unpushed=true
        if [[ "$uncommitted" = true || "$no_remote" = true || "$no_upstream" = true ]]; then
          status_output+=", "
        fi
        status_output+="${COLOR_RED}Unpushed commits${COLOR_NC}"
      fi
    fi
  fi

  # Print status if there's anything to report
  if [[ "$uncommitted" = true || "$unpushed" = true || ("$no_upstream" = true && "$unpushed" = false && $fetch_status -eq 0) || "$no_remote" = true || $fetch_timed_out = true || ($fetch_status -ne 0 && $fetch_timed_out = false) ]]; then
    # Add fetch status message if needed and not implicitly covered
    add_fetch_status_msg=false
    if [[ $fetch_timed_out = true || ($fetch_status -ne 0 && $fetch_timed_out = false && "$no_remote" = false) ]]; then
        if [[ "$status_output" != *"upstream status unknown"* ]]; then
             add_fetch_status_msg=true
        fi
    fi

    if [[ -n "$status_output" && $add_fetch_status_msg = true ]]; then
        status_output+=", "
    fi

     if [[ $add_fetch_status_msg = true ]]; then
         if [[ $fetch_timed_out = true ]]; then
             status_output+="${COLOR_YELLOW}Fetch timed out${COLOR_NC}"
         elif [[ $fetch_status -ne 0 ]]; then
             status_output+="${COLOR_YELLOW}Fetch failed${COLOR_NC}"
         fi
     fi

    printf "${COLOR_BLUE}Repo:${COLOR_NC} %s - %s\n" "$repo_path" "$status_output"
  fi

  # Change back to the original directory
  cd "$original_dir" || {
      printf "${COLOR_RED}Fatal Error: Could not cd back to original directory from %s. Exiting script.${COLOR_NC}\n" "$repo_path" >&2
      # In sequential mode, failure to cd back is critical
      exit 1
  }
}
# Function does not need to be exported anymore

# --- Main Script ---

# Determine the target directory
TARGET_DIR="${1:-$DEFAULT_DIR}"
# Ensure TARGET_DIR has no trailing slash for consistent path manipulation
TARGET_DIR=${TARGET_DIR%/}

# Check if the target directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "${COLOR_RED}Error: Directory '$TARGET_DIR' not found.${COLOR_NC}" >&2
  exit 1
fi

echo "Scanning for Git repositories under '$TARGET_DIR' (sequentially)..."

# Find all .git directories, process them sequentially
# Use process substitution to read find results safely
while IFS= read -r -d $'\0' git_dir; do
  repo_root=$(dirname "$git_dir")
  # Check if the found .git is actually part of a submodule's .git directory structure
  if [[ "$git_dir" != *".git/modules/"* ]]; then
      # Mark the top-level directory containing this repo
      relative_path=${repo_root#$TARGET_DIR/}
      top_level_component=${relative_path%%/*}
      top_level_dir_path="$TARGET_DIR/$top_level_component"
      top_level_dirs_with_git[$top_level_dir_path]=1

      # Check the status of this specific repo SEQUENTIALLY
      check_repo_status "$repo_root"
      # No backgrounding (&), no PID storage, no job limiting needed
  fi
done < <(find "$TARGET_DIR" -type d -name ".git" -print0) # Use process substitution

echo "Repository scans finished."


# Now check for non-Git directories - this runs *after* all scans are done
echo "\nChecking for top-level directories without Git repositories..."

# Find all immediate subdirectories of the target directory
find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' top_level_dir; do
  # Check if this top-level directory was marked as containing a git repo
  if [[ -z "${top_level_dirs_with_git[$top_level_dir]}" ]]; then
    # If it's not in the associative array, it (and its children) contain no git repos
    echo "${COLOR_MAGENTA}Non-Git Dir:${COLOR_NC} $top_level_dir"
  fi
done


echo "\nScan complete."

# Make the script executable: chmod +x your_script_name.sh
# Run it: ./your_script_name.sh [optional_directory_path]
# Example: ./your_script_name.sh ~/my_projects

