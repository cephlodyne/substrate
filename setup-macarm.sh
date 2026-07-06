#!/bin/bash
set -euo pipefail
# ==============================================================================
# ZERO-TRUST IDE BOOTSTRAP SCRIPT (macOS / Apple Silicon ARM64)
# SMART UPDATE MODE: Only installs/updates tools if version variables change.
# CONFIGURATION MODE: Enforces script defaults on every run (Overwrites local tweaks)
# ==============================================================================

# 🔒 Enforce strict permissions (Only owner can read/write/execute)
umask 077

echo "🛠️ Bootstrapping & Syncing macOS Zero-Trust Environment..."

# 🔥 Ensure Xcode CLI Tools (which includes Python 3 for gcloud) are installed FIRST
if ! xcode-select -p &>/dev/null; then
  echo "❌ Xcode Command Line Tools missing. This provides Python for gcloud and Git!"
  echo "👉 A popup should appear. Click 'Install', wait for it to finish, and run this script again."
  xcode-select --install
  exit 1
fi

# ==============================================================================
# 1. TOOL VERSIONS, URLS & SHAS (macOS ARM64)
# ==============================================================================

# --- Infrastructure & Virtualization ---

# Colima
# sha: https://github.com/abiosoft/colima/releases
COLIMA_VERSION="v0.10.3"
COLIMA_FILE="colima-Darwin-arm64"
COLIMA_URL="https://github.com/abiosoft/colima/releases/download/${COLIMA_VERSION}/${COLIMA_FILE}"
COLIMA_SHA="sha256:980ad8bf61a4ca370243f4cb41401a61276dcd2c2502bee7b9b86f9250169f34"

# Lima
# sha: https://github.com/lima-vm/lima/releases
LIMA_VERSION="v2.1.4"
LIMA_FILE="lima-${LIMA_VERSION#v}-Darwin-arm64.tar.gz"
LIMA_URL="https://github.com/lima-vm/lima/releases/download/${LIMA_VERSION}/${LIMA_FILE}"
LIMA_SHA="sha256:14c5b283f1c5eb4078e5a300b8d241f69197a3e41326dfc685a69c9455917acf"

# Google Cloud SDK
# look at the windows releases to see the version number
# sha: https://cloud.google.com/sdk/docs/downloads-versioned-archives
GCLOUD_VERSION="575.0"
GCLOUD_FILE="google-cloud-cli-darwin-arm.tar.gz"
GCLOUD_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${GCLOUD_FILE}"
GCLOUD_SHA="b4edcca2e5312748ecf6235197970ed0944a2a1318d8aa268a3e3314e7d302b3"

# Alacritty
# sha: https://github.com/alacritty/alacritty/releases
ALACRITTY_VERSION="v0.17.0"
ALACRITTY_FILE="Alacritty-${ALACRITTY_VERSION}.dmg"
ALACRITTY_URL="https://github.com/alacritty/alacritty/releases/download/${ALACRITTY_VERSION}/${ALACRITTY_FILE}"
ALACRITTY_SHA="sha256:ad8d7de35fb38e43184776cac6dfee05ca325caa0b6639a06a55e54e4b026620"

# JetBrains Mono Nerd Font
# sha: https://github.com/ryanoasis/nerd-fonts/releases
JB_MONO_VERSION="v3.4.0"
JB_MONO_FILE="JetBrainsMono.zip"
JB_MONO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${JB_MONO_VERSION}/${JB_MONO_FILE}"
JB_MONO_SHA="76f05ff3ace48a464a6ca57977998784ff7bdbb65a6d915d7e401cd3927c493c"

# --- Languages & Base Tools ---

# Go
# sha: https://go.dev/dl/
GO_VERSION="1.26.4"
GO_FILE="go${GO_VERSION}.darwin-arm64.tar.gz"
GO_URL="https://go.dev/dl/${GO_FILE}"
GO_SHA="b62ad2b6d7d2464f12a5bcad7ff47f19d08325773b5efd21610e445a05a9bf53"

# Node.js
NODE_VERSION="v24.18.0"
NODE_FILE="node-${NODE_VERSION}-darwin-arm64.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_FILE}"
NODE_SHA_SOURCE="https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt"

