#!/bin/bash
#
# Uninstaller for Global Git Hooks & TruffleHog Configuration
# -----------------------------------------------------------
# This script completely reverses the secret scanning setup:
# 1. Unsets the global Git 'core.hooksPath' configuration.
# 2. Deletes the global hooks directory (~/.git-hooks).
# 3. Cleans up the Colima-compatible temporary directory (~/.trufflehog-tmp).

set -euo pipefail

# --- Configuration ---
HOOKS_DIR="$HOME/.git-hooks"
TEMP_DIR_BASE="$HOME/.trufflehog-tmp"

echo "🗑️  Uninstalling global TruffleHog Git hooks and configurations..."
echo "────────────────────────────────────────────────────────"

# --- Step 1: Unset the global Git hooks path ---
echo "➡️  Restoring Git configuration..."

if git config --global --get core.hooksPath >/dev/null 2>&1; then
  git config --global --unset core.hooksPath
  echo "   ✅ Global 'core.hooksPath' has been unset."
else
  echo "   ⚪ Global 'core.hooksPath' was not set. Skipping."
fi

# --- Step 2: Remove the global hooks directory ---
echo "➡️  Removing hooks directory..."

if [ -d "$HOOKS_DIR" ]; then
  # Removes pre-commit, commit-msg, and exclude-paths.txt
  rm -rf "$HOOKS_DIR"
  echo "   ✅ Directory '$HOOKS_DIR' has been deleted."
else
  echo "   ⚪ Directory '$HOOKS_DIR' not found. Skipping."
fi

# --- Step 3: Clean up TruffleHog temporary working directory ---
echo "➡️  Cleaning up temporary workspace..."

if [ -d "$TEMP_DIR_BASE" ]; then
  # Cleans up the directory used to pass files safely to Colima/Docker
  rm -rf "$TEMP_DIR_BASE"
  echo "   ✅ Staging directory '$TEMP_DIR_BASE' has been deleted."
else
  echo "   ⚪ Staging directory '$TEMP_DIR_BASE' not found. Skipping."
fi

# --- Finalize ---
echo "────────────────────────────────────────────────────────"
echo "✅ Uninstallation complete. Git is now using default local hooks."

