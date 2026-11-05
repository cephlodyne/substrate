#!/bin/bash
set -euo pipefail
# ==============================================================================
# ZERO-TRUST SUBSTRATE TEARDOWN SCRIPT (macOS / Apple Silicon ARM64)
# Usage:
#   ./uninstall-arm.sh [OPTIONS]
#
# Options:
#   --keep-vms   Preserve ~/.colima and ~/.lima virtual machines & Docker volumes
#   --yes, -y    Skip confirmation prompt
# ==============================================================================

KEEP_VMS=0
SKIP_CONFIRM=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --keep-vms)
    KEEP_VMS=1
    shift
    ;;
  --yes | -y)
    SKIP_CONFIRM=1
    shift
    ;;
  *)
    echo "❌ Unknown flag: $1"
    echo "👉 Usage: ./uninstall-arm.sh [--keep-vms] [--yes|-y]"
    exit 1
    ;;
  esac
done

echo "🧹 Initiating Zero-Trust Substrate teardown..."
if [ "$KEEP_VMS" -eq 1 ]; then
  echo "ℹ️  --keep-vms enabled: Colima/Lima virtual machines and Docker volumes will be preserved."
else
  echo "⚠️  WARNING: This will permanently delete your Colima containers, volumes, fonts, and Neovim configurations."
fi

if [ "$SKIP_CONFIRM" -eq 0 ]; then
  read -r -p "Are you sure you want to proceed? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "🛑 Aborting uninstall."
    exit 0
  fi
fi

LOCAL_DIR="$HOME/.local"
BIN_DIR="$LOCAL_DIR/bin"
CACHE_DIR="$HOME/.cache/ide-bootstrap"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------------------
# 1. REMOVE GLOBAL GIT HOOKS (TruffleHog)
# ------------------------------------------------------------------------------
echo "🛡️  Removing TruffleHog global Git hooks..."
if [ -f "$SCRIPT_DIR/scripts/hog-uninstall.sh" ]; then
  bash "$SCRIPT_DIR/scripts/hog-uninstall.sh"
else
  git config --global --unset core.hooksPath 2>/dev/null || true
  rm -rf "$HOME/.git-hooks" "$HOME/.trufflehog-tmp"
fi

# ------------------------------------------------------------------------------
# 2. STOP RUNNING SERVICES (Colima / Lima)
# ------------------------------------------------------------------------------
if [ "$KEEP_VMS" -eq 0 ]; then
  echo "🛑 Stopping Colima and Lima virtual machines..."
  if command -v colima &>/dev/null; then
    colima stop --force 2>/dev/null || true
  fi
  if command -v limactl &>/dev/null; then
    limactl stop --force colima 2>/dev/null || true
  fi
fi

# ------------------------------------------------------------------------------
# 3. UNLOCK READ-ONLY DIRECTORIES & CLEAR CACHES
# ------------------------------------------------------------------------------
echo "🔓 Clearing Go module cache and unlocking read-only files..."
if [ -x "$LOCAL_DIR/go/bin/go" ]; then
  env GOPATH="$HOME/go" "$LOCAL_DIR/go/bin/go" clean -modcache 2>/dev/null || true
elif command -v go &>/dev/null; then
  go clean -modcache 2>/dev/null || true
fi

chmod -R u+rwX "$HOME/go" "$LOCAL_DIR/go" "$HOME/.config/nvim" "$HOME/.local/share/nvim" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. REMOVE APPLICATION DIRECTORIES, CACHES & LEDGERS
# ------------------------------------------------------------------------------
echo "🗑️  Removing extracted application directories and ledgers..."
rm -rf "$LOCAL_DIR/nvim-app"
rm -rf "$LOCAL_DIR/google-cloud-sdk"
rm -rf "$LOCAL_DIR/python"
rm -rf "$LOCAL_DIR/go"
rm -rf "$HOME/go"
rm -rf "$LOCAL_DIR/node"
rm -rf "$LOCAL_DIR/include/google"
rm -rf "$LOCAL_DIR/share/lima"
rm -rf "$CACHE_DIR"
rm -f "$LOCAL_DIR/.ide_receipts"
rm -f "$LOCAL_DIR/versions.env"

