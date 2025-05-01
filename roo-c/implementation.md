# Git Repository Status Checker - Implementation

## Overview

This document outlines the implementation details for the Git Repository Status Checker, including the algorithm, key functions, and step-by-step implementation guide.

## Algorithm

The core algorithm for the Git Repository Status Checker consists of the following steps:

1. **Initialization**:
   - Parse command-line arguments to get the root directory
   - Initialize data structures to store results
   - Validate the root directory exists and is accessible

2. **First Pass - Find Git Repositories**:
   - Traverse the directory structure starting from the root
   - For each directory, check if it's a Git repository
   - If it is a Git repository:
     - Check its status (uncommitted changes, unpushed commits)
     - Add it to the list of Git repositories with its status
     - Mark it and all its parent directories as processed
     - Skip further traversal into this directory

3. **Second Pass - Identify Non-Git Directories**:
   - Traverse the directory structure again, skipping already processed directories
   - For each unprocessed directory, check if any of its subdirectories contain a Git repository
   - If none of its subdirectories contain a Git repository, mark it as a top-level non-Git directory

4. **Result Generation**:
   - Compile the list of Git repositories with their status
   - Compile the list of top-level non-Git directories
   - Format and display the results

## Key Functions

### 1. `check_git_status(directory)`

This function checks if a directory is a Git repository and determines its status.

```bash
# Function to check if a directory is a Git repository and determine its status
check_git_status() {
  local dir="$1"
  local status=""

  # Check if it's a Git repository
  if [ ! -d "$dir/.git" ]; then
    return 1  # Not a Git repository
  fi

  # Check for uncommitted changes
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    status="UNCOMMITTED"
  else
    # Check for unpushed commits
    if git -C "$dir" rev-parse --abbrev-ref '@{u}' &>/dev/null; then
      if [ -n "$(git -C "$dir" log '@{u}..' --oneline)" ]; then
        status="UNPUSHED"
      fi
    else
      # No upstream branch configured
      if [ -n "$(git -C "$dir" log --oneline)" ]; then
        status="NO_REMOTE"
      fi
    fi
  fi

  # Output the status
  echo "$status"
  return 0  # It is a Git repository
}
```

### 2. `process_directory(directory, is_top_level)`

This function processes a directory, checking if it's a Git repository and recursively processing its subdirectories if it's not.

```bash
# Function to process a directory
process_directory() {
  local dir="$1"
  local is_top_level="$2"
  local found_git=false

  # Check if this directory is already processed
  if is_processed "$dir"; then
    return 0
  fi

  # Check if it's a Git repository
  local status=$(check_git_status "$dir")
  if [ $? -eq 0 ]; then
    # It's a Git repository
    found_git=true

    # Add to the list of Git repositories with its status
    if [ -n "$status" ]; then
      git_repos+=("$dir:$status")
    fi

    # Mark this directory as processed
    mark_processed "$dir"

    return 0
  fi

  # Not a Git repository, process subdirectories
  for subdir in "$dir"/*; do
    if [ -d "$subdir" ]; then
      process_directory "$subdir" false
      if [ $? -eq 0 ]; then
        found_git=true
      fi
    fi
  done

  # If this is a top-level directory and no Git repository was found,
  # add it to the list of non-Git directories
  if [ "$is_top_level" = true ] && [ "$found_git" = false ]; then
    non_git_dirs+=("$dir")
  fi

  return $found_git
}
```

### 3. `is_processed(directory)` and `mark_processed(directory)`

These functions check if a directory has been processed and mark a directory as processed.

```bash
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
```

### 4. `display_results()`

This function formats and displays the results.

```bash
# Function to display the results
display_results() {
  echo "=== Git Repositories with Uncommitted Changes ==="
  for repo in "${git_repos[@]}"; do
    IFS=':' read -r dir status <<< "$repo"
    if [ "$status" = "UNCOMMITTED" ]; then
      echo "[UNCOMMITTED] $dir"
    fi
  done

  echo -e "\n=== Git Repositories with Unpushed Commits ==="
  for repo in "${git_repos[@]}"; do
    IFS=':' read -r dir status <<< "$repo"
    if [ "$status" = "UNPUSHED" ]; then
      echo "[UNPUSHED] $dir"
    fi
  done

  echo -e "\n=== Git Repositories with No Remote ==="
  for repo in "${git_repos[@]}"; do
    IFS=':' read -r dir status <<< "$repo"
    if [ "$status" = "NO_REMOTE" ]; then
      echo "[NO_REMOTE] $dir"
    fi
  done

  echo -e "\n=== Top-Level Non-Git Directories ==="
  for dir in "${non_git_dirs[@]}"; do
    echo "[NON-GIT] $dir"
  done
}
```