# Neovim
# sha: https://github.com/neovim/neovim/releases
NVIM_VERSION="v0.12.3"
NVIM_FILE="nvim-macos-arm64.tar.gz"
NVIM_URL="https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/${NVIM_FILE}"
NVIM_SHA="sha256:532da1d00e465a660fa01c3d4991333d09c52107dce7df937368545daca0a14e"

# --- CLI Utilities ---

# Ripgrep
# sha: https://github.com/BurntSushi/ripgrep/releases
RG_VERSION="15.1.0"
RG_FILE="ripgrep-$RG_VERSION-aarch64-apple-darwin.tar.gz"
RG_URL="https://github.com/BurntSushi/ripgrep/releases/download/$RG_VERSION/${RG_FILE}"
RG_SHA="sha256:378e973289176ca0c6054054ee7f631a065874a352bf43f0fa60ef079b6ba715"

# fd
# sha: https://github.com/sharkdp/fd/releases
FD_VERSION="v10.4.2"
FD_FILE="fd-$FD_VERSION-aarch64-apple-darwin.tar.gz"
FD_URL="https://github.com/sharkdp/fd/releases/download/$FD_VERSION/${FD_FILE}"
FD_SHA="sha256:623dc0afc81b92e4d4606b380d7bc91916ba7b97814263e554d50923a39e480a"

# Protoc (Protocol Buffers Compiler)
# sha: https://github.com/protocolbuffers/protobuf/releases
PROTOC_VERSION="35.1"
PROTOC_FILE="protoc-${PROTOC_VERSION}-osx-aarch_64.zip"
PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_FILE}"
PROTOC_SHA="sha256:193289af0470c6a1aada357d4fba0bbf8d78bfaac8b5e42ca30af2ef75583de2"

# Tree-sitter
# sha: https://github.com/tree-sitter/tree-sitter/releases
TS_VERSION="v0.26.10"
TS_FILE="tree-sitter-macos-arm64.gz"
TS_URL="https://github.com/tree-sitter/tree-sitter/releases/download/$TS_VERSION/${TS_FILE}"
TS_SHA="sha256:821a387182db59a1942a90a1fbd8f9756d9926e2c265f5c7b9a23c523114134a"

# TruffleHog
# sha: https://github.com/trufflesecurity/trufflehog/releases
TRUFFLEHOG_VERSION="3.95.8"
TRUFFLEHOG_FILE="trufflehog_${TRUFFLEHOG_VERSION}_darwin_arm64.tar.gz"
TRUFFLEHOG_URL="https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/${TRUFFLEHOG_FILE}"
TRUFFLEHOG_SHA="sha256:d6ed1f34499b97aae275e400a207c6f5d5c25b0626ddc464b82c104a719cd33b"

# Lazygit
# sha: https://github.com/jesseduffield/lazygit/releases
LAZYGIT_VERSION="v0.63.0"
LAZYGIT_FILE="lazygit_${LAZYGIT_VERSION#v}_darwin_arm64.tar.gz"
LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/$LAZYGIT_VERSION/${LAZYGIT_FILE}"
LAZYGIT_SHA="sha256:60e6bf29a1501a57a9d078538aa576a1b4db45779db2e3dd6931a7207f560a9c"

# Tofu
# sha: https://github.com/opentofu/opentofu/releases
TOFU_VERSION="1.12.3"
TOFU_FILE="tofu_${TOFU_VERSION}_darwin_arm64.zip"
TOFU_URL="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/${TOFU_FILE}"
TOFU_SHA="sha256:2b81c065cdcf5e573cfb5d9e0c663ac4cfc32512927078b645b58ef81cec2474"

# Open Tofu LS
# sha: https://github.com/opentofu/tofu-ls/releases
TOFULS_VERSION="0.5.2"
TOFULS_FILE="tofu-ls_Darwin_arm64.tar.gz"
TOFULS_URL="https://github.com/opentofu/tofu-ls/releases/download/v${TOFULS_VERSION}/${TOFULS_FILE}"
TOFULS_SHA="sha256:935852b3a3264d3a9ae6192c309beefe2de58b4fe2d4cceb19c110f6b82b9f60"

# --- Global Packages (Pinned for Zero-Trust Updates) ---

GOPLS_VERSION="v0.22.0"
GOIMPORTS_VERSION="v0.47.0"
PNPM_VERSION="11.10.0"
BIOME_VERSION="2.5.2"

