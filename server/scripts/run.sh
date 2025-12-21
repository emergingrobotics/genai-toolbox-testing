#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source environment variables
source "$PROJECT_ROOT/.envrc"

export VERSION=0.24.0
podman run -p 5001:5000 \
  -e SQLCMDSERVER \
  -e SQLCMDUSER \
  -e SQLCMDPASSWORD \
  -e SQLCMDDBNAME \
  -v "$PROJECT_ROOT/configs/tools.yaml:/app/tools.yaml:Z" \
  us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:$VERSION \
  --tools-file "/app/tools.yaml" \
  --address "0.0.0.0"
