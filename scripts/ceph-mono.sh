#!/bin/bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "❌ Error: Missing project name."
  echo "👉 Usage: ceph-mono <project-name> [target-directory]"
  exit 1
fi

PROJECT_NAME=$1
TARGET_DIR=${2:-$PROJECT_NAME}
WORKSPACE_DIRS="./api"

echo "🚀 Bootstrapping Zero-Trust Monorepo: $PROJECT_NAME in ./$TARGET_DIR..."
mkdir -p "$TARGET_DIR" && cd "$TARGET_DIR"

echo "📦 Initializing go.work..."
go work init
ceph -pattern contracts -name "${PROJECT_NAME}-api" -dir api >/dev/null

# 1. Interactive Database Prompt
echo ""
read -p "❓ Include a local PostgreSQL database (docker-compose)? (Y/n): " add_db
if [[ "$add_db" =~ ^[Yy]?$ ]]; then
  echo "🏗️  Scaffolding root workspace (docker-compose)..."
  ceph -pattern workspace -name "$PROJECT_NAME" -dir . >/dev/null
fi

# 2. Interactive Backend Prompt
echo ""
read -p "❓ Add a Core Backend API? (Y/n): " add_backend
if [[ "$add_backend" =~ ^[Yy]?$ ]]; then
  echo "⚙️  Scaffolding Backend..."
  ceph -pattern api -name "${PROJECT_NAME}-backend" -dir backend -contracts ../api >/dev/null
  cp backend/.env.example backend/.env 2>/dev/null || true
  WORKSPACE_DIRS="$WORKSPACE_DIRS ./backend"
fi

# 3. Interactive Frontend Prompt
echo ""
echo "❓ What kind of UI do you need?"
echo "   1) Internal Admin (IAP Protected)"
echo "   2) External Web (Publicly accessible)"
echo "   3) None"
read -p "Select (1-3) [1]: " ui_type
ui_type=${ui_type:-1}

if [ "$ui_type" = "1" ]; then
  echo "🖥️  Scaffolding Internal Admin UI..."
  ceph -pattern internal_admin -name "${PROJECT_NAME}-ui" -dir ui -contracts ../api >/dev/null
  cp ui/.env.example ui/.env 2>/dev/null || true
  WORKSPACE_DIRS="$WORKSPACE_DIRS ./ui"
elif [ "$ui_type" = "2" ]; then
  echo "🖥️  Scaffolding External Web UI..."
  ceph -pattern external_web -name "${PROJECT_NAME}-ui" -dir ui -contracts ../api >/dev/null
  cp ui/.env.example ui/.env 2>/dev/null || true
  WORKSPACE_DIRS="$WORKSPACE_DIRS ./ui"
fi

# 4. Finalize
echo ""
echo "🔗 Linking modules to Go workspace..."
# shellcheck disable=SC2086
go work use $WORKSPACE_DIRS

echo "========================================================"
echo "✅ Monorepo '$PROJECT_NAME' generated successfully!"
echo "========================================================"