# ==============================================================================
# Paths & Ledger Setup
# ==============================================================================
CACHE_DIR="$HOME/.cache/ide-bootstrap"
LOCAL_DIR="$HOME/.local"
BIN_DIR="$LOCAL_DIR/bin"
NVIM_APP_DIR="$LOCAL_DIR/nvim-app"
GCLOUD_DIR="$LOCAL_DIR/google-cloud-sdk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECEIPTS_FILE="$LOCAL_DIR/.ide_receipts"

mkdir -p "$BIN_DIR" "$CACHE_DIR" "$NVIM_APP_DIR"
touch "$RECEIPTS_FILE"
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
    return 1 # False: Does not need update
  else
    echo "🔄 Updating $tool to $target_version..."
    return 0 # True: Needs update
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
    # 🔒 Enforce HTTPS and TLS 1.2+
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

  # 🧹 Sanitize the expected SHA
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
# 3. SMART INSTALL / UPDATE BLOCKS
# ------------------------------------------------------------------------------

if needs_update "Colima" "$COLIMA_VERSION"; then
  fetch_and_verify "Colima" "$COLIMA_URL" "$COLIMA_FILE" "colima" "$COLIMA_SHA"
  cp "$CACHE_DIR/colima" "$BIN_DIR/colima" && chmod +x "$BIN_DIR/colima"
  xattr -r -d com.apple.quarantine "$BIN_DIR/colima" 2>/dev/null || true
  echo "🖋️  Cryptographic check passed. Signing binary for Apple Silicon execution..."
  codesign --force --deep --sign - "$BIN_DIR/colima"
  mark_updated "Colima" "$COLIMA_VERSION"
fi

if needs_update "Lima" "$LIMA_VERSION"; then
  fetch_and_verify "Lima" "$LIMA_URL" "$LIMA_FILE" "lima.tar.gz" "$LIMA_SHA"
  tar -xzf "$CACHE_DIR/lima.tar.gz" -C "$LOCAL_DIR" bin/lima bin/limactl share/lima
  xattr -r -d com.apple.quarantine "$BIN_DIR/lima" "$BIN_DIR/limactl" 2>/dev/null || true
  mark_updated "Lima" "$LIMA_VERSION"
fi

if needs_update "Gcloud" "$GCLOUD_VERSION"; then
  fetch_and_verify "Google Cloud SDK" "$GCLOUD_URL" "$GCLOUD_FILE" "gcloud.tar.gz" "$GCLOUD_SHA"
  rm -rf "$GCLOUD_DIR" && tar -xzf "$CACHE_DIR/gcloud.tar.gz" -C "$LOCAL_DIR"

  echo "📦 Bootstrapping gcloud (Fetching isolated Python 3.10+)..."
  # Run installer headlessly to fetch Google's bundled Python without modifying user dotfiles
  env CLOUDSDK_CORE_DISABLE_PROMPTS=1 "$GCLOUD_DIR/install.sh" --quiet --path-update=false --command-completion=false

  ln -sf "$GCLOUD_DIR/bin/gcloud" "$BIN_DIR/gcloud"
  xattr -r -d com.apple.quarantine "$GCLOUD_DIR" 2>/dev/null || true

  echo "🔒 Disabling gcloud internal updaters to prevent version drift..."
  "$BIN_DIR/gcloud" config set component_manager/disable_update_check true --quiet || true
  "$BIN_DIR/gcloud" config set core/disable_usage_reporting true --quiet || true

  mark_updated "Gcloud" "$GCLOUD_VERSION"
fi

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
  cp "$CACHE_DIR/jb-mono/"*.ttf "$HOME/Library/Fonts/"
  mark_updated "JetBrainsMono" "$JB_MONO_VERSION"
fi

if needs_update "Go" "$GO_VERSION"; then
  fetch_and_verify "Go" "$GO_URL" "$GO_FILE" "go.tar.gz" "$GO_SHA"
  rm -rf "$LOCAL_DIR/go" && tar -xzf "$CACHE_DIR/go.tar.gz" -C "$LOCAL_DIR"
  ln -sf "$LOCAL_DIR/go/bin/go" "$BIN_DIR/go"
  xattr -r -d com.apple.quarantine "$LOCAL_DIR/go" 2>/dev/null || true
  echo "🔒 Locking Go environment (No auto-updates, strict proxy, strict checksums)..."
  env GOPATH="$HOME/go" "$LOCAL_DIR/go/bin/go" env -w GOTOOLCHAIN=local GOPROXY=https://proxy.golang.org,direct GOSUMDB=sum.golang.org
  mark_updated "Go" "$GO_VERSION"
