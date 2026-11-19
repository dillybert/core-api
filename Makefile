SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------- Project ----------

APP_NAME := core-api
IMAGE_NAME := docker.io/dillybert/core-api

# ---------- Git metadata ----------

GIT_VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo v0.0.0-dev)
GIT_COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

APP_VERSION := $(GIT_VERSION)
APP_COMMIT  := $(GIT_COMMIT)

IMAGE_TAG := $(APP_VERSION)-$(APP_COMMIT)
IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)

# ---------- Docker ----------

DOCKERFILE := Dockerfile
DOCKER_CONTEXT := .

# ---------- Go ----------

GO := go

# ---------- Registry ----------

REGISTRY := docker.io

# ---------- Phony ----------

.PHONY: help inspect
.PHONY: test test-race vet fmt lint check
.PHONY: build image run
.PHONY: tag release push-release
.PHONY: publish clean

# ---------- Metadata ----------

inspect: ## Show build metadata
	@echo "Application:  $(APP_NAME)"
	@echo "Version:      $(APP_VERSION)"
	@echo "Commit:       $(APP_COMMIT)"
	@echo "Image:        $(IMAGE)"

# ---------- Development ----------

test: ## Run Go tests
	$(GO) test ./...

test-race: ## Run tests with race detector
	$(GO) test -race ./...

vet: ## Run go vet
	$(GO) vet ./...

fmt: ## Format Go source files
	$(GO) fmt ./...

lint: ## Run Go linters (requires golangci-lint)
	golangci-lint run ./...

check: fmt vet test ## Run standard quality checks

# ---------- Build ----------

build: ## Build Go binary locally
	CGO_ENABLED=0 $(GO) build \
		-trimpath \
		-tags timetzdata \
		-ldflags="-s -w -X main.version=$(APP_VERSION) -X main.commit=$(APP_COMMIT)" \
		-o bin/core-api \
		./cmd/core-api

image: ## Build Docker image
	docker build \
		--build-arg APP_VERSION="$(APP_VERSION)" \
		--build-arg APP_COMMIT="$(APP_COMMIT)" \
		-t "$(IMAGE)" \
		-f "$(DOCKERFILE)" \
		"$(DOCKER_CONTEXT)"

run: build ## Run locally
	./bin/core-api

# ---------- Versioning ----------

tag: ## Create annotated Git tag: make tag VERSION=v1.0.0
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required"; exit 1)
	@[[ "$(VERSION)" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$$ ]] || \
		(echo "ERROR: invalid SemVer version"; exit 1)
	@test -z "$$(git status --porcelain)" || \
		(echo "ERROR: working tree is not clean"; exit 1)
	@if git rev-parse -q --verify "refs/tags/$(VERSION)" >/dev/null; then \
		echo "ERROR: tag already exists"; exit 1; \
	fi
	git tag -a "$(VERSION)" -m "Release $(VERSION)"

release: tag ## Create and push release tag
	git push origin "$(VERSION)"

push-release: ## Push existing release tag
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required"; exit 1)
	@git rev-parse -q --verify "refs/tags/$(VERSION)" >/dev/null || \
		(echo "ERROR: tag does not exist"; exit 1)
	git push origin "$(VERSION)"

# ---------- Registry ----------

login: ## Login to Docker Hub
	docker login $(REGISTRY)

publish: image ## Build and publish Docker image
	docker push "$(IMAGE)"

# ---------- Cleanup ----------

clean: ## Remove local build artifacts
	rm -rf bin/

# ---------- Help ----------

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; \
		{printf "  %-16s %s\n", $$1, $$2}'
