APP_VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0-dev)
APP_COMMIT  := $(shell git rev-parse HEAD)

.PHONY: build up

build:
	docker compose build \
		--build-arg APP_VERSION=$(APP_VERSION) \
		--build-arg APP_COMMIT=$(APP_COMMIT) \
		core-api

up: build
	APP_VERSION=$(APP_VERSION) APP_COMMIT=$(APP_COMMIT) docker compose up -d
