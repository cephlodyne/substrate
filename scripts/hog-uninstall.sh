#!/bin/bash
# Uninstaller for Global Git Hooks & TruffleHog Configuration

set -euo pipefail

HOOKS_DIR="$HOME/.git-hooks"

echo "🗑️  Uninstalling global TruffleHog Git hooks and configurations..."
echo "────────────────────────────────────────────────────────"

echo "➡️  Restoring Git configuration..."
if git config --global --get core.hooksPath >/dev/null 2>&1; then
  git config --global --unset core.hooksPath
  echo "   ✅ Global 'core.hooksPath' has been unset."
else
  echo "   ⚪ Global 'core.hooksPath' was not set. Skipping."
fi

echo "➡️  Removing hooks directory..."
if [ -d "$HOOKS_DIR" ]; then
  rm -rf "$HOOKS_DIR"
  echo "   ✅ Directory '$HOOKS_DIR' has been deleted."
else
  echo "   ⚪ Directory '$HOOKS_DIR' not found. Skipping."
fi

echo "────────────────────────────────────────────────────────"
echo "✅ Uninstallation complete. Git is now using default local hooks."
