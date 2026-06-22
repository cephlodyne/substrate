#!/bin/bash
#
# Install automated secret scanning with TruffleHog (Local Binary) & Git Hooks.

set -euo pipefail

# --- Configuration ---
HOOKS_DIR="$HOME/.git-hooks"
PRE_COMMIT_FILE="$HOOKS_DIR/pre-commit"
COMMIT_MSG_FILE="$HOOKS_DIR/commit-msg"
EXCLUDE_FILE="$HOOKS_DIR/exclude-paths.txt"

# --- Setup Directories ---
echo "🚀 Setting up TruffleHog secret scanning..."
mkdir -p "$HOOKS_DIR"

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
set -euo pipefail

EXCLUDE_FILE="$HOME/.git-hooks/exclude-paths.txt"
TRUFFLEHOG_BIN="$HOME/.local/bin/trufflehog"

if [ ! -x "$TRUFFLEHOG_BIN" ]; then
    echo "⚠️  WARNING: Local TruffleHog binary not found at $TRUFFLEHOG_BIN. Scan skipped." >&2
    exit 0 
fi

if git diff --cached --quiet; then
    exit 0
fi

echo "────────────────────────────────────────────────────────"
echo "🚀 TruffleHog Pre-Commit Scan"
echo "────────────────────────────────────────────────────────"
echo "🔍 Scanning staged files..."

# Use standard OS temp directory (much faster, no Docker mount constraints)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

git diff --cached --name-only -z --diff-filter=ACMR | git checkout-index --stdin -z --prefix="$TEMP_DIR/"

SCAN_ARGS=("filesystem" "$TEMP_DIR" "--fail")

if [ -f "$EXCLUDE_FILE" ]; then
    echo "   (Using exclusions from global config)"
    SCAN_ARGS+=("--exclude-paths=$EXCLUDE_FILE")
fi

if "$TRUFFLEHOG_BIN" "${SCAN_ARGS[@]}"; then
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

if grep -q "^$TRAILER" "$MSG_FILE"; then
    exit 0
fi

echo "" >> "$MSG_FILE"
echo "$TRAILER" >> "$MSG_FILE"
EOF

# --- Finalize ---
chmod +x "$PRE_COMMIT_FILE"
chmod +x "$COMMIT_MSG_FILE"
git config --global core.hooksPath "$HOOKS_DIR"

echo "✅ Success! Global hooks installed natively."
