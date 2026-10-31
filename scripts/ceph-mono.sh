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

if [ -z "${NPM_REGISTRY:-}" ]; then
  read -p "❓ Enter your NPM Registry URL [https://us-central1-npm.pkg.dev/YOUR_PROJECT/golden-npm-store/]: " input_npm
  NPM_REGISTRY=${input_npm:-"https://us-central1-npm.pkg.dev/YOUR_PROJECT/golden-npm-store/"}

  echo ""
  echo "💡 Tip: To skip this prompt on future projects, add this to your ~/.zshrc or ~/.bash_profile:"
  echo "   export NPM_REGISTRY=\"$NPM_REGISTRY\""
  echo "---------------------------------------------------------"
  echo ""
fi

# Ensure trailing slash and extract auth host path
[[ "$NPM_REGISTRY" != */ ]] && NPM_REGISTRY="${NPM_REGISTRY}/"
NPM_AUTH_HOST="${NPM_REGISTRY#https:}"

# Pre-authenticate npm and pnpm before invoking ceph so dynamic version lookups against GAR succeed
if [[ "$NPM_REGISTRY" != *"YOUR_PROJECT"* ]]; then
  if TOKEN=$(gcloud auth print-access-token 2>/dev/null); then
    npm config set "${NPM_AUTH_HOST}:_authToken" "$TOKEN" --location=user
    pnpm config set "${NPM_AUTH_HOST}:_authToken" "$TOKEN" --location=global
  fi
fi

echo "🚀 Bootstrapping Zero-Trust Monorepo: $PROJECT_NAME in ./$TARGET_DIR..."
mkdir -p "$TARGET_DIR" && cd "$TARGET_DIR"

echo "📦 Initializing go.work..."
go work init

# 1. Contracts Setup
echo ""
read -p "❓ Include a ConnectRPC Contracts API? (Y/n): " add_contracts
if [[ "$add_contracts" =~ ^[Yy]?$ ]]; then
  read -p "   ↳ Directory name for Contracts API [contracts]: " DIR_CONTRACTS
  DIR_CONTRACTS=${DIR_CONTRACTS:-contracts}
  echo "📜 Scaffolding Contracts API..."
  ceph -pattern contracts -name "${PROJECT_NAME}-contracts" -dir "$DIR_CONTRACTS" >/dev/null
  WORKSPACE_DIRS="$WORKSPACE_DIRS ./$DIR_CONTRACTS"
  RPC_FLAG=""
else
  DIR_CONTRACTS="none"
  RPC_FLAG="--no-rpc"
fi

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
  ceph -pattern api -name "${PROJECT_NAME}-backend" -dir "$DIR_BACKEND" -contracts "../$DIR_CONTRACTS" -npm-registry "$NPM_REGISTRY" $RPC_FLAG >/dev/null
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
echo "   1) Internal Admin (Svelte, IAP Protected)"
echo "   2) External Web (Svelte, Public)"
echo "   3) Internal Admin (SolidJS, IAP Protected)"
echo "   4) External Web (SolidJS, Public)"
echo "   5) None"
read -p "Select (1-5) [3]: " ui_type
ui_type=${ui_type:-3}

if [[ "$ui_type" =~ ^[1-4]$ ]]; then
  read -p "   ↳ Directory name for Web App [web]: " DIR_FRONTEND
  DIR_FRONTEND=${DIR_FRONTEND:-web}

  if [ "$ui_type" = "1" ]; then
    echo "🖥️  Scaffolding Internal Admin UI (Svelte)..."
    ceph -pattern internal_admin -name "${PROJECT_NAME}-frontend" -dir "$DIR_FRONTEND" -contracts "../$DIR_CONTRACTS" -npm-registry "$NPM_REGISTRY" $RPC_FLAG >/dev/null
  elif [ "$ui_type" = "2" ]; then
    echo "🖥️  Scaffolding External Web UI (Svelte)..."
    ceph -pattern external_web -name "${PROJECT_NAME}-frontend" -dir "$DIR_FRONTEND" -contracts "../$DIR_CONTRACTS" -npm-registry "$NPM_REGISTRY" $RPC_FLAG >/dev/null
  elif [ "$ui_type" = "3" ]; then
    echo "🖥️  Scaffolding Internal Admin UI (SolidJS)..."
    ceph -pattern internal_admin_solid -name "${PROJECT_NAME}-frontend" -dir "$DIR_FRONTEND" -contracts "../$DIR_CONTRACTS" -npm-registry "$NPM_REGISTRY" $RPC_FLAG >/dev/null
  elif [ "$ui_type" = "4" ]; then
    echo "🖥️  Scaffolding External Web UI (SolidJS)..."
    ceph -pattern external_web_solid -name "${PROJECT_NAME}-frontend" -dir "$DIR_FRONTEND" -contracts "../$DIR_CONTRACTS" -npm-registry "$NPM_REGISTRY" $RPC_FLAG >/dev/null
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
EOF

    # Only depend on API if it actually exists
    if [[ "$add_backend" =~ ^[Yy]?$ ]]; then
      cat <<EOF >>docker-compose.yml
    depends_on:
      - api
