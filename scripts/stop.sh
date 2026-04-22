#!/usr/bin/env bash
# =============================================================================
# Stop the EAFIT Team A stack locally via Docker Compose
# =============================================================================
#
# Usage:
#   ./scripts/stop.sh           # stop containers, keep volumes
#   ./scripts/stop.sh -v        # stop containers and remove volumes
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

set -a
# shellcheck source=../config.env
source "$REPO_ROOT/config.env"
set +a

echo "============================================="
echo " EAFIT Team A — Local Stop"
echo "============================================="
echo "  VS Agent container : ${VS_AGENT_CONTAINER_NAME}"
echo "  Chatbot port       : ${CHATBOT_PORT}"
echo ""

echo "Stopping Docker Compose stack..."
docker compose -f "$REPO_ROOT/docker/docker-compose.yml" down "$@"

echo "Done."
