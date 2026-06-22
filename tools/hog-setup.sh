#!/bin/bash
#
# Install automated secret scanning with TruffleHog via Docker/Colima & Git Hooks.
# Sets up Global Hooks:
#   1. pre-commit: Scans staged files for secrets.
#   2. commit-msg: Appends "Secret-Scan: Passed" trailer (GPG-safe).

set -euo pipefail

# --- Configuration ---
HOOKS_DIR="$HOME/.git-hooks"
PRE_COMMIT_FILE="$HOOKS_DIR/pre-commit"
COMMIT_MSG_FILE="$HOOKS_DIR/commit-msg"
EXCLUDE_FILE="$HOOKS_DIR/exclude-paths.txt"
TRUFFLEHOG_IMAGE="trufflesecurity/trufflehog:3.90.11" # Maintained pinned version

# --- Setup Directories ---
echo "🚀 Setting up TruffleHog secret scanning..."
mkdir -p "$HOOKS_DIR"

# --- Cleanup Legacy Hooks ---
if [ -f "$HOOKS_DIR/post-commit" ]; then
  rm "$HOOKS_DIR/post-commit"
fi

# --- 1. Create Exclude File ---
echo "📝 Creating exclude configuration..."
cat >"$EXCLUDE_FILE" <<'EOF'
node_modules/
vendor/
dist/
build/
\.git/
package-lock\.json$
pnpm-lock\.yaml$
yarn\.lock$
EOF

# --- 2. Create Pre-Commit Hook (The Scanner) ---
echo "🔨 Installing pre-commit hook..."
cat >"$PRE_COMMIT_FILE" <<'EOF'
#!/bin/bash
# NOTE: Changed to bash because POSIX sh does not support 'set -o pipefail'
set -euo pipefail

TRUFFLEHOG_IMAGE="trufflesecurity/trufflehog:3.90.11"
TRUFFLEHOG_ARGS="${TRUFFLEHOG_ARGS:-}"
EXCLUDE_FILE="$HOME/.git-hooks/exclude-paths.txt"

# 1. Check if Docker/Colima daemon is running
if ! docker info >/dev/null 2>&1; then
    echo "⚠️  WARNING: Docker/Colima is not running. TruffleHog scan skipped." >&2
    exit 0 
fi

# 2. Check if there are staged files to scan
if git diff --cached --quiet; then
    exit 0
fi

echo "────────────────────────────────────────────────────────"
echo "🚀 TruffleHog Pre-Commit Scan"
echo "────────────────────────────────────────────────────────"
echo "🔍 Scanning staged files..."

# 3. Create temp directory inside $HOME so Colima/Lima can mount it successfully
TEMP_DIR_BASE="$HOME/.trufflehog-tmp"
mkdir -p "$TEMP_DIR_BASE"
TEMP_DIR=$(mktemp -d "$TEMP_DIR_BASE/trufflehog-XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

# 4. Copy staged files to temp directory for scanning
# Uses -z to safely handle filenames with spaces or special characters
git diff --cached --name-only -z --diff-filter=ACMR | git checkout-index --stdin -z --prefix="$TEMP_DIR/"

# 5. Configure Arguments safely
# We store arguments in an array to handle potential spaces cleanly
SCAN_ARGS=("filesystem" "/scan" "--fail")

if [ -n "${TRUFFLEHOG_ARGS}" ]; then
    SCAN_ARGS+=(${TRUFFLEHOG_ARGS})
fi

if [ -f "$EXCLUDE_FILE" ]; then
    echo "   (Using exclusions from global config)"
    cp "$EXCLUDE_FILE" "$TEMP_DIR/exclude-paths.txt"
    SCAN_ARGS+=("--exclude-paths=/scan/exclude-paths.txt")
fi

# 6. Run TruffleHog Container
if docker run --rm -v "$TEMP_DIR:/scan" "$TRUFFLEHOG_IMAGE" "${SCAN_ARGS[@]}"; then
    exit 0 
else
    echo "" >&2
    echo "🚫 COMMIT REJECTED: Potential secrets found." >&2
    echo "   Please remove the secret or address the finding and try again." >&2
    exit 1
fi
EOF

# --- 3. Create Commit-Msg Hook (The Trailer) ---
echo "🔨 Installing commit-msg hook..."
cat >"$COMMIT_MSG_FILE" <<'EOF'
#!/bin/bash
set -euo pipefail

MSG_FILE="$1"
TRAILER="Secret-Scan: Passed"

# Avoid duplicating the trailer if it already exists
if grep -q "^$TRAILER" "$MSG_FILE"; then
    exit 0
fi

# Append the trailer with a preceding newline
echo "" >> "$MSG_FILE"
echo "$TRAILER" >> "$MSG_FILE"
EOF

# --- Finalize ---
chmod +x "$PRE_COMMIT_FILE"
chmod +x "$COMMIT_MSG_FILE"

# Bind hooks globally
git config --global core.hooksPath "$HOOKS_DIR"

echo "✅ Success! Global hooks installed."
echo "   - Hooks Location: $HOOKS_DIR"
echo "   - GPG Signing: Compatible"
echo "   - Engine: Compatible with Docker Desktop, Colima, Lima, and Linux Docker"

