#!/usr/bin/env bash
# =============================================================================
# Start the Example Agent stack locally via Docker Compose
# =============================================================================
#
# Prerequisites:
#   - Example Agent VS Agent running (setup.sh completed)
#   - config.env sourced
#   - ANTHROPIC_API_KEY set in environment
#   - NGROK_DOMAIN set in environment
#
# Usage:
#   source config.env
#   export NGROK_DOMAIN=your-domain.ngrok-free.app
#   export ANTHROPIC_API_KEY=sk-ant-...
#   ./scripts/start.sh
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load and export configuration (set -a auto-exports all variables)
set -a
# shellcheck source=../config.env
source "$REPO_ROOT/config.env"
set +a

echo "============================================="
echo " Example Agent VS — Local Start"
echo "============================================="
echo "  VS Agent image  : ${VS_AGENT_IMAGE}"
echo "  Chatbot image   : ${CHATBOT_IMAGE}"
echo "  Chatbot port    : ${CHATBOT_PORT}"
echo "  Service name    : ${SERVICE_NAME}"
echo "  NGROK_DOMAIN    : ${NGROK_DOMAIN:-<not set>}"
echo ""

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "WARNING: ANTHROPIC_API_KEY is not set. The chatbot LLM will not work."
fi

if [ -z "${NGROK_DOMAIN:-}" ]; then
  echo "WARNING: NGROK_DOMAIN is not set. Run setup.sh first or set it manually."
fi

echo "Starting Docker Compose stack..."
docker compose -f "$REPO_ROOT/docker/docker-compose.yml" up "$@"
