#!/bin/bash
set -euo pipefail

# ==============================================================================
# 0. CONFIGURATION & FLAGS
# ==============================================================================

RECEIPTS_FILE="$HOME/.local/.ide_receipts"

DO_HASH=0
# POSIX-safe argument parsing (avoids macOS Bash 3.2 syntax errors)
for arg in "$@"; do
  if [ "$arg" = "--hash" ] || [ "$arg" = "-h" ]; then
    DO_HASH=1
    echo "⚠️  HASH MODE ENABLED: Will prompt to download artifacts and compute new SHAs."
  fi
done

echo "🔍 Reading local state from $RECEIPTS_FILE..."
echo "----------------------------------------------------"

if [ ! -f "$RECEIPTS_FILE" ]; then
  echo "❌ No receipts file found at $RECEIPTS_FILE. Have you run the bootstrap script yet?"
  exit 1
fi

# Global arrays to hold pending updates for the interactive menu
PENDING_TOOLS=()
PENDING_URLS=()

# ==============================================================================
# 1. HELPER FUNCTIONS
# ==============================================================================

queue_for_hash() {
  local tool="$1"
  local url="$2"
  PENDING_TOOLS+=("$tool")
  PENDING_URLS+=("$url")
}

prefetch_sha() {
  local url="$1"
  local YELLOW='\033[0;33m'
  local GREEN='\033[0;32m'
  local RED='\033[0;31m'
  local NC='\033[0m'

  echo -n "   📥 Fetching artifact to compute SHA... "
  local tmp_file
  tmp_file=$(mktemp)

  if curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp_file" "$url"; then
    local sha
    sha=$(shasum -a 256 "$tmp_file" | awk '{print $1}')
    echo -e "${GREEN}Done!${NC}"
    echo -e "   🔐 New SHA256: ${YELLOW}${sha}${NC}"
  else
    echo -e "${RED}Download failed.${NC} (Check if the URL template matched the release asset)"
  fi

  rm -f "$tmp_file"
}

github_curl() {
  local full_url="$1"
  local cache_key=$(echo "$full_url" | sed 's/[^a-zA-Z0-9]/_/g')
  local cache_file="/tmp/substrate_cache_${cache_key}.json"

  if [ -f "$cache_file" ]; then
    local current_time=$(date +%s)
    local file_time=$(stat -f "%m" "$cache_file" 2>/dev/null)
    if [ -n "$file_time" ]; then
      local age_seconds=$((current_time - file_time))
      if [ "$age_seconds" -lt 3600 ]; then
        cat "$cache_file"
        return
      fi
    fi
  fi

  local response=$(curl --proto '=https' --tlsv1.2 -sSL "$full_url" || true)
  if echo "$response" | grep -q '"tag_name"'; then
    echo "$response" >"$cache_file"
  fi
  echo "$response"
}

get_local_version() {
  local tool_name="$1"
  grep "^${tool_name}=" "$RECEIPTS_FILE" | head -n 1 | cut -d'=' -f2 | tr -cd '[:alnum:]_.-' || true
}

evaluate_version() {
  local tool_name="$1"
  local current="$2"
  local latest="$3"
  local date_iso="${4:-}"
  local link="${5:-}"

  local age_seconds=99999999
  local age_str=""

  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  local NC='\033[0m'

  if [ -n "$date_iso" ]; then
    local release_epoch
    if release_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date_iso" "+%s" 2>/dev/null); then
      local current_epoch=$(date "+%s")
      age_seconds=$((current_epoch - release_epoch))
      local diff_days=$((age_seconds / 86400))

      local color_code="${GREEN}"
      if [ "$age_seconds" -lt 86400 ]; then color_code="${YELLOW}"; fi

      if [ "$diff_days" -eq 0 ]; then
        age_str="${color_code}(Released today)${NC}"
      elif [ "$diff_days" -lt 30 ]; then
        local day_str="days"
        if [ "$diff_days" -eq 1 ]; then day_str="day"; fi
        age_str="${color_code}(Released $diff_days $day_str ago)${NC}"
      elif [ "$diff_days" -lt 365 ]; then
        local months=$((diff_days / 30))
        local month_str="months"
        if [ "$months" -eq 1 ]; then month_str="month"; fi
        age_str="${color_code}(Released $months $month_str ago)${NC}"
      else
        local years=$((diff_days / 365))
        local year_str="years"
        if [ "$years" -eq 1 ]; then year_str="year"; fi
        age_str="${color_code}(Released $years $year_str ago)${NC}"
      fi
    fi
  fi

  if [ -n "$age_str" ]; then age_str=" $age_str"; fi

  if [ "$current" != "$latest" ]; then
    if [ "$age_seconds" -lt 86400 ]; then
      echo -e "⏳ COOLING OFF: $tool_name (Current: $current -> Latest: $latest)$age_str"
      echo -e "   ⏸️  Waiting 24 hours for stability before upgrading."
    else
      echo -e "🚨 UPDATE AVAILABLE: $tool_name (Current: $current -> Latest: $latest)$age_str"
      if [ -n "$link" ]; then echo -e "   👉 $link"; fi
    fi
  else
    echo -e "✅ $tool_name is up-to-date ($current)$age_str"
  fi
}

