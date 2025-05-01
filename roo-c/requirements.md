# Git Repository Status Checker - Requirements

## Overview

This document outlines the requirements for a system that scans a directory structure to identify Git repositories and their status before backing up or formatting a computer.

## Functional Requirements

1. **Directory Traversal**
   - Start from a user-specified root folder
   - Recursively traverse the directory structure
   - Skip further traversal into directories that are identified as Git repositories
   - Continue traversal into non-Git directories

2. **Git Repository Identification**
   - Identify if a directory is a Git repository
   - For Git repositories, determine:
     - If there are uncommitted changes (modified, staged, or untracked files)
     - If there are committed changes that haven't been pushed to a remote repository
   - Do not traverse deeper into Git repositories

3. **Non-Git Directory Handling**
   - For directories that are not Git repositories, continue traversal
   - If no Git repository is found in any subfolder, identify the topmost non-Git folder

4. **Output Generation**
   - Generate an ordered list of directories that need attention:
     - Git repositories with uncommitted changes
     - Git repositories with unpushed commits
     - Top-level non-Git directories (that don't contain any Git repositories)

## Non-Functional Requirements

1. **Performance**
   - Efficiently handle large directory structures with many repositories
   - Minimize unnecessary file system operations

2. **Usability**
   - Clear, readable output that distinguishes between different types of issues
   - Ability to specify the root directory as a command-line argument
   - Helpful error messages for invalid inputs or permissions issues

3. **Compatibility**
   - Work on common Unix-like operating systems (Linux, macOS)
   - Minimal dependencies beyond standard shell utilities and Git

## Constraints

1. **Tools and Technologies**
   - Implementation using shell scripting (Bash/Zsh)
   - Reliance only on common Unix utilities and Git commands
   - No additional software dependencies required

## Success Criteria

The solution will be considered successful if it:

1. Correctly identifies all Git repositories in the specified directory structure
2. Accurately reports the status of each Git repository (uncommitted changes, unpushed commits)
3. Identifies top-level non-Git directories
4. Provides clear, actionable output that helps the user decide which directories need attention before formatting
