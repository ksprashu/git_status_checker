#!/bin/bash

# Set text colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if a directory path is provided
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Usage: $0 <directory_path>${NC}"
    echo -e "Example: $0 ~/code"
    exit 1
fi

CODE_DIR="$1"

# Check if the provided directory exists
if [ ! -d "$CODE_DIR" ]; then
    echo -e "${RED}Error: Directory '$CODE_DIR' does not exist${NC}"
    exit 1
fi

# Arrays to store results
declare -a UNCOMMITTED_REPOS=()
declare -a UNPUSHED_REPOS=()
declare -a NON_GIT_TOPLEVEL=()
declare -a PROCESSED_DIRS=()

# Function to check if a directory is already processed
is_processed() {
    local dir=$1
    for processed in "${PROCESSED_DIRS[@]}"; do
        if [[ "$dir" == "$processed" || "$dir" == "$processed/"* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if a directory is a git repository
is_git_repo() {
    local dir=$1
    if [ -d "$dir/.git" ]; then
        return 0
    fi
    return 1
}

# Function to check if a git repository has uncommitted changes
has_uncommitted_changes() {
    local dir=$1
    cd "$dir" || return 1
    if ! git diff --quiet || ! git diff --staged --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        return 0
    fi
    return 1
}

# Function to check if a git repository has unpushed commits
has_unpushed_commits() {
    local dir=$1
    cd "$dir" || return 1

    # Get the current branch
    local current_branch
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ $? -ne 0 ]; then
        # Not on any branch, possibly in detached HEAD state
        return 1
    fi

    # Check if there's a remote tracking branch
    if git rev-parse --verify --quiet "$current_branch@{upstream}" >/dev/null 2>&1; then
        # Check if there are unpushed commits
        if [ -n "$(git log "$current_branch@{upstream}".."$current_branch" --oneline 2>/dev/null)" ]; then
            return 0
        fi
    else
        # No upstream branch, consider it as having unpushed commits
        if [ -n "$(git log --oneline 2>/dev/null)" ]; then
            return 0
        fi
    fi

    return 1
}

# Function to check if any subdirectory contains a git repo
contains_git_repo() {
    local dir=$1
    local found=false

    find "$dir" -type d -name ".git" 2>/dev/null | while read -r gitdir; do
        found=true
        break
    done

    if $found; then
        return 0
    else
        return 1
    fi
}

# Function to process a directory
process_directory() {
    local dir=$1
    local is_toplevel=$2

    # Check if this directory is already processed
    if is_processed "$dir"; then
        return
    fi

    # Check if it's a git repository
    if is_git_repo "$dir"; then
        # Mark as processed
        PROCESSED_DIRS+=("$dir")

        # Check for uncommitted changes
        if has_uncommitted_changes "$dir"; then
            UNCOMMITTED_REPOS+=("$dir")
        fi

        # Check for unpushed commits
        if has_unpushed_commits "$dir"; then
            UNPUSHED_REPOS+=("$dir")
        fi
    else
        # Not a git repository, check subdirectories
        local contains_git=false

        # Process all immediate subdirectories
        for subdir in "$dir"/*/; do
            if [ -d "$subdir" ]; then
                process_directory "$subdir" false
            fi
        done

        # If this is a top-level directory and doesn't contain any git repos, add to list
        if [ "$is_toplevel" = true ] && ! contains_git_repo "$dir"; then
            NON_GIT_TOPLEVEL+=("$dir")
        fi
    fi
}

# Start processing from the given directory
echo -e "${BLUE}Checking repositories in $CODE_DIR...${NC}"
# Process immediate subdirectories as top-level
for subdir in "$CODE_DIR"/*/; do
    if [ -d "$subdir" ]; then
        process_directory "$subdir" true
    fi
done

# Print results
echo -e "\n${YELLOW}=== REPOS WITH UNCOMMITTED CHANGES ===${NC}"
if [ ${#UNCOMMITTED_REPOS[@]} -eq 0 ]; then
    echo -e "${GREEN}No repositories with uncommitted changes found.${NC}"
else
    for repo in "${UNCOMMITTED_REPOS[@]}"; do
        echo -e "${RED}$repo${NC}"
    done
fi

echo -e "\n${YELLOW}=== REPOS WITH UNPUSHED COMMITS ===${NC}"
if [ ${#UNPUSHED_REPOS[@]} -eq 0 ]; then
    echo -e "${GREEN}No repositories with unpushed commits found.${NC}"
else
    for repo in "${UNPUSHED_REPOS[@]}"; do
        echo -e "${YELLOW}$repo${NC}"
    done
fi

echo -e "\n${YELLOW}=== TOP-LEVEL DIRECTORIES WITHOUT GIT REPOS ===${NC}"
if [ ${#NON_GIT_TOPLEVEL[@]} -eq 0 ]; then
    echo -e "${GREEN}All directories contain git repositories.${NC}"
else
    for dir in "${NON_GIT_TOPLEVEL[@]}"; do
        echo -e "${BLUE}$dir${NC}"
    done
fi

exit 0
