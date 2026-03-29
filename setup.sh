#!/bin/bash
set -euo pipefail

# Hub Modules Workspace Setup
#
# Clones all child repos, installs DynamoDB Local, and sets up the
# pnpm workspace. Runs automatically on new Claude Code sessions via
# the SessionStart hook in .claude/settings.json.
#
# Usage:
#   ./setup.sh    — Full setup from scratch
#
# Works on:
#   - macOS (local dev with SSH)
#   - Claude Code on the web (Ubuntu, HTTPS via git proxy)

# Use HTTPS for Claude Code on the web (git proxy handles auth),
# SSH for local development (uses your SSH keys).
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  ORG="https://github.com/viva-leisure"
else
  ORG="git@github.com:viva-leisure"
fi

REPOS=(
  framework
  framework-deploy
  hub-core
  hub-module-access
  hub-module-brands
  hub-module-classes
  hub-module-customers
  hub-module-development
  hub-module-giftcards
  hub-module-infratest
  hub-module-music
  hub-module-pos
  hub-module-products
  hub-module-vivapay
)

DYNAMODB_LOCAL_DIR="$HOME/.dynamodb-local"
DYNAMODB_LOCAL_JAR="$DYNAMODB_LOCAL_DIR/DynamoDBLocal.jar"
DYNAMODB_LOCAL_URL="https://d1ni2b6xgvw0s0.cloudfront.net/v2.x/dynamodb_local_latest.tar.gz"

echo "=== Hub Modules Workspace Setup ==="
echo ""

# ── Clone repos ──────────────────────────────────────────────────────────────

CLONED=0
for repo in "${REPOS[@]}"; do
  if [ -d "$repo" ]; then
    echo "  ✓ $repo (exists)"
  else
    echo "  ↓ Cloning $repo..."
    git clone "$ORG/$repo.git" "$repo"
    CLONED=$((CLONED + 1))
  fi
done
echo ""
echo "  $CLONED repo(s) cloned, $((${#REPOS[@]} - CLONED)) already present"

# ── DynamoDB Local ───────────────────────────────────────────────────────────

echo ""
echo "=== DynamoDB Local ==="

# Check Java 17+
JAVA_OK=false
if command -v java &>/dev/null; then
  JAVA_VER=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
  if [ "$JAVA_VER" -ge 17 ] 2>/dev/null; then
    JAVA_OK=true
    echo "  ✓ Java $JAVA_VER found"
  else
    echo "  ⚠ Java $JAVA_VER found (need 17+)"
  fi
else
  echo "  ⚠ Java not found"
fi

if [ "$JAVA_OK" = false ]; then
  echo "  Installing Java 17..."
  if command -v apt-get &>/dev/null; then
    # On Claude Code web, environment runs as root. Locally, try sudo.
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update -qq && apt-get install -y -qq openjdk-17-jre-headless
    else
      sudo apt-get update -qq && sudo apt-get install -y -qq openjdk-17-jre-headless
    fi
  elif command -v brew &>/dev/null; then
    brew install openjdk@17
  else
    echo "  ⚠ Cannot install Java automatically. Please install Java 17+ manually."
    echo "    DynamoDB Local will fall back to Docker if available."
  fi
  echo "  ✓ Java installed"
fi

# Download DynamoDB Local JAR
if [ -f "$DYNAMODB_LOCAL_JAR" ]; then
  echo "  ✓ DynamoDB Local JAR found at $DYNAMODB_LOCAL_JAR"
else
  echo "  ↓ Downloading DynamoDB Local..."
  mkdir -p "$DYNAMODB_LOCAL_DIR"
  curl -sL "$DYNAMODB_LOCAL_URL" | tar -xz -C "$DYNAMODB_LOCAL_DIR"
  echo "  ✓ DynamoDB Local installed to $DYNAMODB_LOCAL_DIR"
fi

# ── Install workspace dependencies ───────────────────────────────────────────
# pnpm install creates workspace symlinks. It does NOT need framework built —
# it just symlinks to the framework directory. Build comes after.

echo ""
echo "=== Installing workspace dependencies ==="
pnpm install

# ── Build framework ──────────────────────────────────────────────────────────
# Framework exports point to dist/*.mjs. The workspace symlink resolves to the
# framework directory, but dist/ must be populated for imports to work.
# Now that deps are installed (above), we can build.

echo ""
echo "=== Building framework ==="
if [ ! -f framework/dist/index.mjs ]; then
  pnpm run build:framework
else
  echo "  ✓ framework/dist already built"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "  Workspace root:  $(pwd)"
echo "  Packages:        $(ls -d hub-module-* hub-core framework framework-deploy 2>/dev/null | wc -l | tr -d ' ')"
echo "  DynamoDB Local:  $DYNAMODB_LOCAL_JAR"
echo ""
echo "  Quick start:"
echo "    pnpm dev:core          # Start hub-core backend (auto-starts DynamoDB Local)"
echo "    pnpm dev:hub           # Start hub-core frontend"
echo "    pnpm build:framework   # Rebuild framework after changes"
echo ""