fi

if needs_update "Node" "$NODE_VERSION"; then
  fetch_and_verify "Node.js" "$NODE_URL" "$NODE_FILE" "node.tar.xz" "$NODE_SHA_SOURCE"
  rm -rf "$LOCAL_DIR/node" && mkdir -p "$LOCAL_DIR/node"
  tar -xf "$CACHE_DIR/node.tar.xz" -C "$LOCAL_DIR/node" --strip-components=1
  ln -sf "$LOCAL_DIR/node/bin/node" "$BIN_DIR/node"
  ln -sf "$LOCAL_DIR/node/bin/npm" "$BIN_DIR/npm"
  ln -sf "$LOCAL_DIR/node/bin/npx" "$BIN_DIR/npx"
  xattr -r -d com.apple.quarantine "$LOCAL_DIR/node" 2>/dev/null || true
  echo "🔒 Disabling NPM lifecycle scripts to prevent malicious post-install execution..."
  "$BIN_DIR/npm" config set ignore-scripts true --global
  mark_updated "Node" "$NODE_VERSION"
fi

if needs_update "NPM_Packages" "${PNPM_VERSION}_${BIOME_VERSION}"; then
  echo "📦 Installing Biome and pnpm securely via verified NPM binary..."
  "$BIN_DIR/npm" install -g "pnpm@${PNPM_VERSION}" "@biomejs/biome@${BIOME_VERSION}"
  ln -sf "$LOCAL_DIR/node/bin/pnpm" "$BIN_DIR/pnpm"
  ln -sf "$LOCAL_DIR/node/bin/pnpx" "$BIN_DIR/pnpx"
  mark_updated "NPM_Packages" "${PNPM_VERSION}_${BIOME_VERSION}"
fi

if needs_update "Neovim" "$NVIM_VERSION"; then
  fetch_and_verify "Neovim" "$NVIM_URL" "$NVIM_FILE" "nvim.tar.gz" "$NVIM_SHA"
  rm -rf "$NVIM_APP_DIR" && mkdir -p "$NVIM_APP_DIR"
  tar -xzf "$CACHE_DIR/nvim.tar.gz" -C "$NVIM_APP_DIR" --strip-components=1
  ln -sf "$NVIM_APP_DIR/bin/nvim" "$BIN_DIR/nvim"
  xattr -r -d com.apple.quarantine "$NVIM_APP_DIR" 2>/dev/null || true
  mark_updated "Neovim" "$NVIM_VERSION"
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

  # 1. Install the binary
  mv "$CACHE_DIR/protoc/bin/protoc" "$BIN_DIR/protoc"
  chmod +x "$BIN_DIR/protoc"
  xattr -r -d com.apple.quarantine "$BIN_DIR/protoc" 2>/dev/null || true

  # 2. Install the standard Protobuf includes (Required for descriptor.proto)
  # protoc automatically looks in ../include relative to its binary location
  mkdir -p "$LOCAL_DIR/include"
  cp -R "$CACHE_DIR/protoc/include/" "$LOCAL_DIR/include/"

  mark_updated "Protoc" "$PROTOC_VERSION"
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

if needs_update "TruffleHog" "$TRUFFLEHOG_VERSION"; then
  fetch_and_verify "TruffleHog" "$TRUFFLEHOG_URL" "$TRUFFLEHOG_FILE" "trufflehog.tar.gz" "$TRUFFLEHOG_SHA"
  tar -xzf "$CACHE_DIR/trufflehog.tar.gz" -C "$CACHE_DIR"
  mv "$CACHE_DIR/trufflehog" "$BIN_DIR/trufflehog"
  xattr -r -d com.apple.quarantine "$BIN_DIR/trufflehog" 2>/dev/null || true
  mark_updated "TruffleHog" "$TRUFFLEHOG_VERSION"
fi