## Implementation Steps

1. **Create the Script File**:
   - Create a new file named `check_git_status.sh`
   - Make it executable with `chmod +x check_git_status.sh`

2. **Add the Shebang and Script Header**:

   ```bash
   #!/bin/bash

   # Git Repository Status Checker
   # This script traverses a directory structure, identifies Git repositories,
   # and reports their status (uncommitted changes, unpushed commits).
   # It also identifies top-level directories that don't contain any Git repositories.

   # Usage: ./check_git_status.sh [root_directory]
   ```

3. **Implement Initialization and Argument Parsing**:

   ```bash
   # Default to current directory if no argument is provided
   ROOT_DIR="${1:-.}"

   # Check if the provided directory exists
   if [ ! -d "$ROOT_DIR" ]; then
     echo "Error: Directory '$ROOT_DIR' does not exist."
     exit 1
   fi

   # Convert to absolute path
   ROOT_DIR=$(realpath "$ROOT_DIR")

   # Initialize arrays to store results
   declare -a git_repos=()
   declare -a non_git_dirs=()
   declare -a processed_dirs=()
   ```

4. **Implement Helper Functions**:
   - Implement `check_git_status()`
   - Implement `is_processed()` and `mark_processed()`
   - Implement `process_directory()`
   - Implement `display_results()`

5. **Implement Main Logic**:

   ```bash
   # Main script logic
   echo "Scanning directory: $ROOT_DIR"
   echo "---"

   # Process the root directory
   for subdir in "$ROOT_DIR"/*; do
     if [ -d "$subdir" ]; then
       process_directory "$subdir" true
     fi
   done

   # Display the results
   display_results

   echo "---"
   echo "Scan complete."
   ```

6. **Add Error Handling and Edge Cases**:
   - Add checks for Git command availability
   - Add error handling for Git commands
   - Handle edge cases like empty repositories, detached HEAD, etc.

7. **Add Performance Optimizations**:
   - Use `find` for more efficient directory traversal
   - Optimize Git commands to minimize overhead
   - Implement aggressive pruning of known large directories:

     ```bash
     # Define directories to ignore (these can significantly slow down traversal)
     declare -a ignore_dirs=(
       "node_modules"  # Node.js dependencies (can be massive)
       ".venv" "venv" "env" ".env"  # Python virtual environments
       "target"  # Java/Maven build directory
       "build" "dist"  # Common build output directories
     )

     # Check if directory should be ignored before processing
     should_ignore() {
       local dir_name=$(basename "$1")
       for ignore_dir in "${ignore_dirs[@]}"; do
         if [ "$dir_name" = "$ignore_dir" ]; then
           return 0  # Should ignore
         fi
       done
       return 1  # Should not ignore
     }

     # Use in directory traversal
     for subdir in "$dir"/*; do
       if [ -d "$subdir" ] && ! should_ignore "$subdir"; then
         process_directory "$subdir"
       fi
     done
     ```

   - Consider using the `-prune` option with `find` to skip ignored directories entirely:

     ```bash
     # Example using find with -prune to skip node_modules and virtual environments
     find "$ROOT_DIR" \
       -name "node_modules" -prune -o \
       -name ".venv" -prune -o \
       -name "venv" -prune -o \
       -path "*/\.*" -prune -o \
       -type d -print
     ```

## Complete Script

The complete script implementation is provided in the `check_git_status.sh` file.

## Testing

To test the script:

1. Make it executable:

   ```bash
   chmod +x check_git_status.sh
   ```

2. Run it on a test directory:

   ```bash
   ./check_git_status.sh /path/to/test/directory
   ```

3. Verify the output:
   - Check that Git repositories with uncommitted changes are correctly identified
   - Check that Git repositories with unpushed commits are correctly identified
   - Check that top-level non-Git directories are correctly identified

## Troubleshooting

Common issues and their solutions:

1. **Permission Denied**: Ensure you have read permissions for all directories being scanned.
2. **Git Command Not Found**: Ensure Git is installed and in your PATH.
3. **Slow Performance**: For large directory structures, consider adding more aggressive pruning of directories that are unlikely to be Git repositories.
