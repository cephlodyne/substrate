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

# Wrapper for GitHub API calls with a 1-hour ephemeral local cache
github_curl() {
  local full_url="$1"

  # Create a safe, unique filename from the URL for the cache
  local cache_key
  cache_key=$(echo "$full_url" | sed 's/[^a-zA-Z0-9]/_/g')
  local cache_file="/tmp/substrate_cache_${cache_key}.json"

  # If cache exists, check its age
  if [ -f "$cache_file" ]; then
    local current_time
    current_time=$(date +%s)

    local file_time
    # macOS BSD stat command to get file modification time in seconds
    file_time=$(stat -f "%m" "$cache_file" 2>/dev/null)

    if [ -n "$file_time" ]; then
      local age_seconds=$((current_time - file_time))
      # If the cache is less than 60 minutes (3600 seconds) old, use it
      if [ "$age_seconds" -lt 3600 ]; then
        cat "$cache_file"
        return
      fi
    fi
  fi

  # Cache is missing or stale. Fetch fresh data from GitHub.
  local response
  response=$(curl --proto '=https' --tlsv1.2 -sSL "$full_url" || true)

  # Only write to the cache if GitHub gave us a valid response (not a rate limit error)
  if echo "$response" | grep -q '"tag_name"'; then
    echo "$response" >"$cache_file"
  fi

  echo "$response"
}