if needs_update "OpenTofu" "${TOFU_VERSION}_${TOFULS_VERSION}"; then
  fetch_and_verify "OpenTofu" "$TOFU_URL" "$TOFU_FILE" "tofu.zip" "$TOFU_SHA"
  fetch_and_verify "OpenTofu LS" "$TOFULS_URL" "$TOFULS_FILE" "tofu-ls.tar.gz" "$TOFULS_SHA"
  unzip -q -o "$CACHE_DIR/tofu.zip" -d "$BIN_DIR"
  tar -xzf "$CACHE_DIR/tofu-ls.tar.gz" -C "$BIN_DIR"
  ln -sf "$BIN_DIR/tofu" "$BIN_DIR/terraform"
  ln -sf "$BIN_DIR/tofu-ls" "$BIN_DIR/terraform-ls"
  xattr -r -d com.apple.quarantine "$BIN_DIR/tofu" "$BIN_DIR/tofu-ls" 2>/dev/null || true
  mark_updated "OpenTofu" "${TOFU_VERSION}_${TOFULS_VERSION}"
fi

if needs_update "Gopls" "$GOPLS_VERSION"; then
  echo "📦 Compiling gopls securely (CGO disabled, strictly proxied)..."
  env CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org "$LOCAL_DIR/go/bin/go" install "golang.org/x/tools/gopls@${GOPLS_VERSION}"
  mark_updated "Gopls" "$GOPLS_VERSION"
fi

if needs_update "Goimports" "$GOIMPORTS_VERSION"; then
  echo "📦 Compiling goimports securely (CGO disabled, strictly proxied)..."
  env CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org "$LOCAL_DIR/go/bin/go" install "golang.org/x/tools/cmd/goimports@${GOIMPORTS_VERSION}"
  mark_updated "Goimports" "$GOIMPORTS_VERSION"
fi

echo "🧹 Cleaning up raw downloaded archives..."
rm -rf "$CACHE_DIR"/*

# ------------------------------------------------------------------------------
# 4. UTILITY SCRIPTS, COMPILATION & GIT HOOKS
# ------------------------------------------------------------------------------

echo "📜 Linking custom utility scripts to local bin..."
if [ -d "$SCRIPT_DIR/scripts" ]; then
  for script in "$SCRIPT_DIR/scripts"/*.sh; do
    if [ -f "$script" ]; then
      script_name=$(basename "$script" .sh)
      chmod +x "$script"
      ln -sf "$script" "$BIN_DIR/$script_name"
      echo "   ✅ Linked: $script_name"
    fi
  done
fi

echo "📦 Compiling custom local tools from src/..."
if [ -d "$SCRIPT_DIR/src" ]; then
  for tool_dir in "$SCRIPT_DIR/src"/*/; do
    if [ -d "$tool_dir" ]; then
      tool_name=$(basename "$tool_dir")
      echo "   ⚙️  Compiling $tool_name..."
      cd "$tool_dir" || continue

      # Auto-detect Go modules and compile securely using our local Go binary
      if [ -f "go.mod" ]; then
        env CGO_ENABLED=0 "$LOCAL_DIR/go/bin/go" build -o "$BIN_DIR/$tool_name" .
        echo "   ✅ Installed: $tool_name"
      else
        echo "   ⏭️  Skipped: $tool_name (No go.mod found)"
      fi
      cd "$CACHE_DIR" || exit
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

echo "🐳 Generating Smart Zero-Download Docker Wrappers..."

# Create a bridge for 'docker' that isolates VM context
cat <<'EOF' >"$BIN_DIR/docker"
#!/bin/bash
printf -v ESCAPED_ARGS "%q " "$@"
exec colima ssh -- bash -c "export DOCKER_CONTEXT=default DOCKER_HOST=unix:///var/run/docker.sock; docker $ESCAPED_ARGS"
EOF
chmod +x "$BIN_DIR/docker"

# Create a bridge for 'docker-compose'
cat <<'EOF' >"$BIN_DIR/docker-compose"
#!/bin/bash
printf -v ESCAPED_ARGS "%q " "$@"
exec colima ssh -- bash -c "export DOCKER_CONTEXT=default DOCKER_HOST=unix:///var/run/docker.sock; docker compose $ESCAPED_ARGS"
EOF
chmod +x "$BIN_DIR/docker-compose"

echo "⚠️  NOTE: Docker is running entirely inside a VM via SSH wrappers."
echo "⚠️  NOTE: Docker is running entirely inside a VM via SSH wrappers."
echo "   - Volume mounts (-v) will only work for paths within /Users."
echo "   - To mount paths outside /Users, run: colima start --edit"

