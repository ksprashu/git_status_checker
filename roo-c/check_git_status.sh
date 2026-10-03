#!/bin/bash

# Git Repository Status Checker
# This script traverses a directory structure, identifies Git repositories,
# and reports their status (uncommitted changes, unpushed commits).
# It also identifies top-level directories that don't contain any Git repositories.

# Usage: ./check_git_status.sh [root_directory] [options]
# Options:
#   --debug    Enable debug output
#   --help     Show help information

# Set text colors for better readability
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a directory is a Git repository and determine its status
check_git_status() {
  local dir="$1"
  local status=""

  # Check if it's a Git repository
  if [ ! -d "$dir/.git" ]; then
    return 1  # Not a Git repository
  fi

  # Change to the directory to run Git commands
  pushd "$dir" > /dev/null || return 1

  # Check for uncommitted changes (includes untracked files)
  if [ -n "$(git status --porcelain)" ]; then
    status="UNCOMMITTED"
  else
    # Check for unpushed commits
    if git rev-parse --abbrev-ref '@{u}' &>/dev/null; then
      if [ -n "$(git log '@{u}..' --oneline)" ]; then
        status="UNPUSHED"
      fi
    else
      # No upstream branch configured
      if [ -n "$(git log --oneline)" ]; then
        status="NO_REMOTE"
      fi
    fi
  fi

  # Return to original directory
  popd > /dev/null

  # Output the status
  echo "$status"
  return 0  # It is a Git repository
}

# Function to check if a directory is already processed
is_processed() {
  local dir="$1"
  for processed in "${processed_dirs[@]}"; do
    if [ "$dir" = "$processed" ]; then
      return 0
    fi
  done
  return 1
}

# Function to mark a directory as processed
mark_processed() {
  local dir="$1"
  processed_dirs+=("$dir")
}

# Function to check if a directory should be ignored
should_ignore() {
  local dir_name="$1"
  for ignore_dir in "${ignore_dirs[@]}"; do
    if [ "$dir_name" = "$ignore_dir" ]; then
      return 0  # Should ignore
    fi
  done
  return 1  # Should not ignore
}

# Function to check if a directory contains a Git repository
contains_git_repo() {
  local dir="$1"

  # Use find to look for .git directories
  if [ -n "$(find "$dir" -name ".git" -type d -print -quit 2>/dev/null)" ]; then
    return 0  # Contains a Git repository
  fi
  return 1  # Does not contain a Git repository
}

