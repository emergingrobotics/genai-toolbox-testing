#!/bin/bash
#
# Start the nginx basic auth proxy for MCP Toolbox
#
# This script:
# 1. Prompts for username/password if .htpasswd doesn't exist
# 2. Builds the nginx container image
# 3. Runs the proxy on port 8080
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONTAINER_NAME="mcp-basic-auth-proxy"
IMAGE_NAME="mcp-basic-auth-proxy:latest"
HTPASSWD_FILE="$SCRIPT_DIR/.htpasswd"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== MCP Toolbox Basic Auth Proxy ===${NC}"
echo ""

# Check if .htpasswd exists, if not create it
if [ ! -f "$HTPASSWD_FILE" ]; then
    echo -e "${YELLOW}No .htpasswd file found. Let's create one.${NC}"
    echo ""

    read -p "Enter username: " USERNAME
    if [ -z "$USERNAME" ]; then
        echo -e "${RED}Error: Username cannot be empty${NC}"
        exit 1
    fi

    echo "Enter password for user '$USERNAME':"
    # Use htpasswd if available, otherwise use openssl
    if command -v htpasswd &> /dev/null; then
        htpasswd -c "$HTPASSWD_FILE" "$USERNAME"
    elif command -v openssl &> /dev/null; then
        read -s PASSWORD
        echo ""
        HASH=$(openssl passwd -apr1 "$PASSWORD")
        echo "$USERNAME:$HASH" > "$HTPASSWD_FILE"
        echo -e "${GREEN}Created .htpasswd file${NC}"
    else
        echo -e "${RED}Error: Neither htpasswd nor openssl found. Install one of them.${NC}"
        echo "  macOS: brew install httpd (for htpasswd)"
        echo "  Linux: apt install apache2-utils (for htpasswd)"
        exit 1
    fi
    echo ""
fi

# Stop existing container if running
if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping existing container..."
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Build the image
echo "Building nginx proxy image..."
podman build -t "$IMAGE_NAME" "$SCRIPT_DIR"

# Run the container
echo ""
echo "Starting proxy container..."
podman run -d \
    --name "$CONTAINER_NAME" \
    -p 8080:8080 \
    -v "$HTPASSWD_FILE:/etc/nginx/auth/.htpasswd:ro,Z" \
    "$IMAGE_NAME"

echo ""
echo -e "${GREEN}=== Proxy is running! ===${NC}"
echo ""
echo "Proxy URL:    http://localhost:8080"
echo "MCP SSE:      http://localhost:8080/mcp/sse"
echo ""
echo -e "${YELLOW}Make sure the MCP Toolbox server is running on port 5001${NC}"
echo "  ./server/scripts/run.sh"
echo ""
echo "To test the proxy:"
echo "  curl -u USERNAME:PASSWORD http://localhost:8080/"
echo ""
echo "To configure Claude Code:"
echo "  claude mcp add --transport sse toolbox-db http://USERNAME:PASSWORD@localhost:8080/mcp/sse"
echo ""
echo "To view logs:"
echo "  podman logs -f $CONTAINER_NAME"
echo ""
echo "To stop the proxy:"
echo "  podman stop $CONTAINER_NAME"
