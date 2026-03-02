#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Build & test the Docker image locally
# =============================================================================
# Usage:  bash scripts/build-and-push.sh [tag]
#
# For Hugging Face Spaces, you don't need this script — just push to your
# Space repo and HF builds automatically. This is for local testing only.
# =============================================================================

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-latest}"

echo "==> Validating config ..."
"$REPO_ROOT/scripts/validate-config.sh"
echo ""
"$REPO_ROOT/scripts/check-secrets.sh"
echo ""

IMAGE="openclaw-cs:$TAG"

echo "==> Building image: $IMAGE ..."
docker build -t "$IMAGE" "$REPO_ROOT"

echo ""
echo "✓ Built $IMAGE"
echo ""
echo "Run locally with:"
echo "  docker run --rm -p 7860:7860 \\"
echo "    -e GOOGLE_API_KEY=your-key \\"
echo "    -e OPENCLAW_GATEWAY_TOKEN=your-token \\"
echo "    $IMAGE"
