# Git Status Checker

This repository contains various shell scripts designed to scan directories for Git repositories and report their status. The scripts help identify repositories that have uncommitted changes, unpushed commits, or other states that might require attention before backing up or formatting a computer.

## Repository Structure

- **roo-c/** - Contains a Git status checker implementation with detailed documentation
  - `check_git_status.sh` - The main script
  - Documentation: `requirements.md`, `design.md`, `implementation.md`

- **roo-g/** - Contains another implementation of a Git repository scanner
  - `scan_git_repos.sh` - The main script
  - Documentation: `docs/requirements.md`, `docs/design.md`, `docs/implementation.md`

- **one-shot/** - Contains various one-shot implementations of Git status checking scripts
  - `check_git_repos_c.sh`
  - `check_git_status_o.sh`
  - `scan_git_repos_gf.sh`
  - `scan_git_repos_gp.sh`

## Usage

### Using the roo-c implementation:

```bash
# Navigate to the roo-c directory
cd roo-c

# Make the script executable (if not already)
chmod +x check_git_status.sh

# Run the script with a target directory
./check_git_status.sh /path/to/your/projects

# Run with debug output
./check_git_status.sh /path/to/your/projects --debug

# Show help information
./check_git_status.sh --help
```

### Using the roo-g implementation:

```bash
# Navigate to the roo-g directory
cd roo-g

# Make the script executable (if not already)
chmod +x scan_git_repos.sh

# Run the script with a target directory
./scan_git_repos.sh /path/to/your/projects
```

### Using the one-shot implementations:

```bash
# Navigate to the one-shot directory
cd one-shot

# Make the script executable (if not already)
chmod +x check_git_repos_c.sh

# Run the script with a target directory
./check_git_repos_c.sh /path/to/your/projects
```

Replace `check_git_repos_c.sh` with any of the other scripts in the one-shot directory.

## Features

These scripts provide the following features:

- Recursive scanning of directories for Git repositories
- Detection of various Git repository states:
  - Uncommitted changes (modified, staged, or untracked files)
  - Unpushed commits
  - Repositories without remote tracking branches
- Identification of top-level directories that don't contain any Git repositories
- Color-coded output for better readability
- Performance optimizations to handle large directory structures efficiently