# ==============================================================================
# 2. COMPONENT CHECKERS
# ==============================================================================

check_github() {
  local tool_name="$1"
  local repo="$2"
  local url_template="${3:-}"

  local current_version=$(get_local_version "$tool_name")
  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Not found in receipts."
    return
  fi

  local api_response=$(github_curl "https://api.github.com/repos/$repo/releases/latest")
  local latest_version=$(echo "$api_response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/"tag_name": *"([^"]+)"/\1/' || true)
  local published_at=$(echo "$api_response" | grep -o '"published_at": *"[^"]*"' | head -n 1 | sed -E 's/"published_at": *"([^"]+)"/\1/' || true)

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  # Bash 3.2 safe pattern matching workaround
  local strip_v=0
  case "$current_version" in v*) ;; *) strip_v=1 ;; esac
  case "$latest_version" in v*) if [ "$strip_v" -eq 1 ]; then latest_version="${latest_version#v}"; fi ;; esac

  local link="https://github.com/$repo/releases/tag/$latest_version"
  case "$latest_version" in v*) ;; *) link="https://github.com/$repo/releases/tag/v$latest_version" ;; esac

  evaluate_version "$tool_name" "$current_version" "$latest_version" "$published_at" "$link"

  if [ "$current_version" != "$latest_version" ] && [ "$DO_HASH" -eq 1 ] && [ -n "$url_template" ]; then
    local clean_version="${latest_version#v}"
    local dl_url="${url_template//__VERSION__/$latest_version}"
    dl_url="${dl_url//__CLEAN_VERSION__/$clean_version}"
    queue_for_hash "$tool_name (v${clean_version})" "$dl_url"
  fi
}

check_gcloud() {
  local current_version=$(get_local_version "Gcloud")
  if [ -z "$current_version" ]; then
    echo "⏭️  Gcloud: Not found in receipts."
    return
  fi

  local latest_version=$(curl --proto '=https' --tlsv1.2 -sSL "https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json" | grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "([^"]+)"/\1/' || true)
  if [ -z "$latest_version" ]; then
    echo "⚠️  Gcloud: Failed to fetch latest version."
    return
  fi

  evaluate_version "Gcloud" "$current_version" "$latest_version" "" "https://cloud.google.com/sdk/docs/downloads-versioned-archives"

  if [ "$current_version" != "$latest_version" ] && [ "$DO_HASH" -eq 1 ]; then
    local dl_url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${latest_version}-darwin-arm.tar.gz"
    queue_for_hash "Gcloud (v${latest_version#v})" "$dl_url"
  fi
}