echo "⚙️  Detecting system hardware for optimal Colima allocation..."
# Get total RAM in GB and logical CPU cores
SYS_RAM_GB=$(($(sysctl -n hw.memsize) / 1073741824))
SYS_CPU_CORES=$(sysctl -n hw.ncpu)

# Smart allocation:
# - RAM: ~25-30% of total system RAM, minimum 2GB, max 8GB.
# - CPU: Half of available cores, minimum 2, max 4.
COLIMA_MEM=$((SYS_RAM_GB / 4))
[ "$COLIMA_MEM" -lt 2 ] && COLIMA_MEM=2
[ "$COLIMA_MEM" -gt 8 ] && COLIMA_MEM=8

COLIMA_CPU=$((SYS_CPU_CORES / 2))
[ "$COLIMA_CPU" -lt 2 ] && COLIMA_CPU=2
[ "$COLIMA_CPU" -gt 4 ] && COLIMA_CPU=4

echo "   👉 Host has ${SYS_RAM_GB}GB RAM and ${SYS_CPU_CORES} CPUs."
echo "   👉 Allocating ${COLIMA_MEM}GB RAM and ${COLIMA_CPU} CPUs to Colima."

mkdir -p "$HOME/.colima/default"
cat <<EOF >"$HOME/.colima/default/colima.yaml"
# Dynamic Hardware Limits
cpu: ${COLIMA_CPU}
disk: 60
memory: ${COLIMA_MEM}

# Apple Silicon Optimizations (Stops corruption, networking loops, and CPU spikes)
vmType: vz
rosetta: true
mountType: virtiofs

# Network Security
network:
  address: false # Disables reachable IP bridge; relies entirely on strict localhost port forwarding
EOF

echo "🔗 Checking shell PATH configuration..."
ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"
grep -q ".local/bin" "$ZSHRC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$ZSHRC"
grep -q ".local/node/bin" "$ZSHRC" || echo 'export PATH="$HOME/.local/node/bin:$PATH"' >>"$ZSHRC"
grep -q "go/bin" "$ZSHRC" || echo 'export PATH="$PATH:$HOME/go/bin"' >>"$ZSHRC"

# prevent go from automatically installing new versions
echo 'export GOTOOLCHAIN=local' >>~/.zshrc

# Clone the LazyVim base repo ONLY if it doesn't exist
if [ ! -d "$HOME/.config/nvim" ]; then
  if ! xcode-select -p &>/dev/null; then
    echo "❌ Xcode Command Line Tools missing. Run 'xcode-select --install' and try again."
    exit 1
  fi

  echo "✨ Bootstrapping LazyVim base repo..."
  git clone https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git

  # Inject lazy-lock.json if it exists alongside the script
  if [ -f "$SCRIPT_DIR/lazy-lock.json" ]; then
    cp "$SCRIPT_DIR/lazy-lock.json" ~/.config/nvim/lazy-lock.json
  fi
fi

# ==============================================================================
# ENFORCED DEFAULTS: The following files are overwritten on EVERY run.
# ==============================================================================
echo "⚙️  Enforcing Alacritty & Neovim configuration defaults..."

mkdir -p ~/.config/alacritty
cat <<EOF >~/.config/alacritty/alacritty.toml
[window]
dimensions = { columns = 120, lines = 35 }
padding = { x = 12, y = 12 }
opacity = 0.95
option_as_alt = "Both"
dynamic_title = true
[font]
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
bold = { family = "JetBrainsMono Nerd Font", style = "Bold" }
italic = { family = "JetBrainsMono Nerd Font", style = "Italic" }
size = 18.0
[keyboard]
bindings = [{ key = "N", mods = "Command", action = "CreateNewWindow" }]
[colors.primary]
background = "#1a1b26"
foreground = "#c0caf5"
EOF

mkdir -p ~/.config/nvim/lua/plugins ~/.config/nvim/lua/config

cat <<'EOF' >~/.config/nvim/lua/config/lazy.lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "lazyvim.plugins.extras.lang.go" },
    { import = "lazyvim.plugins.extras.lang.markdown" },
    { import = "lazyvim.plugins.extras.lang.svelte" },
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  install = { colorscheme = { "tokyonight" } },
})
EOF

echo "⚙️  Configuring Neovim options..."
cat <<'EOF' >~/.config/nvim/lua/config/options.lua
-- Disable swap files completely to prevent E325 errors
vim.opt.swapfile = false

