#!/bin/bash
set -euo pipefail

RECEIPTS_FILE="$HOME/.local/.ide_receipts"

echo "🔍 Reading local state from $RECEIPTS_FILE..."
echo "----------------------------------------------------"

if [ ! -f "$RECEIPTS_FILE" ]; then
  echo "❌ No receipts file found at $RECEIPTS_FILE. Have you run the bootstrap script yet?"
  exit 1
fi

# ==============================================================================
# 1. HELPER FUNCTIONS
# ==============================================================================

# Extract the currently installed version from the ledger and sanitize it
get_local_version() {
  local tool_name="$1"
  # Grabs the right side of the '=', then deletes everything EXCEPT letters, numbers, dots, hyphens, and underscores
  grep "^${tool_name}=" "$RECEIPTS_FILE" | head -n 1 | cut -d'=' -f2 | tr -cd '[:alnum:]_.-' || true
}

# Check standard GitHub repositories
check_github() {
  local tool_name="$1"
  local repo="$2"

  local current_version
  current_version=$(get_local_version "$tool_name")

  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Not found in receipts (Not installed)."
    return
  fi

  # Fetch the latest release tag from GitHub API
  local latest_version
  latest_version=$(curl --proto '=https' --tlsv1.2 -sSL "https://api.github.com/repos/$repo/releases/latest" |
    grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version from GitHub."
    return
  fi

  if [ "$current_version" != "$latest_version" ]; then
    echo "🚨 UPDATE AVAILABLE: $tool_name (Current: $current_version -> Latest: $latest_version)"
    echo "   👉 https://github.com/$repo/releases/tag/$latest_version"
  else
    echo "✅ $tool_name is up-to-date ($current_version)"
  fi
}

# Check basic custom JSON endpoints (Go, Node)
check_custom_api() {
  local tool_name="$1"
  local latest_version="$2"
  local current_version

  current_version=$(get_local_version "$tool_name")

  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Not found in receipts."
    return
  fi

  if [ "$current_version" != "$latest_version" ]; then
    echo "🚨 UPDATE AVAILABLE: $tool_name (Current: $current_version -> Latest: $latest_version)"
  else
    echo "✅ $tool_name is up-to-date ($current_version)"
  fi
}

# Check NPM Registry for composite pnpm & biome receipt
check_npm_packages() {
  local receipt_val
  receipt_val=$(get_local_version "NPM_Packages")

  if [ -z "$receipt_val" ]; then
    echo "⏭️  NPM_Packages: Not found in receipts."
    return
  fi

  # Split the composite string (e.g., 11.1.2_2.4.15)
  local current_pnpm="${receipt_val%_*}"
  local current_biome="${receipt_val#*_}"

  # Fetch from NPM registry
  local latest_pnpm
  latest_pnpm=$(curl --proto '=https' --tlsv1.2 -sSL "https://registry.npmjs.org/pnpm/latest" |
    grep -o '"version":"[^"]*"' | head -n 1 | sed -E 's/"version":"([^"]+)"/\1/')

  local latest_biome
  latest_biome=$(curl --proto '=https' --tlsv1.2 -sSL "https://registry.npmjs.org/@biomejs/biome/latest" |
    grep -o '"version":"[^"]*"' | head -n 1 | sed -E 's/"version":"([^"]+)"/\1/')

  if [ "$current_pnpm" != "$latest_pnpm" ]; then
    echo "🚨 UPDATE AVAILABLE: pnpm (Current: $current_pnpm -> Latest: $latest_pnpm)"
  else
    echo "✅ pnpm is up-to-date ($current_pnpm)"
  fi

  if [ "$current_biome" != "$latest_biome" ]; then
    echo "🚨 UPDATE AVAILABLE: biome (Current: $current_biome -> Latest: $latest_biome)"
  else
    echo "✅ biome is up-to-date ($current_biome)"
  fi
}

# Check Google Cloud SDK manifest
check_gcloud() {
  local current_version
  current_version=$(get_local_version "Gcloud")

  if [ -z "$current_version" ]; then
    echo "⏭️  Gcloud: Not found in receipts."
    return
  fi

  local latest_version
  latest_version=$(curl --proto '=https' --tlsv1.2 -sSL "https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json" |
    grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "([^"]+)"/\1/')

  if [ "$current_version" != "$latest_version" ]; then
    echo "🚨 UPDATE AVAILABLE: Gcloud (Current: $current_version -> Latest: $latest_version)"
    echo "   👉 https://cloud.google.com/sdk/docs/downloads-versioned-archives"
  else
    echo "✅ Gcloud is up-to-date ($current_version)"
  fi
}