check_opentofu() {
  local receipt_val=$(get_local_version "OpenTofu")
  if [ -z "$receipt_val" ]; then
    echo "⏭️  OpenTofu: Not found in receipts."
    return
  fi

  local current_tofu="${receipt_val%_*}"
  local current_tofuls="${receipt_val#*_}"

  # Core Tofu
  local tofu_response=$(github_curl "https://api.github.com/repos/opentofu/opentofu/releases/latest")
  local latest_tofu=$(echo "$tofu_response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/"tag_name": *"v?([^"]+)"/\1/' || true)
  local tofu_date=$(echo "$tofu_response" | grep -o '"published_at": *"[^"]*"' | head -n 1 | sed -E 's/"published_at": *"([^"]+)"/\1/' || true)
  if [ -n "$latest_tofu" ]; then evaluate_version "OpenTofu" "$current_tofu" "$latest_tofu" "$tofu_date" "https://github.com/opentofu/opentofu/releases/tag/v$latest_tofu"; fi

  if [ -n "$latest_tofu" ] && [ "$current_tofu" != "$latest_tofu" ] && [ "$DO_HASH" -eq 1 ]; then
    local clean_tofu="${latest_tofu#v}"
    queue_for_hash "OpenTofu (v${clean_tofu})" "https://github.com/opentofu/opentofu/releases/download/v${clean_tofu}/tofu_${clean_tofu}_darwin_arm64.zip"
  fi

  # Tofu LS
  local tofuls_response=$(github_curl "https://api.github.com/repos/opentofu/tofu-ls/releases/latest")
  local latest_tofuls=$(echo "$tofuls_response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/"tag_name": *"v?([^"]+)"/\1/' || true)
  local tofuls_date=$(echo "$tofuls_response" | grep -o '"published_at": *"[^"]*"' | head -n 1 | sed -E 's/"published_at": *"([^"]+)"/\1/' || true)
  if [ -n "$latest_tofuls" ]; then evaluate_version "OpenTofu LS" "$current_tofuls" "$latest_tofuls" "$tofuls_date" "https://github.com/opentofu/tofu-ls/releases/tag/v$latest_tofuls"; fi

  if [ -n "$latest_tofuls" ] && [ "$current_tofuls" != "$latest_tofuls" ] && [ "$DO_HASH" -eq 1 ]; then
    local clean_tofuls="${latest_tofuls#v}"
    queue_for_hash "OpenTofu LS (v${clean_tofuls})" "https://github.com/opentofu/tofu-ls/releases/download/v${clean_tofuls}/tofu-ls_Darwin_arm64.tar.gz"
  fi
}

check_custom_api() {
  local tool_name="$1"
  local latest_version="$2"
  local date_iso="${3:-}"
  local url_template="${4:-}"

  local current_version=$(get_local_version "$tool_name")
  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Not found in receipts."
    return
  fi
  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  evaluate_version "$tool_name" "$current_version" "$latest_version" "$date_iso" ""

  if [ "$current_version" != "$latest_version" ] && [ "$DO_HASH" -eq 1 ] && [ -n "$url_template" ]; then
    local clean_version="${latest_version#v}"
    local dl_url="${url_template//__VERSION__/$latest_version}"
    dl_url="${dl_url//__CLEAN_VERSION__/$clean_version}"
    queue_for_hash "$tool_name (v${clean_version})" "$dl_url"
  fi
}

check_npm_packages() {
  local receipt_val=$(get_local_version "NPM_Packages")
  if [ -z "$receipt_val" ]; then
    echo "⏭️  NPM_Packages: Not found in receipts."
    return
  fi
  local current_pnpm="${receipt_val%_*}"
  local current_biome="${receipt_val#*_}"
  local NPM_BIN="$HOME/.local/bin/npm"
  if [ ! -x "$NPM_BIN" ]; then NPM_BIN="npm"; fi

  local latest_pnpm=$("$NPM_BIN" view pnpm version 2>/dev/null || true)
  local pnpm_time=$("$NPM_BIN" view pnpm time --json 2>/dev/null | grep "\"$latest_pnpm\":" | head -n 1 | cut -d'"' -f4 | cut -c1-19 || true)
  if [ -n "$pnpm_time" ]; then pnpm_time="${pnpm_time}Z"; fi

  local latest_biome=$("$NPM_BIN" view @biomejs/biome version 2>/dev/null || true)
  local biome_time=$("$NPM_BIN" view @biomejs/biome time --json 2>/dev/null | grep "\"$latest_biome\":" | head -n 1 | cut -d'"' -f4 | cut -c1-19 || true)
  if [ -n "$biome_time" ]; then biome_time="${biome_time}Z"; fi

  if [ -n "$latest_pnpm" ]; then evaluate_version "pnpm" "$current_pnpm" "$latest_pnpm" "$pnpm_time" ""; fi
  if [ -n "$latest_biome" ]; then evaluate_version "biome" "$current_biome" "$latest_biome" "$biome_time" ""; fi
}

check_go_pkg() {
  local tool_name="$1"
  local module_path="$2"
  local current_version=$(get_local_version "$tool_name")
  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Not found in receipts."
    return
  fi

  local api_response=$(curl --proto '=https' --tlsv1.2 -sSL "https://proxy.golang.org/${module_path}/@latest" || true)
  local latest_version=$(echo "$api_response" | grep -o '"Version":"[^"]*"' | sed -E 's/"Version":"([^"]+)"/\1/' || true)
  local pkg_time=$(echo "$api_response" | grep -o '"Time":"[^"]*"' | sed -E 's/"Time":"([^"]+)"/\1/' || true)

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi
  evaluate_version "$tool_name" "$current_version" "$latest_version" "$pkg_time" ""
}

check_go_generators() {
  local receipt_val=$(get_local_version "Go_Generators")
  if [ -z "$receipt_val" ]; then
    echo "⏭️  Go_Generators: Not found in receipts."
    return
  fi
  local current_go="${receipt_val%_*}"
  local current_connect_go="${receipt_val#*_}"

  local go_api_resp=$(curl --proto '=https' --tlsv1.2 -sSL "https://proxy.golang.org/google.golang.org/protobuf/cmd/protoc-gen-go/@latest" || true)
  local latest_go=$(echo "$go_api_resp" | grep -o '"Version":"[^"]*"' | sed -E 's/"Version":"([^"]+)"/\1/' || true)
  local go_time=$(echo "$go_api_resp" | grep -o '"Time":"[^"]*"' | sed -E 's/"Time":"([^"]+)"/\1/' || true)
  if [ -n "$latest_go" ]; then evaluate_version "protoc-gen-go" "$current_go" "$latest_go" "$go_time" ""; fi

  local connect_api_resp=$(curl --proto '=https' --tlsv1.2 -sSL "https://proxy.golang.org/connectrpc.com/connect/cmd/protoc-gen-connect-go/@latest" || true)
  local latest_connect=$(echo "$connect_api_resp" | grep -o '"Version":"[^"]*"' | sed -E 's/"Version":"([^"]+)"/\1/' || true)
  local connect_time=$(echo "$connect_api_resp" | grep -o '"Time":"[^"]*"' | sed -E 's/"Time":"([^"]+)"/\1/' || true)
  if [ -n "$latest_connect" ]; then evaluate_version "protoc-gen-connect-go" "$current_connect_go" "$latest_connect" "$connect_time" ""; fi
}

check_node_generators() {
  local receipt_val=$(get_local_version "Node_Generators")
  if [ -z "$receipt_val" ]; then
    echo "⏭️  Node_Generators: Not found in receipts."
    return
  fi
  local current_es="$receipt_val"
  local NPM_BIN="$HOME/.local/bin/npm"
  if [ ! -x "$NPM_BIN" ]; then NPM_BIN="npm"; fi

  local latest_es=$("$NPM_BIN" view @bufbuild/protoc-gen-es version 2>/dev/null || true)
  local es_time=$("$NPM_BIN" view @bufbuild/protoc-gen-es time --json 2>/dev/null | grep "\"$latest_es\":" | head -n 1 | cut -d'"' -f4 | cut -c1-19 || true)
  if [ -n "$es_time" ]; then es_time="${es_time}Z"; fi

  if [ -n "$latest_es" ]; then evaluate_version "protoc-gen-es" "$current_es" "$latest_es" "$es_time" ""; fi
}

# ==============================================================================
# 3. EXECUTE CHECKS
# ==============================================================================

echo "--- Virtualization & Infrastructure ---"
check_github "Colima" "abiosoft/colima" "https://github.com/abiosoft/colima/releases/download/__VERSION__/colima-Darwin-arm64"
check_github "Lima" "lima-vm/lima" "https://github.com/lima-vm/lima/releases/download/__VERSION__/lima-__CLEAN_VERSION__-Darwin-arm64.tar.gz"
check_gcloud
check_opentofu

echo -e "\n--- Core Applications ---"
check_github "Alacritty" "alacritty/alacritty" "https://github.com/alacritty/alacritty/releases/download/__VERSION__/Alacritty-__VERSION__.dmg"
check_github "JetBrainsMono" "ryanoasis/nerd-fonts" "https://github.com/ryanoasis/nerd-fonts/releases/download/__VERSION__/JetBrainsMono.zip"
check_github "Neovim" "neovim/neovim" "https://github.com/neovim/neovim/releases/download/__VERSION__/nvim-macos-arm64.tar.gz"

echo -e "\n--- Languages & Environments ---"
LATEST_GO=$(curl --proto '=https' --tlsv1.2 -sSL "https://go.dev/dl/?mode=json" | grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "go([^"]+)"/\1/' || true)
check_custom_api "Go" "$LATEST_GO" "" "https://go.dev/dl/go__CLEAN_VERSION__.darwin-arm64.tar.gz"

NODE_INFO=$(curl --proto '=https' --tlsv1.2 -sSL "https://nodejs.org/dist/index.tab" | awk 'NR>1 && $10!="-" && !found {print $1, $2; found=1}' || true)
LATEST_NODE=$(echo "$NODE_INFO" | awk '{print $1}' || true)
NODE_DATE=$(echo "$NODE_INFO" | awk '{print $2}' || true)
if [ -n "$NODE_DATE" ]; then NODE_DATE="${NODE_DATE}T00:00:00Z"; fi
check_custom_api "Node" "$LATEST_NODE" "$NODE_DATE" "https://nodejs.org/dist/__VERSION__/node-__VERSION__-darwin-arm64.tar.xz"

echo -e "\n--- CLI Utilities & Packages ---"
check_github "Ripgrep" "BurntSushi/ripgrep" "https://github.com/BurntSushi/ripgrep/releases/download/__VERSION__/ripgrep-__CLEAN_VERSION__-aarch64-apple-darwin.tar.gz"
check_github "fd" "sharkdp/fd" "https://github.com/sharkdp/fd/releases/download/__VERSION__/fd-__VERSION__-aarch64-apple-darwin.tar.gz"
check_github "Protoc" "protocolbuffers/protobuf" "https://github.com/protocolbuffers/protobuf/releases/download/v__CLEAN_VERSION__/protoc-__CLEAN_VERSION__-osx-aarch_64.zip"
check_github "Lazygit" "jesseduffield/lazygit" "https://github.com/jesseduffield/lazygit/releases/download/__VERSION__/lazygit___CLEAN_VERSION___darwin_arm64.tar.gz"
check_github "Treesitter" "tree-sitter/tree-sitter" "https://github.com/tree-sitter/tree-sitter/releases/download/__VERSION__/tree-sitter-macos-arm64.gz"
check_github "TruffleHog" "trufflesecurity/trufflehog" "https://github.com/trufflesecurity/trufflehog/releases/download/v__CLEAN_VERSION__/trufflehog___CLEAN_VERSION___darwin_arm64.tar.gz"

check_npm_packages
check_node_generators
check_go_pkg "Gopls" "golang.org/x/tools/gopls"
check_go_pkg "Goimports" "golang.org/x/tools"
check_go_pkg "Buf" "github.com/bufbuild/buf"
check_go_generators

echo "----------------------------------------------------"
echo "🏁 Update check complete."

# ==============================================================================
# 4. INTERACTIVE VERIFICATION MENU (Triggered by --hash)
# ==============================================================================

if [ "$DO_HASH" -eq 1 ]; then
  while true; do
    if [ ${#PENDING_TOOLS[@]} -eq 0 ]; then
      echo -e "\n✅ All available updates have been processed."
      break
    fi

    echo -e "\n========================================"
    echo "🛠️  SELECT AN UPDATE TO HASH"
    echo "========================================"
    for i in "${!PENDING_TOOLS[@]}"; do
      echo "$((i + 1))) ${PENDING_TOOLS[$i]}"
    done
    echo "q) Quit / Exit"
    echo "========================================"
    read -p "Enter number to hash (or 'q' to quit): " choice

    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
      echo "Exiting hash menu."
      break
    fi

    # POSIX-safe regex validation to ensure choice is a number
    if ! echo "$choice" | grep -Eq '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#PENDING_TOOLS[@]}" ]; then
      echo "❌ Invalid selection. Try again."
      continue
    fi

    idx=$((choice - 1))
    tool="${PENDING_TOOLS[$idx]}"
    url="${PENDING_URLS[$idx]}"

    echo -e "\n🔍 Fetching $tool..."
    prefetch_sha "$url"

    unset 'PENDING_TOOLS[$idx]'
    unset 'PENDING_URLS[$idx]'

    temp_tools=("${PENDING_TOOLS[@]}")
    temp_urls=("${PENDING_URLS[@]}")
    PENDING_TOOLS=("${temp_tools[@]}")
    PENDING_URLS=("${temp_urls[@]}")
  done
fi