-- Broadcast the current file/project to the Alacritty window title
vim.opt.title = true
EOF

cat <<'EOF' >~/.config/nvim/lua/plugins/treesitter.lua
return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    if type(opts.ensure_installed) == "table" then
      vim.list_extend(opts.ensure_installed, { 
        "css", "html", "javascript", "typescript", "json",
        "go", "gomod", "gowork", "gosum", 
        "terraform", "hcl",
        "svelte"
      })
    end

    -- FIX: Disable Tree-sitter highlighting for Terraform/HCL to prevent UI freezes
    -- on complex Heredoc string interpolations. Falls back to standard regex highlighting.
    opts.highlight = opts.highlight or {}
    local prev_disable = opts.highlight.disable
    opts.highlight.disable = function(lang, buf)
      if lang == "terraform" or lang == "hcl" then
        return true
      end
      if type(prev_disable) == "function" then
        return prev_disable(lang, buf)
      elseif type(prev_disable) == "table" then
        for _, disabled_lang in ipairs(prev_disable) do
          if lang == disabled_lang then return true end
        end
      end
      return false
    end
  end,
}
EOF

cat <<'EOF' >~/.config/nvim/lua/plugins/lsp.lua
return {
  "neovim/nvim-lspconfig",
  opts = { 
    servers = { 
      biome = {}, 
      gopls = {}, 
      svelte = {},
      terraformls = {
        -- Force Neovim to use the tofu-ls binary symlinked in ~/.local/bin
        cmd = { "terraform-ls", "serve" },
        filetypes = { "terraform", "terraform-vars", "hcl" },
      }
    },
    setup = {
      terraformls = function()
        -- Return true to completely bypass Mason for this LSP
        return true
      end,
    }
  }
}
EOF

cat <<'EOF' >~/.config/nvim/lua/plugins/formatting.lua
return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      go = { "goimports", "gofmt" },
      terraform = { "terraform_fmt" },
      tf = { "terraform_fmt" },
      ["terraform-vars"] = { "terraform_fmt" },
      javascript = { "biome" },
      typescript = { "biome" },
      javascriptreact = { "biome" },
      typescriptreact = { "biome" },
      css = { "biome" },
      json = { "biome" },
    },
  },
}
EOF

cat <<'EOF' >~/.config/nvim/lua/plugins/theme.lua
return {
  { "folke/tokyonight.nvim", lazy = false, priority = 1000, opts = { style = "night" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight" } },
}
EOF

echo "⚙️  Disabling smooth scrolling animations..."
cat <<'EOF' >~/.config/nvim/lua/plugins/ui.lua
return {
  -- Disable mini.animate (used in older LazyVim versions)
  { "nvim-mini/mini.animate", enabled = false },
  
  -- Disable Snacks smooth scroll (used in newer LazyVim versions)
  {
    "folke/snacks.nvim",
    opts = {
      scroll = { enabled = false },
    }
  }
}
EOF

echo "⌨️  Injecting 'jk' escape shortcut into Neovim..."
cat <<'EOF' >~/.config/nvim/lua/config/keymaps.lua
-- Press jk fast to exit insert mode 
vim.keymap.set("i", "jk", "<esc>", { desc = "Exit insert mode" })
EOF

echo "⚙️  Injecting safety overrides for Terraform files..."
cat <<'EOF' >~/.config/nvim/lua/config/autocmds.lua
-- Disable aggressive visual scanners for Terraform/HCL files to prevent lockups on complex Heredocs
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "terraform", "terraform-vars", "hcl" },
  callback = function()
    vim.b.miniindentscope_disable = true
    vim.cmd("NoMatchParen")
  end,
})
EOF

# ------------------------------------------------------------------------------
# 6. HEADLESS PLUGIN SYNC
# ------------------------------------------------------------------------------
echo "⚙️  Syncing Neovim Plugins and Parsers..."
export PATH="$BIN_DIR:$HOME/.local/node/bin:$PATH"

nvim --headless "+Lazy! sync" +qa
TS_LUA="require('lazy').load({plugins={'nvim-treesitter'}}); require('nvim-treesitter.install').update({with_sync=true}); vim.cmd('qa')"
nvim --headless -c "lua $TS_LUA"

echo "=============================================================================="
echo "🎉 Secure IDE environment is synced and ready!"
echo "=============================================================================="
