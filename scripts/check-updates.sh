#!/bin/bash
set -euo pipefail

# ==============================================================================
# 0. CONFIGURATION & FLAGS
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSIONS_FILE="$REPO_ROOT/versions.env"
RECEIPTS_FILE="$HOME/.local/.ide_receipts"

DO_HASH=0
for arg in "$@"; do
  if [ "$arg" = "--hash" ] || [ "$arg" = "-h" ] || [ "$arg" = "--update" ] || [ "$arg" = "-u" ]; then
    DO_HASH=1
    echo "⚠️  HASH & UPDATE MODE ENABLED: Will compute new SHAs and update versions.env in-place."
  fi
done

if [ ! -f "$VERSIONS_FILE" ]; then
  echo "❌ No versions.env file found at $VERSIONS_FILE."
  exit 1
fi

echo "🔍 Reading pinned versions from $VERSIONS_FILE..."
echo "----------------------------------------------------"

# shellcheck disable=SC1090
source "$VERSIONS_FILE"

# Global arrays to hold pending updates for the interactive menu
PENDING_TOOLS=()
PENDING_URLS=()
PENDING_VER_VARS=()
PENDING_SHA_VARS=()
PENDING_NEW_VERS=()

# ==============================================================================
# 1. HELPER FUNCTIONS
# ==============================================================================

queue_for_update() {
  local tool="$1"
  local url="$2"
  local ver_var="$3"
  local sha_var="$4"
  local new_ver="$5"
  PENDING_TOOLS+=("$tool")
  PENDING_URLS+=("$url")
  PENDING_VER_VARS+=("$ver_var")
  PENDING_SHA_VARS+=("$sha_var")
  PENDING_NEW_VERS+=("$new_ver")
}

update_env_var() {
  local var_name="$1"
  local new_val="$2"
  if [ -n "$var_name" ] && grep -q "^${var_name}=" "$VERSIONS_FILE"; then
    sed -i '' "s|^${var_name}=.*|${var_name}=\"${new_val}\"|" "$VERSIONS_FILE"
    echo -e "   📝 Updated ${var_name}=\"${new_val}\" in versions.env"
  fi
}

process_update() {
  local tool="$1"
  local url="$2"
  local ver_var="$3"
  local sha_var="$4"
  local new_ver="$5"

  local YELLOW='\033[0;33m'
  local GREEN='\033[0;32m'
  local RED='\033[0;31m'
  local NC='\033[0m'

  echo -e "\n🔍 Updating $tool..."

  # Case 1: Tool has a pinned SHA variable in versions.env
  if [ -n "$url" ] && [ -n "$sha_var" ]; then
    echo -n "   📥 Fetching artifact to compute SHA... "
    local tmp_file
    tmp_file=$(mktemp)

    if curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp_file" "$url"; then
      local sha
      sha=$(shasum -a 256 "$tmp_file" | awk '{print $1}')
      echo -e "${GREEN}Done!${NC}"
      echo -e "   🔐 New SHA256: ${YELLOW}${sha}${NC}"

      # Preserve 'sha256:' prefix if the existing variable uses it
      local current_sha_val="${!sha_var:-}"
      case "$current_sha_val" in
      sha256:*) sha="sha256:${sha}" ;;
      esac

      update_env_var "$ver_var" "$new_ver"
      update_env_var "$sha_var" "$sha"
    else
      echo -e "${RED}Download failed.${NC} (Check URL: $url)"
    fi
    rm -f "$tmp_file"

  # Case 2: Tool is verified via upstream SHASUMS / Go SumDB / NPM (Version update only)
  else
    update_env_var "$ver_var" "$new_ver"
  fi
}

github_curl() {
  local full_url="$1"
  local cache_key
  cache_key=$(echo "$full_url" | sed 's/[^a-zA-Z0-9]/_/g')
  local cache_file="/tmp/substrate_cache_${cache_key}.json"

  if [ -f "$cache_file" ]; then
    local current_time
    current_time=$(date +%s)
    local file_time
    file_time=$(stat -f "%m" "$cache_file" 2>/dev/null || true)
    if [ -n "$file_time" ]; then
      local age_seconds=$((current_time - file_time))
      if [ "$age_seconds" -lt 3600 ]; then
        cat "$cache_file"
        return
      fi
    fi
  fi

  local response
  response=$(curl --proto '=https' --tlsv1.2 -sSL "$full_url" || true)
  if echo "$response" | grep -q '"tag_name"'; then
    echo "$response" >"$cache_file"
  fi
  echo "$response"
}