# Check OpenTofu & OpenTofu LS composite receipt
check_opentofu() {
  local receipt_val
  receipt_val=$(get_local_version "OpenTofu")

  if [ -z "$receipt_val" ]; then
    echo "⏭️  OpenTofu: Not found in receipts."
    return
  fi

  local current_tofu="${receipt_val%_*}"
  local current_tofuls="${receipt_val#*_}"

  # Fetch from GitHub (stripping 'v' from the tag name because your variables omit it)
  local latest_tofu
  latest_tofu=$(curl --proto '=https' --tlsv1.2 -sSL "https://api.github.com/repos/opentofu/opentofu/releases/latest" |
    grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')

  local latest_tofuls
  latest_tofuls=$(curl --proto '=https' --tlsv1.2 -sSL "https://api.github.com/repos/opentofu/tofu-ls/releases/latest" |
    grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')

  if [ "$current_tofu" != "$latest_tofu" ]; then
    echo "🚨 UPDATE AVAILABLE: OpenTofu (Current: $current_tofu -> Latest: $latest_tofu)"
    echo "   👉 https://github.com/opentofu/opentofu/releases/tag/v$latest_tofu"
  else
    echo "✅ OpenTofu is up-to-date ($current_tofu)"
  fi

  if [ "$current_tofuls" != "$latest_tofuls" ]; then
    echo "🚨 UPDATE AVAILABLE: OpenTofu LS (Current: $current_tofuls -> Latest: $latest_tofuls)"
    echo "   👉 https://github.com/opentofu/tofu-ls/releases/tag/v$latest_tofuls"
  else
    echo "✅ OpenTofu LS is up-to-date ($current_tofuls)"
  fi
}

# Check Go module proxy
check_go_pkg() {
  local tool_name="$1"
  local module_path="$2"
  local current_version

  current_version=$(get_local_version "$tool_name")

  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Not found in receipts."
    return
  fi

  local latest_version
  latest_version=$(curl --proto '=https' --tlsv1.2 -sSL "https://proxy.golang.org/${module_path}/@latest" |
    grep -o '"Version":"[^"]*"' | sed -E 's/"Version":"([^"]+)"/\1/')

  if [ "$current_version" != "$latest_version" ]; then
    echo "🚨 UPDATE AVAILABLE: $tool_name (Current: $current_version -> Latest: $latest_version)"
  else
    echo "✅ $tool_name is up-to-date ($current_version)"
  fi
}

# ==============================================================================
# 2. EXECUTE CHECKS
# ==============================================================================

echo "--- Virtualization & Infrastructure ---"
check_github "Colima" "abiosoft/colima"
check_github "Lima" "lima-vm/lima"
check_gcloud
check_opentofu

echo -e "\n--- Core Applications ---"
check_github "Alacritty" "alacritty/alacritty"
check_github "Chromium" "ungoogled-software/ungoogled-chromium-macos"
check_github "JetBrainsMono" "ryanoasis/nerd-fonts"
check_github "Neovim" "neovim/neovim"

echo -e "\n--- Languages & Environments ---"
LATEST_GO=$(curl --proto '=https' --tlsv1.2 -sSL "https://go.dev/dl/?mode=json" | grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "go([^"]+)"/\1/')
check_custom_api "Go" "$LATEST_GO"

LATEST_NODE=$(curl --proto '=https' --tlsv1.2 -sSL "https://nodejs.org/dist/index.json" | grep -o '"version":"[^"]*"' | head -n 1 | sed -E 's/"version":"([^"]+)"/\1/')
check_custom_api "Node" "$LATEST_NODE"

echo -e "\n--- CLI Utilities & Packages ---"
check_github "Ripgrep" "BurntSushi/ripgrep"
check_github "fd" "sharkdp/fd"
check_github "Lazygit" "jesseduffield/lazygit"
check_github "Treesitter" "tree-sitter/tree-sitter"
check_github "TruffleHog" "trufflesecurity/trufflehog"
check_npm_packages
check_go_pkg "Gopls" "golang.org/x/tools/gopls"
check_go_pkg "Goimports" "golang.org/x/tools"

echo "----------------------------------------------------"
echo "🏁 Update check complete."
