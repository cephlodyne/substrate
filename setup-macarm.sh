#!/bin/bash
set -euo pipefail
# ==============================================================================
# ZERO-TRUST SUBSTRATE BOOTSTRAP & TARBALL BUILDER (macOS ARM64)
# Usage:
#   ./setup-macarm.sh [OPTIONS]
#
# Options:
#   --profile <name>   Profile preset: full (default), app, headless, minimal
#   --no-ide           Skip Neovim, Lazygit, Tree-sitter, Alacritty, and Fonts
#   --no-infra         Skip OpenTofu, tofu-ls, Python, and Google Cloud SDK
#   --no-containers    Skip Colima, Lima, and Docker SSH wrappers
#   --tarball          Package the installed profile into a slim .tar.xz in dist/
# ==============================================================================

umask 077

# ==============================================================================
# 0. PARSE PROFILE & FLAGS
# ==============================================================================
PROFILE="full"
INSTALL_APP=1
INSTALL_INFRA=1
INSTALL_CONTAINERS=1
INSTALL_IDE=1
INSTALL_GUI=1
BUILD_TARBALL=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --profile)
    PROFILE="$2"
    shift 2
    ;;
  --no-ide)
    INSTALL_IDE=0
    INSTALL_GUI=0
    shift
    ;;
  --no-infra)
    INSTALL_INFRA=0
    shift
    ;;
  --no-containers)
    INSTALL_CONTAINERS=0
    shift
    ;;
  --tarball)
    BUILD_TARBALL=1
    shift
    ;;
  *)
    echo "❌ Unknown flag: $1"
    echo "👉 Usage: ./setup-macarm.sh [--profile full|app|headless|minimal] [--no-ide] [--no-infra] [--no-containers] [--tarball]"
    exit 1
    ;;
  esac
done

case "$PROFILE" in
full)
  ;; # All enabled by default
app)
  INSTALL_INFRA=0
  ;;
headless)
  INSTALL_GUI=0
  INSTALL_CONTAINERS=0
  ;;
minimal)
  INSTALL_INFRA=0
  INSTALL_CONTAINERS=0
  INSTALL_IDE=0
  INSTALL_GUI=0
  ;;
*)
  echo "❌ Unknown profile '$PROFILE'. Valid profiles: full, app, headless, minimal"
  exit 1
  ;;
esac

echo "🛠️  Bootstrapping Substrate Environment (Profile: $PROFILE)..."
echo "   [App/Core: $INSTALL_APP | Infra: $INSTALL_INFRA | Containers: $INSTALL_CONTAINERS | IDE: $INSTALL_IDE | GUI: $INSTALL_GUI]"

if ! xcode-select -p &>/dev/null; then
  echo "❌ Xcode Command Line Tools missing. This provides Git and system headers!"
  echo "👉 A popup should appear. Click 'Install', wait for it to finish, and run this script again."
  xcode-select --install
  exit 1
fi

# ==============================================================================
# 1. LOAD TOOL VERSIONS, URLS & SHAS (from versions.env)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/versions.env" ]; then
  echo "❌ FATAL: Missing $SCRIPT_DIR/versions.env"
  exit 1
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/versions.env"

CACHE_DIR="$HOME/.cache/ide-bootstrap"
LOCAL_DIR="$HOME/.local"
BIN_DIR="$LOCAL_DIR/bin"
NVIM_APP_DIR="$LOCAL_DIR/nvim-app"
GCLOUD_DIR="$LOCAL_DIR/google-cloud-sdk"
RECEIPTS_FILE="$LOCAL_DIR/.ide_receipts"

mkdir -p "$BIN_DIR" "$CACHE_DIR"
touch "$RECEIPTS_FILE"
# Keep a copy of versions.env in ~/.local so 'check-updates' works when invoked from PATH
cp "$SCRIPT_DIR/versions.env" "$LOCAL_DIR/versions.env"
export PATH="$BIN_DIR:$LOCAL_DIR/node/bin:$PATH"

# ------------------------------------------------------------------------------
# 2. STATE TRACKING & VERIFICATION LOGIC
# ------------------------------------------------------------------------------
needs_update() {
  local tool="$1"
  local target_version="$2"
  local current_version=""

  if grep -q "^${tool}=" "$RECEIPTS_FILE" 2>/dev/null; then
    current_version=$(grep "^${tool}=" "$RECEIPTS_FILE" | cut -d'=' -f2)
  fi

  if [ "$current_version" == "$target_version" ]; then
    echo "✅ $tool is up-to-date ($target_version). Skipping."
    return 1
  else
    echo "🔄 Updating $tool to $target_version..."
    return 0
  fi
}

mark_updated() {
  local tool="$1"
  local version="$2"
  grep -v "^${tool}=" "$RECEIPTS_FILE" >"${RECEIPTS_FILE}.tmp" 2>/dev/null || true
  echo "${tool}=${version}" >>"${RECEIPTS_FILE}.tmp"
  mv "${RECEIPTS_FILE}.tmp" "$RECEIPTS_FILE"
}