EOF
    fi
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
.PHONY: setup dev dev-offline prod

OFFLINE ?= false
GOLDEN_NPM_HOST ?= ${NPM_AUTH_HOST}

setup:
EOF

if [[ "$ui_type" =~ ^[1-4]$ ]]; then
  cat <<EOF >>Makefile
	@if [ "\$(OFFLINE)" != "true" ]; then \\
		echo "🔑 Fetching GAR token for local development..."; \\
		if TOKEN=\$\$(gcloud auth print-access-token 2>/dev/null); then \\
			echo "NPM_TOKEN=\$\$TOKEN" > .env; \\
			npm config set "\$(GOLDEN_NPM_HOST):_authToken" "\$\$TOKEN" --location=user; \\
			pnpm config set "\$(GOLDEN_NPM_HOST):_authToken" "\$\$TOKEN" --location=global; \\
		else \\
			echo "⚠️  Could not reach GCP. Running setup in OFFLINE=true mode..."; \\
			\$(MAKE) setup OFFLINE=true || exit 1; \\
			exit 0; \\
		fi; \\
	else \\
		echo "📴 Offline mode enabled: Skipping GAR token fetch."; \\
	fi
EOF
fi

cat <<EOF >>Makefile
	@for dir in $WORKSPACE_DIRS; do \\
		if [ -f "\$\$dir/Makefile" ]; then \\
			echo ""; \\
			echo "↳ Bootstrapping \$\$dir..."; \\
			\$(MAKE) -C \$\$dir setup OFFLINE=\$(OFFLINE) || exit 1; \\
		fi; \\
	done

dev:
EOF

if [[ "$ui_type" =~ ^[1-4]$ ]]; then
  cat <<EOF >>Makefile
	@if [ "\$(OFFLINE)" != "true" ]; then \\
		echo "🔑 Refreshing GAR token..."; \\
		if TOKEN=\$\$(gcloud auth print-access-token 2>/dev/null); then \\
			echo "NPM_TOKEN=\$\$TOKEN" > .env; \\
			npm config set "\$(GOLDEN_NPM_HOST):_authToken" "\$\$TOKEN" --location=user; \\
			pnpm config set "\$(GOLDEN_NPM_HOST):_authToken" "\$\$TOKEN" --location=global; \\
		else \\
			echo "⚠️  No internet / GCP connection detected. Switching to OFFLINE=true..."; \\
			\$(MAKE) dev OFFLINE=true; \\
			exit 0; \\
		fi; \\
	fi
EOF
fi

if [[ -f "docker-compose.yml" ]]; then
  cat <<EOF >>Makefile
	@echo "🐳 Booting local development environment..."
	@docker-compose build --pull
	@docker-compose up
EOF
else
  cat <<EOF >>Makefile
	@echo "🚀 Booting standalone apps..."
	@bash -c "trap 'kill 0' EXIT; \\
EOF
  if [[ "$add_backend" =~ ^[Yy]?$ ]]; then
    cat <<EOF >>Makefile
		if [ -d '$DIR_BACKEND' ]; then \$(MAKE) -C $DIR_BACKEND dev OFFLINE=\$(OFFLINE) & fi; \\
EOF
  fi
  if [[ "$ui_type" =~ ^[1-4]$ ]]; then
    cat <<EOF >>Makefile
		if [ -d '$DIR_FRONTEND' ]; then \$(MAKE) -C $DIR_FRONTEND dev OFFLINE=\$(OFFLINE) & fi; \\
EOF
  fi
  cat <<EOF >>Makefile
		wait"
EOF
fi

cat <<EOF >>Makefile

dev-offline:
	@\$(MAKE) dev OFFLINE=true

prod:
EOF

if [[ -f "docker-compose.yml" ]]; then
  cat <<EOF >>Makefile
	@echo "🐳 Booting local production environment..."
	@IS_PROD=true docker-compose up --build
EOF
else
  cat <<EOF >>Makefile
	@echo "🚀 Booting standalone apps in PROD mode..."
	@bash -c "trap 'kill 0' EXIT; \\
EOF
  if [[ "$add_backend" =~ ^[Yy]?$ ]]; then
    cat <<EOF >>Makefile
		if [ -d '$DIR_BACKEND' ]; then \$(MAKE) -C $DIR_BACKEND prod OFFLINE=\$(OFFLINE) & fi; \\
EOF
  fi
  if [[ "$ui_type" =~ ^[1-4]$ ]]; then
    cat <<EOF >>Makefile
		if [ -d '$DIR_FRONTEND' ]; then \$(MAKE) -C $DIR_FRONTEND prod OFFLINE=\$(OFFLINE) & fi; \\
EOF
  fi
  cat <<EOF >>Makefile
		wait"
EOF
fi

echo "⚙️  Initializing dependencies and generating RPC contracts..."
make setup

echo "========================================================"
echo "✅ Monorepo '$PROJECT_NAME' generated successfully!"
echo "👉 Run 'make dev' to boot the environment (or 'make dev-offline' when offline)."
echo "========================================================"
