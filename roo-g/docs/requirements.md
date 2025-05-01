# Requirements for Git Status Scanner Script

## 1. Functional Requirements

1.1. **Root Directory Specification:**
    - The script MUST accept an optional command-line argument specifying the root directory to start scanning from.
    - If no argument is provided, the script MUST default to the current working directory.

1.2. **Recursive Directory Traversal:**
    - The script MUST recursively scan all subdirectories starting from the specified root directory.
    - The script MUST NOT traverse into directories named `node_modules`, `venv`, `.venv`, `env`, `.env`, `target`, `build`, or `dist`.

1.3. **Git Repository Detection:**
    - For each directory encountered, the script MUST determine if it is part of a Git working tree.

1.4. **Git Status Check (if Git Repo):**
    - If a directory is identified as a Git repository:
        - The script MUST check for uncommitted local changes (modified, added, deleted, untracked files).
        - The script MUST check if there are local commits that have not been pushed to the remote tracking branch (`@{upstream}`).
        - The script MUST report the status (e.g., "Uncommitted changes", "Unpushed commits", "Synced", "No remote configured").
        - Traversal MUST NOT proceed deeper into subdirectories once a Git repository is identified.

1.5. **Non-Git Directory Handling:**
    - If a directory is NOT a Git repository, the script MUST continue traversing its subdirectories.
    - If a directory and all its subdirectories down to the leaf level do not contain a Git repository, the script MUST identify and report the path of this top-level non-Git directory encountered in that branch of the scan.

1.6. **Output:**
    - The script MUST output the results to the standard output (console).
    - The output MUST clearly list the paths of:
        - Git repositories with uncommitted changes.
        - Git repositories with unpushed commits.
        - Git repositories that are synced (optional, could be noisy).
        - Top-level directories that are not part of any Git repository.
    - Each reported path SHOULD have a clear status indicator.

## 2. Non-Functional Requirements

2.1. **Performance:** The script should be reasonably performant, though thoroughness is prioritized over speed. Avoid excessively slow operations.
2.2. **Clarity:** The output should be easy to read and understand.
2.3. **Error Handling:** Basic error handling for invalid paths or permissions issues is desirable.
2.4. **Platform:** Should ideally run on macOS and Linux environments (using standard Git and shell commands).