fetch_and_verify() {
  local name=$1 bin_url=$2 orig_file=$3 local_file=$4 source=$5
  local expected_sha=""
  cd "$CACHE_DIR" || exit

  if [[ "$source" == http* ]]; then
    local temp_sum="${local_file}.sum"
    curl --proto '=https' --tlsv1.2 -fsSL -o "$temp_sum" "$source"
    if grep -q "$orig_file" "$temp_sum" 2>/dev/null; then
      expected_sha=$(grep "$orig_file" "$temp_sum" | awk '{print $1}' | head -n 1)
    else
      echo "❌ FATAL: The filename '$orig_file' was NOT found in the checksums file."
      exit 1
    fi
  else
    expected_sha="$source"
  fi

  expected_sha="${expected_sha#sha256:}"
  expected_sha="${expected_sha#sha256-}"

  echo "⬇️  Downloading $name..."
  curl --proto '=https' --tlsv1.2 -fsSL -o "$local_file" "$bin_url"

  echo "🔐 Verifying $name..."
  if ! echo "$expected_sha  $local_file" | shasum -a 256 -c; then
    echo "❌ FATAL: Checksum validation failed for $name!"
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# 3. SMART INSTALL / UPDATE BLOCKS (GROUPED BY CAPABILITY)
# ------------------------------------------------------------------------------

# === A. CONTAINERS (Colima & Lima) ===
if [ "$INSTALL_CONTAINERS" -eq 1 ]; then
  if needs_update "Colima" "$COLIMA_VERSION"; then
    echo "🛑 Stopping active Colima instances for safe update..."
    command -v colima &>/dev/null && colima stop 2>/dev/null || true
    fetch_and_verify "Colima" "$COLIMA_URL" "$COLIMA_FILE" "colima" "$COLIMA_SHA"
    cp "$CACHE_DIR/colima" "$BIN_DIR/colima" && chmod +x "$BIN_DIR/colima"
    xattr -r -d com.apple.quarantine "$BIN_DIR/colima" 2>/dev/null || true
    echo "🖋️  Cryptographic check passed. Signing binary for Apple Silicon execution..."
    codesign --force --deep --sign - "$BIN_DIR/colima"
    mark_updated "Colima" "$COLIMA_VERSION"
  fi

  if needs_update "Lima" "$LIMA_VERSION"; then
    echo "🛑 Stopping underlying Lima VMs for safe update..."
    command -v colima &>/dev/null && colima stop 2>/dev/null || true
    command -v limactl &>/dev/null && limactl stop --force colima 2>/dev/null || true
    fetch_and_verify "Lima" "$LIMA_URL" "$LIMA_FILE" "lima.tar.gz" "$LIMA_SHA"
    tar -xzf "$CACHE_DIR/lima.tar.gz" -C "$LOCAL_DIR" bin/lima bin/limactl share/lima
    find "$LOCAL_DIR/share/lima" -type f ! -name "*aarch64*" ! -name "*arm64*" -name "lima-guestagent*" -delete 2>/dev/null || true
    xattr -r -d com.apple.quarantine "$BIN_DIR/lima" "$BIN_DIR/limactl" 2>/dev/null || true
    mark_updated "Lima" "$LIMA_VERSION"
  fi
fi

# === B. INFRASTRUCTURE (Python, Gcloud, OpenTofu, Tofu-LS) ===
if [ "$INSTALL_INFRA" -eq 1 ]; then
  if needs_update "Python" "$PYTHON_VERSION"; then
    fetch_and_verify "Python" "$PYTHON_URL" "$PYTHON_FILE" "python.tar.gz" "$PYTHON_SHA"
    rm -rf "$LOCAL_DIR/python" && mkdir -p "$LOCAL_DIR/python"
    tar -xzf "$CACHE_DIR/python.tar.gz" -C "$LOCAL_DIR/python" --strip-components=1
    ln -sf "../python/bin/python3" "$BIN_DIR/python3"
    xattr -r -d com.apple.quarantine "$LOCAL_DIR/python" 2>/dev/null || true
    mark_updated "Python" "$PYTHON_VERSION"
  fi

  if needs_update "Gcloud" "$GCLOUD_VERSION"; then
    fetch_and_verify "Google Cloud SDK" "$GCLOUD_URL" "$GCLOUD_FILE" "gcloud.tar.gz" "$GCLOUD_SHA"
    rm -rf "$GCLOUD_DIR" && tar -xzf "$CACHE_DIR/gcloud.tar.gz" -C "$LOCAL_DIR"

    echo "📦 Configuring gcloud (Using isolated Python)..."
    ln -sf "../google-cloud-sdk/bin/gcloud" "$BIN_DIR/gcloud"
    xattr -r -d com.apple.quarantine "$GCLOUD_DIR" 2>/dev/null || true

    echo "🔒 Disabling gcloud internal updaters to prevent version drift..."
    env CLOUDSDK_PYTHON="$BIN_DIR/python3" PYTHONDONTWRITEBYTECODE=1 "$BIN_DIR/gcloud" config set component_manager/disable_update_check true --quiet || true
    env CLOUDSDK_PYTHON="$BIN_DIR/python3" PYTHONDONTWRITEBYTECODE=1 "$BIN_DIR/gcloud" config set core/disable_usage_reporting true --quiet || true

    mark_updated "Gcloud" "$GCLOUD_VERSION"
  fi

  if needs_update "OpenTofu" "${TOFU_VERSION}_${TOFULS_VERSION}"; then
    fetch_and_verify "OpenTofu" "$TOFU_URL" "$TOFU_FILE" "tofu.zip" "$TOFU_SHA"
    fetch_and_verify "OpenTofu LS" "$TOFULS_URL" "$TOFULS_FILE" "tofu-ls.tar.gz" "$TOFULS_SHA"
    unzip -q -o "$CACHE_DIR/tofu.zip" "tofu" -d "$BIN_DIR"
    tar -xzf "$CACHE_DIR/tofu-ls.tar.gz" -C "$BIN_DIR" "tofu-ls"
    ln -sf "tofu" "$BIN_DIR/terraform"
    ln -sf "tofu-ls" "$BIN_DIR/terraform-ls"
    xattr -r -d com.apple.quarantine "$BIN_DIR/tofu" "$BIN_DIR/tofu-ls" 2>/dev/null || true
    mark_updated "OpenTofu" "${TOFU_VERSION}_${TOFULS_VERSION}"
  fi
fi

# === C. MACOS GUI (Alacritty & Fonts) ===
if [ "$INSTALL_GUI" -eq 1 ]; then
  if needs_update "Alacritty" "$ALACRITTY_VERSION"; then
    fetch_and_verify "Alacritty" "$ALACRITTY_URL" "$ALACRITTY_FILE" "alacritty.dmg" "$ALACRITTY_SHA"
    hdiutil attach "$CACHE_DIR/alacritty.dmg" -mountpoint /Volumes/Alacritty -nobrowse -quiet
    rm -rf /Applications/Alacritty.app 2>/dev/null || sudo rm -rf /Applications/Alacritty.app
    cp -R /Volumes/Alacritty/Alacritty.app /Applications/
    hdiutil detach /Volumes/Alacritty -quiet
    xattr -r -d com.apple.quarantine /Applications/Alacritty.app 2>/dev/null || true
    mark_updated "Alacritty" "$ALACRITTY_VERSION"
  fi

  if needs_update "JetBrainsMono" "$JB_MONO_VERSION"; then
    fetch_and_verify "JetBrains Mono Nerd Font" "$JB_MONO_URL" "$JB_MONO_FILE" "JetBrainsMono.zip" "$JB_MONO_SHA"
    mkdir -p "$CACHE_DIR/jb-mono"
    unzip -q -o "$CACHE_DIR/JetBrainsMono.zip" -d "$CACHE_DIR/jb-mono"
    rm -f "$HOME/Library/Fonts/JetBrainsMono"*.ttf "$HOME/Library/Fonts/JetBrainsMono"*.otf 2>/dev/null || true
    for weight in Regular Bold Italic BoldItalic; do
      if [ -f "$CACHE_DIR/jb-mono/JetBrainsMonoNerdFont-${weight}.ttf" ]; then
        cp "$CACHE_DIR/jb-mono/JetBrainsMonoNerdFont-${weight}.ttf" "$HOME/Library/Fonts/"
      fi
    done
    mark_updated "JetBrainsMono" "$JB_MONO_VERSION"
  fi
fi

# === D. CORE LANGUAGES & CLI TOOLS ===
if [ "$INSTALL_APP" -eq 1 ]; then
  if needs_update "Go" "$GO_VERSION"; then
    fetch_and_verify "Go" "$GO_URL" "$GO_FILE" "go.tar.gz" "$GO_SHA"
    rm -rf "$LOCAL_DIR/go" && tar -xzf "$CACHE_DIR/go.tar.gz" -C "$LOCAL_DIR"
    ln -sf "../go/bin/go" "$BIN_DIR/go"
    xattr -r -d com.apple.quarantine "$LOCAL_DIR/go" 2>/dev/null || true
    echo "🔒 Locking Go environment (No auto-updates, strict proxy, strict checksums)..."
    env GOPATH="$HOME/go" "$LOCAL_DIR/go/bin/go" env -w GOTOOLCHAIN=local GOPROXY=https://proxy.golang.org,direct GOSUMDB=sum.golang.org
    mark_updated "Go" "$GO_VERSION"
  fi

  if needs_update "Node" "$NODE_VERSION"; then
    fetch_and_verify "Node.js" "$NODE_URL" "$NODE_FILE" "node.tar.xz" "$NODE_SHA_SOURCE"
    rm -rf "$LOCAL_DIR/node" && mkdir -p "$LOCAL_DIR/node"
    tar -xf "$CACHE_DIR/node.tar.xz" -C "$LOCAL_DIR/node" --strip-components=1
    ln -sf "../node/bin/node" "$BIN_DIR/node"
    ln -sf "../node/bin/npm" "$BIN_DIR/npm"
    ln -sf "../node/bin/npx" "$BIN_DIR/npx"
    xattr -r -d com.apple.quarantine "$LOCAL_DIR/node" 2>/dev/null || true
    echo "🔒 Disabling NPM lifecycle scripts to prevent malicious post-install execution..."
    "$BIN_DIR/npm" config set ignore-scripts true --global
    mark_updated "Node" "$NODE_VERSION"
  fi

  if needs_update "NPM_Packages" "${PNPM_VERSION}_${BIOME_VERSION}"; then
    echo "📦 Installing Biome and pnpm securely via verified NPM binary..."
    "$BIN_DIR/npm" install -g --allow-scripts=pnpm "pnpm@${PNPM_VERSION}" "@biomejs/biome@${BIOME_VERSION}"
    ln -sf "../node/bin/pnpm" "$BIN_DIR/pnpm"
    ln -sf "../node/bin/pnpx" "$BIN_DIR/pnpx"
    ln -sf "../node/bin/biome" "$BIN_DIR/biome"
    mark_updated "NPM_Packages" "${PNPM_VERSION}_${BIOME_VERSION}"
  fi

  if needs_update "Ripgrep" "$RG_VERSION"; then
    fetch_and_verify "Ripgrep" "$RG_URL" "$RG_FILE" "rg.tar.gz" "$RG_SHA"
    tar -xzf "$CACHE_DIR/rg.tar.gz" -C "$CACHE_DIR"
    mv "$CACHE_DIR/ripgrep-$RG_VERSION-aarch64-apple-darwin/rg" "$BIN_DIR/rg"
    xattr -r -d com.apple.quarantine "$BIN_DIR/rg" 2>/dev/null || true
    mark_updated "Ripgrep" "$RG_VERSION"
  fi

  if needs_update "fd" "$FD_VERSION"; then
    fetch_and_verify "fd" "$FD_URL" "$FD_FILE" "fd.tar.gz" "$FD_SHA"
    tar -xzf "$CACHE_DIR/fd.tar.gz" -C "$CACHE_DIR"
    mv "$CACHE_DIR/fd-$FD_VERSION-aarch64-apple-darwin/fd" "$BIN_DIR/fd"
    xattr -r -d com.apple.quarantine "$BIN_DIR/fd" 2>/dev/null || true
    mark_updated "fd" "$FD_VERSION"
  fi

  if needs_update "Protoc" "$PROTOC_VERSION"; then
    fetch_and_verify "Protoc" "$PROTOC_URL" "$PROTOC_FILE" "protoc.zip" "$PROTOC_SHA"
    mkdir -p "$CACHE_DIR/protoc"
    unzip -q -o "$CACHE_DIR/protoc.zip" -d "$CACHE_DIR/protoc"
    mv "$CACHE_DIR/protoc/bin/protoc" "$BIN_DIR/protoc"
    chmod +x "$BIN_DIR/protoc"
    xattr -r -d com.apple.quarantine "$BIN_DIR/protoc" 2>/dev/null || true
    mkdir -p "$LOCAL_DIR/include"
    cp -R "$CACHE_DIR/protoc/include/" "$LOCAL_DIR/include/"
    mark_updated "Protoc" "$PROTOC_VERSION"
  fi

  if needs_update "TruffleHog" "$TRUFFLEHOG_VERSION"; then
    fetch_and_verify "TruffleHog" "$TRUFFLEHOG_URL" "$TRUFFLEHOG_FILE" "trufflehog.tar.gz" "$TRUFFLEHOG_SHA"
    tar -xzf "$CACHE_DIR/trufflehog.tar.gz" -C "$CACHE_DIR"
    mv "$CACHE_DIR/trufflehog" "$BIN_DIR/trufflehog"
    xattr -r -d com.apple.quarantine "$BIN_DIR/trufflehog" 2>/dev/null || true
    mark_updated "TruffleHog" "$TRUFFLEHOG_VERSION"
  fi

  if needs_update "Gopls" "$GOPLS_VERSION"; then
    echo "📦 Compiling gopls securely (CGO disabled, stripped)..."
    env CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org "$LOCAL_DIR/go/bin/go" install -ldflags="-s -w" "golang.org/x/tools/gopls@${GOPLS_VERSION}"
    mark_updated "Gopls" "$GOPLS_VERSION"
  fi

  if needs_update "Goimports" "$GOIMPORTS_VERSION"; then
    echo "📦 Compiling goimports securely (CGO disabled, stripped)..."
    env CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org "$LOCAL_DIR/go/bin/go" install -ldflags="-s -w" "golang.org/x/tools/cmd/goimports@${GOIMPORTS_VERSION}"
    mark_updated "Goimports" "$GOIMPORTS_VERSION"
  fi

  if needs_update "Buf" "$BUF_VERSION"; then
    echo "📦 Compiling Buf CLI securely (CGO disabled, stripped)..."
    env CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org "$LOCAL_DIR/go/bin/go" install -ldflags="-s -w" "github.com/bufbuild/buf/cmd/buf@${BUF_VERSION}"
    mark_updated "Buf" "$BUF_VERSION"
  fi

  if needs_update "Go_Generators" "${PROTOC_GEN_GO_VERSION}_${PROTOC_GEN_CONNECT_GO_VERSION}"; then
    echo "📦 Compiling Go Protobuf plugins securely (CGO disabled, stripped)..."
    env CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org "$LOCAL_DIR/go/bin/go" install -ldflags="-s -w" "google.golang.org/protobuf/cmd/protoc-gen-go@${PROTOC_GEN_GO_VERSION}"
    env CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org "$LOCAL_DIR/go/bin/go" install -ldflags="-s -w" "connectrpc.com/connect/cmd/protoc-gen-connect-go@${PROTOC_GEN_CONNECT_GO_VERSION}"
    mark_updated "Go_Generators" "${PROTOC_GEN_GO_VERSION}_${PROTOC_GEN_CONNECT_GO_VERSION}"
  fi

  if needs_update "Node_Generators" "$PROTOC_GEN_ES_VERSION"; then
    echo "📦 Installing Node Protobuf plugins securely via verified NPM binary..."
    "$BIN_DIR/npm" install -g --ignore-scripts "@bufbuild/protoc-gen-es@${PROTOC_GEN_ES_VERSION}"
    ln -sf "../node/bin/protoc-gen-es" "$BIN_DIR/protoc-gen-es"
    mark_updated "Node_Generators" "$PROTOC_GEN_ES_VERSION"
  fi
fi

# === E. TERMINAL IDE (Neovim, Lazygit, Tree-sitter) ===
if [ "$INSTALL_IDE" -eq 1 ]; then
  mkdir -p "$NVIM_APP_DIR"
  if needs_update "Neovim" "$NVIM_VERSION"; then
    fetch_and_verify "Neovim" "$NVIM_URL" "$NVIM_FILE" "nvim.tar.gz" "$NVIM_SHA"
    rm -rf "$NVIM_APP_DIR" && mkdir -p "$NVIM_APP_DIR"
    tar -xzf "$CACHE_DIR/nvim.tar.gz" -C "$NVIM_APP_DIR" --strip-components=1
    ln -sf "../nvim-app/bin/nvim" "$BIN_DIR/nvim"
    xattr -r -d com.apple.quarantine "$NVIM_APP_DIR" 2>/dev/null || true
    mark_updated "Neovim" "$NVIM_VERSION"
  fi

  if needs_update "Lazygit" "$LAZYGIT_VERSION"; then
    fetch_and_verify "Lazygit" "$LAZYGIT_URL" "$LAZYGIT_FILE" "lazygit.tar.gz" "$LAZYGIT_SHA"
    tar -xzf "$CACHE_DIR/lazygit.tar.gz" -C "$CACHE_DIR"
    mv "$CACHE_DIR/lazygit" "$BIN_DIR/lazygit"
    xattr -r -d com.apple.quarantine "$BIN_DIR/lazygit" 2>/dev/null || true
    mark_updated "Lazygit" "$LAZYGIT_VERSION"
  fi

  if needs_update "Treesitter" "$TS_VERSION"; then
    fetch_and_verify "Tree-sitter" "$TS_URL" "$TS_FILE" "tree-sitter.gz" "$TS_SHA"
    gzip -d -c "$CACHE_DIR/tree-sitter.gz" >"$BIN_DIR/tree-sitter" && chmod +x "$BIN_DIR/tree-sitter"
    xattr -r -d com.apple.quarantine "$BIN_DIR/tree-sitter" 2>/dev/null || true
    mark_updated "Treesitter" "$TS_VERSION"
  fi
fi

echo "🧹 Cleaning up raw downloaded archives and stray docs in bin..."
rm -rf "$CACHE_DIR"/*
rm -f "$BIN_DIR/CHANGELOG.md" "$BIN_DIR/LICENSE" "$BIN_DIR/README.md" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. UTILITY SCRIPTS, COMPILATION & GIT HOOKS
# ------------------------------------------------------------------------------

echo "📜 Installing custom utility scripts to local bin..."
if [ -d "$SCRIPT_DIR/scripts" ]; then
  for script in "$SCRIPT_DIR/scripts"/*.sh; do
    if [ -f "$script" ]; then
      script_name=$(basename "$script" .sh)
      rm -f "$BIN_DIR/$script_name"
      cp "$script" "$BIN_DIR/$script_name"
      chmod +x "$BIN_DIR/$script_name"
      echo "   ✅ Installed: $script_name"
    fi
  done
fi

if [ "$INSTALL_APP" -eq 1 ] && [ -d "$SCRIPT_DIR/src" ]; then
  echo "📦 Compiling custom local tools from src/ (stripped)..."
  for tool_dir in "$SCRIPT_DIR/src"/*/; do
    if [ -d "$tool_dir" ]; then
      tool_name=$(basename "$tool_dir")
      echo "   ⚙️  Compiling $tool_name..."
      cd "$tool_dir" || continue

      if [ -f "go.mod" ]; then
        if [ "$tool_name" == "catalyst" ]; then
          env CGO_ENABLED=0 "$LOCAL_DIR/go/bin/go" build -ldflags="-s -w" -o "$BIN_DIR/ceph" .
          echo "   ✅ Installed: catalyst (as 'ceph')"
        else
          env CGO_ENABLED=0 "$LOCAL_DIR/go/bin/go" build -ldflags="-s -w" -o "$BIN_DIR/$tool_name" .
          echo "   ✅ Installed: $tool_name"
        fi
      fi
      cd "$SCRIPT_DIR" || exit
    fi
  done
fi

echo "🛡️  Configuring TruffleHog global Git hooks..."
if [ -f "$SCRIPT_DIR/scripts/hog-setup.sh" ]; then
  bash "$SCRIPT_DIR/scripts/hog-setup.sh"
fi

# ------------------------------------------------------------------------------
# 5. CONFIGURATIONS & ZSH INJECTIONS
# ------------------------------------------------------------------------------

if [ "$INSTALL_CONTAINERS" -eq 1 ]; then
  echo "🐳 Generating Smart Zero-Download Docker Wrappers..."
  cat <<'EOF' >"$BIN_DIR/docker"
#!/bin/bash
printf -v ESCAPED_ARGS "%q " "$@"
exec colima ssh -- bash -c "export DOCKER_CONTEXT=default DOCKER_HOST=unix:///var/run/docker.sock; docker $ESCAPED_ARGS"
EOF
  chmod +x "$BIN_DIR/docker"

  cat <<'EOF' >"$BIN_DIR/docker-compose"
#!/bin/bash
printf -v ESCAPED_ARGS "%q " "$@"
exec colima ssh -- bash -c "export DOCKER_CONTEXT=default DOCKER_HOST=unix:///var/run/docker.sock; docker compose $ESCAPED_ARGS"
EOF
  chmod +x "$BIN_DIR/docker-compose"

  SYS_RAM_GB=$(($(sysctl -n hw.memsize) / 1073741824))
  SYS_CPU_CORES=$(sysctl -n hw.ncpu)

  COLIMA_MEM=$((SYS_RAM_GB / 2))
  [ "$COLIMA_MEM" -lt 4 ] && COLIMA_MEM=4
  [ "$COLIMA_MEM" -gt 12 ] && COLIMA_MEM=12

  COLIMA_CPU=$((SYS_CPU_CORES / 2))
  [ "$COLIMA_CPU" -lt 2 ] && COLIMA_CPU=2
  [ "$COLIMA_CPU" -gt 6 ] && COLIMA_CPU=6

  mkdir -p "$HOME/.colima/default"
  cat <<EOF >"$HOME/.colima/default/colima.yaml"
cpu: ${COLIMA_CPU}
disk: 60
memory: ${COLIMA_MEM}
vmType: vz
rosetta: true
mountType: virtiofs
network:
  address: false
EOF
fi

echo "🔗 Checking shell PATH configuration..."
ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"
grep -q ".local/bin" "$ZSHRC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$ZSHRC"
grep -q ".local/node/bin" "$ZSHRC" || echo 'export PATH="$HOME/.local/node/bin:$PATH"' >>"$ZSHRC"
grep -q "PNPM_HOME" "$ZSHRC" || echo 'export PNPM_HOME="$HOME/.local/node/bin"' >>"$ZSHRC"
grep -q "go/bin" "$ZSHRC" || echo 'export PATH="$PATH:$HOME/go/bin"' >>"$ZSHRC"
grep -q "GOTOOLCHAIN=local" "$ZSHRC" || echo 'export GOTOOLCHAIN=local' >>"$ZSHRC"
if [ "$INSTALL_INFRA" -eq 1 ]; then
  grep -q "CLOUDSDK_PYTHON" "$ZSHRC" || echo 'export CLOUDSDK_PYTHON="$HOME/.local/bin/python3"' >>"$ZSHRC"
  grep -q "PYTHONDONTWRITEBYTECODE" "$ZSHRC" || echo 'export PYTHONDONTWRITEBYTECODE=1' >>"$ZSHRC"
fi

if [ "$INSTALL_GUI" -eq 1 ] && [ -f "$SCRIPT_DIR/configs/alacritty/alacritty.toml" ]; then
  echo "⚙️  Syncing Alacritty configuration from configs/alacritty/..."
  mkdir -p "$HOME/.config/alacritty"
  cp "$SCRIPT_DIR/configs/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
fi

if [ "$INSTALL_IDE" -eq 1 ] && [ -d "$SCRIPT_DIR/configs/nvim" ]; then
  echo "⚙️  Syncing Neovim configurations from configs/nvim/..."
  mkdir -p "$HOME/.config/nvim"
  if [ ! -f "$SCRIPT_DIR/configs/nvim/init.lua" ]; then
    printf '%s\n' '-- bootstrap lazy.nvim, LazyVim and your plugins' 'require("config.lazy")' >"$SCRIPT_DIR/configs/nvim/init.lua"
  fi
  cp -R "$SCRIPT_DIR/configs/nvim/"* "$HOME/.config/nvim/"

  if [ -f "$SCRIPT_DIR/lazy-lock.json" ] && [ ! -f "$SCRIPT_DIR/configs/nvim/lazy-lock.json" ]; then
    cp "$SCRIPT_DIR/lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"
    cp "$SCRIPT_DIR/lazy-lock.json" "$SCRIPT_DIR/configs/nvim/lazy-lock.json"
  fi

  echo "⚙️  Restoring pinned Neovim Plugins (from lazy-lock.json) and Parsers..."
  rm -rf "$LOCAL_DIR/share/nvim/mason" 2>/dev/null || true
  if [ -f "$HOME/.config/nvim/lazy-lock.json" ]; then
    nvim --headless "+Lazy! restore" +qa
  else
    nvim --headless "+Lazy! sync" +qa
    cp "$HOME/.config/nvim/lazy-lock.json" "$SCRIPT_DIR/configs/nvim/lazy-lock.json" 2>/dev/null || true
  fi
  TS_LUA="require('lazy').load({plugins={'nvim-treesitter'}}); require('nvim-treesitter.install').update({with_sync=true}); vim.cmd('qa')"
  nvim --headless -c "lua $TS_LUA"
fi

# ------------------------------------------------------------------------------
# 6. PORTABLE TARBALL PACKAGING (Triggered by --tarball)
# ------------------------------------------------------------------------------
if [ "$BUILD_TARBALL" -eq 1 ]; then
  DIST_DIR="$SCRIPT_DIR/dist"
  BUNDLE_NAME="substrate-${PROFILE}-darwin-arm64"
  STAGE_DIR="$DIST_DIR/$BUNDLE_NAME"
  TARBALL_FILE="${BUNDLE_NAME}.tar.xz"
  TARBALL_PATH="$DIST_DIR/$TARBALL_FILE"

  echo "=============================================================================="
  echo "📦 Staging portable bundle: $STAGE_DIR..."
  rm -rf "$STAGE_DIR" "${STAGE_DIR}.tar.gz" "$TARBALL_PATH"
  mkdir -p "$STAGE_DIR/local/bin" "$STAGE_DIR/configs" "$STAGE_DIR/scripts"

  # 1. Copy profile-specific runtime directories and binaries using 'cp -a' (preserves symlinks!)
  cp -a "$BIN_DIR/"* "$STAGE_DIR/local/bin/" 2>/dev/null || true
  cp -a "$RECEIPTS_FILE" "$STAGE_DIR/local/.ide_receipts" 2>/dev/null || true
  cp -a "$SCRIPT_DIR/versions.env" "$STAGE_DIR/local/versions.env"

  if [ "$INSTALL_APP" -eq 1 ]; then
    [ -d "$LOCAL_DIR/go" ] && cp -a "$LOCAL_DIR/go" "$STAGE_DIR/local/"
    [ -d "$LOCAL_DIR/node" ] && cp -a "$LOCAL_DIR/node" "$STAGE_DIR/local/"
    [ -d "$LOCAL_DIR/include" ] && cp -a "$LOCAL_DIR/include" "$STAGE_DIR/local/"
  fi
  if [ "$INSTALL_INFRA" -eq 1 ]; then
    [ -d "$LOCAL_DIR/python" ] && cp -a "$LOCAL_DIR/python" "$STAGE_DIR/local/"
    [ -d "$LOCAL_DIR/google-cloud-sdk" ] && cp -a "$LOCAL_DIR/google-cloud-sdk" "$STAGE_DIR/local/"
  fi
  if [ "$INSTALL_CONTAINERS" -eq 1 ]; then
    [ -d "$LOCAL_DIR/share/lima" ] && mkdir -p "$STAGE_DIR/local/share" && cp -a "$LOCAL_DIR/share/lima" "$STAGE_DIR/local/share/"
  fi
  if [ "$INSTALL_IDE" -eq 1 ]; then
    [ -d "$LOCAL_DIR/nvim-app" ] && cp -a "$LOCAL_DIR/nvim-app" "$STAGE_DIR/local/"
    if [ -d "$HOME/.config/nvim" ]; then
      cp -a "$HOME/.config/nvim" "$STAGE_DIR/configs/nvim"
      rm -rf "$STAGE_DIR/configs/nvim/.git"
    elif [ -d "$SCRIPT_DIR/configs/nvim" ]; then
      cp -a "$SCRIPT_DIR/configs/nvim" "$STAGE_DIR/configs/nvim"
    fi

    # Bundle pre-installed LazyVim plugins & compiled ARM64 Tree-sitter parsers for 100% air-gapped startup
    mkdir -p "$STAGE_DIR/local/share/nvim"
    [ -d "$LOCAL_DIR/share/nvim/lazy" ] && cp -a "$LOCAL_DIR/share/nvim/lazy" "$STAGE_DIR/local/share/nvim/"
    [ -d "$LOCAL_DIR/share/nvim/site" ] && cp -a "$LOCAL_DIR/share/nvim/site" "$STAGE_DIR/local/share/nvim/"

    # Strip .git history, C grammar sources, and tests from bundled Neovim plugins (~45MB saved)
    find "$STAGE_DIR/local/share/nvim" -type d \( -name ".git" -o -name ".github" -o -name "test" -o -name "tests" -o -name "spec" \) -prune -exec rm -rf {} + 2>/dev/null || true
    find "$STAGE_DIR/local/share/nvim" -type f \( -name "*.o" -o -name "*.a" -o -name "*.md" \) -delete 2>/dev/null || true
  fi
  if [ "$INSTALL_GUI" -eq 1 ]; then
    [ -d "$SCRIPT_DIR/configs/alacritty" ] && cp -a "$SCRIPT_DIR/configs/alacritty" "$STAGE_DIR/configs/"
    if [ -d "/Applications/Alacritty.app" ]; then
      mkdir -p "$STAGE_DIR/Applications"
      cp -a "/Applications/Alacritty.app" "$STAGE_DIR/Applications/"
    fi
    mkdir -p "$STAGE_DIR/fonts"
    for weight in Regular Bold Italic BoldItalic; do
      [ -f "$HOME/Library/Fonts/JetBrainsMonoNerdFont-${weight}.ttf" ] && cp -a "$HOME/Library/Fonts/JetBrainsMonoNerdFont-${weight}.ttf" "$STAGE_DIR/fonts/"
    done
  fi

  cp -a "$SCRIPT_DIR/versions.env" "$STAGE_DIR/versions.env"
  cp -a "$SCRIPT_DIR/scripts/"*.sh "$STAGE_DIR/scripts/" 2>/dev/null || true
  [ -f "$SCRIPT_DIR/chrome-settings.sh" ] && cp -a "$SCRIPT_DIR/chrome-settings.sh" "$STAGE_DIR/scripts/"

  # 2. Aggressive Dead-Weight & Builder-State Scrubber
  echo "🔪 Trimming dead weight & host state (tests, docs, headers, redundant binaries)..."

  # Remove tools from staged bin/ if their profile flag is disabled
  if [ "$INSTALL_INFRA" -eq 0 ]; then
    rm -f "$STAGE_DIR/local/bin/tofu" "$STAGE_DIR/local/bin/tofu-ls" "$STAGE_DIR/local/bin/terraform" "$STAGE_DIR/local/bin/terraform-ls" "$STAGE_DIR/local/bin/gcloud" "$STAGE_DIR/local/bin/python3"
  fi
  if [ "$INSTALL_CONTAINERS" -eq 0 ]; then
    rm -f "$STAGE_DIR/local/bin/colima" "$STAGE_DIR/local/bin/lima" "$STAGE_DIR/local/bin/limactl" "$STAGE_DIR/local/bin/docker" "$STAGE_DIR/local/bin/docker-compose"
  fi
  if [ "$INSTALL_IDE" -eq 0 ]; then
    rm -f "$STAGE_DIR/local/bin/nvim" "$STAGE_DIR/local/bin/lazygit" "$STAGE_DIR/local/bin/tree-sitter"
  fi

  # Go: Strip compiler test suites, docs, api specs, prebuilt pkg cache, and unused pprof/trace/tour tools
  if [ -d "$STAGE_DIR/local/go" ]; then
    rm -rf "$STAGE_DIR/local/go/test" \
      "$STAGE_DIR/local/go/doc" \
      "$STAGE_DIR/local/go/api" \
      "$STAGE_DIR/local/go/misc" \
      "$STAGE_DIR/local/go/pkg/obj" \
      "$STAGE_DIR/local/go/pkg/darwin_arm64"
    rm -f "$STAGE_DIR/local/go/pkg/tool/darwin_arm64/trace" \
      "$STAGE_DIR/local/go/pkg/tool/darwin_arm64/pprof" \
      "$STAGE_DIR/local/go/pkg/tool/darwin_arm64/tour" \
      "$STAGE_DIR/local/go/pkg/tool/darwin_arm64/covdata" \
      "$STAGE_DIR/local/go/pkg/tool/darwin_arm64/doc" 2>/dev/null || true
    find "$STAGE_DIR/local/go" -type d -name "testdata" -prune -exec rm -rf {} + 2>/dev/null || true
  fi

  # Node: Strip C++ headers, docs, corepack, bundled npm, host npmrc, sourcemaps, and unused cross-platform binaries
  if [ -d "$STAGE_DIR/local/node" ]; then
    rm -rf "$STAGE_DIR/local/node/include" \
      "$STAGE_DIR/local/node/share" \
      "$STAGE_DIR/local/node/etc" \
      "$STAGE_DIR/local/node/lib/node_modules/corepack" \
      "$STAGE_DIR/local/node/lib/node_modules/npm"
    rm -f "$STAGE_DIR/local/node/bin/npm" "$STAGE_DIR/local/node/bin/npx" "$STAGE_DIR/local/node/bin/corepack"
    rm -f "$STAGE_DIR/local/bin/npm" "$STAGE_DIR/local/bin/npx"
    find "$STAGE_DIR/local/node" -type d \( -name "test" -o -name "tests" -o -name "docs" \) -prune -exec rm -rf {} + 2>/dev/null || true
    find "$STAGE_DIR/local/node/lib/node_modules" -type f \( -name "*.map" -o -name "*.d.ts" -o -name "*.md" -o -name "*.exe" -o -name "*linux*" -o -name "*win32*" -o -name "*x64*" \) -delete 2>/dev/null || true
  fi

  # Python: Strip test suites, Tkinter/Idle GUI, pip/ensurepip wheels, config static libs, and pycache
  if [ -d "$STAGE_DIR/local/python" ]; then
    rm -rf "$STAGE_DIR/local/python/include" "$STAGE_DIR/local/python/share"
    find "$STAGE_DIR/local/python" -type d \( \
      -name "test" -o -name "tests" -o -name "idlelib" -o -name "turtledemo" \
      -name "tkinter" -o -name "ensurepip" -o -name "pip" -o -name "__pycache__" \
      -o -name "config-3.*" -o -name "lib2to3" -o -name "pydoc_data" \
      \) -prune -exec rm -rf {} + 2>/dev/null || true
    find "$STAGE_DIR/local/python" -type f \( -name "*.a" -o -name "*.pyc" -o -name "*.pyo" \) -delete 2>/dev/null || true
  fi

  # Gcloud: Strip anthoscli, bundled Python, bq, gsutil, host properties, alpha/beta generated API bloat, and tests
  if [ -d "$STAGE_DIR/local/google-cloud-sdk" ]; then
    rm -rf "$STAGE_DIR/local/google-cloud-sdk/platform/bundledpythonunix" \
      "$STAGE_DIR/local/google-cloud-sdk/platform/gsutil" \
      "$STAGE_DIR/local/google-cloud-sdk/platform/bq" \
      "$STAGE_DIR/local/google-cloud-sdk/platform/ext-runtime" \
      "$STAGE_DIR/local/google-cloud-sdk/.install" \
      "$STAGE_DIR/local/google-cloud-sdk/properties" \
      "$STAGE_DIR/local/google-cloud-sdk/help" \
      "$STAGE_DIR/local/google-cloud-sdk/deb" \
      "$STAGE_DIR/local/google-cloud-sdk/rpm" \
      "$STAGE_DIR/local/google-cloud-sdk/bin/anthoscli" \
      "$STAGE_DIR/local/google-cloud-sdk/bin/bq" \
      "$STAGE_DIR/local/google-cloud-sdk/bin/gsutil" \
      "$STAGE_DIR/local/google-cloud-sdk/bin/java_dev_appserver.sh" \
      "$STAGE_DIR/local/google-cloud-sdk/completion.bash.inc" \
      "$STAGE_DIR/local/google-cloud-sdk/completion.zsh.inc"
    find "$STAGE_DIR/local/google-cloud-sdk/lib/googlecloudsdk/generated_clients/apis" -mindepth 2 -maxdepth 2 -type d \( -name "v*alpha*" -o -name "v*beta*" \) -prune -exec rm -rf {} + 2>/dev/null || true
    find "$STAGE_DIR/local/google-cloud-sdk" -type d \( -name "tests" -o -name "test" -o -name "__pycache__" -o -name "doc" -o -name "docs" \) -prune -exec rm -rf {} + 2>/dev/null || true
    find "$STAGE_DIR/local/google-cloud-sdk" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete 2>/dev/null || true
  fi

  # Neovim: Strip unused language locale translations
  if [ -d "$STAGE_DIR/local/nvim-app" ]; then
    rm -rf "$STAGE_DIR/local/nvim-app/share/locale" "$STAGE_DIR/local/nvim-app/share/man"
  fi

  # Lima: Strip non-ARM64 guest agents
  if [ -d "$STAGE_DIR/local/share/lima" ]; then
    find "$STAGE_DIR/local/share/lima" -type f ! -name "*aarch64*" ! -name "*arm64*" -name "lima-guestagent*" -delete 2>/dev/null || true
  fi

  # Global pass: Strip manpages and docs across staged tree (excluding share/nvim runtime files)
  find "$STAGE_DIR/local/go" "$STAGE_DIR/local/node" "$STAGE_DIR/local/python" "$STAGE_DIR/local/google-cloud-sdk" -type d \( -name "man" -o -name "doc" -o -name "docs" \) -prune -exec rm -rf {} + 2>/dev/null || true

  # Strip DWARF (-S) and local (-x) debug symbols ONLY from unsigned/ad-hoc non-Go Mach-O binaries
  # Preserves official Apple Developer ID notarized signatures on upstream vendor binaries
  echo "🪄 Stripping debug symbol tables from unsigned/ad-hoc Mach-O binaries..."
  while IFS= read -r -d '' bin_file; do
    if [ ! -L "$bin_file" ] && file -b "$bin_file" 2>/dev/null | grep -Eq "Mach-O 64-bit (executable|dynamically linked shared library)"; then
      if ! "$LOCAL_DIR/go/bin/go" version "$bin_file" >/dev/null 2>&1; then
        if ! codesign -dv "$bin_file" 2>&1 | grep -q "Authority=Developer ID"; then
          chmod u+w "$bin_file" 2>/dev/null || true
          if strip -S -x "$bin_file" 2>/dev/null; then
            codesign --force --sign - "$bin_file" >/dev/null 2>&1 || true
          fi
        fi
      fi
    fi
  done < <(find "$STAGE_DIR/local" -type f -print0 2>/dev/null)

  # Print exact breakdown of staged directories before compressing
  echo "📊 Staged size breakdown before compression:"
  du -sh "$STAGE_DIR/local/"* "$STAGE_DIR/Applications" "$STAGE_DIR/fonts" 2>/dev/null | sort -hr | sed 's/^/   /'

  # 3. Generate self-contained turnkey offline installer inside the bundle
  cat <<'EOF' >"$STAGE_DIR/install.sh"
#!/bin/bash
set -euo pipefail
umask 077
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Clear macOS Gatekeeper quarantine attribute on the extracted bundle before copying
xattr -r -d com.apple.quarantine "$BUNDLE_DIR" 2>/dev/null || true

echo "🧹 Cleaning isolated Substrate runtime trees and legacy Mason bloat..."
chmod -R u+rwX "$HOME/.local/go" "$HOME/.config/nvim" "$HOME/.local/share/nvim" 2>/dev/null || true

# 1. Only wipe Substrate's private runtime directories (never wipe shared ~/.local/bin!)
rm -rf "$HOME/.local/go" \
       "$HOME/.local/node" \
       "$HOME/.local/python" \
       "$HOME/.local/google-cloud-sdk" \
       "$HOME/.local/nvim-app" \
       "$HOME/.local/include/google" \
       "$HOME/.local/share/lima" \
       "$HOME/.local/share/nvim/mason" \
       "$HOME/.local/share/nvim/lazy" \
       "$HOME/.local/share/nvim/site" \
       "$HOME/.cache/ide-bootstrap"

# 2. Surgically remove legacy stray files/symlinks in ~/.local/bin from older Substrate builds
rm -f "$HOME/.local/bin/npm" \
      "$HOME/.local/bin/npx" \
      "$HOME/.local/bin/CHANGELOG.md" \
      "$HOME/.local/bin/LICENSE" \
      "$HOME/.local/bin/README.md" 2>/dev/null || true

echo "🚀 Installing pre-compiled Substrate bundle into ~/.local..."
mkdir -p "$HOME/.local/bin"
cp -a "$BUNDLE_DIR/local/"* "$HOME/.local/"
[ -f "$BUNDLE_DIR/local/.ide_receipts" ] && cp -a "$BUNDLE_DIR/local/.ide_receipts" "$HOME/.local/.ide_receipts"

if [ -d "$BUNDLE_DIR/Applications/Alacritty.app" ]; then
  echo "🖥️  Installing Alacritty.app to /Applications..."
  rm -rf /Applications/Alacritty.app 2>/dev/null || sudo rm -rf /Applications/Alacritty.app
  cp -a "$BUNDLE_DIR/Applications/Alacritty.app" /Applications/
  xattr -r -d com.apple.quarantine /Applications/Alacritty.app 2>/dev/null || true
fi

if [ -d "$BUNDLE_DIR/fonts" ]; then
  echo "🔤 Installing JetBrainsMono Nerd Fonts (cleaning old weights)..."
  mkdir -p "$HOME/Library/Fonts"
  rm -f "$HOME/Library/Fonts/JetBrainsMono"*.ttf "$HOME/Library/Fonts/JetBrainsMono"*.otf 2>/dev/null || true
  cp -a "$BUNDLE_DIR/fonts/"*.ttf "$HOME/Library/Fonts/" 2>/dev/null || true
fi

if [ -d "$BUNDLE_DIR/configs/alacritty" ]; then
  mkdir -p "$HOME/.config/alacritty"
  cp -a "$BUNDLE_DIR/configs/alacritty/"* "$HOME/.config/alacritty/"
fi

if [ -d "$BUNDLE_DIR/configs/nvim" ]; then
  rm -rf "$HOME/.config/nvim"
  mkdir -p "$HOME/.config/nvim"
  cp -a "$BUNDLE_DIR/configs/nvim/"* "$HOME/.config/nvim/"
fi

# Lock Go and Gcloud settings on the target machine
if [ -x "$HOME/.local/go/bin/go" ]; then
  env GOPATH="$HOME/go" "$HOME/.local/go/bin/go" env -w GOTOOLCHAIN=local GOPROXY=https://proxy.golang.org,direct GOSUMDB=sum.golang.org
fi

if [ -x "$HOME/.local/bin/gcloud" ] && [ -x "$HOME/.local/bin/python3" ]; then
  env CLOUDSDK_PYTHON="$HOME/.local/bin/python3" PYTHONDONTWRITEBYTECODE=1 "$HOME/.local/bin/gcloud" config set component_manager/disable_update_check true --quiet 2>/dev/null || true
  env CLOUDSDK_PYTHON="$HOME/.local/bin/python3" PYTHONDONTWRITEBYTECODE=1 "$HOME/.local/bin/gcloud" config set core/disable_usage_reporting true --quiet 2>/dev/null || true
fi

if [ -x "$HOME/.local/bin/colima" ]; then
  SYS_RAM_GB=$(($(sysctl -n hw.memsize) / 1073741824))
  SYS_CPU_CORES=$(sysctl -n hw.ncpu)
  COLIMA_MEM=$((SYS_RAM_GB / 2)); [ "$COLIMA_MEM" -lt 4 ] && COLIMA_MEM=4; [ "$COLIMA_MEM" -gt 12 ] && COLIMA_MEM=12
  COLIMA_CPU=$((SYS_CPU_CORES / 2)); [ "$COLIMA_CPU" -lt 2 ] && COLIMA_CPU=2; [ "$COLIMA_CPU" -gt 6 ] && COLIMA_CPU=6
  mkdir -p "$HOME/.colima/default"
  cat <<COLIMA_EOF >"$HOME/.colima/default/colima.yaml"
cpu: ${COLIMA_CPU}
disk: 60
memory: ${COLIMA_MEM}
vmType: vz
rosetta: true
mountType: virtiofs
network:
  address: false
COLIMA_EOF
fi

if [ -f "$BUNDLE_DIR/scripts/hog-setup.sh" ]; then
  bash "$BUNDLE_DIR/scripts/hog-setup.sh"
fi

ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"
grep -q ".local/bin" "$ZSHRC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$ZSHRC"
grep -q ".local/node/bin" "$ZSHRC" || echo 'export PATH="$HOME/.local/node/bin:$PATH"' >>"$ZSHRC"
grep -q "PNPM_HOME" "$ZSHRC" || echo 'export PNPM_HOME="$HOME/.local/node/bin"' >>"$ZSHRC"
grep -q "go/bin" "$ZSHRC" || echo 'export PATH="$PATH:$HOME/go/bin"' >>"$ZSHRC"
grep -q "GOTOOLCHAIN=local" "$ZSHRC" || echo 'export GOTOOLCHAIN=local' >>"$ZSHRC"
if [ -x "$HOME/.local/bin/gcloud" ]; then
  grep -q "CLOUDSDK_PYTHON" "$ZSHRC" || echo 'export CLOUDSDK_PYTHON="$HOME/.local/bin/python3"' >>"$ZSHRC"
  grep -q "PYTHONDONTWRITEBYTECODE" "$ZSHRC" || echo 'export PYTHONDONTWRITEBYTECODE=1' >>"$ZSHRC"
fi

echo "✅ Offline Substrate bundle installed! Run 'source ~/.zshrc' to activate."
EOF
  chmod +x "$STAGE_DIR/install.sh"

  # 4. Compress using multi-threaded XZ (-T0 uses all Apple Silicon cores)
  echo "🗜️  Compressing streamlined archive with multi-threaded XZ..."
  STAGE_SIZE=$(du -sh "$STAGE_DIR" | cut -f1)
  echo "   📐 Total uncompressed staged size: $STAGE_SIZE"

  env XZ_OPT="-6 -T0" tar -cJf "$TARBALL_PATH" -C "$DIST_DIR" "$BUNDLE_NAME"
  rm -rf "$STAGE_DIR"
  (cd "$DIST_DIR" && shasum -a 256 "$TARBALL_FILE" >"${TARBALL_FILE}.sha256")

  TARBALL_SIZE=$(du -h "$TARBALL_PATH" | cut -f1)
  TARBALL_SHA=$(awk '{print $1}' "${TARBALL_PATH}.sha256")

  # 5. Generate dist/README.md with secure mktemp -d extraction commands
  cat <<EOF >"$DIST_DIR/README.md"
# Substrate Portable Bundle (${PROFILE})

- **Artifact:** \`${TARBALL_FILE}\` (${TARBALL_SIZE})
- **SHA256:** \`${TARBALL_SHA}\`

## Option 1: Install from Local File (IAP Portal Download / USB / AirDrop / SCP)

Run this in the directory containing \`${TARBALL_FILE}\` and \`${TARBALL_FILE}.sha256\`:

\`\`\`bash
shasum -a 256 -c ${TARBALL_FILE}.sha256 && \\
SUBSTRATE_TMP="\$(mktemp -d)" && \\
tar -xJf ${TARBALL_FILE} -C "\$SUBSTRATE_TMP" --strip-components=1 && \\
"\$SUBSTRATE_TMP/install.sh" && \\
rm -rf "\$SUBSTRATE_TMP" && \\
source ~/.zshrc
\`\`\`

## Option 2: Stream & Install from Cloud Storage (GCS via IAM)

\`\`\`bash
SUBSTRATE_TMP="\$(mktemp -d)" && \\
gcloud storage cp gs://YOUR_BUCKET/${TARBALL_FILE} - | tar -xJf - -C "\$SUBSTRATE_TMP" --strip-components=1 && \\
"\$SUBSTRATE_TMP/install.sh" && \\
rm -rf "\$SUBSTRATE_TMP" && \\
source ~/.zshrc
\`\`\`
EOF

  echo "✅ Streamlined Tarball created: $TARBALL_PATH ($TARBALL_SIZE)"
  echo "🔐 Checksum saved:              ${TARBALL_PATH}.sha256"
  echo "📖 Install instructions saved:  $DIST_DIR/README.md"

  # 6. Optional GCS Upload (Dormant until SUBSTRATE_BUCKET is set in versions.env or env)
  if [ -n "${SUBSTRATE_BUCKET:-}" ]; then
    echo "☁️  Uploading bundle and checksum to ${SUBSTRATE_BUCKET%/}/..."
    env CLOUDSDK_PYTHON="$BIN_DIR/python3" PYTHONDONTWRITEBYTECODE=1 \
      "$BIN_DIR/gcloud" storage cp \
      "$TARBALL_PATH" \
      "${TARBALL_PATH}.sha256" \
      "$DIST_DIR/README.md" \
      "$SCRIPT_DIR/versions.env" \
      "${SUBSTRATE_BUCKET%/}/"
    echo "✅ Published to ${SUBSTRATE_BUCKET%/}/${TARBALL_FILE}"
  else
    echo "ℹ️  Skipping GCS upload (set SUBSTRATE_BUCKET in versions.env when your bucket is ready)."
  fi
fi

echo "=============================================================================="
echo "🎉 Secure IDE environment ($PROFILE) is synced and ready!"
echo "=============================================================================="
echo "👉 Note: Run 'source ~/.zshrc' or restart your terminal to clear the old environment variables."
