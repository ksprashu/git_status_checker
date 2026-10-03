#!/bin/bash

echo "Applying chmod +x to specific .sh files..."

chmod +x ./one-shot/check_git_repos_c.sh
echo "Applied chmod +x to ./one-shot/check_git_repos_c.sh"

chmod +x ./one-shot/check_git_status_o.sh
echo "Applied chmod +x to ./one-shot/check_git_status_o.sh"

chmod +x ./one-shot/scan_git_repos_gf.sh
echo "Applied chmod +x to ./one-shot/scan_git_repos_gf.sh"

chmod +x ./one-shot/scan_git_repos_gp.sh
echo "Applied chmod +x to ./one-shot/scan_git_repos_gp.sh"

chmod +x ./roo-c/check_git_status.sh
echo "Applied chmod +x to ./roo-c/check_git_status.sh"

chmod +x ./roo-g/scan_git_repos.sh
echo "Applied chmod +x to ./roo-g/scan_git_repos.sh"

echo "Finished applying chmod +x."