# Calculate human-readable age from ISO 8601 timestamp and colorize it
format_age() {
  local release_date_iso="$1"
  if [ -z "$release_date_iso" ]; then
    echo ""
    return
  fi

  local release_epoch
  # macOS (BSD date) parsing
  if ! release_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$release_date_iso" "+%s" 2>/dev/null); then
    echo ""
    return
  fi

  local current_epoch
  current_epoch=$(date "+%s")

  local diff_seconds=$((current_epoch - release_epoch))
  local diff_days=$((diff_seconds / 86400))

  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local NC='\033[0m' # No Color
  local color_code=""

  if [ "$diff_seconds" -lt 86400 ]; then
    color_code="${RED}"
  else
    color_code="${GREEN}"
  fi
  if [ "$diff_days" -eq 0 ]; then
    echo -e "${color_code}(Released today)${NC}"
  elif [ "$diff_days" -lt 30 ]; then
    local day_str="days"
    [ "$diff_days" -eq 1 ] && day_str="day"
    echo -e "${color_code}(Released $diff_days $day_str ago)${NC}"
  elif [ "$diff_days" -lt 365 ]; then
    local months=$((diff_days / 30))
    local month_str="months"
    [ "$months" -eq 1 ] && month_str="month"
    echo -e "${color_code}(Released $months $month_str ago)${NC}"
  else
    local years=$((diff_days / 365))
    local year_str="years"
    [ "$years" -eq 1 ] && year_str="year"
    echo -e "${color_code}(Released $years $year_str ago)${NC}"
  fi
}

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

  # Fetch the JSON response via our caching wrapper
  local api_response
  api_response=$(github_curl "https://api.github.com/repos/$repo/releases/latest")

  # Extract tag and date (Immune to minified JSON)
  local latest_version
  latest_version=$(echo "$api_response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/"tag_name": *"([^"]+)"/\1/' || true)

  local published_at
  published_at=$(echo "$api_response" | grep -o '"published_at": *"[^"]*"' | head -n 1 | sed -E 's/"published_at": *"([^"]+)"/\1/' || true)

  local age_str=""
  if [ -n "$published_at" ]; then
    age_str=$(format_age "$published_at")
  fi

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version from GitHub."
    return
  fi

  # ✨ SMART ALIGNMENT: If local version lacks a 'v' but GitHub has one, strip the 'v' from GitHub's tag
  if [[ ! "$current_version" == v* ]] && [[ "$latest_version" == v* ]]; then
    latest_version="${latest_version#v}"
  fi

  if [ "$current_version" != "$latest_version" ]; then
    echo -e "🚨 UPDATE AVAILABLE: $tool_name (Current: $current_version -> Latest: $latest_version) $age_str"
    if [[ ! "$latest_version" == v* ]]; then
      echo "   👉 https://github.com/$repo/releases/tag/v$latest_version"
    else
      echo "   👉 https://github.com/$repo/releases/tag/$latest_version"
    fi
  else
    echo -e "✅ $tool_name is up-to-date ($current_version) $age_str"
  fi
}

# Check basic custom JSON endpoints (Go, Node)
check_custom_api() {
  local tool_name="$1"
  local latest_version="$2"
  local age_str="${3:-}"
  local current_version

  current_version=$(get_local_version "$tool_name")

  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Not found in receipts."
    return
  fi

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  if [ "$current_version" != "$latest_version" ]; then
    echo -e "🚨 UPDATE AVAILABLE: $tool_name (Current: $current_version -> Latest: $latest_version) $age_str"
  else
    echo -e "✅ $tool_name is up-to-date ($current_version) $age_str"
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

  # Split the composite string
  local current_pnpm="${receipt_val%_*}"
  local current_biome="${receipt_val#*_}"

  local NPM_BIN="$HOME/.local/bin/npm"
  if [ ! -x "$NPM_BIN" ]; then
    NPM_BIN="npm"
  fi

  local latest_pnpm
  latest_pnpm=$("$NPM_BIN" view pnpm version 2>/dev/null || true)

  local pnpm_time
  pnpm_time=$("$NPM_BIN" view pnpm time --json 2>/dev/null | grep "\"$latest_pnpm\":" | head -n 1 | cut -d'"' -f4 | cut -c1-19 || true)

  local pnpm_age=""
  if [ -n "$pnpm_time" ]; then
    pnpm_age=$(format_age "${pnpm_time}Z")
  fi

  local latest_biome
  latest_biome=$("$NPM_BIN" view @biomejs/biome version 2>/dev/null || true)

  local biome_time
  biome_time=$("$NPM_BIN" view @biomejs/biome time --json 2>/dev/null | grep "\"$latest_biome\":" | head -n 1 | cut -d'"' -f4 | cut -c1-19 || true)

  local biome_age=""
  if [ -n "$biome_time" ]; then
    biome_age=$(format_age "${biome_time}Z")
  fi

  if [ -n "$latest_pnpm" ]; then
    if [ "$current_pnpm" != "$latest_pnpm" ]; then
      echo -e "🚨 UPDATE AVAILABLE: pnpm (Current: $current_pnpm -> Latest: $latest_pnpm) $pnpm_age"
    else
      echo -e "✅ pnpm is up-to-date ($current_pnpm) $pnpm_age"
    fi
  else
    echo "⚠️  pnpm: Failed to fetch latest version."
  fi

  if [ -n "$latest_biome" ]; then
    if [ "$current_biome" != "$latest_biome" ]; then
      echo -e "🚨 UPDATE AVAILABLE: biome (Current: $current_biome -> Latest: $latest_biome) $biome_age"
    else
      echo -e "✅ biome is up-to-date ($current_biome) $biome_age"
    fi
  else
    echo "⚠️  biome: Failed to fetch latest version."
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
    grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "([^"]+)"/\1/' || true)

  if [ -z "$latest_version" ]; then
    echo "⚠️  Gcloud: Failed to fetch latest version."
    return
  fi

  if [ "$current_version" != "$latest_version" ]; then
    echo -e "🚨 UPDATE AVAILABLE: Gcloud (Current: $current_version -> Latest: $latest_version)"
    echo "   👉 https://cloud.google.com/sdk/docs/downloads-versioned-archives"
  else
    echo -e "✅ Gcloud is up-to-date ($current_version)"
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

  local tofu_response
  tofu_response=$(github_curl "https://api.github.com/repos/opentofu/opentofu/releases/latest")
  local latest_tofu=$(echo "$tofu_response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/"tag_name": *"v?([^"]+)"/\1/' || true)
  local tofu_date=$(echo "$tofu_response" | grep -o '"published_at": *"[^"]*"' | head -n 1 | sed -E 's/"published_at": *"([^"]+)"/\1/' || true)
  local tofu_age=$(format_age "$tofu_date")

  local tofuls_response
  tofuls_response=$(github_curl "https://api.github.com/repos/opentofu/tofu-ls/releases/latest")
  local latest_tofuls=$(echo "$tofuls_response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/"tag_name": *"v?([^"]+)"/\1/' || true)
  local tofuls_date=$(echo "$tofuls_response" | grep -o '"published_at": *"[^"]*"' | head -n 1 | sed -E 's/"published_at": *"([^"]+)"/\1/' || true)
  local tofuls_age=$(format_age "$tofuls_date")

  if [ -n "$latest_tofu" ]; then
    if [ "$current_tofu" != "$latest_tofu" ]; then
      echo -e "🚨 UPDATE AVAILABLE: OpenTofu (Current: $current_tofu -> Latest: $latest_tofu) $tofu_age"
      echo "   👉 https://github.com/opentofu/opentofu/releases/tag/v$latest_tofu"
    else
      echo -e "✅ OpenTofu is up-to-date ($current_tofu) $tofu_age"
    fi
  else
    echo "⚠️  OpenTofu: Failed to fetch latest version."
  fi

  if [ -n "$latest_tofuls" ]; then
    if [ "$current_tofuls" != "$latest_tofuls" ]; then
      echo -e "🚨 UPDATE AVAILABLE: OpenTofu LS (Current: $current_tofuls -> Latest: $latest_tofuls) $tofuls_age"
      echo "   👉 https://github.com/opentofu/tofu-ls/releases/tag/v$latest_tofuls"
    else
      echo -e "✅ OpenTofu LS is up-to-date ($current_tofuls) $tofuls_age"
    fi
  else
    echo "⚠️  OpenTofu LS: Failed to fetch latest version."
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

  local api_response
  api_response=$(curl --proto '=https' --tlsv1.2 -sSL "https://proxy.golang.org/${module_path}/@latest" || true)

  local latest_version
  latest_version=$(echo "$api_response" | grep -o '"Version":"[^"]*"' | sed -E 's/"Version":"([^"]+)"/\1/' || true)

  local pkg_time
  pkg_time=$(echo "$api_response" | grep -o '"Time":"[^"]*"' | sed -E 's/"Time":"([^"]+)"/\1/' || true)

  local pkg_age=""
  if [ -n "$pkg_time" ]; then
    pkg_age=$(format_age "$pkg_time")
  fi

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  if [ "$current_version" != "$latest_version" ]; then
    echo -e "🚨 UPDATE AVAILABLE: $tool_name (Current: $current_version -> Latest: $latest_version) $pkg_age"
  else
    echo -e "✅ $tool_name is up-to-date ($current_version) $pkg_age"
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
check_github "JetBrainsMono" "ryanoasis/nerd-fonts"
check_github "Neovim" "neovim/neovim"

echo -e "\n--- Languages & Environments ---"
LATEST_GO=$(curl --proto '=https' --tlsv1.2 -sSL "https://go.dev/dl/?mode=json" | grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "go([^"]+)"/\1/' || true)
check_custom_api "Go" "$LATEST_GO"

NODE_INFO=$(curl --proto '=https' --tlsv1.2 -sSL "https://nodejs.org/dist/index.tab" | awk 'NR>1 && $10!="-" && !found {print $1, $2; found=1}' || true)
LATEST_NODE=$(echo "$NODE_INFO" | awk '{print $1}' || true)
NODE_DATE=$(echo "$NODE_INFO" | awk '{print $2}' || true)
NODE_AGE=""
if [ -n "$NODE_DATE" ]; then
  NODE_AGE=$(format_age "${NODE_DATE}T00:00:00Z")
fi

check_custom_api "Node" "$LATEST_NODE" "$NODE_AGE"

echo -e "\n--- CLI Utilities & Packages ---"
check_github "Ripgrep" "BurntSushi/ripgrep"
check_github "fd" "sharkdp/fd"
check_github "Protoc" "protocolbuffers/protobuf"
check_github "Lazygit" "jesseduffield/lazygit"
check_github "Treesitter" "tree-sitter/tree-sitter"
check_github "TruffleHog" "trufflesecurity/trufflehog"
check_npm_packages
check_go_pkg "Gopls" "golang.org/x/tools/gopls"
check_go_pkg "Goimports" "golang.org/x/tools"

echo "----------------------------------------------------"
echo "🏁 Update check complete."
