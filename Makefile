# Makefile for MCP Toolbox + Agent local development
#
# Usage:
#   make up       - Start all services
#   make down     - Stop all services
#   make logs     - View logs
#   make attach   - Attach to agent for interactive chat
#   make build    - Build all container images

COMPOSE := podman-compose
COMPOSE_FILE := compose.yaml

.PHONY: up down stop start restart logs attach build build-server build-agent \
        ps clean pull help env-check

help:
	@echo "MCP Toolbox + Agent Development Environment"
	@echo ""
	@echo "Lifecycle:"
	@echo "  up        - Start all services (detached)"
	@echo "  down      - Stop and remove all services"
	@echo "  stop      - Stop services (keep containers)"
	@echo "  start     - Start stopped services"
	@echo "  restart   - Restart all services"
	@echo ""
	@echo "Monitoring:"
	@echo "  ps        - Show running containers"
	@echo "  logs      - Follow logs from all services"
	@echo "  logs-toolbox - Follow toolbox logs only"
	@echo "  logs-agent   - Follow agent logs only"
	@echo ""
	@echo "Interaction:"
	@echo "  attach    - Attach to agent for interactive chat"
	@echo "  shell-toolbox - Open shell in toolbox container"
	@echo "  shell-agent   - Open shell in agent container"
	@echo ""
	@echo "Build:"
	@echo "  build        - Build all container images"
	@echo "  build-server - Build toolbox server image"
	@echo "  build-agent  - Build agent image"
	@echo "  pull         - Pull latest base images"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean     - Remove containers, networks, and images"
	@echo ""
	@echo "Setup:"
	@echo "  env-check - Verify environment variables are set"

# Environment check
env-check:
	@echo "Checking environment variables..."
	@test -f .env || (echo "ERROR: .env file not found. Copy .env.example to .env and configure." && exit 1)
	@echo "✓ .env file exists"
	@grep -q "AWS_ACCESS_KEY_ID=" .env && echo "✓ AWS_ACCESS_KEY_ID is set" || echo "⚠ AWS_ACCESS_KEY_ID not set"
	@grep -q "AWS_SECRET_ACCESS_KEY=" .env && echo "✓ AWS_SECRET_ACCESS_KEY is set" || echo "⚠ AWS_SECRET_ACCESS_KEY not set"
	@test -f configs/tools.yaml && echo "✓ configs/tools.yaml exists" || echo "⚠ configs/tools.yaml not found"

# Lifecycle targets
up: env-check
	$(COMPOSE) -f $(COMPOSE_FILE) up -d
	@echo ""
	@echo "Services started. Use 'make attach' to interact with the agent."
	@echo "Use 'make logs' to view logs."

down:
	$(COMPOSE) -f $(COMPOSE_FILE) down

stop:
	$(COMPOSE) -f $(COMPOSE_FILE) stop

start:
	$(COMPOSE) -f $(COMPOSE_FILE) start

restart:
	$(COMPOSE) -f $(COMPOSE_FILE) restart

# Monitoring targets
ps:
	$(COMPOSE) -f $(COMPOSE_FILE) ps

logs:
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f

logs-toolbox:
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f toolbox

logs-agent:
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f agent

# Interaction targets
attach:
	@echo "Attaching to agent container. Use Ctrl+P, Ctrl+Q to detach."
	podman attach mcp-agent

shell-toolbox:
	podman exec -it mcp-toolbox /bin/sh

shell-agent:
	podman exec -it mcp-agent /bin/bash

# Build targets
build: build-server build-agent

build-server:
	$(MAKE) -C server build

build-agent:
	$(MAKE) -C python-agent build

pull:
	podman pull us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:$${TOOLBOX_VERSION:-0.24.0}
	podman pull python:3.11-slim

# Cleanup targets
clean: down
	-podman rmi mcp-agent:latest
	-podman rmi mcp-toolbox:latest
	-podman network rm mcp-network 2>/dev/null || true
