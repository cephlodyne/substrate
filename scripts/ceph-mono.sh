#!/bin/bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "❌ Error: Missing project name."
  echo "👉 Usage: ceph-mono <project-name> [target-directory]"
  exit 1
fi

PROJECT_NAME=$1
TARGET_DIR=${2:-$PROJECT_NAME}
WORKSPACE_DIRS=""

# ---------------------------------------------------------
# Global Registry Configuration
# ---------------------------------------------------------
if [ -z "${GOLDEN_REGISTRY:-}" ]; then
  echo "🌐 No GOLDEN_REGISTRY environment variable found."
  echo "   We need this to wire up your Docker Compose base images."
  read -p "❓ Enter your Registry URL [us-central1-docker.pkg.dev/YOUR_PROJECT/main-repo]: " input_registry

  # Use their input, or fallback to the generic placeholder string
  GOLDEN_REGISTRY=${input_registry:-"us-central1-docker.pkg.dev/YOUR_PROJECT/main-repo"}

  echo ""
  echo "💡 Tip: To skip this prompt on future projects, add this to your ~/.zshrc or ~/.bash_profile:"
  echo "   export GOLDEN_REGISTRY=\"$GOLDEN_REGISTRY\""
  echo "---------------------------------------------------------"
  echo ""
fi

echo "🚀 Bootstrapping Zero-Trust Monorepo: $PROJECT_NAME in ./$TARGET_DIR..."
mkdir -p "$TARGET_DIR" && cd "$TARGET_DIR"

echo "📦 Initializing go.work..."
go work init

# 1. Contracts Setup (Required for schema-first)
echo ""
read -p "❓ Directory name for Contracts API [contracts]: " DIR_CONTRACTS
DIR_CONTRACTS=${DIR_CONTRACTS:-contracts}
echo "📜 Scaffolding Contracts API..."
ceph -pattern contracts -name "${PROJECT_NAME}-contracts" -dir "$DIR_CONTRACTS" >/dev/null
WORKSPACE_DIRS="$WORKSPACE_DIRS ./$DIR_CONTRACTS"

# 2. Interactive Database Prompt
echo ""
read -p "❓ Include a local PostgreSQL database (docker-compose)? (Y/n): " add_db
if [[ "$add_db" =~ ^[Yy]?$ ]]; then
  echo "🏗️  Scaffolding root workspace (docker-compose)..."
  ceph -pattern workspace -name "$PROJECT_NAME" -dir . >/dev/null
fi

# 3. Interactive Backend Prompt
echo ""
read -p "❓ Add a Core Backend API? (Y/n): " add_backend
if [[ "$add_backend" =~ ^[Yy]?$ ]]; then
  read -p "   ↳ Directory name for Backend [backend]: " DIR_BACKEND
  DIR_BACKEND=${DIR_BACKEND:-backend}
  echo "⚙️  Scaffolding Backend..."
  ceph -pattern api -name "${PROJECT_NAME}-backend" -dir "$DIR_BACKEND" -contracts "../$DIR_CONTRACTS" >/dev/null
  cp "$DIR_BACKEND/.env.example" "$DIR_BACKEND/.env" 2>/dev/null || true
  WORKSPACE_DIRS="$WORKSPACE_DIRS ./$DIR_BACKEND"

  # Dynamically append to Docker Compose if it exists
  if [[ -f "docker-compose.yml" ]]; then
    cat <<EOF >>docker-compose.yml

  api:
    container_name: ${PROJECT_NAME}-backend
    build:
      context: ./${DIR_BACKEND}
      dockerfile: Dockerfile
      args:
        GO_IMAGE: ${GOLDEN_REGISTRY}/go:latest
    environment:
      - IS_CLOUD=false
      - IS_PROD=false
      - PORT=8080
      - DB_MAIN_DSN=postgres://${PROJECT_NAME}_sa:local-dev-password@postgres:5432/${PROJECT_NAME}_main?sslmode=disable
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
EOF
  fi
fi

# 4. Interactive Frontend Prompt
echo ""
echo "❓ What kind of UI do you need?"
echo "   1) Internal Admin (IAP Protected)"
echo "   2) External Web (Publicly accessible)"
echo "   3) None"
read -p "Select (1-3) [1]: " ui_type
ui_type=${ui_type:-1}

