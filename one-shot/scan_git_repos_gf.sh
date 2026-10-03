#!/bin/zsh

# --- Configuration ---
# Set the base directory to start checking from.
# You can change this path to your "code" folder.
BASE_DIR="$HOME/code"
# ---------------------

# Array to store top-level directories that have no Git repos within them
non_repo_top_dirs=()

# Function to recursively check a directory for Git repositories.
# If a Git repo is found, it prints its status and stops recursing down that path.
# It returns 0 if a Git repo was found in this directory or any subdirectory,
# and 1 if no Git repo was found in this directory or any subdirectory.
check_and_report_git() {
    local current_dir="$1"
    local repo_found_in_path=1 # Assume no repo found in this path initially

    # Check if the current directory is a Git repository
    if [ -d "$current_dir/.git" ]; then
        echo "--- Git Repository Found: $current_dir ---"
        # Use a subshell () to run git status without changing the script's working directory
        (cd "$current_dir" && git status)
        echo "---------------------------------------"
        repo_found_in_path=0 # A repo was found here
    else
        # Not a Git repo, so check its subdirectories
        # Use find to safely iterate through directories, handling spaces/special characters
        find "$current_dir" -maxdepth 1 -mindepth 1 -type d | while read -r subdir; do
            # Recursively call the function for each subdirectory
            # If the recursive call returns 0 (meaning a repo was found in the subdir or below)
            if check_and_report_git "$subdir"; then
                repo_found_in_path=0 # A repo was found somewhere below
            fi
        done
    fi

    # Return the status: 0 if repo found, 1 otherwise
    return $repo_found_in_path
}

echo "Starting Git repository check in: $BASE_DIR"
echo ""

# Check if the base directory exists
if [ ! -d "$BASE_DIR" ]; then
    echo "Error: Base directory '$BASE_DIR' not found."
    exit 1
fi

# Iterate through the top-level items in the base directory
# Use find to get only directories at the first level, excluding the base directory itself
find "$BASE_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r top_dir; do
    echo "Checking top-level directory: $top_dir"
    # Call the function to check this top-level directory and its children
    # The `if ! check_and_report_git "$top_dir"` syntax checks if the function's exit status is non-zero (i.e., 1)
    # If the function returns 1 (meaning no repo was found in $top_dir or its children)
    if ! check_and_report_git "$top_dir"; then
        # Add this top-level directory to our list
        non_repo_top_dirs+=("$top_dir")
    fi
    echo "" # Add a blank line for readability between top-level checks
done

echo "--- Summary ---"
echo "Finished checking Git repositories."
echo ""

echo "--- Top-level directories with no Git repositories (including children): ---"
if [ ${#non_repo_top_dirs[@]} -eq 0 ]; then
    echo "None found."
else
    # Print the list of non-repo top-level directories
    for dir in "${non_repo_top_dirs[@]}"; do
        echo "$dir"
    done
fi
echo "--------------------------------------------------------------------------"

exit 0
