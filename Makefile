SHELL := /bin/bash
.DEFAULT_GOAL := help

# ─── Project ──────────────────────────────────────
APP_NAME   := core-api
IMAGE_NAME := docker.io/dillybert/core-api
DOCKERFILE := Dockerfile

# ─── Git metadata ────────────────────────────────
GIT_VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo v0.0.0-dev)
GIT_COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

LOCAL_IMAGE := $(IMAGE_NAME):local

# ─── Tools (binary installation, per official docs) ──
GOLANGCI_LINT_VERSION := v2.15.0
GOLANGCI_LINT_BIN     := $(shell go env GOPATH)/bin/golangci-lint

# ─── Phony ────────────────────────────────────────
.PHONY: help inspect
.PHONY: gen fmt vet test lint verify
.PHONY: image run
.PHONY: tag release
.PHONY: clean install-lint

# ─── Help ────────────────────────────────────────
help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

# ─── Metadata ────────────────────────────────────
inspect: ## Show build metadata
	@echo "Application:  $(APP_NAME)"
	@echo "Version:      $(GIT_VERSION)"
	@echo "Commit:       $(GIT_COMMIT)"
	@echo "Local image:  $(LOCAL_IMAGE)"

# ─── Install golangci-lint (binary, official way) ─
install-lint: ## Install golangci-lint binary (official install.sh)
	@if [ -x "$(GOLANGCI_LINT_BIN)" ]; then \
		echo "golangci-lint already installed at $(GOLANGCI_LINT_BIN)"; \
		$(GOLANGCI_LINT_BIN) version; \
	else \
		echo "Installing golangci-lint $(GOLANGCI_LINT_VERSION)..."; \
		curl -sSfL https://golangci-lint.run/install.sh | \
			sh -s -- -b $(shell go env GOPATH)/bin $(GOLANGCI_LINT_VERSION); \
	fi

# ─── Local quality ───────────────────────────────
gen: ## Regenerate code (ogen, sqlc, pigeon)
	go generate ./...

fmt: ## Format code
	gofmt -l -w .

vet: ## Run go vet
	go vet ./...

test: ## Run tests
	go test -race ./...

lint: ## Run golangci-lint (requires install-lint first)
	@if [ ! -x "$(GOLANGCI_LINT_BIN)" ]; then \
		echo "ERROR: golangci-lint not found at $(GOLANGCI_LINT_BIN)"; \
		echo "Run: make install-lint"; \
		exit 1; \
	fi
	$(GOLANGCI_LINT_BIN) run ./...

verify: gen fmt vet test lint ## Full pre-push check
	@git diff --quiet || { echo "✗ working tree modified — review and commit"; git diff --stat; exit 1; }
	@echo "✓ verify passed"

# ─── Image (local build only) ────────────────────
image: ## Build Docker image locally (tagged :local)
	docker build \
		--build-arg APP_VERSION=$(GIT_VERSION) \
		--build-arg APP_COMMIT=$(GIT_COMMIT) \
		-t "$(LOCAL_IMAGE)" \
		-f "$(DOCKERFILE)" \
		.

run: image ## Run the local image (foreground, uses .env)
	docker run --rm -it \
		--env-file .env \
		-p 8080:8080 \
		"$(LOCAL_IMAGE)"

# ─── Tagging (это триггерит CI Release) ──────────
tag: ## Create annotated git tag: make tag VERSION=v1.0.0
	@test -n "$(VERSION)" || { echo "ERROR: VERSION is required"; exit 1; }
	@[[ "$(VERSION)" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$$ ]] || \
		{ echo "ERROR: invalid SemVer (v1.2.3 or v1.2.3-rc1)"; exit 1; }
	@test -z "$$(git status --porcelain)" || \
		{ echo "ERROR: working tree is not clean"; exit 1; }
	@if git rev-parse -q --verify "refs/tags/$(VERSION)" >/dev/null; then \
		echo "ERROR: tag already exists"; exit 1; \
	fi
	git tag -a "$(VERSION)" -m "Release $(VERSION)"
	@echo "✓ tag $(VERSION) created. Push with: make release VERSION=$(VERSION)"

release: tag ## Create tag and push it (triggers CI Release workflow)
	git push origin "$(VERSION)"
	@echo "✓ $(VERSION) pushed. Watch CI: Actions → Release"

# ─── Cleanup ─────────────────────────────────────
clean: ## Remove local image
	-docker rmi "$(LOCAL_IMAGE)" 2>/dev/null || true