# ------------------------------------------------------------------------------
# 5. REMOVE CONFIGURATIONS, STATE & VIRTUAL MACHINES
# ------------------------------------------------------------------------------
echo "🗑️  Removing configuration files and editor state..."
rm -rf "$HOME/.config/nvim"
rm -rf "$HOME/.config/alacritty"
rm -rf "$HOME/.local/share/nvim"
rm -rf "$HOME/.local/state/nvim"
rm -rf "$HOME/.cache/nvim"

if [ "$KEEP_VMS" -eq 0 ]; then
  echo "🗑️  Removing Colima and Lima VM disks..."
  rm -rf "$HOME/.colima"
  rm -rf "$HOME/.lima"
fi

# ------------------------------------------------------------------------------
# 6. REMOVE ALACRITTY APP
# ------------------------------------------------------------------------------
if [[ -d "/Applications/Alacritty.app" ]]; then
  echo "🗑️  Removing Alacritty.app from System Applications (may prompt for password)..."
  rm -rf /Applications/Alacritty.app 2>/dev/null || sudo rm -rf /Applications/Alacritty.app
elif [[ -d "$HOME/Applications/Alacritty.app" ]]; then
  echo "🗑️  Removing Alacritty.app from User Applications..."
  rm -rf "$HOME/Applications/Alacritty.app"
fi

# ------------------------------------------------------------------------------
# 7. REMOVE FONTS
# ------------------------------------------------------------------------------
echo "🔤 Removing JetBrains Mono Nerd Font..."
rm -f "$HOME/Library/Fonts/JetBrainsMono"*.ttf
rm -f "$HOME/Library/Fonts/JetBrainsMono"*.otf 2>/dev/null || true

# ------------------------------------------------------------------------------
# 8. SURGICALLY REMOVE BINARIES & SYMLINKS
# ------------------------------------------------------------------------------
echo "🗑️  Cleaning up ~/.local/bin..."
BINARIES_TO_REMOVE=(
  "colima" "lima" "limactl" "docker" "docker-compose" "gcloud" "python3"
  "go" "node" "npm" "npx" "pnpm" "pnpx" "biome" "nvim" "rg" "fd"
  "lazygit" "tree-sitter" "tofu" "tofu-ls" "terraform" "terraform-ls"
  "gopls" "goimports" "trufflehog" "govulnfix" "protoc"
  "buf" "protoc-gen-go" "protoc-gen-connect-go" "protoc-gen-es" "ceph"
  "CHANGELOG.md" "LICENSE" "README.md"
)

if [ -d "$SCRIPT_DIR/scripts" ]; then
  for script in "$SCRIPT_DIR/scripts"/*.sh; do
    if [ -f "$script" ]; then
      BINARIES_TO_REMOVE+=("$(basename "$script" .sh)")
    fi
  done
fi

for bin in "${BINARIES_TO_REMOVE[@]}"; do
  rm -f "$BIN_DIR/$bin"
done

# ------------------------------------------------------------------------------
# 9. CLEAN UP ZSHRC
# ------------------------------------------------------------------------------
echo "📝 Cleaning up ~/.zshrc profile..."
ZSHRC="$HOME/.zshrc"
if [ -f "$ZSHRC" ]; then
  sed -i '' '/export PATH="$HOME\/.local\/bin:\$PATH"/d' "$ZSHRC"
  sed -i '' '/export PATH="$HOME\/.local\/node\/bin:\$PATH"/d' "$ZSHRC"
  sed -i '' '/export PNPM_HOME="$HOME\/.local\/node\/bin"/d' "$ZSHRC"
  sed -i '' '/export PATH="\$PATH:\$HOME\/go\/bin"/d' "$ZSHRC"
  sed -i '' '/export GOTOOLCHAIN=local/d' "$ZSHRC"
  sed -i '' '/export CLOUDSDK_PYTHON=/d' "$ZSHRC"
  sed -i '' '/export PYTHONDONTWRITEBYTECODE=1/d' "$ZSHRC"
fi

echo "=============================================================================="
echo "✅ Teardown complete! The Zero-Trust Substrate environment has been removed."
echo "=============================================================================="