# Function to process a directory
process_directory() {
  local dir="$1"
  local is_top_level="$2"
  local found_git=false

  debug_log "Processing directory: $dir"

  # Check if this directory is already processed
  if is_processed "$dir"; then
    debug_log "Directory already processed: $dir"
    return 0
  fi

  # Increment the counter
  ((total_dirs_processed++))

  # Check if it's a Git repository
  local status=$(check_git_status "$dir")
  if [ $? -eq 0 ]; then
    # It's a Git repository
    found_git=true
    debug_log "Found Git repository during traversal: $dir (Status: $status)"

    # Add to the list of Git repositories with its status
    if [ -n "$status" ]; then
      # Check if we already have this repository (could have been found by find)
      local already_found=false
      for repo in "${git_repos[@]}"; do
        IFS=':' read -r existing_dir existing_status <<< "$repo"
        if [ "$existing_dir" = "$dir" ]; then
          already_found=true
          break
        fi
      done

      if [ "$already_found" = false ]; then
        git_repos+=("$dir:$status")
        debug_log "Added Git repository: $dir"
      else
        debug_log "Repository already in list: $dir"
      fi
    else
      # Same check for already found repos
      local already_found=false
      for repo in "${git_repos[@]}"; do
        IFS=':' read -r existing_dir existing_status <<< "$repo"
        if [ "$existing_dir" = "$dir" ]; then
          already_found=true
          break
        fi
      done

      if [ "$already_found" = false ]; then
        git_repos+=("$dir:CLEAN")
        debug_log "Added clean Git repository: $dir"
      else
        debug_log "Clean repository already in list: $dir"
      fi
    fi

    # Mark this directory as processed
    mark_processed "$dir"

    return 0
  fi

  # Not a Git repository, process subdirectories
  debug_log "Not a Git repository, processing subdirectories of: $dir"

  # Check if we can access the directory contents
  if [ ! -r "$dir" ]; then
    debug_log "Cannot read directory: $dir (permission denied)"
    return 1
  fi

  # Check if the directory exists and is not empty
  if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    debug_log "Directory is empty or does not exist: $dir"
    return 1
  fi

  for subdir in "$dir"/*; do
    if [ -d "$subdir" ] && [ ! -L "$subdir" ]; then  # Skip symlinks
      # Check if this directory should be ignored
      dir_name=$(basename "$subdir")
      if ! should_ignore "$dir_name"; then
        process_directory "$subdir" false
        if [ $? -eq 0 ]; then
          found_git=true
          debug_log "Found Git in subdirectory of: $dir"
        fi
      else
        debug_log "Ignoring directory: $subdir"
        ((total_dirs_ignored++))
      fi
    fi
  done

  # If this is a top-level directory and no Git repository was found,
  # add it to the list of non-Git directories
  if [ "$is_top_level" = true ] && [ "$found_git" = false ]; then
    non_git_dirs+=("$dir")
    debug_log "Added non-Git directory: $dir"
  fi

  # Mark this directory as processed
  mark_processed "$dir"

  if [ "$found_git" = true ]; then
    return 0
  else
    return 1
  fi
}

# Function to display the results
display_results() {
  # Sort the repository arrays for easier reading
  IFS=$'\n' sorted_repos=($(sort <<<"${git_repos[*]}"))
  unset IFS

  echo -e "${YELLOW}=== Git Repositories with Uncommitted Changes ===${NC}"
  local uncommitted_count=0
  for repo in "${sorted_repos[@]}"; do
    IFS=':' read -r dir status <<< "$repo"
    if [ "$status" = "UNCOMMITTED" ]; then
      echo -e "${RED}[UNCOMMITTED] $dir${NC}"
      ((uncommitted_count++))
    fi
  done
  if [ $uncommitted_count -eq 0 ]; then
    echo -e "${GREEN}No repositories with uncommitted changes found.${NC}"
  fi

  echo -e "\n${YELLOW}=== Git Repositories with Unpushed Commits ===${NC}"
  local unpushed_count=0
  for repo in "${sorted_repos[@]}"; do
    IFS=':' read -r dir status <<< "$repo"
    if [ "$status" = "UNPUSHED" ]; then
      echo -e "${YELLOW}[UNPUSHED] $dir${NC}"
      ((unpushed_count++))
    fi
  done
  if [ $unpushed_count -eq 0 ]; then
    echo -e "${GREEN}No repositories with unpushed commits found.${NC}"
  fi

  echo -e "\n${YELLOW}=== Git Repositories with No Remote ===${NC}"
  local no_remote_count=0
  for repo in "${sorted_repos[@]}"; do
    IFS=':' read -r dir status <<< "$repo"
    if [ "$status" = "NO_REMOTE" ]; then
      echo -e "${BLUE}[NO_REMOTE] $dir${NC}"
      ((no_remote_count++))
    fi
  done
  if [ $no_remote_count -eq 0 ]; then
    echo -e "${GREEN}No repositories without remote tracking branches found.${NC}"
  fi

  echo -e "\n${YELLOW}=== Clean Git Repositories ===${NC}"
  local clean_count=0
  for repo in "${sorted_repos[@]}"; do
    IFS=':' read -r dir status <<< "$repo"
    if [ "$status" = "CLEAN" ]; then
      echo -e "${GREEN}[CLEAN] $dir${NC}"
      ((clean_count++))
    fi
  done
  if [ $clean_count -eq 0 ]; then
    echo -e "${YELLOW}No clean repositories found.${NC}"
  fi

  echo -e "\n${YELLOW}=== Top-Level Non-Git Directories ===${NC}"
  if [ ${#non_git_dirs[@]} -eq 0 ]; then
    echo -e "${GREEN}All directories contain Git repositories.${NC}"
  else
    # Sort non-git directories for easier reading
    IFS=$'\n' sorted_non_git=($(sort <<<"${non_git_dirs[*]}"))
    unset IFS

    for dir in "${sorted_non_git[@]}"; do
      echo -e "${BLUE}[NON-GIT] $dir${NC}"
    done
  fi

  # Print diagnostic information
  echo -e "\n${YELLOW}=== Scan Statistics ===${NC}"
  echo -e "Total directories checked: $total_dirs_checked"
  echo -e "Total directories processed: $total_dirs_processed"
  echo -e "Total directories ignored: $total_dirs_ignored"
  echo -e "Total git repositories found: ${#git_repos[@]}"
  echo -e "Total processed directories tracked: ${#processed_dirs[@]}"
}

# Function to check if Git is installed
check_git_installed() {
  if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: Git is not installed or not in PATH.${NC}"
    exit 1
  fi
}

# Function to check if realpath is available
check_realpath_available() {
  if ! command -v realpath &> /dev/null; then
    # Define a simple fallback for realpath
    realpath() {
      [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
    }
  fi
}

# Debug mode flag (disabled by default)
DEBUG=false

# Function to log debug information
debug_log() {
  if [ "$DEBUG" = true ]; then
    echo -e "${BLUE}DEBUG: $1${NC}" >&2
  fi
}

# Function to show help information
show_help() {
  echo "Git Repository Status Checker"
  echo "Usage: ./check_git_status.sh [root_directory] [options]"
  echo ""
  echo "Options:"
  echo "  --debug    Enable debug output"
  echo "  --help     Show this help information"
  echo ""
  echo "Examples:"
  echo "  ./check_git_status.sh               # Scan the current directory"
  echo "  ./check_git_status.sh ~/code        # Scan the ~/code directory"
  echo "  ./check_git_status.sh ~/code --debug  # Scan with debug output enabled"
  exit 0
}

# Main script logic

# Check if Git is installed
check_git_installed

# Check if realpath is available
check_realpath_available

# Process command-line arguments
ROOT_DIR="."
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --debug)
      DEBUG=true
      ;;
    --help)
      show_help
      ;;
    *)
      if [[ "$arg" != -* ]]; then
        # If not starting with -, treat as directory
        ROOT_DIR="$arg"
      else
        echo -e "${RED}Unknown option: $arg${NC}" >&2
        echo "Use --help for available options" >&2
        exit 1
      fi
      ;;
  esac
done

# Check if the provided directory exists
if [ ! -d "$ROOT_DIR" ]; then
  echo -e "${RED}Error: Directory '$ROOT_DIR' does not exist.${NC}"
  exit 1
fi

# Convert to absolute path
ROOT_DIR=$(realpath "$ROOT_DIR")

# Initialize arrays to store results
declare -a git_repos=()
declare -a non_git_dirs=()
declare -a processed_dirs=()
declare total_dirs_checked=0
declare total_dirs_processed=0
declare total_dirs_ignored=0

# Modify the ignore list to be less aggressive
# Define directories to ignore (these can significantly slow down traversal)
declare -a ignore_dirs=(
  "node_modules"  # Node.js dependencies (can be massive)
  ".venv" "venv"  # Python virtual environments
  "target"  # Java/Maven build directory
  ".git"  # Skip .git directories themselves
)

echo -e "${BLUE}Scanning directory: $ROOT_DIR${NC}"
echo "---"

# Use find command to locate all .git directories for more reliable identification
echo "Scanning for Git repositories using find..."

# Count total directories for diagnostic purposes
total_dirs_checked=$(find "$ROOT_DIR" -type d | wc -l)
debug_log "Total directories under $ROOT_DIR: $total_dirs_checked"

# Use find with maxdepth to limit excessive recursion
find_max_depth=15
debug_log "Using find with max depth $find_max_depth"

found_git_dirs=$(find "$ROOT_DIR" -maxdepth $find_max_depth -type d -name ".git" 2>/dev/null | wc -l)
debug_log "Found $found_git_dirs .git directories"

while IFS= read -r git_dir; do
  if [ -d "$git_dir" ]; then
    # Get the parent directory (repository root)
    repo_root=$(dirname "$git_dir")
    debug_log "Found Git repository: $repo_root"

    # Check repository status
    status=$(check_git_status "$repo_root")
    if [ $? -eq 0 ]; then
      if [ -n "$status" ]; then
        git_repos+=("$repo_root:$status")
      else
        git_repos+=("$repo_root:CLEAN")
      fi

      # Mark this directory as processed
      mark_processed "$repo_root"
    fi
  fi
done < <(find "$ROOT_DIR" -maxdepth $find_max_depth -type d -name ".git" 2>/dev/null)

debug_log "Found ${#git_repos[@]} Git repositories using find"

# Process the root directory using our recursive method as backup
debug_log "Starting recursive directory traversal from root..."
for subdir in "$ROOT_DIR"/*; do
  if [ -d "$subdir" ] && [ ! -L "$subdir" ]; then  # Skip symlinks
    # Check if this directory should be ignored
    dir_name=$(basename "$subdir")
    if ! should_ignore "$dir_name"; then
      debug_log "Processing top-level directory: $dir_name"
      process_directory "$subdir" true
      ((total_dirs_processed++))
    else
      debug_log "Ignoring top-level directory: $dir_name"
      ((total_dirs_ignored++))
    fi
  fi
done

# Display the results
display_results

echo "---"
echo -e "${BLUE}Scan complete.${NC}"
echo -e "Found ${#git_repos[@]} Git repositories and ${#non_git_dirs[@]} top-level non-Git directories."

exit 0