if [ "$ui_type" = "1" ] || [ "$ui_type" = "2" ]; then
  read -p "   ↳ Directory name for Frontend [frontend]: " DIR_FRONTEND
  DIR_FRONTEND=${DIR_FRONTEND:-frontend}

  if [ "$ui_type" = "1" ]; then
    echo "🖥️  Scaffolding Internal Admin UI..."
    ceph -pattern internal_admin -name "${PROJECT_NAME}-frontend" -dir "$DIR_FRONTEND" -contracts "../$DIR_CONTRACTS" >/dev/null
  elif [ "$ui_type" = "2" ]; then
    echo "🖥️  Scaffolding External Web UI..."
    ceph -pattern external_web -name "${PROJECT_NAME}-frontend" -dir "$DIR_FRONTEND" -contracts "../$DIR_CONTRACTS" >/dev/null
  fi

  cp "$DIR_FRONTEND/.env.example" "$DIR_FRONTEND/.env" 2>/dev/null || true
  WORKSPACE_DIRS="$WORKSPACE_DIRS ./$DIR_FRONTEND"

  # Dynamically append to Docker Compose if it exists
  if [[ -f "docker-compose.yml" ]]; then
    cat <<EOF >>docker-compose.yml

ui:
    container_name: ${PROJECT_NAME}-frontend
    build:
      context: ./${DIR_FRONTEND}
      dockerfile: Dockerfile
      args:
        NODE_IMAGE: ${GOLDEN_REGISTRY}/node:latest
        GO_IMAGE: ${GOLDEN_REGISTRY}/go:latest
        NPM_TOKEN: \${NPM_TOKEN}
    environment:
      - IS_CLOUD=false
      - IS_PROD=false
      - PORT=8081
    ports:
      - "8081:8081"
    depends_on:
      - api
EOF
  fi
fi

# 5. Finalize
echo ""
echo "🔗 Linking modules to Go workspace..."
# shellcheck disable=SC2086
go work use $WORKSPACE_DIRS

# ---------------------------------------------------------
# Auto-Generate Root Makefile & Initialize
# ---------------------------------------------------------
echo ""
echo "📝 Generating master workspace Makefile..."

cat <<EOF >Makefile
.PHONY: setup dev

setup:
EOF

# Only fetch the NPM GAR token if a UI is included
if [ "$ui_type" = "1" ] || [ "$ui_type" = "2" ]; then
  cat <<EOF >>Makefile
	@echo "🔑 Fetching GAR token for local development..."
	@echo "NPM_TOKEN=\$\$(gcloud auth print-access-token)" > .env
EOF
fi

cat <<EOF >>Makefile
	@for dir in $WORKSPACE_DIRS; do \\
		if [ -f "\$\$dir/Makefile" ]; then \\
			echo ""; \\
			echo "↳ Bootstrapping \$\$dir..."; \\
			\$(MAKE) -C \$\$dir setup || exit 1; \\
		fi; \\
	done

dev:
EOF

# Only refresh the GAR token on boot if a UI is included
if [ "$ui_type" = "1" ] || [ "$ui_type" = "2" ]; then
  cat <<EOF >>Makefile
	@echo "🔑 Refreshing GAR token..."
	@echo "NPM_TOKEN=\$\$(gcloud auth print-access-token)" > .env
EOF
fi

# Dynamically decide how to boot based on whether docker-compose exists
if [[ -f "docker-compose.yml" ]]; then
  cat <<EOF >>Makefile
	@echo "🐳 Booting local development environment..."
	@docker-compose build --pull
	@docker-compose up
EOF
else
  cat <<EOF >>Makefile
	@echo "🚀 Booting standalone backend..."
	@if [ -d "$DIR_BACKEND" ]; then \$(MAKE) -C $DIR_BACKEND dev; fi
EOF
fi

echo "⚙️  Initializing dependencies and generating RPC contracts..."
make setup

echo "========================================================"
echo "✅ Monorepo '$PROJECT_NAME' generated successfully!"
echo "👉 Simply run 'make dev' to boot the environment."
echo "========================================================"
