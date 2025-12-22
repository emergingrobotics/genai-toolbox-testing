.PHONY: build run stop restart logs clean help credentials

IMAGE_NAME := mcp-basic-auth-proxy
CONTAINER_NAME := mcp-basic-auth-proxy
PROXY_PORT := 8080

help:
	@echo "MCP Toolbox Basic Auth Proxy"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build        Build the nginx proxy container image"
	@echo "  run          Build and run the proxy (creates credentials if needed)"
	@echo "  stop         Stop the proxy container"
	@echo "  restart      Restart the proxy container"
	@echo "  logs         Follow the proxy logs"
	@echo "  clean        Stop and remove container and image"
	@echo "  credentials  Create or update .htpasswd file"
	@echo ""
	@echo "Examples:"
	@echo "  make run              # Start the proxy"
	@echo "  make logs             # View logs"
	@echo "  make credentials      # Add/change users"

build:
	podman build -t $(IMAGE_NAME):latest .

credentials:
	@if command -v htpasswd >/dev/null 2>&1; then \
		read -p "Enter username: " USER && \
		if [ -f .htpasswd ]; then \
			htpasswd .htpasswd $$USER; \
		else \
			htpasswd -c .htpasswd $$USER; \
		fi; \
	elif command -v openssl >/dev/null 2>&1; then \
		read -p "Enter username: " USER && \
		read -s -p "Enter password: " PASS && echo && \
		HASH=$$(openssl passwd -apr1 $$PASS) && \
		if [ -f .htpasswd ]; then \
			echo "$$USER:$$HASH" >> .htpasswd; \
		else \
			echo "$$USER:$$HASH" > .htpasswd; \
		fi && \
		echo "Created/updated credentials for $$USER"; \
	else \
		echo "Error: htpasswd or openssl required"; \
		exit 1; \
	fi

.htpasswd:
	@echo "No .htpasswd file found. Creating one..."
	@$(MAKE) credentials

run: .htpasswd build
	@podman stop $(CONTAINER_NAME) 2>/dev/null || true
	@podman rm $(CONTAINER_NAME) 2>/dev/null || true
	podman run -d \
		--name $(CONTAINER_NAME) \
		-p $(PROXY_PORT):8080 \
		-v $(CURDIR)/.htpasswd:/etc/nginx/auth/.htpasswd:ro,Z \
		$(IMAGE_NAME):latest
	@echo ""
	@echo "Proxy running at http://localhost:$(PROXY_PORT)"
	@echo "MCP SSE endpoint: http://localhost:$(PROXY_PORT)/mcp/sse"

stop:
	podman stop $(CONTAINER_NAME)

restart:
	podman restart $(CONTAINER_NAME)

logs:
	podman logs -f $(CONTAINER_NAME)

clean:
	podman stop $(CONTAINER_NAME) 2>/dev/null || true
	podman rm $(CONTAINER_NAME) 2>/dev/null || true
	podman rmi $(IMAGE_NAME):latest 2>/dev/null || true
	@echo "Cleaned up container and image"