evaluate_version() {
  local tool_name="$1"
  local current="$2"
  local latest="$3"
  local date_iso="${4:-}"
  local link="${5:-}"

  local age_seconds=99999999
  local age_str=""

  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  local NC='\033[0m'

  if [ -n "$date_iso" ]; then
    local release_epoch
    if release_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date_iso" "+%s" 2>/dev/null); then
      local current_epoch
      current_epoch=$(date "+%s")
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
      echo -e "⏳ COOLING OFF: $tool_name (Pinned: $current -> Latest: $latest)$age_str"
      echo -e "   ⏸️  Waiting 24 hours for stability before upgrading."
    else
      echo -e "🚨 UPDATE AVAILABLE: $tool_name (Pinned: $current -> Latest: $latest)$age_str"
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
  local ver_var="$3"
  local sha_var="$4"
  local url_template="${5:-}"

  local current_version="${!ver_var:-}"
  if [ -z "$current_version" ]; then
    echo "⏭️  $tool_name: Variable $ver_var not found in versions.env."
    return
  fi

  local api_response
  api_response=$(github_curl "https://api.github.com/repos/$repo/releases/latest")
  local latest_version
  latest_version=$(echo "$api_response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/"tag_name": *"([^"]+)"/\1/' || true)
  local published_at
  published_at=$(echo "$api_response" | grep -o '"published_at": *"[^"]*"' | head -n 1 | sed -E 's/"published_at": *"([^"]+)"/\1/' || true)

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  # Align 'v' prefix with whatever convention versions.env uses for this variable
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
    queue_for_update "$tool_name ($current_version -> $latest_version)" "$dl_url" "$ver_var" "$sha_var" "$latest_version"
  fi
}

check_gcloud() {
  local current_version="${GCLOUD_VERSION:-}"
  local latest_version
  latest_version=$(curl --proto '=https' --tlsv1.2 -sSL "https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json" | grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "([^"]+)"/\1/' || true)
  if [ -z "$latest_version" ]; then
    echo "⚠️  Gcloud: Failed to fetch latest version."
    return
  fi

  evaluate_version "Gcloud" "$current_version" "$latest_version" "" "https://cloud.google.com/sdk/docs/downloads-versioned-archives"

  if [ "$current_version" != "$latest_version" ] && [ "$DO_HASH" -eq 1 ]; then
    local dl_url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${latest_version}-darwin-arm.tar.gz"
    queue_for_update "Gcloud ($current_version -> $latest_version)" "$dl_url" "GCLOUD_VERSION" "GCLOUD_SHA" "$latest_version"
  fi
}

check_custom_api() {
  local tool_name="$1"
  local ver_var="$2"
  local sha_var="$3"
  local latest_version="$4"
  local date_iso="${5:-}"
  local url_template="${6:-}"

  local current_version="${!ver_var:-}"
  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  evaluate_version "$tool_name" "$current_version" "$latest_version" "$date_iso" ""

  if [ "$current_version" != "$latest_version" ] && [ "$DO_HASH" -eq 1 ]; then
    local clean_version="${latest_version#v}"
    local dl_url="${url_template//__VERSION__/$latest_version}"
    dl_url="${dl_url//__CLEAN_VERSION__/$clean_version}"
    queue_for_update "$tool_name ($current_version -> $latest_version)" "$dl_url" "$ver_var" "$sha_var" "$latest_version"
  fi
}

check_npm_pkg() {
  local tool_name="$1"
  local pkg_name="$2"
  local ver_var="$3"

  local current_version="${!ver_var:-}"
  local NPM_BIN="$HOME/.local/bin/npm"
  if [ ! -x "$NPM_BIN" ]; then NPM_BIN="npm"; fi

  local latest_version
  latest_version=$("$NPM_BIN" view "$pkg_name" version 2>/dev/null || true)
  local pkg_time
  pkg_time=$("$NPM_BIN" view "$pkg_name" time --json 2>/dev/null | grep "\"$latest_version\":" | head -n 1 | cut -d'"' -f4 | cut -c1-19 || true)
  if [ -n "$pkg_time" ]; then pkg_time="${pkg_time}Z"; fi

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  evaluate_version "$tool_name" "$current_version" "$latest_version" "$pkg_time" ""

  if [ "$current_version" != "$latest_version" ] && [ "$DO_HASH" -eq 1 ]; then
    queue_for_update "$tool_name ($current_version -> $latest_version)" "" "$ver_var" "" "$latest_version"
  fi
}

check_go_pkg() {
  local tool_name="$1"
  local module_path="$2"
  local ver_var="$3"

  local current_version="${!ver_var:-}"
  local api_response
  api_response=$(curl --proto '=https' --tlsv1.2 -sSL "https://proxy.golang.org/${module_path}/@latest" || true)
  local latest_version
  latest_version=$(echo "$api_response" | grep -o '"Version":"[^"]*"' | sed -E 's/"Version":"([^"]+)"/\1/' || true)
  local pkg_time
  pkg_time=$(echo "$api_response" | grep -o '"Time":"[^"]*"' | sed -E 's/"Time":"([^"]+)"/\1/' || true)

  if [ -z "$latest_version" ]; then
    echo "⚠️  $tool_name: Failed to fetch latest version."
    return
  fi

  evaluate_version "$tool_name" "$current_version" "$latest_version" "$pkg_time" ""

  if [ "$current_version" != "$latest_version" ] && [ "$DO_HASH" -eq 1 ]; then
    queue_for_update "$tool_name ($current_version -> $latest_version)" "" "$ver_var" "" "$latest_version"
  fi
}

# ==============================================================================
# 3. EXECUTE CHECKS
# ==============================================================================

echo "--- Virtualization & Infrastructure ---"
check_github "Colima" "abiosoft/colima" "COLIMA_VERSION" "COLIMA_SHA" "https://github.com/abiosoft/colima/releases/download/__VERSION__/colima-Darwin-arm64"
check_github "Lima" "lima-vm/lima" "LIMA_VERSION" "LIMA_SHA" "https://github.com/lima-vm/lima/releases/download/__VERSION__/lima-__CLEAN_VERSION__-Darwin-arm64.tar.gz"
check_gcloud
check_github "OpenTofu" "opentofu/opentofu" "TOFU_VERSION" "TOFU_SHA" "https://github.com/opentofu/opentofu/releases/download/v__CLEAN_VERSION__/tofu___CLEAN_VERSION___darwin_arm64.zip"
check_github "OpenTofu LS" "opentofu/tofu-ls" "TOFULS_VERSION" "TOFULS_SHA" "https://github.com/opentofu/tofu-ls/releases/download/v__CLEAN_VERSION__/tofu-ls_Darwin_arm64.tar.gz"

echo -e "\n--- Core Applications ---"
check_github "Alacritty" "alacritty/alacritty" "ALACRITTY_VERSION" "ALACRITTY_SHA" "https://github.com/alacritty/alacritty/releases/download/__VERSION__/Alacritty-__VERSION__.dmg"
check_github "JetBrainsMono" "ryanoasis/nerd-fonts" "JB_MONO_VERSION" "JB_MONO_SHA" "https://github.com/ryanoasis/nerd-fonts/releases/download/__VERSION__/JetBrainsMono.zip"
check_github "Neovim" "neovim/neovim" "NVIM_VERSION" "NVIM_SHA" "https://github.com/neovim/neovim/releases/download/__VERSION__/nvim-macos-arm64.tar.gz"

echo -e "\n--- Languages & Environments ---"
LATEST_GO=$(curl --proto '=https' --tlsv1.2 -sSL "https://go.dev/dl/?mode=json" | grep -o '"version": "[^"]*"' | head -n 1 | sed -E 's/"version": "go([^"]+)"/\1/' || true)
check_custom_api "Go" "GO_VERSION" "GO_SHA" "$LATEST_GO" "" "https://go.dev/dl/go__CLEAN_VERSION__.darwin-arm64.tar.gz"

NODE_INFO=$(curl --proto '=https' --tlsv1.2 -sSL "https://nodejs.org/dist/index.tab" | awk 'NR>1 && $10!="-" && !found {print $1, $2; found=1}' || true)
LATEST_NODE=$(echo "$NODE_INFO" | awk '{print $1}' || true)
NODE_DATE=$(echo "$NODE_INFO" | awk '{print $2}' || true)
if [ -n "$NODE_DATE" ]; then NODE_DATE="${NODE_DATE}T00:00:00Z"; fi
check_custom_api "Node" "NODE_VERSION" "" "$LATEST_NODE" "$NODE_DATE" ""

echo -e "\n--- CLI Utilities & Packages ---"
check_github "Ripgrep" "BurntSushi/ripgrep" "RG_VERSION" "RG_SHA" "https://github.com/BurntSushi/ripgrep/releases/download/__VERSION__/ripgrep-__CLEAN_VERSION__-aarch64-apple-darwin.tar.gz"
check_github "fd" "sharkdp/fd" "FD_VERSION" "FD_SHA" "https://github.com/sharkdp/fd/releases/download/__VERSION__/fd-__VERSION__-aarch64-apple-darwin.tar.gz"
check_github "Protoc" "protocolbuffers/protobuf" "PROTOC_VERSION" "PROTOC_SHA" "https://github.com/protocolbuffers/protobuf/releases/download/v__CLEAN_VERSION__/protoc-__CLEAN_VERSION__-osx-aarch_64.zip"
check_github "Lazygit" "jesseduffield/lazygit" "LAZYGIT_VERSION" "LAZYGIT_SHA" "https://github.com/jesseduffield/lazygit/releases/download/__VERSION__/lazygit___CLEAN_VERSION___darwin_arm64.tar.gz"
check_github "Treesitter" "tree-sitter/tree-sitter" "TS_VERSION" "TS_SHA" "https://github.com/tree-sitter/tree-sitter/releases/download/__VERSION__/tree-sitter-macos-arm64.gz"
check_github "TruffleHog" "trufflesecurity/trufflehog" "TRUFFLEHOG_VERSION" "TRUFFLEHOG_SHA" "https://github.com/trufflesecurity/trufflehog/releases/download/v__CLEAN_VERSION__/trufflehog___CLEAN_VERSION___darwin_arm64.tar.gz"

check_npm_pkg "pnpm" "pnpm" "PNPM_VERSION"
check_npm_pkg "biome" "@biomejs/biome" "BIOME_VERSION"
check_npm_pkg "protoc-gen-es" "@bufbuild/protoc-gen-es" "PROTOC_GEN_ES_VERSION"
check_go_pkg "Gopls" "golang.org/x/tools/gopls" "GOPLS_VERSION"
check_go_pkg "Goimports" "golang.org/x/tools" "GOIMPORTS_VERSION"
check_go_pkg "Buf" "github.com/bufbuild/buf" "BUF_VERSION"
check_go_pkg "protoc-gen-go" "google.golang.org/protobuf/cmd/protoc-gen-go" "PROTOC_GEN_GO_VERSION"
check_go_pkg "protoc-gen-connect-go" "connectrpc.com/connect/cmd/protoc-gen-connect-go" "PROTOC_GEN_CONNECT_GO_VERSION"

echo "----------------------------------------------------"
echo "🏁 Update check complete."

# ==============================================================================
# 4. INTERACTIVE UPDATE & HASH MENU (Triggered by --hash / -h)
# ==============================================================================

if [ "$DO_HASH" -eq 1 ]; then
  while true; do
    if [ ${#PENDING_TOOLS[@]} -eq 0 ]; then
      echo -e "\n✅ All available updates have been processed in versions.env."
      echo "👉 Run './setup-macarm.sh' to apply the updated tools to your machine."
      break
    fi

    echo -e "\n========================================"
    echo "🛠️  SELECT AN UPDATE TO APPLY TO versions.env"
    echo "========================================"
    for i in "${!PENDING_TOOLS[@]}"; do
      echo "$((i + 1))) ${PENDING_TOOLS[$i]}"
    done
    echo "a) Update ALL listed above"
    echo "q) Quit / Exit"
    echo "========================================"
    read -r -p "Enter number to update, 'a' for all, or 'q' to quit: " choice

    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
      echo "Exiting update menu."
      break
    fi

    if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
      for i in "${!PENDING_TOOLS[@]}"; do
        process_update "${PENDING_TOOLS[$i]}" "${PENDING_URLS[$i]}" "${PENDING_VER_VARS[$i]}" "${PENDING_SHA_VARS[$i]}" "${PENDING_NEW_VERS[$i]}"
      done
      PENDING_TOOLS=()
      continue
    fi

    if ! echo "$choice" | grep -Eq '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#PENDING_TOOLS[@]}" ]; then
      echo "❌ Invalid selection. Try again."
      continue
    fi

    idx=$((choice - 1))
    process_update "${PENDING_TOOLS[$idx]}" "${PENDING_URLS[$idx]}" "${PENDING_VER_VARS[$idx]}" "${PENDING_SHA_VARS[$idx]}" "${PENDING_NEW_VERS[$idx]}"

    unset 'PENDING_TOOLS[$idx]'
    unset 'PENDING_URLS[$idx]'
    unset 'PENDING_VER_VARS[$idx]'
    unset 'PENDING_SHA_VARS[$idx]'
    unset 'PENDING_NEW_VERS[$idx]'

    PENDING_TOOLS=("${PENDING_TOOLS[@]}")
    PENDING_URLS=("${PENDING_URLS[@]}")
    PENDING_VER_VARS=("${PENDING_VER_VARS[@]}")
    PENDING_SHA_VARS=("${PENDING_SHA_VARS[@]}")
    PENDING_NEW_VERS=("${PENDING_NEW_VERS[@]}")
  done
fi
