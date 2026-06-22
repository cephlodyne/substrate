#!/bin/bash
set -euo pipefail
# ==============================================================================
# ZERO-TRUST IDE TEARDOWN SCRIPT (macOS / Apple Silicon ARM64)
# Completely removes all tools, caches, configs, ledgers, and VMs installed.
# ==============================================================================

echo "🧹 Initiating Zero-Trust IDE teardown..."
echo "⚠️  WARNING: This will permanently delete your Colima containers, volumes, fonts, and Neovim configurations."
read -p "Are you sure you want to proceed? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "🛑 Aborting uninstall."
  exit 0
fi

LOCAL_DIR="$HOME/.local"
BIN_DIR="$LOCAL_DIR/bin"
CACHE_DIR="$HOME/.cache/ide-bootstrap"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------------------
# 1. REMOVE GLOBAL GIT HOOKS (TruffleHog)
# ------------------------------------------------------------------------------
echo "🛡️  Removing TruffleHog global Git hooks..."
if [ -f "$SCRIPT_DIR/hog-uninstall.sh" ]; then
  bash "$SCRIPT_DIR/hog-uninstall.sh"
else
  git config --global --unset core.hooksPath 2>/dev/null || true
  rm -rf "$HOME/.git-hooks" "$HOME/.trufflehog-tmp"
fi

# ------------------------------------------------------------------------------
# 2. STOP RUNNING SERVICES (Colima / Lima)
# ------------------------------------------------------------------------------
echo "🛑 Stopping Colima and Lima virtual machines..."
if command -v colima &>/dev/null; then
  colima stop --force 2>/dev/null || true
fi
if command -v limactl &>/dev/null; then
  limactl stop --force colima 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 3. UNLOCK READ-ONLY DIRECTORIES & CLEAR CACHES
# ------------------------------------------------------------------------------
echo "🔓 Clearing Go module cache and unlocking read-only files..."

# 1. Let Go natively handle its own stubborn read-only module cache BEFORE we delete Go
if [ -x "$LOCAL_DIR/go/bin/go" ]; then
  env GOPATH="$HOME/go" "$LOCAL_DIR/go/bin/go" clean -modcache 2>/dev/null || true
elif command -v go &>/dev/null; then
  go clean -modcache 2>/dev/null || true
fi

# 2. Add 'X' to chmod (capital X grants execute/traversal rights to directories)
#    This acts as a failsafe for Go, and handles read-only Git objects in Neovim dirs.
chmod -R u+rwX "$HOME/go" "$LOCAL_DIR/go" "$HOME/.config/nvim" "$HOME/.local/share/nvim" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. REMOVE APPLICATION DIRECTORIES, CACHES & LEDGERS
# ------------------------------------------------------------------------------
echo "🗑️  Removing extracted application directories and ledgers..."
rm -rf "$LOCAL_DIR/nvim-app"
rm -rf "$LOCAL_DIR/google-cloud-sdk"
rm -rf "$LOCAL_DIR/go"
rm -rf "$HOME/go"        # Removes Go module cache and any user-installed Go binaries
rm -rf "$LOCAL_DIR/node" # This automatically removes global Biome & npm packages
rm -rf "$CACHE_DIR"
rm -f "$LOCAL_DIR/.ide_receipts" # Removes the smart-update ledger

# ------------------------------------------------------------------------------
# 5. REMOVE CONFIGURATIONS, STATE & VIRTUAL MACHINES
# ------------------------------------------------------------------------------
echo "🗑️  Removing configuration files, editor state, and VM data..."
rm -rf "$HOME/.config/nvim"
rm -rf "$HOME/.config/alacritty"
rm -rf "$HOME/.local/share/nvim"
rm -rf "$HOME/.local/state/nvim"
rm -rf "$HOME/.cache/nvim"
rm -rf "$HOME/.colima"
rm -rf "$HOME/.lima"

# ------------------------------------------------------------------------------
# 6. REMOVE ALACRITTY APP
# ------------------------------------------------------------------------------
if [[ -d "/Applications/Alacritty.app" ]]; then
  echo "🗑️  Removing Alacritty.app from System Applications (may prompt for password)..."
  sudo rm -rf "/Applications/Alacritty.app" 2>/dev/null || true
elif [[ -d "$HOME/Applications/Alacritty.app" ]]; then
  echo "🗑️  Removing Alacritty.app from User Applications..."
  rm -rf "$HOME/Applications/Alacritty.app"
fi

# ------------------------------------------------------------------------------
# 7. REMOVE CHROMIUM APP
# ------------------------------------------------------------------------------
if [[ -d "$HOME/Applications/Chromium.app" ]]; then
  echo "🗑️  Removing Chromium.app from User Applications..."
  rm -rf "$HOME/Applications/Chromium.app"
fi

# ------------------------------------------------------------------------------
# 8. REMOVE FONTS
# ------------------------------------------------------------------------------
echo "🔤 Removing JetBrains Mono Nerd Font..."
rm -f "$HOME/Library/Fonts/JetBrainsMono"*.ttf
rm -f "$HOME/Library/Fonts/JetBrainsMono"*.otf 2>/dev/null || true

# ------------------------------------------------------------------------------
# 9. SURGICALLY REMOVE BINARIES & SYMLINKS
# ------------------------------------------------------------------------------
echo "🗑️  Cleaning up ~/.local/bin..."
# We explicitly target only the binaries, wrappers, and symlinks our script created.
BINARIES_TO_REMOVE=(
  "colima" "lima" "limactl" "docker" "docker-compose" "gcloud"
  "go" "node" "npm" "npx" "pnpm" "pnpx" "nvim" "rg" "fd"
  "lazygit" "tree-sitter" "tofu" "tofu-ls" "terraform" "terraform-ls"
  "gopls" "goimports" "consolidate" "trufflehog"
)

# Dynamically find and remove any symlinks we created from the scripts directory
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -d "$ROOT_DIR/scripts" ]; then
  for script in "$ROOT_DIR/scripts"/*.sh; do
    if [ -f "$script" ]; then
      BINARIES_TO_REMOVE+=("$(basename "$script" .sh)")
    fi
  done
fi

for bin in "${BINARIES_TO_REMOVE[@]}"; do
  rm -f "$BIN_DIR/$bin"
done

# ------------------------------------------------------------------------------
# 10. CLEAN UP ZSHRC
# ------------------------------------------------------------------------------
echo "📝 Cleaning up ~/.zshrc profile..."
ZSHRC="$HOME/.zshrc"
if [ -f "$ZSHRC" ]; then
  # Use macOS compatible 'sed' (-i '') to delete the specific lines we injected
  sed -i '' '/export PATH="$HOME\/.local\/bin:$PATH"/d' "$ZSHRC"
  sed -i '' '/export PATH="$HOME\/.local\/node\/bin:$PATH"/d' "$ZSHRC"
  sed -i '' '/export PATH="$PATH:$HOME\/go\/bin"/d' "$ZSHRC"
  sed -i '' '/export DOCKER_HOST="unix:\/\/$HOME\/.colima\/default\/docker.sock"/d' "$ZSHRC"
fi

echo "=============================================================================="
echo "✅ Teardown complete! The Zero-Trust IDE has been completely removed."
echo "👉 Note: Run 'source ~/.zshrc' or restart your terminal to clear the old environment variables."
echo "=============================================================================="
