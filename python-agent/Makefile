# Makefile for MCP Python Agent container
#
# Usage:
#   make build    - Build the container image
#   make push     - Push to ECR (requires AWS_ACCOUNT and AWS_REGION)
#   make clean    - Remove local images

IMAGE_NAME := mcp-agent
VERSION ?= 0.1.0
REGISTRY ?= localhost

# ECR settings (override with environment variables)
AWS_ACCOUNT ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
AWS_REGION ?= us-east-1
ECR_REGISTRY := $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com

.PHONY: build tag push login clean help

help:
	@echo "MCP Python Agent Container"
	@echo ""
	@echo "Targets:"
	@echo "  build   - Build container image"
	@echo "  tag     - Tag image for ECR"
	@echo "  push    - Push image to ECR"
	@echo "  login   - Login to ECR"
	@echo "  clean   - Remove local images"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION=$(VERSION)"
	@echo "  AWS_ACCOUNT=$(AWS_ACCOUNT)"
	@echo "  AWS_REGION=$(AWS_REGION)"

build:
	podman build \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):latest \
		-f Containerfile \
		.

tag: build
	podman tag $(IMAGE_NAME):$(VERSION) $(ECR_REGISTRY)/$(IMAGE_NAME):$(VERSION)
	podman tag $(IMAGE_NAME):latest $(ECR_REGISTRY)/$(IMAGE_NAME):latest

login:
	aws ecr get-login-password --region $(AWS_REGION) | \
		podman login --username AWS --password-stdin $(ECR_REGISTRY)

push: login tag
	podman push $(ECR_REGISTRY)/$(IMAGE_NAME):$(VERSION)
	podman push $(ECR_REGISTRY)/$(IMAGE_NAME):latest

clean:
	-podman rmi $(IMAGE_NAME):$(VERSION)
	-podman rmi $(IMAGE_NAME):latest
	-podman rmi $(ECR_REGISTRY)/$(IMAGE_NAME):$(VERSION)
	-podman rmi $(ECR_REGISTRY)/$(IMAGE_NAME):latest
