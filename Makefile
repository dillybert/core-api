SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------- Project ----------

GO_VERSION := 1.27.2
GOLANGCI_LINT_VERSION := v2.14.0
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
DOCKER_BUILD_ARGS := \
	--build-arg GO_VERSION=$(GO_VERSION) \
	--build-arg GOLANGCI_LINT_VERSION=$(GOLANGCI_LINT_VERSION) \
	--build-arg APP_VERSION=$(GIT_VERSION) \
	--build-arg APP_COMMIT=$(GIT_COMMIT)

# ---------- Registry ----------

REGISTRY := docker.io

# ---------- Phony ----------

.PHONY: help inspect
.PHONY: build image run
.PHONY: tag release push-release
.PHONY: publish clean

# ---------- Metadata ----------

inspect: ## Show build metadata
	@echo "Application:  $(APP_NAME)"
	@echo "Version:      $(APP_VERSION)"
	@echo "Commit:       $(APP_COMMIT)"
	@echo "Image:        $(IMAGE)"


# ---------- Build ----------

image: ## Build Docker image
	docker build \
		$(DOCKER_BUILD_ARGS) \
		-t "$(IMAGE)" \
		-f "$(DOCKERFILE)" \
		"$(DOCKER_CONTEXT)"

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

# ---------- Help ----------

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; \
		{printf "  %-16s %s\n", $$1, $$2}'
