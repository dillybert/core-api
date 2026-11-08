APP_VERSION := $(shell git describe --tags --always --dirty)
APP_COMMIT  := $(shell git rev-parse --short=12 HEAD)

.PHONY: build up

build:
	APP_VERSION=$(APP_VERSION) docker compose build \
		--build-arg APP_VERSION=$(APP_VERSION) \
		--build-arg APP_COMMIT=$(APP_COMMIT) \
		core-api

up: build
	APP_VERSION=$(APP_VERSION) docker compose up -d
